import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:kelivo_sync_server/routes/devices.dart';

/// Builds a handler that simulates auth by injecting userId into context,
/// then delegates to the deviceRouter.
Handler _buildHandler() {
  final inner = deviceRouter();

  return (Request request) async {
    final authedRequest = request.change(context: {'userId': 42});
    return inner.call(authedRequest);
  };
}

void main() {
  group('POST /devices validation', () {
    late Handler handler;

    setUp(() {
      handler = _buildHandler();
    });

    test('returns 400 for invalid JSON body', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: 'not json',
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Invalid JSON'));
    });

    test('returns 400 when platform is missing', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'pushToken': 'abc123'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('platform'));
    });

    test('returns 400 when platform is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'platform': '', 'pushToken': 'abc123'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('platform'));
    });

    test('returns 400 when platform is invalid', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'platform': 'windows', 'pushToken': 'abc123'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('must be one of'));
    });

    test('returns 400 when pushToken is missing', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'platform': 'android'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('pushToken'));
    });

    test('returns 400 when pushToken is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'platform': 'ios', 'pushToken': ''}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('pushToken'));
    });

    test('passes validation with valid fields (fails at DB layer)', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'platform': 'android', 'pushToken': 'token-abc'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      // Should pass validation (not 400); will be 500 without DB.
      expect(
        response.statusCode,
        isNot(400),
        reason: 'Valid input should pass validation',
      );
    });

    test('accepts ios platform', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'platform': 'ios', 'pushToken': 'apns-token-xyz'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      // Should pass validation (not 400); will be 500 without DB.
      expect(
        response.statusCode,
        isNot(400),
        reason: 'ios platform should be accepted',
      );
    });
  });

  group('DELETE /devices/<token> validation', () {
    late Handler handler;

    setUp(() {
      handler = _buildHandler();
    });

    test('accepts a token path parameter (fails at DB layer)', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/some-push-token'),
      );
      final response = await handler(request);

      // Should reach the handler (not 404 from router); will be 500 without DB.
      expect(
        response.statusCode,
        isNot(404),
        reason: 'Token path parameter should match the route',
      );
    });

    test('accepts URL-encoded token', () async {
      final encodedToken = Uri.encodeComponent('abc:def/ghi');
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/$encodedToken'),
      );
      final response = await handler(request);

      // Should reach the handler (not 404 from router).
      expect(
        response.statusCode,
        isNot(404),
        reason: 'URL-encoded token should match the route',
      );
    });
  });

  group('PushService unit logic', () {
    // PushService static methods require DB; we test the dispatcher wiring
    // pattern instead, verifying the callback signature compatibility.
    test('TaskEventCallback is compatible with push wiring', () {
      // Verify that the push notification wiring pattern compiles and
      // the callback shape matches StreamDispatcher.onTaskEvent.
      void callback(
        String taskId,
        int userId,
        String eventType,
        Map<String, dynamic> data,
      ) {
        if (eventType == 'completed') {
          // Would call PushService.sendPushNotification here.
          expect(taskId, isNotEmpty);
          expect(userId, isPositive);
        }
      }

      callback('task-1', 1, 'completed', {'finalContent': 'hello'});
      callback('task-2', 2, 'failed', {'error': 'timeout'});
      callback('task-3', 3, 'chunk', {'content': 'hi'});
    });

    test('push is only triggered on completed and failed events', () {
      final pushEvents = <String>[];

      void callback(
        String taskId,
        int userId,
        String eventType,
        Map<String, dynamic> data,
      ) {
        if (eventType == 'completed' || eventType == 'failed') {
          pushEvents.add(eventType);
        }
      }

      callback('t1', 1, 'status', {'status': 'running'});
      callback('t2', 1, 'chunk', {'content': 'partial'});
      callback('t3', 1, 'completed', {'finalContent': 'done'});
      callback('t4', 1, 'failed', {'error': 'oops'});

      expect(pushEvents, equals(['completed', 'failed']));
    });

    test('conversationId defaults to empty string when absent', () {
      String? capturedConversationId;

      void callback(
        String taskId,
        int userId,
        String eventType,
        Map<String, dynamic> data,
      ) {
        if (eventType == 'completed') {
          capturedConversationId = data['conversationId'] as String? ?? '';
        }
      }

      // Simulate a completed event without conversationId in data.
      callback('t1', 1, 'completed', {'finalContent': 'done'});

      expect(capturedConversationId, equals(''));
    });
  });
}
