import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/services/sync/sync_category_handler.dart';

/// Sync handler for general app settings (SharedPreferences key-value pairs).
///
/// Each change represents a single setting entry:
/// - `recordId` — the SharedPreferences key
/// - `payload` — `{'value': <serialized value>}`
/// - `updatedAt` — millisecondsSinceEpoch of the remote edit
///
/// Because individual settings don't carry their own timestamps, a secondary
/// metadata key `_sync_setting_ts_v1` stores a JSON map of
/// `{settingKey: lastUpdatedAtMs}` to support per-key LWW.
class SettingsSyncHandler extends SyncCategoryHandler {
  static const String _syncSettingTsKey = '_sync_setting_ts_v1';

  @override
  SyncCategory get category => SyncCategory.settings;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    final results = <Map<String, dynamic>>[];

    final prefs = await SharedPreferences.getInstance();
    final tsRaw = prefs.getString(_syncSettingTsKey);
    if (tsRaw == null || tsRaw.isEmpty) return results;

    Map<String, int> keyTimestamps;
    try {
      keyTimestamps = (jsonDecode(tsRaw) as Map).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      );
    } catch (e) {
      debugPrint('[SettingsSyncHandler] Failed to decode timestamp map: $e');
      return results;
    }

    for (final entry in keyTimestamps.entries) {
      try {
        final key = entry.key;
        final ts = entry.value;
        if (ts <= sinceCursor) continue;

        // Read the current value of this setting.
        final value = prefs.containsKey(key) ? prefs.get(key) : null;

        results.add({
          'recordId': key,
          'payload': {'value': value},
          'updatedAt': ts,
          if (value == null) 'deletedAt': ts,
        });
      } catch (e) {
        debugPrint(
          '[SettingsSyncHandler] Error collecting setting ${entry.key}: $e',
        );
      }
    }

    return results;
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    // Load per-key timestamp metadata.
    final tsRaw = prefs.getString(_syncSettingTsKey);
    Map<String, int> keyTimestamps = <String, int>{};
    if (tsRaw != null && tsRaw.isNotEmpty) {
      try {
        keyTimestamps = (jsonDecode(tsRaw) as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        );
      } catch (_) {
        // keep empty map
      }
    }

    bool tsChanged = false;

    for (final change in changes) {
      try {
        final recordId = change['recordId'] as String;
        final payload = change['payload'] as Map<String, dynamic>?;
        final remoteUpdatedAt = change['updatedAt'] as int;
        final remoteDeletedAt = change['deletedAt'] as int?;

        // LWW: remote wins only if strictly newer than our last-known ts.
        final localTs = keyTimestamps[recordId] ?? 0;
        if (remoteUpdatedAt <= localTs) continue;

        if (remoteDeletedAt != null) {
          // Remote says delete — remove the key locally.
          await prefs.remove(recordId);
          keyTimestamps[recordId] = remoteUpdatedAt;
          tsChanged = true;
          continue;
        }

        if (payload == null) continue;

        // Payload carries the value to store.
        final value = payload['value'];
        if (value == null) {
          await prefs.remove(recordId);
        } else if (value is bool) {
          await prefs.setBool(recordId, value);
        } else if (value is int) {
          await prefs.setInt(recordId, value);
        } else if (value is double) {
          await prefs.setDouble(recordId, value);
        } else if (value is String) {
          await prefs.setString(recordId, value);
        } else if (value is List) {
          await prefs.setStringList(
            recordId,
            value.map((e) => e.toString()).toList(),
          );
        } else {
          // Fallback: serialize as JSON string
          await prefs.setString(recordId, jsonEncode(value));
        }

        keyTimestamps[recordId] = remoteUpdatedAt;
        tsChanged = true;
      } catch (e) {
        debugPrint('[SettingsSyncHandler] Error applying change: $e');
      }
    }

    if (tsChanged) {
      await prefs.setString(_syncSettingTsKey, jsonEncode(keyTimestamps));
    }
  }
}
