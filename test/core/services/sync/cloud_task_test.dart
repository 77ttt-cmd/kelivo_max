import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_max/core/services/sync/cloud_task_stream.dart';
import 'package:kelivo_max/core/services/sync/sync_api_client.dart';
import 'package:kelivo_max/core/models/sync_config.dart';

void main() {
  group('CloudTaskEvent', () {
    test('chunk event contains content', () {
      const event = CloudTaskChunk('Hello world');
      expect(event, isA<CloudTaskChunk>());
      expect(event.content, 'Hello world');
    });

    test('chunk event with empty content', () {
      const event = CloudTaskChunk('');
      expect(event.content, isEmpty);
    });

    test('completed event contains final content', () {
      const event = CloudTaskCompleted('Full response text');
      expect(event, isA<CloudTaskCompleted>());
      expect(event.finalContent, 'Full response text');
      expect(event.totalTokens, 0); // default
    });

    test('completed event with totalTokens', () {
      const event = CloudTaskCompleted('Response', totalTokens: 150);
      expect(event.finalContent, 'Response');
      expect(event.totalTokens, 150);
    });

    test('completed event with empty content', () {
      const event = CloudTaskCompleted('');
      expect(event.finalContent, isEmpty);
      expect(event.totalTokens, 0);
    });

    test('failed event contains error', () {
      const event = CloudTaskFailed('Provider error');
      expect(event, isA<CloudTaskFailed>());
      expect(event.error, 'Provider error');
    });

    test('failed event with empty error', () {
      const event = CloudTaskFailed('');
      expect(event.error, isEmpty);
    });

    test('all event types are subtypes of CloudTaskEvent', () {
      const chunk = CloudTaskChunk('c');
      const completed = CloudTaskCompleted('d');
      const failed = CloudTaskFailed('e');

      expect(chunk, isA<CloudTaskEvent>());
      expect(completed, isA<CloudTaskEvent>());
      expect(failed, isA<CloudTaskEvent>());
    });

    test('switch exhaustiveness on sealed class', () {
      // Helper to prevent the analyzer from narrowing the type.
      String classify(CloudTaskEvent event) {
        switch (event) {
          case CloudTaskChunk(:final content):
            return 'chunk:$content';
          case CloudTaskCompleted(:final finalContent, :final totalTokens):
            return 'completed:$finalContent:$totalTokens';
          case CloudTaskFailed(:final error):
            return 'failed:$error';
        }
      }

      expect(classify(const CloudTaskChunk('test')), 'chunk:test');
      expect(
        classify(const CloudTaskCompleted('done', totalTokens: 42)),
        'completed:done:42',
      );
      expect(classify(const CloudTaskFailed('oops')), 'failed:oops');
    });
  });

  group('Cloud execution configuration', () {
    test('cloud execution disabled by default', () {
      const config = SyncConfig();
      expect(config.cloudExecutionEnabled, false);
    });

    test('cloud execution enabled with flag', () {
      const config = SyncConfig(cloudExecutionEnabled: true, enabled: true);
      expect(config.cloudExecutionEnabled, true);
    });

    test('cloud execution requires sync enabled', () {
      const config = SyncConfig(cloudExecutionEnabled: true, enabled: false);
      // Both must be true for cloud execution to activate
      expect(config.enabled && config.cloudExecutionEnabled, false);
    });

    test('local execution path when cloud disabled', () {
      const config = SyncConfig(enabled: true, cloudExecutionEnabled: false);
      final shouldUseCloud = config.enabled && config.cloudExecutionEnabled;
      expect(shouldUseCloud, false);
    });

    test('cloudExecutionEnabled round-trips through JSON', () {
      const config = SyncConfig(
        enabled: true,
        cloudExecutionEnabled: true,
        serverUrl: 'https://example.com',
      );
      final json = config.toJson();
      final restored = SyncConfig.fromJson(json);

      expect(restored.cloudExecutionEnabled, true);
      expect(restored.enabled, true);
      expect(restored.serverUrl, 'https://example.com');
    });

    test('cloudExecutionEnabled defaults to false in fromJson', () {
      final config = SyncConfig.fromJson(<String, dynamic>{});
      expect(config.cloudExecutionEnabled, false);
    });

    test('copyWith preserves cloudExecutionEnabled', () {
      const original = SyncConfig(cloudExecutionEnabled: true, enabled: true);
      final copy = original.copyWith(serverUrl: 'https://new.url');
      expect(copy.cloudExecutionEnabled, true);
      expect(copy.serverUrl, 'https://new.url');
    });

    test('copyWith can toggle cloudExecutionEnabled', () {
      const original = SyncConfig(cloudExecutionEnabled: true, enabled: true);
      final toggled = original.copyWith(cloudExecutionEnabled: false);
      expect(toggled.cloudExecutionEnabled, false);
      expect(toggled.enabled, true);
    });
  });

  group('SyncApiClient result types', () {
    test('PushChangesResult constructs correctly', () {
      final result = PushChangesResult(
        accepted: 3,
        skipped: ['id1'],
        latestSeq: 99,
      );
      expect(result.accepted, 3);
      expect(result.skipped, ['id1']);
      expect(result.latestSeq, 99);
    });

    test('PushChangesResult with empty skipped list', () {
      final result = PushChangesResult(accepted: 5, skipped: [], latestSeq: 10);
      expect(result.accepted, 5);
      expect(result.skipped, isEmpty);
      expect(result.latestSeq, 10);
    });

    test('PushChangesResult with multiple skipped IDs', () {
      final result = PushChangesResult(
        accepted: 0,
        skipped: ['a', 'b', 'c'],
        latestSeq: 50,
      );
      expect(result.accepted, 0);
      expect(result.skipped, hasLength(3));
      expect(result.skipped, containsAll(['a', 'b', 'c']));
    });

    test('PullChangesResult constructs correctly', () {
      final result = PullChangesResult(
        entries: [
          {'recordId': 'r1', 'category': 'chats'},
        ],
        latestSeq: 42,
        hasMore: true,
      );
      expect(result.entries, hasLength(1));
      expect(result.latestSeq, 42);
      expect(result.hasMore, true);
    });

    test('PullChangesResult with empty entries', () {
      final result = PullChangesResult(
        entries: [],
        latestSeq: 0,
        hasMore: false,
      );
      expect(result.entries, isEmpty);
      expect(result.latestSeq, 0);
      expect(result.hasMore, false);
    });

    test('SyncApiException provides descriptive toString', () {
      final exception = SyncApiException(401, 'Unauthorized');
      expect(exception.statusCode, 401);
      expect(exception.message, 'Unauthorized');
      expect(exception.toString(), contains('401'));
      expect(exception.toString(), contains('Unauthorized'));
    });

    test('SyncApiException with server error', () {
      final exception = SyncApiException(500, 'Internal server error');
      expect(exception.statusCode, 500);
      expect(exception.message, 'Internal server error');
    });
  });
}
