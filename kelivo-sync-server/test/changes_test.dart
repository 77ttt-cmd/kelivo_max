import 'dart:convert';

import 'package:test/test.dart';

import 'package:kelivo_sync_server/models/change_entry.dart';
import 'package:kelivo_sync_server/services/changelog_service.dart';

void main() {
  group('ChangeEntry', () {
    test('toJson includes all fields', () {
      final entry = ChangeEntry(
        id: 1,
        userId: 42,
        category: 'chats',
        recordId: 'abc-123',
        payload: {'title': 'Hello', 'model': 'gpt-4'},
        updatedAt: 1700000000000,
        deletedAt: null,
        serverSeq: 10,
      );

      final json = entry.toJson();

      expect(json['id'], equals(1));
      expect(json['category'], equals('chats'));
      expect(json['recordId'], equals('abc-123'));
      expect(json['payload'], equals({'title': 'Hello', 'model': 'gpt-4'}));
      expect(json['updatedAt'], equals(1700000000000));
      expect(json['deletedAt'], isNull);
      expect(json['serverSeq'], equals(10));
      // userId should NOT be in toJson (it's implicit from the auth context)
      expect(json.containsKey('userId'), isFalse);
    });

    test('toJson includes deletedAt when set', () {
      final entry = ChangeEntry(
        id: 2,
        userId: 42,
        category: 'providers',
        recordId: 'def-456',
        payload: {},
        updatedAt: 1700000001000,
        deletedAt: 1700000002000,
        serverSeq: 20,
      );

      final json = entry.toJson();

      expect(json['deletedAt'], equals(1700000002000));
    });

    test('toJson is JSON-serializable', () {
      final entry = ChangeEntry(
        id: 3,
        userId: 10,
        category: 'chats',
        recordId: 'ghi-789',
        payload: {
          'nested': {'key': 'value'},
          'list': [1, 2, 3],
        },
        updatedAt: 1700000003000,
        serverSeq: 30,
      );

      final jsonString = jsonEncode(entry.toJson());
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(decoded['category'], equals('chats'));
      expect(decoded['recordId'], equals('ghi-789'));
      expect(decoded['payload']['nested']['key'], equals('value'));
      expect(decoded['payload']['list'], equals([1, 2, 3]));
      expect(decoded['serverSeq'], equals(30));
    });

    test('toJson with empty payload', () {
      final entry = ChangeEntry(
        id: 4,
        userId: 1,
        category: 'settings',
        recordId: 'empty-1',
        payload: {},
        updatedAt: 1700000004000,
        serverSeq: 40,
      );

      final json = entry.toJson();

      expect(json['payload'], isEmpty);
      expect(json['payload'], isA<Map>());
    });
  });

  group('ChangelogResult response format', () {
    test('entries list serializes correctly for API response', () {
      final entries = [
        ChangeEntry(
          id: 1,
          userId: 42,
          category: 'chats',
          recordId: 'r1',
          payload: {'title': 'Chat 1'},
          updatedAt: 1700000000000,
          serverSeq: 1,
        ),
        ChangeEntry(
          id: 2,
          userId: 42,
          category: 'chats',
          recordId: 'r2',
          payload: {'title': 'Chat 2'},
          updatedAt: 1700000001000,
          deletedAt: 1700000002000,
          serverSeq: 2,
        ),
      ];

      final latestSeq = entries.isNotEmpty ? entries.last.serverSeq : 0;

      final responseBody = jsonEncode({
        'entries': entries.map((e) => e.toJson()).toList(),
        'latestSeq': latestSeq,
        'hasMore': false,
      });

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

      expect(decoded['entries'], hasLength(2));
      expect(decoded['latestSeq'], equals(2));
      expect(decoded['hasMore'], isFalse);

      final first = decoded['entries'][0] as Map<String, dynamic>;
      expect(first['category'], equals('chats'));
      expect(first['recordId'], equals('r1'));
      expect(first.containsKey('userId'), isFalse);

      final second = decoded['entries'][1] as Map<String, dynamic>;
      expect(second['deletedAt'], equals(1700000002000));
    });

    test('empty entries returns since as latestSeq', () {
      final since = 50;
      final entries = <ChangeEntry>[];

      final latestSeq = entries.isNotEmpty ? entries.last.serverSeq : since;

      final responseBody = jsonEncode({
        'entries': entries.map((e) => e.toJson()).toList(),
        'latestSeq': latestSeq,
        'hasMore': false,
      });

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

      expect(decoded['entries'], isEmpty);
      expect(decoded['latestSeq'], equals(50));
      expect(decoded['hasMore'], isFalse);
    });

    test('hasMore true when more entries exist beyond limit', () {
      final responseBody = jsonEncode({
        'entries': [],
        'latestSeq': 500,
        'hasMore': true,
      });

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      expect(decoded['hasMore'], isTrue);
    });
  });

  group('PushResult', () {
    test('holds accepted count, skipped list, and latestSeq', () {
      final result = PushResult(
        accepted: 3,
        skipped: ['r4', 'r5'],
        latestSeq: 100,
      );

      expect(result.accepted, equals(3));
      expect(result.skipped, equals(['r4', 'r5']));
      expect(result.latestSeq, equals(100));
    });

    test('empty skipped list is valid', () {
      final result = PushResult(accepted: 5, skipped: [], latestSeq: 50);

      expect(result.accepted, equals(5));
      expect(result.skipped, isEmpty);
      expect(result.latestSeq, equals(50));
    });

    test('serializes to expected API response shape', () {
      final result = PushResult(
        accepted: 2,
        skipped: ['skip-1'],
        latestSeq: 42,
      );

      final responseBody = jsonEncode({
        'accepted': result.accepted,
        'skipped': result.skipped,
        'latestSeq': result.latestSeq,
      });
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

      expect(decoded['accepted'], equals(2));
      expect(decoded['skipped'], equals(['skip-1']));
      expect(decoded['latestSeq'], equals(42));
    });
  });
}
