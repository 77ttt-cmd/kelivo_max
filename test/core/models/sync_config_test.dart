import 'package:flutter_test/flutter_test.dart';

import 'package:kelivo_max/core/models/sync_config.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';

void main() {
  group('SyncConfig', () {
    test('default constructor creates valid defaults', () {
      const config = SyncConfig();
      expect(config.serverUrl, '');
      expect(config.username, '');
      expect(config.enabled, false);
      expect(config.categories, isEmpty);
      expect(config.direction, SyncDirection.pullOnly);
      expect(config.cloudExecutionEnabled, false);
      expect(config.lastSyncCursor, 0);
      expect(config.lastSyncAt, isNull);
    });

    test('JSON round trip preserves all fields', () {
      final original = SyncConfig(
        serverUrl: 'https://sync.example.com',
        username: 'alice',
        enabled: true,
        categories: {
          SyncCategory.chats: true,
          SyncCategory.files: false,
          SyncCategory.providers: true,
        },
        direction: SyncDirection.bidirectional,
        cloudExecutionEnabled: true,
        lastSyncCursor: 42,
        lastSyncAt: 1700000000000,
      );

      final json = original.toJson();
      final restored = SyncConfig.fromJson(json);

      expect(restored.serverUrl, original.serverUrl);
      expect(restored.username, original.username);
      expect(restored.enabled, original.enabled);
      expect(restored.direction, original.direction);
      expect(restored.cloudExecutionEnabled, original.cloudExecutionEnabled);
      expect(restored.lastSyncCursor, original.lastSyncCursor);
      expect(restored.lastSyncAt, original.lastSyncAt);
      expect(restored.isCategoryEnabled(SyncCategory.chats), true);
      expect(restored.isCategoryEnabled(SyncCategory.files), false);
      expect(restored.isCategoryEnabled(SyncCategory.providers), true);
    });

    test('fromJson with missing fields uses defaults', () {
      final config = SyncConfig.fromJson(<String, dynamic>{});
      expect(config.serverUrl, '');
      expect(config.username, '');
      expect(config.enabled, false);
      expect(config.categories, isEmpty);
      expect(config.direction, SyncDirection.pullOnly);
      expect(config.cloudExecutionEnabled, false);
      expect(config.lastSyncCursor, 0);
      expect(config.lastSyncAt, isNull);
    });

    test('fromJson with unknown category keys ignores them', () {
      final config = SyncConfig.fromJson({
        'categories': {
          'chats': true,
          'unknownCategory': true,
          'anotherFake': false,
        },
      });
      expect(config.isCategoryEnabled(SyncCategory.chats), true);
      // Unknown keys should have been silently ignored
      expect(config.categories.length, 1);
    });

    test('fromJson with invalid direction falls back to pullOnly', () {
      final config = SyncConfig.fromJson({'direction': 'invalidDirection'});
      expect(config.direction, SyncDirection.pullOnly);
    });

    test('fromJsonString with malformed JSON returns default SyncConfig', () {
      final config = SyncConfig.fromJsonString('{not valid json!!!');
      expect(config.serverUrl, '');
      expect(config.enabled, false);
      expect(config.direction, SyncDirection.pullOnly);
      expect(config.lastSyncCursor, 0);
    });

    test('fromJsonString round trip preserves data', () {
      final original = SyncConfig(
        serverUrl: 'https://example.com',
        enabled: true,
        direction: SyncDirection.bidirectional,
      );

      final jsonString = original.toJsonString();
      final restored = SyncConfig.fromJsonString(jsonString);

      expect(restored.serverUrl, original.serverUrl);
      expect(restored.enabled, original.enabled);
      expect(restored.direction, original.direction);
    });

    test('copyWith replaces specified fields only', () {
      const original = SyncConfig();
      final modified = original.copyWith(
        serverUrl: 'https://new.example.com',
        enabled: true,
        direction: SyncDirection.bidirectional,
        lastSyncAt: () => 9999,
      );

      expect(modified.serverUrl, 'https://new.example.com');
      expect(modified.enabled, true);
      expect(modified.direction, SyncDirection.bidirectional);
      expect(modified.lastSyncAt, 9999);
      // Unchanged fields retain defaults
      expect(modified.username, '');
      expect(modified.cloudExecutionEnabled, false);
      expect(modified.lastSyncCursor, 0);
    });

    test('copyWith lastSyncAt can be set to null', () {
      final original = SyncConfig(lastSyncAt: 12345);
      final modified = original.copyWith(lastSyncAt: () => null);
      expect(modified.lastSyncAt, isNull);
    });

    test('isCategoryEnabled returns false for all categories when empty', () {
      const config = SyncConfig();
      for (final cat in SyncCategory.values) {
        expect(config.isCategoryEnabled(cat), false);
      }
    });

    test('isCategoryEnabled returns correct values for set categories', () {
      final config = SyncConfig(
        categories: {SyncCategory.chats: true, SyncCategory.files: false},
      );
      expect(config.isCategoryEnabled(SyncCategory.chats), true);
      expect(config.isCategoryEnabled(SyncCategory.files), false);
      // Not in the map at all
      expect(config.isCategoryEnabled(SyncCategory.providers), false);
    });

    test('fromJson with non-bool category values ignores them', () {
      final config = SyncConfig.fromJson({
        'categories': {
          'chats': true,
          'files': 'yes', // not a bool
          'providers': 42, // not a bool
        },
      });
      expect(config.isCategoryEnabled(SyncCategory.chats), true);
      expect(config.categories.length, 1);
    });
  });
}
