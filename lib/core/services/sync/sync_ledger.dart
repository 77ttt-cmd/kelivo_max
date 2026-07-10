import 'package:hive/hive.dart';
import 'package:Kelivo/core/models/sync_enums.dart';

/// Tracks which records and files were synced (pulled or pushed).
/// Used by IncognitoWipe to know what to delete.
class SyncLedger {
  static const String boxName = 'sync_ledger_v1';

  Box<Map>? _box;

  /// Initialize the ledger by opening the Hive box.
  Future<void> init() async {
    _box = await Hive.openBox<Map>(boxName);
  }

  /// Append a record sync entry.
  Future<void> append({
    required SyncCategory category,
    required String recordId,
    required String direction,
    required String sessionId,
  }) async {
    final box = _box;
    if (box == null) return;
    final key = '${category.toKey()}::$recordId';
    await box.put(key, {
      'category': category.toKey(),
      'recordId': recordId,
      'direction': direction,
      'sessionId': sessionId,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Append a file sync entry.
  Future<void> appendFile({
    required String fileHash,
    required String path,
    required String direction,
    required String sessionId,
  }) async {
    final box = _box;
    if (box == null) return;
    final key = 'file::$fileHash';
    await box.put(key, {
      'category': SyncCategory.files.toKey(),
      'recordId': fileHash,
      'direction': direction,
      'sessionId': sessionId,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'fileHash': fileHash,
      'path': path,
    });
  }

  /// Get all ledger entries.
  List<Map<dynamic, dynamic>> allEntries() {
    final box = _box;
    if (box == null) return [];
    return box.values.toList();
  }

  /// Clear all entries.
  Future<void> clear() async {
    final box = _box;
    if (box == null) return;
    await box.clear();
  }
}
