import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kelivo_max/core/models/sync_config.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/providers/settings_provider.dart';

Future<void> _waitForSettingsLoad() async {
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider SyncConfig integration', () {
    test('defaults to disabled SyncConfig when no stored value', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();

      await _waitForSettingsLoad();

      expect(settings.syncConfig.enabled, false);
      expect(settings.syncConfig.serverUrl, SyncConfig.defaultServerUrl);
      expect(settings.syncConfig.direction, SyncDirection.pullOnly);
    });

    test('loads persisted SyncConfig from preferences', () async {
      final storedConfig = SyncConfig(
        serverUrl: 'https://sync.test.com',
        username: 'testuser',
        enabled: true,
        direction: SyncDirection.bidirectional,
        cloudExecutionEnabled: true,
        lastSyncCursor: 50,
        lastSyncAt: 9999999,
        categories: {SyncCategory.chats: true},
      );

      SharedPreferences.setMockInitialValues({
        'sync_config_v1': storedConfig.toJsonString(),
      });

      final settings = SettingsProvider();
      await _waitForSettingsLoad();

      expect(settings.syncConfig.serverUrl, 'https://sync.test.com');
      expect(settings.syncConfig.username, 'testuser');
      expect(settings.syncConfig.enabled, true);
      expect(settings.syncConfig.direction, SyncDirection.bidirectional);
      expect(settings.syncConfig.cloudExecutionEnabled, true);
      expect(settings.syncConfig.lastSyncCursor, 50);
      expect(settings.syncConfig.lastSyncAt, 9999999);
      expect(settings.syncConfig.isCategoryEnabled(SyncCategory.chats), true);
    });

    test(
      'falls back to default SyncConfig when stored JSON is malformed',
      () async {
        SharedPreferences.setMockInitialValues({
          'sync_config_v1': 'not valid json {{',
        });

        final settings = SettingsProvider();
        await _waitForSettingsLoad();

        expect(settings.syncConfig.enabled, false);
        expect(settings.syncConfig.serverUrl, SyncConfig.defaultServerUrl);
      },
    );

    test('setSyncConfig persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await _waitForSettingsLoad();

      final newConfig = SyncConfig(
        serverUrl: 'https://new.server',
        enabled: true,
        direction: SyncDirection.bidirectional,
      );
      await settings.setSyncConfig(newConfig);

      expect(settings.syncConfig.serverUrl, 'https://new.server');
      expect(settings.syncConfig.enabled, true);

      // Verify it was persisted to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('sync_config_v1');
      expect(stored, isNotNull);
      final decoded = jsonDecode(stored!) as Map<String, dynamic>;
      expect(decoded['serverUrl'], 'https://new.server');
      expect(decoded['enabled'], true);
    });

    test('setSyncConfig can disable sync', () async {
      final initialConfig = SyncConfig(
        serverUrl: 'https://sync.example.com',
        enabled: true,
      );
      SharedPreferences.setMockInitialValues({
        'sync_config_v1': initialConfig.toJsonString(),
      });
      final settings = SettingsProvider();
      await _waitForSettingsLoad();

      expect(settings.syncConfig.enabled, true);

      await settings.setSyncConfig(const SyncConfig());

      expect(settings.syncConfig.enabled, false);
      expect(settings.syncConfig.serverUrl, SyncConfig.defaultServerUrl);
    });
  });
}
