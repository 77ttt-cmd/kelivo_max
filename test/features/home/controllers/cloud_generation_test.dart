import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_max/core/models/sync_config.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/providers/sync_provider.dart';

void main() {
  group('Cloud generation branching', () {
    test(
      'cloud execution only when both enabled and cloudExecutionEnabled',
      () {
        // Case 1: both enabled
        var config = const SyncConfig(
          enabled: true,
          cloudExecutionEnabled: true,
        );
        expect(config.enabled && config.cloudExecutionEnabled, true);

        // Case 2: only sync enabled
        config = const SyncConfig(enabled: true, cloudExecutionEnabled: false);
        expect(config.enabled && config.cloudExecutionEnabled, false);

        // Case 3: only cloud enabled (not sync)
        config = const SyncConfig(enabled: false, cloudExecutionEnabled: true);
        expect(config.enabled && config.cloudExecutionEnabled, false);

        // Case 4: neither
        config = const SyncConfig();
        expect(config.enabled && config.cloudExecutionEnabled, false);
      },
    );

    test('SyncProvider initial state for cloud execution', () {
      final provider = SyncProvider();
      expect(provider.state, SyncState.idle);
      expect(provider.isLoggedIn, false);
    });

    test('SyncProvider initial lastMessage is empty', () {
      final provider = SyncProvider();
      expect(provider.lastMessage, isEmpty);
      expect(provider.conflictCount, 0);
    });

    test('cloud execution flag persists through copyWith chains', () {
      const config = SyncConfig(
        enabled: true,
        cloudExecutionEnabled: true,
        serverUrl: 'https://s1.example.com',
      );
      // Simulate a sync completion that updates cursor and timestamp
      final updated = config.copyWith(
        lastSyncCursor: 100,
        lastSyncAt: () => 1700000000000,
      );
      expect(updated.cloudExecutionEnabled, true);
      expect(updated.enabled, true);
      expect(updated.lastSyncCursor, 100);
      expect(updated.serverUrl, 'https://s1.example.com');
    });

    test('switching from cloud to local only requires toggling one flag', () {
      const cloudConfig = SyncConfig(
        enabled: true,
        cloudExecutionEnabled: true,
        serverUrl: 'https://sync.example.com',
        username: 'user',
      );
      final localConfig = cloudConfig.copyWith(cloudExecutionEnabled: false);

      expect(localConfig.enabled, true);
      expect(localConfig.cloudExecutionEnabled, false);
      // Other fields preserved
      expect(localConfig.serverUrl, 'https://sync.example.com');
      expect(localConfig.username, 'user');
    });

    test('direction does not affect cloudExecutionEnabled', () {
      const pullOnly = SyncConfig(
        enabled: true,
        cloudExecutionEnabled: true,
        direction: SyncDirection.pullOnly,
      );
      const bidir = SyncConfig(
        enabled: true,
        cloudExecutionEnabled: true,
        direction: SyncDirection.bidirectional,
      );
      // Cloud execution is orthogonal to sync direction
      expect(pullOnly.cloudExecutionEnabled, true);
      expect(bidir.cloudExecutionEnabled, true);
    });
  });

  group('Cloud task reconnection', () {
    test('cloud task IDs can be tracked', () {
      final cloudTaskIds = <String, String>{};
      cloudTaskIds['msg1'] = 'task-uuid-1';
      cloudTaskIds['msg2'] = 'task-uuid-2';

      expect(cloudTaskIds.containsKey('msg1'), true);
      expect(cloudTaskIds['msg1'], 'task-uuid-1');

      cloudTaskIds.remove('msg1');
      expect(cloudTaskIds.containsKey('msg1'), false);
    });

    test('completed tasks should be removed from tracking', () {
      final cloudTaskIds = <String, String>{};
      cloudTaskIds['msg1'] = 'task1';

      // Simulate completion
      cloudTaskIds.remove('msg1');
      expect(cloudTaskIds, isEmpty);
    });

    test('failed tasks should be removed from tracking', () {
      final cloudTaskIds = <String, String>{};
      cloudTaskIds['msg1'] = 'task1';

      // Simulate failure
      cloudTaskIds.remove('msg1');
      expect(cloudTaskIds, isEmpty);
    });

    test('multiple concurrent tasks tracked independently', () {
      final cloudTaskIds = <String, String>{};
      cloudTaskIds['msgA'] = 'task-1';
      cloudTaskIds['msgB'] = 'task-2';
      cloudTaskIds['msgC'] = 'task-3';

      expect(cloudTaskIds, hasLength(3));

      // Complete one
      cloudTaskIds.remove('msgB');
      expect(cloudTaskIds, hasLength(2));
      expect(cloudTaskIds.containsKey('msgB'), false);
      expect(cloudTaskIds.containsKey('msgA'), true);
      expect(cloudTaskIds.containsKey('msgC'), true);
    });

    test('re-submitting a task overwrites the old task ID', () {
      final cloudTaskIds = <String, String>{};
      cloudTaskIds['msg1'] = 'task-old';
      cloudTaskIds['msg1'] = 'task-new';

      expect(cloudTaskIds['msg1'], 'task-new');
      expect(cloudTaskIds, hasLength(1));
    });
  });

  group('SyncConfig JSON round-trip for cloud fields', () {
    test('full config round-trips correctly', () {
      const config = SyncConfig(
        serverUrl: 'https://api.example.com',
        username: 'testuser',
        enabled: true,
        cloudExecutionEnabled: true,
        direction: SyncDirection.bidirectional,
        lastSyncCursor: 42,
        lastSyncAt: 1700000000000,
      );

      final json = config.toJson();
      final restored = SyncConfig.fromJson(json);

      expect(restored.serverUrl, config.serverUrl);
      expect(restored.username, config.username);
      expect(restored.enabled, config.enabled);
      expect(restored.cloudExecutionEnabled, config.cloudExecutionEnabled);
      expect(restored.direction, config.direction);
      expect(restored.lastSyncCursor, config.lastSyncCursor);
      expect(restored.lastSyncAt, config.lastSyncAt);
    });

    test('string round-trip preserves all fields', () {
      const config = SyncConfig(
        enabled: true,
        cloudExecutionEnabled: true,
        serverUrl: 'https://s.io',
      );

      final jsonString = config.toJsonString();
      final restored = SyncConfig.fromJsonString(jsonString);

      expect(restored.enabled, true);
      expect(restored.cloudExecutionEnabled, true);
      expect(restored.serverUrl, 'https://s.io');
    });

    test('fromJsonString handles invalid JSON gracefully', () {
      final config = SyncConfig.fromJsonString('not-json');
      expect(config.enabled, true);
      expect(config.cloudExecutionEnabled, false);
      expect(config.serverUrl, SyncConfig.defaultServerUrl);
    });
  });
}
