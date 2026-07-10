import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/models/quick_phrase.dart';
import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/services/sync/sync_category_handler.dart';

/// Sync handler for quick phrases (SharedPreferences-backed JSON list).
class QuickPhrasesSyncHandler extends SyncCategoryHandler {
  static const String _phrasesKey = 'quick_phrases_v1';

  @override
  SyncCategory get category => SyncCategory.quickPhrases;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    final results = <Map<String, dynamic>>[];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_phrasesKey);
    if (raw == null || raw.isEmpty) return results;

    List<QuickPhrase> phrases;
    try {
      final list = jsonDecode(raw) as List;
      phrases = list
          .map((e) => QuickPhrase.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[QuickPhrasesSyncHandler] Failed to decode phrases: $e');
      return results;
    }

    for (final phrase in phrases) {
      try {
        if (phrase.localOnly) continue;
        final updatedAt = phrase.updatedAt;
        if (updatedAt == null || updatedAt <= sinceCursor) continue;
        results.add({
          'recordId': phrase.id,
          'payload': phrase.toJson(),
          'updatedAt': updatedAt,
          if (phrase.deletedAt != null) 'deletedAt': phrase.deletedAt,
        });
      } catch (e) {
        debugPrint('[QuickPhrasesSyncHandler] Error collecting phrase: $e');
      }
    }

    return results;
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_phrasesKey);
    List<QuickPhrase> phrases = <QuickPhrase>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        phrases = list
            .map((e) => QuickPhrase.fromJson(e as Map<String, dynamic>))
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

        final localIdx = phrases.indexWhere((p) => p.id == recordId);

        if (localIdx == -1) {
          // New phrase from remote
          if (remoteDeletedAt != null) continue; // Already deleted — skip
          if (payload == null) continue;
          phrases.add(QuickPhrase.fromJson(payload));
          changed = true;
          continue;
        }

        // LWW: remote wins only if strictly newer
        final local = phrases[localIdx];
        final localUpdatedAt = local.updatedAt ?? 0;
        if (remoteUpdatedAt <= localUpdatedAt) continue;

        if (remoteDeletedAt != null) {
          // Remote says delete — soft-delete locally
          phrases[localIdx] = local.copyWith(deletedAt: remoteDeletedAt);
          changed = true;
        } else if (payload != null) {
          // Remote is newer — replace with remote version
          phrases[localIdx] = QuickPhrase.fromJson(payload);
          changed = true;
        }
      } catch (e) {
        debugPrint('[QuickPhrasesSyncHandler] Error applying change: $e');
      }
    }

    if (changed) {
      final encoded = jsonEncode(phrases.map((p) => p.toJson()).toList());
      await prefs.setString(_phrasesKey, encoded);
    }
  }
}
