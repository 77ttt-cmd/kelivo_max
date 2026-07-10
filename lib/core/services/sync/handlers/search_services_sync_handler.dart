import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:Kelivo/core/services/sync/sync_category_handler.dart';

/// Sync handler for search service configurations (SharedPreferences-backed).
///
/// [SearchServiceOptions] does not carry its own `updatedAt` / `deletedAt`,
/// so this handler relies on the change-level timestamps for LWW decisions.
/// When no local timestamp is available, a remote change that is present
/// will always overwrite the matching local entry.
class SearchServicesSyncHandler extends SyncCategoryHandler {
  static const String _searchServicesKey = 'search_services_v1';

  @override
  SyncCategory get category => SyncCategory.searchServices;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    // SearchServiceOptions does not carry updatedAt / deletedAt / localOnly
    // metadata. Without per-record timestamps, we cannot determine which
    // records changed since sinceCursor. Return empty until the model is
    // extended with sync metadata.
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_searchServicesKey);
    List<SearchServiceOptions> services = <SearchServiceOptions>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        services = list
            .map(
              (e) => SearchServiceOptions.fromJson(
                (e as Map).cast<String, dynamic>(),
              ),
            )
            .toList();
      } catch (_) {
        // keep empty list
      }
    }

    // Serialize back for comparison — map id -> json for quick lookup.
    final Map<String, int> indexById = {
      for (int i = 0; i < services.length; i++) services[i].id: i,
    };

    bool changed = false;

    for (final change in changes) {
      try {
        final recordId = change['recordId'] as String;
        final payload = change['payload'] as Map<String, dynamic>?;
        final remoteDeletedAt = change['deletedAt'] as int?;

        final localIdx = indexById[recordId];

        if (localIdx == null) {
          // New service from remote
          if (remoteDeletedAt != null) continue; // Already deleted — skip
          if (payload == null) continue;
          final svc = SearchServiceOptions.fromJson(payload);
          services.add(svc);
          indexById[svc.id] = services.length - 1;
          changed = true;
          continue;
        }

        if (remoteDeletedAt != null) {
          // Remote says delete — remove locally
          services.removeAt(localIdx);
          // Rebuild index
          indexById.clear();
          for (int i = 0; i < services.length; i++) {
            indexById[services[i].id] = i;
          }
          changed = true;
        } else if (payload != null) {
          // SearchServiceOptions has no local updatedAt — always accept remote
          services[localIdx] = SearchServiceOptions.fromJson(payload);
          changed = true;
        }
      } catch (e) {
        debugPrint('[SearchServicesSyncHandler] Error applying change: $e');
      }
    }

    if (changed) {
      final encoded = jsonEncode(services.map((e) => e.toJson()).toList());
      await prefs.setString(_searchServicesKey, encoded);
    }
  }
}
