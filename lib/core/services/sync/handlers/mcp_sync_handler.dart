import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/providers/mcp_provider.dart';
import 'package:kelivo_max/core/services/sync/sync_category_handler.dart';

/// Sync handler for MCP server configurations (SharedPreferences-backed).
class McpSyncHandler extends SyncCategoryHandler {
  static const String _prefsKey = 'mcp_servers_v1';

  @override
  SyncCategory get category => SyncCategory.mcp;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    final results = <Map<String, dynamic>>[];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return results;

    List<McpServerConfig> servers;
    try {
      servers = (jsonDecode(raw) as List)
          .map(
            (e) => McpServerConfig.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList();
    } catch (e) {
      debugPrint('[McpSyncHandler] Failed to decode servers: $e');
      return results;
    }

    for (final server in servers) {
      try {
        if (server.localOnly) continue;
        final updatedAt = server.updatedAt;
        if (updatedAt == null || updatedAt <= sinceCursor) continue;
        results.add({
          'recordId': server.id,
          'payload': server.toJson(),
          'updatedAt': updatedAt,
          if (server.deletedAt != null) 'deletedAt': server.deletedAt,
        });
      } catch (e) {
        debugPrint('[McpSyncHandler] Error collecting server: $e');
      }
    }

    return results;
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    List<McpServerConfig> servers = <McpServerConfig>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        servers = (jsonDecode(raw) as List)
            .map(
              (e) =>
                  McpServerConfig.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
      } catch (_) {
        // keep empty list
      }
    }

    bool changed = false;

    for (final change in changes) {
      try {
        final recordId = change['recordId'] as String;
        final payload = change['payload'] as Map<String, dynamic>?;
        final remoteUpdatedAt = change['updatedAt'] as int;
        final remoteDeletedAt = change['deletedAt'] as int?;

        final localIdx = servers.indexWhere((s) => s.id == recordId);

        if (localIdx == -1) {
          // New server from remote
          if (remoteDeletedAt != null) continue; // Already deleted — skip
          if (payload == null) continue;
          servers.add(McpServerConfig.fromJson(payload));
          changed = true;
          continue;
        }

        // LWW: remote wins only if strictly newer
        final local = servers[localIdx];
        final localUpdatedAt = local.updatedAt ?? 0;
        if (remoteUpdatedAt <= localUpdatedAt) continue;

        if (remoteDeletedAt != null) {
          // Remote says delete — soft-delete locally
          servers[localIdx] = local.copyWith(deletedAt: remoteDeletedAt);
          changed = true;
        } else if (payload != null) {
          // Remote is newer — replace with remote version
          servers[localIdx] = McpServerConfig.fromJson(payload);
          changed = true;
        }
      } catch (e) {
        debugPrint('[McpSyncHandler] Error applying change: $e');
      }
    }

    if (changed) {
      final encoded = jsonEncode(servers.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
    }
  }
}
