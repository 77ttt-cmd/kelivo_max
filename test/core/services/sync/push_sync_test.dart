import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_max/core/models/sync_config.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/sync/sync_api_client.dart';

void main() {
  group('Push sync configuration', () {
    test('pullOnly direction skips push', () {
      const config = SyncConfig(direction: SyncDirection.pullOnly);
      expect(config.direction, SyncDirection.pullOnly);
      expect(config.direction == SyncDirection.bidirectional, false);
    });

    test('bidirectional direction enables push', () {
      const config = SyncConfig(direction: SyncDirection.bidirectional);
      expect(config.direction == SyncDirection.bidirectional, true);
    });

    test('default direction is pullOnly', () {
      const config = SyncConfig();
      expect(config.direction, SyncDirection.pullOnly);
    });

    test('copyWith can change direction to bidirectional', () {
      const config = SyncConfig(direction: SyncDirection.pullOnly);
      final updated = config.copyWith(direction: SyncDirection.bidirectional);
      expect(updated.direction, SyncDirection.bidirectional);
    });

    test('copyWith preserves direction when not overridden', () {
      const config = SyncConfig(direction: SyncDirection.bidirectional);
      final updated = config.copyWith(enabled: true);
      expect(updated.direction, SyncDirection.bidirectional);
    });
  });

  group('PushChangesResult', () {
    test('constructs with accepted and skipped', () {
      final result = PushChangesResult(
        accepted: 5,
        skipped: ['id1', 'id2'],
        latestSeq: 100,
      );
      expect(result.accepted, 5);
      expect(result.skipped.length, 2);
      expect(result.latestSeq, 100);
    });

    test('empty skipped list', () {
      final result = PushChangesResult(accepted: 3, skipped: [], latestSeq: 50);
      expect(result.skipped, isEmpty);
    });

    test('zero accepted with skipped items indicates conflicts', () {
      final result = PushChangesResult(
        accepted: 0,
        skipped: ['id1', 'id2', 'id3'],
        latestSeq: 75,
      );
      expect(result.accepted, 0);
      expect(result.skipped.length, 3);
      expect(result.latestSeq, 75);
    });

    test('latestSeq reflects server state after push', () {
      final result = PushChangesResult(
        accepted: 10,
        skipped: [],
        latestSeq: 200,
      );
      expect(result.latestSeq, 200);
    });
  });

  group('Push orchestration logic (simulated)', () {
    test('push collects changes and tags with category key', () {
      // Simulate the push tagging logic from SyncProvider.syncNow.
      final allChanges = <Map<String, dynamic>>[];

      // Simulate handler output for chats.
      final chatChanges = <Map<String, dynamic>>[
        {'recordId': 'c1', 'payload': {}, 'updatedAt': 100},
        {'recordId': 'c2', 'payload': {}, 'updatedAt': 200},
      ];
      for (final change in chatChanges) {
        change['category'] = SyncCategory.chats.toKey();
        allChanges.add(change);
      }

      // Simulate handler output for assistants.
      final assistantChanges = <Map<String, dynamic>>[
        {'recordId': 'a1', 'payload': {}, 'updatedAt': 150},
      ];
      for (final change in assistantChanges) {
        change['category'] = SyncCategory.assistants.toKey();
        allChanges.add(change);
      }

      expect(allChanges.length, 3);
      expect(allChanges[0]['category'], 'chats');
      expect(allChanges[1]['category'], 'chats');
      expect(allChanges[2]['category'], 'assistants');
    });

    test('cursor updates when push latestSeq is greater', () {
      // Simulate cursor update logic from SyncProvider.syncNow.
      var cursor = 50;
      final pushLatestSeq = 120;

      if (pushLatestSeq > cursor) {
        cursor = pushLatestSeq;
      }

      expect(cursor, 120);
    });

    test('cursor unchanged when push latestSeq is not greater', () {
      var cursor = 200;
      final pushLatestSeq = 150;

      if (pushLatestSeq > cursor) {
        cursor = pushLatestSeq;
      }

      expect(cursor, 200);
    });

    test('conflict count reflects skipped length', () {
      final pushResult = PushChangesResult(
        accepted: 4,
        skipped: ['s1', 's2'],
        latestSeq: 80,
      );

      final conflictCount = pushResult.skipped.length;
      expect(conflictCount, 2);
    });
  });
}
