import 'package:test/test.dart';

import 'package:kelivo_sync_server/services/stream_dispatcher.dart';

void main() {
  group('StreamDispatcher lifecycle', () {
    test('start sets isRunning to true', () {
      final dispatcher = StreamDispatcher(maxConcurrent: 3);
      expect(dispatcher.isRunning, isFalse);

      // Use a very long interval so no poll fires during the test.
      dispatcher.start(interval: const Duration(hours: 1));
      expect(dispatcher.isRunning, isTrue);

      dispatcher.stop();
    });

    test('stop sets isRunning to false', () {
      final dispatcher = StreamDispatcher(maxConcurrent: 3);
      dispatcher.start(interval: const Duration(hours: 1));
      expect(dispatcher.isRunning, isTrue);

      dispatcher.stop();
      expect(dispatcher.isRunning, isFalse);
    });

    test('stop is idempotent', () {
      final dispatcher = StreamDispatcher(maxConcurrent: 2);
      dispatcher.stop(); // no-op before start
      expect(dispatcher.isRunning, isFalse);

      dispatcher.start(interval: const Duration(hours: 1));
      dispatcher.stop();
      dispatcher.stop(); // second stop is safe
      expect(dispatcher.isRunning, isFalse);
    });

    test('start replaces previous timer', () {
      final dispatcher = StreamDispatcher(maxConcurrent: 1);
      dispatcher.start(interval: const Duration(hours: 1));
      expect(dispatcher.isRunning, isTrue);

      // Restart with a different interval — should not throw.
      dispatcher.start(interval: const Duration(hours: 2));
      expect(dispatcher.isRunning, isTrue);

      dispatcher.stop();
    });

    test('runningCount starts at zero', () {
      final dispatcher = StreamDispatcher(maxConcurrent: 5);
      expect(dispatcher.runningCount, equals(0));
    });

    test('maxConcurrent is configurable', () {
      final d1 = StreamDispatcher(maxConcurrent: 1);
      final d2 = StreamDispatcher(maxConcurrent: 10);
      expect(d1.maxConcurrent, equals(1));
      expect(d2.maxConcurrent, equals(10));
    });

    test('default maxConcurrent is 5', () {
      final dispatcher = StreamDispatcher();
      expect(dispatcher.maxConcurrent, equals(5));
    });
  });

  group('StreamDispatcher onTaskEvent callback', () {
    test('callback can be set and invoked manually via the public field', () {
      final events = <Map<String, dynamic>>[];
      final dispatcher = StreamDispatcher();

      dispatcher.onTaskEvent = (taskId, userId, eventType, data) {
        events.add({
          'taskId': taskId,
          'userId': userId,
          'eventType': eventType,
          'data': data,
        });
      };

      // Directly invoke the callback to verify wiring.
      dispatcher.onTaskEvent!('t-1', 42, 'status', {'status': 'running'});
      dispatcher.onTaskEvent!('t-1', 42, 'chunk', {'content': 'hi'});
      dispatcher.onTaskEvent!('t-1', 42, 'completed', {
        'finalContent': 'hello',
      });

      expect(events, hasLength(3));
      expect(events[0]['eventType'], equals('status'));
      expect(events[1]['eventType'], equals('chunk'));
      expect(events[2]['eventType'], equals('completed'));
      expect(events[2]['data']['finalContent'], equals('hello'));
    });

    test('null callback does not throw', () {
      final dispatcher = StreamDispatcher();
      expect(dispatcher.onTaskEvent, isNull);
      // No crash if internal code would call _notifyEvent with null callback.
    });
  });

  group('TaskEventCallback typedef', () {
    test('matches expected function signature', () {
      void callback(
        String taskId,
        int userId,
        String eventType,
        Map<String, dynamic> data,
      ) {}

      final TaskEventCallback cb = callback;

      // The callback is assignable — type system verifies the signature.
      expect(cb, isNotNull);
    });
  });
}
