import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/sync/sync_ledger.dart';

void main() {
  late Directory tempDir;
  late SyncLedger ledger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_ledger_test_');
    Hive.init(tempDir.path);
    ledger = SyncLedger();
    await ledger.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SyncLedger', () {
    test('starts with zero entries', () {
      expect(ledger.allEntries(), isEmpty);
    });

    test('append stores a record entry', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-1',
        direction: 'pull',
        sessionId: 'session-abc',
      );

      final entries = ledger.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first['category'], 'chats');
      expect(entries.first['recordId'], 'chat-1');
      expect(entries.first['direction'], 'pull');
      expect(entries.first['sessionId'], 'session-abc');
      expect(entries.first['ts'], isA<int>());
    });

    test('append overwrites entry with same category::recordId key', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-1',
        direction: 'pull',
        sessionId: 'session-1',
      );
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-1',
        direction: 'push',
        sessionId: 'session-2',
      );

      final entries = ledger.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first['direction'], 'push');
      expect(entries.first['sessionId'], 'session-2');
    });

    test('append different categories are separate entries', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'id-1',
        direction: 'pull',
        sessionId: 's1',
      );
      await ledger.append(
        category: SyncCategory.providers,
        recordId: 'id-1',
        direction: 'pull',
        sessionId: 's1',
      );

      expect(ledger.allEntries(), hasLength(2));
    });

    test('appendFile stores a file entry', () async {
      await ledger.appendFile(
        fileHash: 'abc123',
        path: '/tmp/test/file.png',
        direction: 'pull',
        sessionId: 'session-xyz',
      );

      final entries = ledger.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first['category'], 'files');
      expect(entries.first['recordId'], 'abc123');
      expect(entries.first['fileHash'], 'abc123');
      expect(entries.first['path'], '/tmp/test/file.png');
      expect(entries.first['direction'], 'pull');
      expect(entries.first['sessionId'], 'session-xyz');
      expect(entries.first['ts'], isA<int>());
    });

    test('appendFile overwrites entry with same fileHash', () async {
      await ledger.appendFile(
        fileHash: 'abc123',
        path: '/old/path.png',
        direction: 'pull',
        sessionId: 's1',
      );
      await ledger.appendFile(
        fileHash: 'abc123',
        path: '/new/path.png',
        direction: 'push',
        sessionId: 's2',
      );

      final entries = ledger.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first['path'], '/new/path.png');
    });

    test('clear removes all entries', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'c1',
        direction: 'pull',
        sessionId: 's1',
      );
      await ledger.append(
        category: SyncCategory.assistants,
        recordId: 'a1',
        direction: 'push',
        sessionId: 's1',
      );
      await ledger.appendFile(
        fileHash: 'f1',
        path: '/f1.png',
        direction: 'pull',
        sessionId: 's1',
      );

      expect(ledger.allEntries(), hasLength(3));

      await ledger.clear();
      expect(ledger.allEntries(), isEmpty);
    });

    test('multiple record and file entries coexist', () async {
      await ledger.append(
        category: SyncCategory.chats,
        recordId: 'chat-1',
        direction: 'pull',
        sessionId: 's1',
      );
      await ledger.append(
        category: SyncCategory.providers,
        recordId: 'prov-1',
        direction: 'push',
        sessionId: 's1',
      );
      await ledger.appendFile(
        fileHash: 'file-hash-1',
        path: '/tmp/f1.bin',
        direction: 'pull',
        sessionId: 's1',
      );

      final entries = ledger.allEntries();
      expect(entries, hasLength(3));

      final categories = entries.map((e) => e['category']).toSet();
      expect(categories, containsAll(['chats', 'providers', 'files']));
    });
  });

  group('SyncLedger without init', () {
    test('operations are no-ops when box is not opened', () async {
      final uninitLedger = SyncLedger();
      // These should not throw
      await uninitLedger.append(
        category: SyncCategory.chats,
        recordId: 'x',
        direction: 'pull',
        sessionId: 's',
      );
      await uninitLedger.appendFile(
        fileHash: 'x',
        path: '/x',
        direction: 'pull',
        sessionId: 's',
      );
      expect(uninitLedger.allEntries(), isEmpty);
      await uninitLedger.clear(); // should not throw
    });
  });
}
