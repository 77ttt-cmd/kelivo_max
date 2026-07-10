import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/services/sync/sync_api_client.dart';
import 'package:Kelivo/core/services/sync/sync_category_handler.dart';
import 'package:Kelivo/core/services/sync/sync_ledger.dart';
import 'package:Kelivo/utils/app_directories.dart';

/// Sync handler for user files (images, avatars, attachments, etc.).
///
/// Collects local file changes for push, and uploads files that the server
/// does not already have (dedup via [SyncApiClient.checkFilesExist]).
/// File downloads during pull are handled by [applyRemoteChanges].
class FilesSyncHandler extends SyncCategoryHandler {
  /// Set by the orchestrator before push to enable file uploads.
  SyncApiClient? apiClient;

  /// Set by the orchestrator to record sync ledger entries after upload.
  SyncLedger? ledger;

  @override
  SyncCategory get category => SyncCategory.files;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    final results = <Map<String, dynamic>>[];

    // Scan syncable directories: upload, images, avatars.
    final dirs = <Directory>[];
    try {
      dirs.addAll([
        await AppDirectories.getUploadDirectory(),
        await AppDirectories.getImagesDirectory(),
        await AppDirectories.getAvatarsDirectory(),
      ]);
    } catch (e) {
      debugPrint('[FilesSyncHandler] Failed to resolve directories: $e');
      return results;
    }

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is! File) continue;
          try {
            final stat = await entity.stat();
            final modifiedMs = stat.modified.millisecondsSinceEpoch;
            if (modifiedMs <= sinceCursor) continue;

            final bytes = await entity.readAsBytes();
            final hash = sha256.convert(bytes).toString();

            results.add({
              'recordId': hash,
              'payload': {'hash': hash, 'path': entity.path, 'size': stat.size},
              'updatedAt': modifiedMs,
            });
          } catch (e) {
            debugPrint(
              '[FilesSyncHandler] Error processing file ${entity.path}: $e',
            );
          }
        }
      } catch (e) {
        debugPrint(
          '[FilesSyncHandler] Error listing directory ${dir.path}: $e',
        );
      }
    }

    return results;
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    // Phase 1: Log that file sync changes were received but cannot be
    // processed yet because the file download mechanism is not wired.
    for (final change in changes) {
      final recordId = change['recordId'] as String?;
      final remoteDeletedAt = change['deletedAt'] as int?;
      if (remoteDeletedAt != null) {
        debugPrint(
          '[FilesSyncHandler] File deleted remotely: $recordId (no-op in Phase 1)',
        );
      } else {
        debugPrint(
          '[FilesSyncHandler] File change received: $recordId '
          '(download not yet implemented in Phase 1)',
        );
      }
    }
  }

  /// Upload files that the server does not already have.
  ///
  /// [localChanges] should come from [collectLocalChanges]. Each entry is
  /// checked against the server via [SyncApiClient.checkFilesExist]; only
  /// missing files are uploaded. After each successful upload the
  /// [SyncLedger] is updated with direction 'push'.
  Future<void> uploadPendingFiles(
    List<Map<String, dynamic>> localChanges,
  ) async {
    if (apiClient == null) return;

    final hashes = localChanges
        .map((c) => c['recordId'] as String)
        .where((h) => h.isNotEmpty)
        .toList();

    if (hashes.isEmpty) return;

    // Check which hashes the server already has.
    final existsMap = await apiClient!.checkFilesExist(hashes);

    for (final change in localChanges) {
      final hash = change['recordId'] as String;
      if (existsMap[hash] == true) continue; // Server already has it.

      final path = change['payload']?['path'] as String?;
      if (path == null) continue;

      final file = File(path);
      if (!await file.exists()) continue;

      try {
        final bytes = await file.readAsBytes();
        await apiClient!.uploadFile(hash: hash, path: path, bytes: bytes);

        // Record in ledger.
        if (ledger != null) {
          await ledger!.appendFile(
            fileHash: hash,
            path: path,
            direction: 'push',
            sessionId: '', // sessionId will be set by the orchestrator
          );
        }
      } catch (e) {
        debugPrint(
          '[FilesSyncHandler] Failed to upload file $hash ($path): $e',
        );
      }
    }
  }
}
