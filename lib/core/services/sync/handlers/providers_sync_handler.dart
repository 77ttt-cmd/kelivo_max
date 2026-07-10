import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/sync/sync_category_handler.dart';

/// Sync handler for LLM provider configurations (SharedPreferences-backed).
///
/// Providers are stored as a JSON map keyed by provider display-key.
/// Sync identification uses [ProviderConfig.syncId] (immutable UUID) rather
/// than the mutable display-key `id`.
class ProvidersSyncHandler extends SyncCategoryHandler {
  static const String _providerConfigsKey = 'provider_configs_v1';

  @override
  SyncCategory get category => SyncCategory.providers;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    final results = <Map<String, dynamic>>[];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_providerConfigsKey);
    if (raw == null || raw.isEmpty) return results;

    Map<String, ProviderConfig> configs;
    try {
      final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
      configs = decoded.map(
        (k, v) => MapEntry(
          k,
          ProviderConfig.fromJson((v as Map).cast<String, dynamic>()),
        ),
      );
    } catch (e) {
      debugPrint('[ProvidersSyncHandler] Failed to decode local configs: $e');
      return results;
    }

    for (final entry in configs.entries) {
      try {
        final config = entry.value;
        if (config.localOnly) continue;
        final updatedAt = config.updatedAt;
        if (updatedAt == null || updatedAt <= sinceCursor) continue;
        results.add({
          'recordId': config.syncId,
          'payload': config.toJson(),
          'updatedAt': updatedAt,
          if (config.deletedAt != null) 'deletedAt': config.deletedAt,
        });
      } catch (e) {
        debugPrint(
          '[ProvidersSyncHandler] Error collecting provider ${entry.key}: $e',
        );
      }
    }

    return results;
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_providerConfigsKey);
    final Map<String, ProviderConfig> configs = {};

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
        configs.addAll(
          decoded.map(
            (k, v) => MapEntry(
              k,
              ProviderConfig.fromJson((v as Map).cast<String, dynamic>()),
            ),
          ),
        );
      } catch (e) {
        debugPrint('[ProvidersSyncHandler] Failed to decode local configs: $e');
      }
    }

    bool changed = false;

    for (final change in changes) {
      try {
        final recordId = change['recordId'] as String; // matches syncId
        final payload = change['payload'] as Map<String, dynamic>?;
        final remoteUpdatedAt = change['updatedAt'] as int;
        final remoteDeletedAt = change['deletedAt'] as int?;

        // Find local provider by syncId
        String? localKey;
        ProviderConfig? local;
        for (final entry in configs.entries) {
          if (entry.value.syncId == recordId) {
            localKey = entry.key;
            local = entry.value;
            break;
          }
        }

        if (local == null) {
          // New provider from remote
          if (remoteDeletedAt != null) continue; // Already deleted — skip
          if (payload == null) continue;
          final config = ProviderConfig.fromJson(payload);
          configs[config.id] = config;
          changed = true;
          continue;
        }

        // LWW: remote wins only if strictly newer
        final localUpdatedAt = local.updatedAt ?? 0;
        if (remoteUpdatedAt <= localUpdatedAt) continue;

        if (remoteDeletedAt != null) {
          // Remote says delete — soft-delete locally
          configs[localKey!] = local.copyWith(
            deletedAt: remoteDeletedAt as Object,
          );
          changed = true;
        } else if (payload != null) {
          // Remote is newer — update local from remote payload
          final updated = ProviderConfig.fromJson(payload);
          // Remove old key if the id (display-key) changed
          if (localKey != updated.id) {
            configs.remove(localKey);
          }
          configs[updated.id] = updated;
          changed = true;
        }
      } catch (e) {
        debugPrint('[ProvidersSyncHandler] Error applying change: $e');
      }
    }

    if (changed) {
      final encoded = jsonEncode(
        configs.map((k, v) => MapEntry(k, v.toJson())),
      );
      await prefs.setString(_providerConfigsKey, encoded);
    }
  }
}
