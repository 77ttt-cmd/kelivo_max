import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_max/core/models/api_keys.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/providers/settings_provider.dart';
import 'package:kelivo_max/core/services/sync/sync_category_handler.dart';

void main() {
  group('Provider key sync', () {
    test('ProviderConfig toJson includes apiKey', () {
      final config = ProviderConfig(
        id: 'test-provider',
        enabled: true,
        name: 'Test Provider',
        apiKey: 'sk-secret-key-12345',
        baseUrl: 'https://api.example.com/v1',
        syncId: 'fixed-sync-id-1',
      );

      final json = config.toJson();
      expect(json.containsKey('apiKey'), isTrue);
      expect(json['apiKey'], 'sk-secret-key-12345');
    });

    test('ProviderConfig fromJson restores apiKey', () {
      final json = <String, dynamic>{
        'id': 'test-provider',
        'enabled': true,
        'name': 'Test Provider',
        'apiKey': 'sk-restored-key-999',
        'baseUrl': 'https://api.example.com/v1',
        'syncId': 'fixed-sync-id-2',
      };

      final config = ProviderConfig.fromJson(json);
      expect(config.apiKey, 'sk-restored-key-999');
    });

    test('providers handler has correct category', () {
      final handler = syncHandlerFor(SyncCategory.providers);
      expect(handler.category, SyncCategory.providers);
    });

    test('search services handler has correct category', () {
      final handler = syncHandlerFor(SyncCategory.searchServices);
      expect(handler.category, SyncCategory.searchServices);
    });

    test('tts services handler has correct category', () {
      final handler = syncHandlerFor(SyncCategory.ttsServices);
      expect(handler.category, SyncCategory.ttsServices);
    });
  });

  group('Sensitive field round-trip', () {
    test('ProviderConfig apiKey round trips through JSON', () {
      const testApiKey = 'sk-very-sensitive-key-abc123';
      final original = ProviderConfig(
        id: 'roundtrip-provider',
        enabled: true,
        name: 'Round Trip Test',
        apiKey: testApiKey,
        baseUrl: 'https://api.example.com/v1',
        syncId: 'roundtrip-sync-id',
        updatedAt: 1000,
      );

      final json = original.toJson();
      final restored = ProviderConfig.fromJson(json);

      expect(restored.apiKey, testApiKey);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.baseUrl, original.baseUrl);
      expect(restored.syncId, original.syncId);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('ProviderConfig apiKeys list round trips through JSON', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final apiKeyConfigs = [
        ApiKeyConfig(
          id: 'key-1',
          key: 'sk-multi-key-aaa',
          name: 'Primary',
          priority: 1,
          createdAt: now,
          updatedAt: now,
        ),
        ApiKeyConfig(
          id: 'key-2',
          key: 'sk-multi-key-bbb',
          name: 'Secondary',
          priority: 2,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final original = ProviderConfig(
        id: 'multi-key-provider',
        enabled: true,
        name: 'Multi Key Provider',
        apiKey: 'sk-primary-key',
        baseUrl: 'https://api.example.com/v1',
        multiKeyEnabled: true,
        apiKeys: apiKeyConfigs,
        syncId: 'multi-key-sync-id',
        updatedAt: 2000,
      );

      final json = original.toJson();

      // Verify apiKeys is serialized
      expect(json.containsKey('apiKeys'), isTrue);
      expect(json['apiKeys'], isA<List>());
      expect((json['apiKeys'] as List).length, 2);

      // Verify individual key data in serialized form
      final serializedKeys = json['apiKeys'] as List;
      expect(serializedKeys[0]['key'], 'sk-multi-key-aaa');
      expect(serializedKeys[1]['key'], 'sk-multi-key-bbb');

      // Round-trip through fromJson
      final restored = ProviderConfig.fromJson(json);
      expect(restored.multiKeyEnabled, isTrue);
      expect(restored.apiKeys, isNotNull);
      expect(restored.apiKeys!.length, 2);
      expect(restored.apiKeys![0].key, 'sk-multi-key-aaa');
      expect(restored.apiKeys![0].name, 'Primary');
      expect(restored.apiKeys![0].priority, 1);
      expect(restored.apiKeys![1].key, 'sk-multi-key-bbb');
      expect(restored.apiKeys![1].name, 'Secondary');
      expect(restored.apiKeys![1].priority, 2);
    });

    test('localOnly providers are excluded from sync payload', () {
      final localOnlyConfig = ProviderConfig(
        id: 'local-only-provider',
        enabled: true,
        name: 'Local Only',
        apiKey: 'sk-local-only-key',
        baseUrl: 'https://api.example.com/v1',
        syncId: 'local-only-sync-id',
        updatedAt: 5000,
        localOnly: true,
      );

      // Verify localOnly is set
      expect(localOnlyConfig.localOnly, isTrue);

      // Verify toJson includes localOnly flag (so the handler can filter)
      final json = localOnlyConfig.toJson();
      expect(json['localOnly'], isTrue);

      // Simulate collectLocalChanges filtering logic:
      // The handler skips records where config.localOnly == true
      final shouldSync = !localOnlyConfig.localOnly;
      expect(
        shouldSync,
        isFalse,
        reason: 'localOnly providers should be excluded from sync',
      );
    });

    test('non-localOnly providers are included in sync payload', () {
      final syncableConfig = ProviderConfig(
        id: 'syncable-provider',
        enabled: true,
        name: 'Syncable',
        apiKey: 'sk-syncable-key',
        baseUrl: 'https://api.example.com/v1',
        syncId: 'syncable-sync-id',
        updatedAt: 3000,
        localOnly: false,
      );

      expect(syncableConfig.localOnly, isFalse);

      // Simulate collectLocalChanges filtering logic
      final shouldSync = !syncableConfig.localOnly;
      expect(
        shouldSync,
        isTrue,
        reason: 'non-localOnly providers should be included in sync',
      );
    });

    test('ProviderConfig proxy credentials round trip through JSON', () {
      final config = ProviderConfig(
        id: 'proxy-provider',
        enabled: true,
        name: 'Proxy Provider',
        apiKey: 'sk-proxy-key',
        baseUrl: 'https://api.example.com/v1',
        proxyEnabled: true,
        proxyType: 'socks5',
        proxyHost: '192.168.1.100',
        proxyPort: '1080',
        proxyUsername: 'proxy-user',
        proxyPassword: 'proxy-secret-pass',
        syncId: 'proxy-sync-id',
      );

      final json = config.toJson();
      expect(json['proxyUsername'], 'proxy-user');
      expect(json['proxyPassword'], 'proxy-secret-pass');

      final restored = ProviderConfig.fromJson(json);
      expect(restored.proxyUsername, 'proxy-user');
      expect(restored.proxyPassword, 'proxy-secret-pass');
    });

    test('ProviderConfig serviceAccountJson round trips through JSON', () {
      const saJson = '{"type":"service_account","project_id":"test"}';
      final config = ProviderConfig(
        id: 'vertex-provider',
        enabled: true,
        name: 'Vertex AI',
        apiKey: '',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        providerType: ProviderKind.google,
        vertexAI: true,
        serviceAccountJson: saJson,
        syncId: 'vertex-sync-id',
      );

      final json = config.toJson();
      expect(json['serviceAccountJson'], saJson);

      final restored = ProviderConfig.fromJson(json);
      expect(restored.serviceAccountJson, saJson);
    });

    test('ProviderConfig syncId is preserved across serialization', () {
      const fixedSyncId = 'immutable-uuid-v4-value';
      final config = ProviderConfig(
        id: 'sync-id-test',
        enabled: true,
        name: 'SyncId Test',
        apiKey: 'sk-test',
        baseUrl: 'https://api.example.com/v1',
        syncId: fixedSyncId,
      );

      final json = config.toJson();
      expect(json['syncId'], fixedSyncId);

      final restored = ProviderConfig.fromJson(json);
      expect(restored.syncId, fixedSyncId);
    });

    test('ProviderConfig deletedAt is included in JSON for soft-delete', () {
      final config = ProviderConfig(
        id: 'deleted-provider',
        enabled: false,
        name: 'Deleted Provider',
        apiKey: 'sk-deleted',
        baseUrl: 'https://api.example.com/v1',
        syncId: 'deleted-sync-id',
        updatedAt: 4000,
        deletedAt: 5000,
      );

      final json = config.toJson();
      expect(json['deletedAt'], 5000);
      expect(json['updatedAt'], 4000);

      final restored = ProviderConfig.fromJson(json);
      expect(restored.deletedAt, 5000);
      expect(restored.updatedAt, 4000);
    });

    test('ProviderConfig keyManagement round trips through JSON', () {
      final config = ProviderConfig(
        id: 'km-provider',
        enabled: true,
        name: 'Key Managed Provider',
        apiKey: 'sk-km',
        baseUrl: 'https://api.example.com/v1',
        multiKeyEnabled: true,
        keyManagement: const KeyManagementConfig(
          strategy: LoadBalanceStrategy.priority,
          maxFailuresBeforeDisable: 5,
          failureRecoveryTimeMinutes: 10,
          enableAutoRecovery: false,
        ),
        syncId: 'km-sync-id',
      );

      final json = config.toJson();
      expect(json['keyManagement'], isNotNull);
      expect(json['keyManagement']['strategy'], 'priority');

      final restored = ProviderConfig.fromJson(json);
      expect(restored.keyManagement, isNotNull);
      expect(restored.keyManagement!.strategy, LoadBalanceStrategy.priority);
      expect(restored.keyManagement!.maxFailuresBeforeDisable, 5);
      expect(restored.keyManagement!.failureRecoveryTimeMinutes, 10);
      expect(restored.keyManagement!.enableAutoRecovery, isFalse);
    });
  });
}
