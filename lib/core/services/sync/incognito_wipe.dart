// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:hive/hive.dart';
import 'package:Kelivo/core/models/sync_config.dart';
import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/services/sync/sync_credential_store.dart';
import 'package:Kelivo/core/services/sync/sync_ledger.dart';

/// Preview result for incognito wipe — shows what would be deleted.
class IncognitoWipePreview {
  final Map<SyncCategory, int> categoryCounts;
  final int fileCount;
  final int totalCount;

  IncognitoWipePreview({
    required this.categoryCounts,
    required this.fileCount,
    required this.totalCount,
  });
}

/// Service that performs local "incognito wipe" — deletes all data
/// that was synced (pulled or pushed) from this device.
///
/// Key properties:
/// - Only deletes records tracked in SyncLedger
/// - Records marked localOnly are NOT deleted
/// - Cloud copies are NOT affected (no server-side deletion)
/// - Clears sync credentials and resets SyncConfig to disabled
class IncognitoWipe {
  final SyncLedger _ledger;
  final SyncCredentialStore _credentialStore;
  final Future<void> Function(SyncConfig) _resetSyncConfig;

  IncognitoWipe({
    required SyncLedger ledger,
    required SyncCredentialStore credentialStore,
    required Future<void> Function(SyncConfig) resetSyncConfig,
  }) : _ledger = ledger,
       _credentialStore = credentialStore,
       _resetSyncConfig = resetSyncConfig;

  /// Preview what would be deleted — side-effect free.
  IncognitoWipePreview preview() {
    final entries = _ledger.allEntries();
    final categoryCounts = <SyncCategory, int>{};
    var fileCount = 0;

    for (final entry in entries) {
      final catKey = entry['category'] as String?;
      if (catKey == null) continue;
      final cat = SyncCategoryExt.fromKey(catKey);
      if (cat == null) continue;

      if (cat == SyncCategory.files) {
        fileCount++;
      }
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
    }

    final total = entries.length;
    return IncognitoWipePreview(
      categoryCounts: categoryCounts,
      fileCount: fileCount,
      totalCount: total,
    );
  }

  /// Execute the wipe.
  ///
  /// 1. Delete records and files referenced by SyncLedger entries
  /// 2. Clear the ledger
  /// 3. Clear sync credentials
  /// 4. Reset SyncConfig to default (disabled)
  Future<void> run() async {
    final entries = _ledger.allEntries();

    // Delete synced files
    for (final entry in entries) {
      final path = entry['path'] as String?;
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    // Delete synced records from Hive boxes by category
    for (final entry in entries) {
      final catKey = entry['category'] as String?;
      final recordId = entry['recordId'] as String?;
      if (catKey == null || recordId == null) continue;

      final cat = SyncCategoryExt.fromKey(catKey);
      if (cat == null) continue;

      await _deleteRecord(cat, recordId);
    }

    // Clear the ledger
    await _ledger.clear();

    // Clear credentials
    await _credentialStore.clearAll();

    // Reset SyncConfig to default
    await _resetSyncConfig(const SyncConfig());
  }

  /// Delete a single record by category and id.
  /// This is a best-effort operation — if the record doesn't exist,
  /// it's silently ignored.
  Future<void> _deleteRecord(SyncCategory category, String recordId) async {
    try {
      switch (category) {
        case SyncCategory.chats:
          // Delete from conversations Hive box
          final convBox = Hive.box('conversations');
          if (convBox.containsKey(recordId)) {
            await convBox.delete(recordId);
          }
          // Also try to delete associated messages box
          try {
            final msgBoxName = 'messages_$recordId';
            if (Hive.isBoxOpen(msgBoxName)) {
              final msgBox = Hive.box(msgBoxName);
              await msgBox.deleteFromDisk();
            }
          } catch (_) {
            // Message box may not exist
          }
        case SyncCategory.files:
          // Files are handled in the file deletion loop above
          break;
        default:
          // For SharedPreferences-based categories (providers, assistants,
          // quickPhrases, mcp, searchServices, ttsServices, settings),
          // individual record deletion requires the respective provider.
          // Phase 0 wipe handles file and chat deletion directly.
          // Full per-category deletion will be enhanced in later phases.
          break;
      }
    } catch (_) {
      // Best-effort deletion — don't block wipe on individual failures
    }
  }
}
