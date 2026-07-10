import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../models/change_entry.dart';
import 'database.dart';
import 'encryption_service.dart';

class ChangelogResult {
  final List<ChangeEntry> entries;
  final bool hasMore;

  ChangelogResult({required this.entries, required this.hasMore});
}

class PushResult {
  final int accepted;
  final List<String> skipped;
  final int latestSeq;

  PushResult({
    required this.accepted,
    required this.skipped,
    required this.latestSeq,
  });
}

class ChangelogService {
  /// Fetches change entries for [userId] with server_seq > [since],
  /// filtered to the given [categories].
  ///
  /// Returns at most [limit] entries ordered by server_seq ascending.
  /// If there are more entries beyond the limit, [ChangelogResult.hasMore]
  /// is true.
  static Future<ChangelogResult> getChanges(
    int userId,
    int since,
    List<String> categories, {
    int limit = 500,
  }) async {
    if (categories.isEmpty) {
      return ChangelogResult(entries: [], hasMore: false);
    }

    // Build parameterised IN-clause: $3, $4, $5, ...
    final categoryParams = <String>[];
    final substitutionValues = <Object>[userId, since];
    for (var i = 0; i < categories.length; i++) {
      categoryParams.add('\$${i + 3}');
      substitutionValues.add(TypedValue(Type.text, categories[i]));
    }
    final inClause = categoryParams.join(', ');

    // Fetch limit+1 rows so we can determine hasMore without a separate count.
    final fetchCount = limit + 1;

    final result = await Database.pool.execute(
      Sql.indexed(
        'SELECT id, user_id, category, record_id, payload, updated_at, '
        'deleted_at, server_seq '
        'FROM change_entries '
        'WHERE user_id = \$1 AND server_seq > \$2 '
        'AND category IN ($inClause) '
        'ORDER BY server_seq ASC '
        'LIMIT $fetchCount',
      ),
      parameters: substitutionValues,
    );

    final hasMore = result.length > limit;
    final rows = hasMore ? result.take(limit).toList() : result.toList();

    final entries = <ChangeEntry>[];
    for (final row in rows) {
      final payloadRaw = row[4];
      final Map<String, dynamic> rawPayload;
      if (payloadRaw is Map) {
        rawPayload = Map<String, dynamic>.from(payloadRaw);
      } else if (payloadRaw is String) {
        rawPayload = jsonDecode(payloadRaw) as Map<String, dynamic>;
      } else {
        rawPayload = <String, dynamic>{};
      }

      final category = row[2] as String;
      final uid = row[1] as int;

      // Decrypt sensitive fields before returning to client.
      final payload = await EncryptionService.decryptPayload(
        uid,
        category,
        rawPayload,
      );

      entries.add(
        ChangeEntry(
          id: row[0] as int,
          userId: uid,
          category: category,
          recordId: row[3] as String,
          payload: payload,
          updatedAt: row[5] as int,
          deletedAt: row[6] as int?,
          serverSeq: row[7] as int,
        ),
      );
    }

    return ChangelogResult(entries: entries, hasMore: hasMore);
  }

  /// Pushes change entries for [userId] using last-write-wins (LWW) semantics.
  ///
  /// Each entry is upserted by (user_id, category, record_id). An existing row
  /// is only overwritten when the incoming [updatedAt] is strictly greater than
  /// the stored value. Entries that lose the LWW comparison are reported in
  /// [PushResult.skipped].
  static Future<PushResult> pushChanges(
    int userId,
    List<Map<String, dynamic>> entries,
  ) async {
    var accepted = 0;
    final skipped = <String>[];

    for (final entry in entries) {
      final category = entry['category'] as String;
      final recordId = entry['recordId'] as String;
      final rawPayload = entry['payload'] as Map<String, dynamic>? ?? {};
      final updatedAt = entry['updatedAt'] as int;
      final deletedAt = entry['deletedAt'] as int?;

      // Encrypt sensitive fields before storage.
      final payload = await EncryptionService.encryptPayload(
        userId,
        category,
        rawPayload,
      );

      // Upsert: INSERT ... ON CONFLICT (user_id, category, record_id)
      // Only update if incoming updatedAt > existing updatedAt (LWW).
      final result = await Database.pool.execute(
        Sql.indexed(
          'INSERT INTO change_entries '
          '(user_id, category, record_id, payload, updated_at, deleted_at) '
          'VALUES (\$1, \$2, \$3, \$4::jsonb, \$5, \$6) '
          'ON CONFLICT (user_id, category, record_id) '
          'DO UPDATE SET '
          'payload = EXCLUDED.payload, '
          'updated_at = EXCLUDED.updated_at, '
          'deleted_at = EXCLUDED.deleted_at '
          'WHERE change_entries.updated_at < EXCLUDED.updated_at',
        ),
        parameters: [
          userId,
          category,
          recordId,
          jsonEncode(payload),
          updatedAt,
          deletedAt,
        ],
      );

      if (result.affectedRows > 0) {
        accepted++;
      } else {
        skipped.add(recordId);
      }
    }

    // Get latest server_seq for this user.
    final seqResult = await Database.pool.execute(
      Sql.indexed(
        'SELECT COALESCE(MAX(server_seq), 0) '
        'FROM change_entries WHERE user_id = \$1',
      ),
      parameters: [userId],
    );
    final latestSeq = seqResult.first[0] as int;

    return PushResult(
      accepted: accepted,
      skipped: skipped,
      latestSeq: latestSeq,
    );
  }
}
