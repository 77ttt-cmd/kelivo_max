import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kelivo_max/core/models/assistant.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/sync/sync_category_handler.dart';

/// Sync handler for assistants (SharedPreferences-backed JSON list).
class AssistantsSyncHandler extends SyncCategoryHandler {
  static const String _assistantsKey = 'assistants_v1';

  @override
  SyncCategory get category => SyncCategory.assistants;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    final results = <Map<String, dynamic>>[];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_assistantsKey);
    if (raw == null || raw.isEmpty) return results;

    List<Assistant> assistants;
    try {
      assistants = Assistant.decodeList(raw);
    } catch (e) {
      debugPrint('[AssistantsSyncHandler] Failed to decode assistants: $e');
      return results;
    }

    for (final assistant in assistants) {
      try {
        if (assistant.localOnly) continue;
        final updatedAt = assistant.updatedAt;
        if (updatedAt == null || updatedAt <= sinceCursor) continue;
        results.add({
          'recordId': assistant.id,
          'payload': assistant.toJson(),
          'updatedAt': updatedAt,
          if (assistant.deletedAt != null) 'deletedAt': assistant.deletedAt,
        });
      } catch (e) {
        debugPrint('[AssistantsSyncHandler] Error collecting assistant: $e');
      }
    }

    return results;
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_assistantsKey);
    final List<Assistant> assistants;
    if (raw != null && raw.isNotEmpty) {
      assistants = Assistant.decodeList(raw);
    } else {
      assistants = <Assistant>[];
    }

    bool changed = false;

    for (final change in changes) {
      try {
        final recordId = change['recordId'] as String;
        final payload = change['payload'] as Map<String, dynamic>?;
        final remoteUpdatedAt = change['updatedAt'] as int;
        final remoteDeletedAt = change['deletedAt'] as int?;

        final localIdx = assistants.indexWhere((a) => a.id == recordId);

        if (localIdx == -1) {
          // New assistant from remote
          if (remoteDeletedAt != null) continue; // Already deleted — skip
          if (payload == null) continue;
          assistants.add(Assistant.fromJson(payload));
          changed = true;
          continue;
        }

        // LWW: remote wins only if strictly newer
        final local = assistants[localIdx];
        final localUpdatedAt = local.updatedAt ?? 0;
        if (remoteUpdatedAt <= localUpdatedAt) continue;

        if (remoteDeletedAt != null) {
          // Remote says delete — soft-delete locally
          assistants[localIdx] = local.copyWith(deletedAt: remoteDeletedAt);
          changed = true;
        } else if (payload != null) {
          // Remote is newer — replace with remote version
          assistants[localIdx] = Assistant.fromJson(payload);
          changed = true;
        }
      } catch (e) {
        debugPrint('[AssistantsSyncHandler] Error applying change: $e');
      }
    }

    if (changed) {
      await prefs.setString(_assistantsKey, Assistant.encodeList(assistants));
    }
  }
}
