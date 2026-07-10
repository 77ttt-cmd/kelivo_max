import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/tts/network_tts.dart';
import 'package:kelivo_max/core/services/sync/sync_category_handler.dart';

/// Sync handler for TTS service configurations (SharedPreferences-backed).
///
/// [TtsServiceOptions] does not carry its own `updatedAt` / `deletedAt`,
/// so this handler relies on the change-level timestamps for LWW decisions.
/// When no local timestamp is available, a remote change will always overwrite
/// the matching local entry.
class TtsServicesSyncHandler extends SyncCategoryHandler {
  static const String _ttsServicesKey = 'tts_services_v1';

  @override
  SyncCategory get category => SyncCategory.ttsServices;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    // TtsServiceOptions does not carry updatedAt / deletedAt / localOnly
    // metadata. Without per-record timestamps, we cannot determine which
    // records changed since sinceCursor. Return empty until the model is
    // extended with sync metadata.
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ttsServicesKey);
    List<TtsServiceOptions> services = <TtsServiceOptions>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        services = list
            .map(
              (e) => TtsServiceOptions.fromJson(
                (e as Map).cast<String, dynamic>(),
              ),
            )
            .toList();
      } catch (_) {
        // keep empty list
      }
    }

    // Index by id for fast lookup.
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
          final svc = TtsServiceOptions.fromJson(payload);
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
          // TtsServiceOptions has no local updatedAt — always accept remote
          services[localIdx] = TtsServiceOptions.fromJson(payload);
          changed = true;
        }
      } catch (e) {
        debugPrint('[TtsServicesSyncHandler] Error applying change: $e');
      }
    }

    if (changed) {
      final encoded = jsonEncode(services.map((e) => e.toJson()).toList());
      await prefs.setString(_ttsServicesKey, encoded);
    }
  }
}
