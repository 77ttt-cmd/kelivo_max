import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant_memory.dart';

void main() {
  group('AssistantMemory uid migration', () {
    test('new AssistantMemory always has non-empty uid', () {
      final memory = AssistantMemory(
        id: 0,
        assistantId: 'assistant-1',
        content: 'test content',
      );
      expect(memory.uid, isNotEmpty);
    });

    test('fromJson with missing uid generates a UUID', () {
      final memory = AssistantMemory.fromJson({
        'id': 1,
        'assistantId': 'assistant-1',
        'content': 'hello',
      });
      expect(memory.uid, isNotEmpty);
      expect(memory.uid.length, 36);
      expect(memory.uid.contains('-'), true);
    });

    test('fromJson with empty uid generates a UUID', () {
      final memory = AssistantMemory.fromJson({
        'id': 1,
        'uid': '',
        'assistantId': 'assistant-1',
        'content': 'hello',
      });
      expect(memory.uid, isNotEmpty);
      expect(memory.uid.length, 36);
    });

    test('fromJson with null uid generates a UUID', () {
      final memory = AssistantMemory.fromJson({
        'id': 1,
        'uid': null,
        'assistantId': 'assistant-1',
        'content': 'hello',
      });
      expect(memory.uid, isNotEmpty);
      expect(memory.uid.length, 36);
    });

    test('fromJson with existing uid preserves it', () {
      const existingUid = '550e8400-e29b-41d4-a716-446655440000';
      final memory = AssistantMemory.fromJson({
        'id': 1,
        'uid': existingUid,
        'assistantId': 'assistant-1',
        'content': 'hello',
      });
      expect(memory.uid, existingUid);
    });

    test('uid is a valid UUID v4 format', () {
      final memory = AssistantMemory(
        id: 0,
        assistantId: 'assistant-1',
        content: 'test',
      );
      // UUID format: 8-4-4-4-12 hex chars
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      expect(memory.uid, matches(uuidRegex));
      expect(memory.uid.length, 36);
    });

    test('each new AssistantMemory gets a unique uid', () {
      final uids = <String>{};
      for (var i = 0; i < 100; i++) {
        final memory = AssistantMemory(
          id: 0,
          assistantId: 'assistant-1',
          content: 'content $i',
        );
        uids.add(memory.uid);
      }
      expect(uids.length, 100);
    });

    test('constructor with explicit uid preserves it', () {
      final memory = AssistantMemory(
        id: 1,
        uid: 'my-custom-uid-value-that-is-set',
        assistantId: 'assistant-1',
        content: 'test',
      );
      expect(memory.uid, 'my-custom-uid-value-that-is-set');
    });
  });
}
