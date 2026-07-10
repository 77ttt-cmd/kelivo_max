import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_max/core/models/sync_config.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/providers/sync_provider.dart';
import 'package:kelivo_max/core/services/sync/sync_api_client.dart';

void main() {
  group('SyncConfig category filtering', () {
    test('enabled categories are returned, disabled are excluded', () {
      final config = SyncConfig(
        enabled: true,
        categories: {
          SyncCategory.chats: true,
          SyncCategory.providers: false,
          SyncCategory.assistants: true,
          SyncCategory.mcp: false,
        },
      );

      final enabled = SyncCategory.values
          .where((c) => config.isCategoryEnabled(c))
          .toList();

      expect(enabled, contains(SyncCategory.chats));
      expect(enabled, contains(SyncCategory.assistants));
      expect(enabled, isNot(contains(SyncCategory.providers)));
      expect(enabled, isNot(contains(SyncCategory.mcp)));
    });

    test('explicitly false category is not enabled', () {
      final config = SyncConfig(
        enabled: true,
        categories: {SyncCategory.chats: false},
      );

      expect(config.isCategoryEnabled(SyncCategory.chats), isFalse);
    });

    test('unspecified category defaults to disabled', () {
      final config = SyncConfig(
        enabled: true,
        categories: {SyncCategory.chats: true},
      );

      // quickPhrases is not in the map — should be disabled.
      expect(config.isCategoryEnabled(SyncCategory.quickPhrases), isFalse);
    });

    test('default config has no categories enabled', () {
      const config = SyncConfig(enabled: true);

      final enabled = SyncCategory.values
          .where((c) => config.isCategoryEnabled(c))
          .toList();

      expect(enabled, isEmpty);
    });

    test('all categories enabled when all set to true', () {
      final config = SyncConfig(
        enabled: true,
        categories: {for (final c in SyncCategory.values) c: true},
      );

      final enabled = SyncCategory.values
          .where((c) => config.isCategoryEnabled(c))
          .toList();

      expect(enabled.length, SyncCategory.values.length);
    });
  });

  group('SyncConfig cursor and timestamp', () {
    test('copyWith updates lastSyncCursor', () {
      const config = SyncConfig(enabled: true, lastSyncCursor: 0);
      final updated = config.copyWith(lastSyncCursor: 42);

      expect(updated.lastSyncCursor, 42);
      expect(updated.enabled, isTrue);
    });

    test('copyWith updates lastSyncAt via factory', () {
      const config = SyncConfig(enabled: true);
      final ts = DateTime(2026, 7, 10).millisecondsSinceEpoch;
      final updated = config.copyWith(lastSyncAt: () => ts);

      expect(updated.lastSyncAt, ts);
    });

    test('copyWith preserves categories when not overridden', () {
      final config = SyncConfig(
        enabled: true,
        categories: {SyncCategory.chats: true, SyncCategory.files: true},
        lastSyncCursor: 5,
      );
      final updated = config.copyWith(lastSyncCursor: 10);

      expect(updated.isCategoryEnabled(SyncCategory.chats), isTrue);
      expect(updated.isCategoryEnabled(SyncCategory.files), isTrue);
      expect(updated.lastSyncCursor, 10);
    });

    test('copyWith can clear lastSyncAt to null', () {
      final config = SyncConfig(
        enabled: true,
        lastSyncAt: DateTime(2026).millisecondsSinceEpoch,
      );
      final cleared = config.copyWith(lastSyncAt: () => null);

      expect(cleared.lastSyncAt, isNull);
    });
  });

  group('SyncConfig JSON round-trip', () {
    test('toJson and fromJson preserve all fields', () {
      final original = SyncConfig(
        serverUrl: 'https://sync.example.com',
        username: 'alice',
        enabled: true,
        categories: {
          SyncCategory.chats: true,
          SyncCategory.providers: false,
          SyncCategory.assistants: true,
        },
        direction: SyncDirection.bidirectional,
        cloudExecutionEnabled: true,
        lastSyncCursor: 99,
        lastSyncAt: 1234567890,
      );

      final json = original.toJson();
      final restored = SyncConfig.fromJson(json);

      expect(restored.serverUrl, original.serverUrl);
      expect(restored.username, original.username);
      expect(restored.enabled, original.enabled);
      expect(
        restored.isCategoryEnabled(SyncCategory.chats),
        original.isCategoryEnabled(SyncCategory.chats),
      );
      expect(
        restored.isCategoryEnabled(SyncCategory.providers),
        original.isCategoryEnabled(SyncCategory.providers),
      );
      expect(
        restored.isCategoryEnabled(SyncCategory.assistants),
        original.isCategoryEnabled(SyncCategory.assistants),
      );
      expect(restored.direction, original.direction);
      expect(restored.cloudExecutionEnabled, original.cloudExecutionEnabled);
      expect(restored.lastSyncCursor, original.lastSyncCursor);
      expect(restored.lastSyncAt, original.lastSyncAt);
    });

    test('fromJsonString handles invalid JSON gracefully', () {
      final config = SyncConfig.fromJsonString('not valid json');

      expect(config.enabled, isFalse);
      expect(config.serverUrl, SyncConfig.defaultServerUrl);
      expect(config.lastSyncCursor, 0);
    });

    test('toJsonString and fromJsonString round-trip', () {
      final original = SyncConfig(
        serverUrl: 'https://sync.test',
        enabled: true,
        categories: {SyncCategory.settings: true},
        lastSyncCursor: 7,
      );

      final jsonStr = original.toJsonString();
      final restored = SyncConfig.fromJsonString(jsonStr);

      expect(restored.serverUrl, original.serverUrl);
      expect(restored.enabled, original.enabled);
      expect(restored.isCategoryEnabled(SyncCategory.settings), isTrue);
      expect(restored.lastSyncCursor, 7);
    });

    test('fromJson with missing fields uses defaults', () {
      final config = SyncConfig.fromJson(<String, dynamic>{});

      expect(config.serverUrl, SyncConfig.defaultServerUrl);
      expect(config.username, isEmpty);
      expect(config.enabled, isFalse);
      expect(config.direction, SyncDirection.pullOnly);
      expect(config.cloudExecutionEnabled, isFalse);
      expect(config.lastSyncCursor, 0);
      expect(config.lastSyncAt, isNull);
    });

    test('fromJson ignores unknown category keys', () {
      final config = SyncConfig.fromJson({
        'categories': {'nonexistent': true, 'chats': true},
      });

      expect(config.isCategoryEnabled(SyncCategory.chats), isTrue);
      // Unknown key should be silently skipped.
      final enabledCount = SyncCategory.values
          .where((c) => config.isCategoryEnabled(c))
          .length;
      expect(enabledCount, 1);
    });
  });

  group('PullChangesResult', () {
    test('constructs with entries and metadata', () {
      final result = PullChangesResult(
        entries: [
          {
            'category': 'chats',
            'recordId': 'r1',
            'payload': <String, dynamic>{},
            'updatedAt': 100,
          },
        ],
        latestSeq: 42,
        hasMore: false,
      );

      expect(result.entries.length, 1);
      expect(result.latestSeq, 42);
      expect(result.hasMore, isFalse);
    });

    test('empty entries list is valid', () {
      final result = PullChangesResult(
        entries: [],
        latestSeq: 0,
        hasMore: false,
      );

      expect(result.entries, isEmpty);
      expect(result.latestSeq, 0);
    });

    test('hasMore true signals pagination needed', () {
      final result = PullChangesResult(
        entries: [
          {'category': 'chats', 'recordId': 'r1', 'updatedAt': 1},
        ],
        latestSeq: 10,
        hasMore: true,
      );

      expect(result.hasMore, isTrue);
      expect(result.latestSeq, 10);
    });
  });

  group('SyncProvider initial state', () {
    test('starts in idle state', () {
      final provider = SyncProvider();

      expect(provider.state, SyncState.idle);
      expect(provider.lastMessage, isEmpty);
      expect(provider.conflictCount, 0);
    });

    test('syncNow without configure returns gracefully', () async {
      final provider = SyncProvider();
      await provider.syncNow();

      expect(provider.state, SyncState.idle);
      expect(provider.lastMessage, 'Sync not configured');
    });
  });

  group('SyncProvider pull orchestration entry grouping', () {
    // Test the grouping logic that syncNow uses: entries with unknown
    // categories or categories not in the enabled set should be skipped.

    test('entries with unknown category key are filtered out', () {
      // Simulate the grouping logic from SyncProvider.syncNow.
      final enabledCategories = [SyncCategory.chats, SyncCategory.assistants];
      final entries = <Map<String, dynamic>>[
        {'category': 'chats', 'recordId': 'r1'},
        {'category': 'unknown_cat', 'recordId': 'r2'},
        {'category': 'assistants', 'recordId': 'r3'},
      ];

      final byCategory = <SyncCategory, List<Map<String, dynamic>>>{};
      for (final entry in entries) {
        final catKey = entry['category'] as String?;
        if (catKey == null) continue;
        final cat = SyncCategoryExt.fromKey(catKey);
        if (cat == null) continue;
        if (!enabledCategories.contains(cat)) continue;
        byCategory.putIfAbsent(cat, () => []).add(entry);
      }

      expect(
        byCategory.keys,
        containsAll([SyncCategory.chats, SyncCategory.assistants]),
      );
      expect(byCategory[SyncCategory.chats]!.length, 1);
      expect(byCategory[SyncCategory.assistants]!.length, 1);
      expect(byCategory.length, 2); // No unknown_cat bucket.
    });

    test('entries with disabled category are skipped', () {
      final enabledCategories = [SyncCategory.chats];
      final entries = <Map<String, dynamic>>[
        {'category': 'chats', 'recordId': 'r1'},
        {'category': 'providers', 'recordId': 'r2'}, // Not enabled.
      ];

      final byCategory = <SyncCategory, List<Map<String, dynamic>>>{};
      for (final entry in entries) {
        final catKey = entry['category'] as String?;
        if (catKey == null) continue;
        final cat = SyncCategoryExt.fromKey(catKey);
        if (cat == null) continue;
        if (!enabledCategories.contains(cat)) continue;
        byCategory.putIfAbsent(cat, () => []).add(entry);
      }

      expect(byCategory.keys, [SyncCategory.chats]);
      expect(byCategory.containsKey(SyncCategory.providers), isFalse);
    });

    test('entries without category key are skipped', () {
      final enabledCategories = SyncCategory.values.toList();
      final entries = <Map<String, dynamic>>[
        {'recordId': 'r1'}, // No 'category' key.
        {'category': null, 'recordId': 'r2'},
      ];

      final byCategory = <SyncCategory, List<Map<String, dynamic>>>{};
      for (final entry in entries) {
        final catKey = entry['category'] as String?;
        if (catKey == null) continue;
        final cat = SyncCategoryExt.fromKey(catKey);
        if (cat == null) continue;
        if (!enabledCategories.contains(cat)) continue;
        byCategory.putIfAbsent(cat, () => []).add(entry);
      }

      expect(byCategory, isEmpty);
    });
  });
}
