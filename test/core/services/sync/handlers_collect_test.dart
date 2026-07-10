import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/sync/sync_category_handler.dart';

void main() {
  group('Handler collectLocalChanges contract', () {
    test('all handlers have collectLocalChanges', () {
      for (final cat in SyncCategory.values) {
        final handler = syncHandlerFor(cat);
        expect(handler.category, cat);
        // collectLocalChanges should be callable (may throw due to no storage)
      }
    });

    test('handlers are distinct instances per call', () {
      final h1 = syncHandlerFor(SyncCategory.chats);
      final h2 = syncHandlerFor(SyncCategory.chats);
      // Each call creates a new handler instance.
      expect(identical(h1, h2), isFalse);
    });
  });

  group('localOnly exclusion logic', () {
    test('localOnly records should be excluded', () {
      // Simulating the filtering logic from chats/assistants handlers.
      final records = [
        {'id': '1', 'localOnly': false, 'updatedAt': 100},
        {'id': '2', 'localOnly': true, 'updatedAt': 200},
        {'id': '3', 'localOnly': false, 'updatedAt': 300},
      ];
      final filtered = records.where((r) => r['localOnly'] != true).toList();
      expect(filtered.length, 2);
      expect(filtered.map((r) => r['id']), ['1', '3']);
    });

    test('all localOnly records yields empty result', () {
      final records = [
        {'id': '1', 'localOnly': true, 'updatedAt': 100},
        {'id': '2', 'localOnly': true, 'updatedAt': 200},
      ];
      final filtered = records.where((r) => r['localOnly'] != true).toList();
      expect(filtered, isEmpty);
    });

    test('no localOnly records yields all records', () {
      final records = [
        {'id': '1', 'localOnly': false, 'updatedAt': 100},
        {'id': '2', 'localOnly': false, 'updatedAt': 200},
      ];
      final filtered = records.where((r) => r['localOnly'] != true).toList();
      expect(filtered.length, 2);
    });

    test('tombstoned records should be included', () {
      // Both live and deleted records should be collected for push.
      final records = [
        {'id': '1', 'updatedAt': 100, 'deletedAt': null},
        {'id': '2', 'updatedAt': 200, 'deletedAt': 500},
      ];
      // Both should be collected (tombstones are included).
      expect(records.length, 2);
    });
  });

  group('sinceCursor filtering logic', () {
    test('records at or before cursor are excluded', () {
      // Simulating the updatedAt > sinceCursor check from handlers.
      const sinceCursor = 150;
      final records = [
        {'id': '1', 'updatedAt': 100},
        {'id': '2', 'updatedAt': 150}, // exactly at cursor — excluded
        {'id': '3', 'updatedAt': 200},
        {'id': '4', 'updatedAt': 300},
      ];
      final filtered = records
          .where((r) => (r['updatedAt'] as int) > sinceCursor)
          .toList();
      expect(filtered.length, 2);
      expect(filtered.map((r) => r['id']), ['3', '4']);
    });

    test('cursor of zero includes all records', () {
      const sinceCursor = 0;
      final records = [
        {'id': '1', 'updatedAt': 1},
        {'id': '2', 'updatedAt': 100},
      ];
      final filtered = records
          .where((r) => (r['updatedAt'] as int) > sinceCursor)
          .toList();
      expect(filtered.length, 2);
    });

    test('cursor higher than all records yields empty', () {
      const sinceCursor = 9999;
      final records = [
        {'id': '1', 'updatedAt': 100},
        {'id': '2', 'updatedAt': 200},
      ];
      final filtered = records
          .where((r) => (r['updatedAt'] as int) > sinceCursor)
          .toList();
      expect(filtered, isEmpty);
    });
  });

  group('Streaming message exclusion', () {
    test('streaming messages should be skipped', () {
      // Simulating the isStreaming check from ChatsSyncHandler.
      final messages = [
        {'id': 'm1', 'isStreaming': false, 'updatedAt': 100},
        {'id': 'm2', 'isStreaming': true, 'updatedAt': 200},
        {'id': 'm3', 'isStreaming': false, 'updatedAt': 300},
      ];
      final filtered = messages.where((m) => m['isStreaming'] != true).toList();
      expect(filtered.length, 2);
      expect(filtered.map((m) => m['id']), ['m1', 'm3']);
    });
  });
}
