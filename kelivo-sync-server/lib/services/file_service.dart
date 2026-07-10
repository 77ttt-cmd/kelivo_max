import 'dart:io';

import 'package:kelivo_max_sync_server/services/database.dart';

class FileService {
  /// Get file metadata by hash for a specific user.
  /// Returns null if not found.
  static Future<Map<String, dynamic>?> getFileByHash(
    int userId,
    String hash,
  ) async {
    final result = await Database.pool.execute(
      r'SELECT stored_path, content_type, size FROM files WHERE user_id = $1 AND sha256_hash = $2',
      parameters: [userId, hash],
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return {
      'storedPath': row[0] as String,
      'contentType': row[1] as String,
      'size': row[2] as int,
    };
  }

  /// Check which hashes exist for a user.
  static Future<Map<String, bool>> checkExists(
    int userId,
    List<String> hashes,
  ) async {
    if (hashes.isEmpty) return {};
    final result = <String, bool>{};
    for (final h in hashes) {
      result[h] = false;
    }

    // Query existing hashes
    final rows = await Database.pool.execute(
      r'SELECT sha256_hash FROM files WHERE user_id = $1 AND sha256_hash = ANY($2)',
      parameters: [userId, hashes],
    );
    for (final row in rows) {
      result[row[0] as String] = true;
    }
    return result;
  }

  /// Store a file for a user.
  /// Returns true if newly stored, false if already existed.
  static Future<bool> storeFile({
    required int userId,
    required String hash,
    required String originalPath,
    required String contentType,
    required List<int> bytes,
  }) async {
    // Check if already exists
    final existing = await getFileByHash(userId, hash);
    if (existing != null) return false;

    // Create storage directory
    final storageDir = Directory('uploads/$userId');
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }

    // Store file
    final storedPath = '${storageDir.path}/$hash';
    await File(storedPath).writeAsBytes(bytes);

    // Insert DB record
    await Database.pool.execute(
      r'''INSERT INTO files (user_id, sha256_hash, original_path, content_type, size, stored_path)
          VALUES ($1, $2, $3, $4, $5, $6)
          ON CONFLICT (user_id, sha256_hash) DO NOTHING''',
      parameters: [
        userId,
        hash,
        originalPath,
        contentType,
        bytes.length,
        storedPath,
      ],
    );

    return true;
  }

  /// Check total storage used by a user (in bytes).
  static Future<int> getUserStorageUsed(int userId) async {
    final result = await Database.pool.execute(
      r'SELECT COALESCE(SUM(size), 0) FROM files WHERE user_id = $1',
      parameters: [userId],
    );
    return result.first[0] as int;
  }
}
