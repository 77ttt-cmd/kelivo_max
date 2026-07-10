import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kelivo_max/core/models/sync_config.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/sync/incognito_wipe.dart';
import 'package:kelivo_max/core/services/sync/sync_credential_store.dart';
import 'package:kelivo_max/core/services/sync/sync_ledger.dart';

/// Fake credential store that extends SyncCredentialStore and overrides
/// all methods to avoid platform-dependent FlutterSecureStorage calls.
class _FakeCredentialStore extends SyncCredentialStore {
  bool cleared = false;

  @override
  Future<void> clearAll() async {
    cleared = true;
  }

  @override
  Future<void> savePassword(String password) async {}

  @override
  Future<String?> readPassword() async => null;

  @override
  Future<void> deletePassword() async {}

  @override
  Future<void> saveAccessToken(String token) async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<void> deleteAccessToken() async {}

  @override
  Future<void> saveRefreshToken(String token) async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> deleteRefreshToken() async {}
}

void main() {
  late Directory tempDir;
  late SyncLedger ledger;
  late _FakeCredentialStore fakeCredentialStore;
  SyncConfig? capturedConfig;
  late IncognitoWipe wipe;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('incognito_wipe_test_');
    Hive.init(tempDir.path);
    ledger = SyncLedger();
    await ledger.init();
    fakeCredentialStore = _FakeCredentialStore();
    capturedConfig = null;
    wipe = IncognitoWipe(
      ledger: ledger,
      credentialStore: fakeCredentialStore,
      resetSyncConfig: (config) async {
        capturedConfig = config;
      },
    );
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('IncognitoWipe preview', () {
    test('returns correct category counts', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-1',
        direction: 'pull',
        sessionId: 's1',
      );
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-2',
        direction: 'pull',
        sessionId: 's1',
      );
      await ledger.appendFile(
        fileHash: 'hash-1',
        path: '/tmp/opencode/nonexistent_test_file.png',
        direction: 'pull',
        sessionId: 's1',
      );

      final preview = wipe.preview();
      expect(preview.totalCount, 3);
      expect(preview.categoryCounts[SyncCategory.chats], 2);
      expect(preview.categoryCounts[SyncCategory.files], 1);
      expect(preview.fileCount, 1);
    });

    test('returns zero counts when ledger is empty', () {
      final preview = wipe.preview();
      expect(preview.totalCount, 0);
      expect(preview.fileCount, 0);
      expect(preview.categoryCounts, isEmpty);
    });

    test('is side-effect free (ledger not cleared after preview)', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-1',
        direction: 'pull',
        sessionId: 's1',
      );

      wipe.preview();
      wipe.preview();

      expect(ledger.allEntries(), hasLength(1));
      expect(fakeCredentialStore.cleared, false);
      expect(capturedConfig, isNull);
    });
  });

  group('IncognitoWipe run', () {
    test('clears ledger', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-1',
        direction: 'pull',
        sessionId: 's1',
      );
      expect(ledger.allEntries(), hasLength(1));

      await wipe.run();

      expect(ledger.allEntries(), isEmpty);
    });

    test('clears credentials and resets config to disabled default', () async {
      await ledger.append(
        category: SyncCategory.providers,
        recordId: 'provider-1',
        direction: 'push',
        sessionId: 's1',
      );

      await wipe.run();

      expect(fakeCredentialStore.cleared, true);
      expect(capturedConfig, isNotNull);
      expect(capturedConfig!.enabled, false);
      expect(capturedConfig!.serverUrl, '');
      expect(capturedConfig!.username, '');
    });

    test('deletes synced files from disk', () async {
      final testFile = File('${tempDir.path}/synced_file.txt');
      await testFile.writeAsString('synced content');
      expect(testFile.existsSync(), isTrue);

      await ledger.appendFile(
        fileHash: 'hash1',
        path: testFile.path,
        direction: 'pull',
        sessionId: 's1',
      );

      await wipe.run();

      expect(testFile.existsSync(), isFalse);
    });

    test('handles already-deleted files gracefully', () async {
      await ledger.appendFile(
        fileHash: 'hash-nonexist',
        path: '/nonexistent/path/file.txt',
        direction: 'pull',
        sessionId: 's1',
      );

      await wipe.run();

      expect(ledger.allEntries(), isEmpty);
      expect(fakeCredentialStore.cleared, true);
    });

    test('can be called twice without error (idempotent)', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-1',
        direction: 'pull',
        sessionId: 's1',
      );

      await wipe.run();
      fakeCredentialStore.cleared = false;
      capturedConfig = null;

      await wipe.run();

      expect(ledger.allEntries(), isEmpty);
      expect(fakeCredentialStore.cleared, true);
      expect(capturedConfig, isNotNull);
    });

    test('handles empty ledger gracefully', () async {
      await wipe.run();

      expect(ledger.allEntries(), isEmpty);
      expect(fakeCredentialStore.cleared, true);
      expect(capturedConfig, isNotNull);
      expect(capturedConfig!.enabled, false);
    });
  });
}
