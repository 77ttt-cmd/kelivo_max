import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:kelivo_sync_server/models/generation_task.dart';
import 'package:kelivo_sync_server/routes/tasks.dart';

/// Builds a handler that simulates auth by injecting userId into context,
/// then delegates to the taskRouter.
///
/// Since the route handlers call TaskService which needs a real DB,
/// we test only parameter validation and model serialization here.
Handler _buildHandler() {
  final inner = taskRouter();

  return (Request request) async {
    final authedRequest = request.change(context: {'userId': 42});
    return inner.call(authedRequest);
  };
}

void main() {
  group('GenerationTask model', () {
    test('toJson serializes correctly', () {
      final now = DateTime.utc(2025, 1, 15, 10, 30);
      final task = GenerationTask(
        id: '550e8400-e29b-41d4-a716-446655440000',
        userId: 42,
        conversationId: 'conv-1',
        providerSyncId: 'provider-1',
        messages: [
          {'role': 'user', 'content': 'Hello'},
        ],
        parameters: {'temperature': 0.7},
        status: 'pending',
        resultChunks: [],
        createdAt: now,
        updatedAt: now,
      );

      final json = task.toJson();

      expect(json['id'], equals('550e8400-e29b-41d4-a716-446655440000'));
      expect(json['conversationId'], equals('conv-1'));
      expect(json['providerSyncId'], equals('provider-1'));
      expect(json['status'], equals('pending'));
      expect(json['resultChunks'], isEmpty);
      expect(json['finalContent'], isNull);
      expect(json['errorMessage'], isNull);
      expect(json['createdAt'], equals('2025-01-15T10:30:00.000Z'));
      expect(json['updatedAt'], equals('2025-01-15T10:30:00.000Z'));
    });

    test('toJson excludes userId and messages (not exposed to client)', () {
      final now = DateTime.utc(2025, 1, 15);
      final task = GenerationTask(
        id: 'abc',
        userId: 42,
        conversationId: 'conv-1',
        providerSyncId: 'p-1',
        messages: [
          {'role': 'user', 'content': 'test'},
        ],
        parameters: {'model': 'gpt-4'},
        status: 'completed',
        resultChunks: [
          {'chunk': 'hello'},
        ],
        finalContent: 'hello world',
        createdAt: now,
        updatedAt: now,
      );

      final json = task.toJson();

      expect(json.containsKey('userId'), isFalse);
      expect(json.containsKey('messages'), isFalse);
      expect(json.containsKey('parameters'), isFalse);
      expect(json['finalContent'], equals('hello world'));
      expect(json['resultChunks'], hasLength(1));
    });

    test('toJson includes errorMessage when present', () {
      final now = DateTime.utc(2025, 1, 15);
      final task = GenerationTask(
        id: 'err-task',
        userId: 1,
        conversationId: 'conv-err',
        providerSyncId: 'p-err',
        messages: [],
        parameters: {},
        status: 'failed',
        resultChunks: [],
        errorMessage: 'API key invalid',
        createdAt: now,
        updatedAt: now,
      );

      final json = task.toJson();

      expect(json['status'], equals('failed'));
      expect(json['errorMessage'], equals('API key invalid'));
    });
  });

  group('POST /tasks validation', () {
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

    test('returns 400 when conversationId is missing', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({
          'providerSyncId': 'p1',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('conversationId'));
    });

    test('returns 400 when conversationId is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({
          'conversationId': '',
          'providerSyncId': 'p1',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('conversationId'));
    });

    test('returns 400 when providerSyncId is missing', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({
          'conversationId': 'conv-1',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('providerSyncId'));
    });

    test('returns 400 when providerSyncId is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({
          'conversationId': 'conv-1',
          'providerSyncId': '',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('providerSyncId'));
    });

    test('returns 400 when messages is missing', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({'conversationId': 'conv-1', 'providerSyncId': 'p1'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('messages'));
    });

    test('returns 400 when messages is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({
          'conversationId': 'conv-1',
          'providerSyncId': 'p1',
          'messages': [],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('messages'));
    });

    test(
      'passes validation with all required fields (fails at DB layer)',
      () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/'),
          body: jsonEncode({
            'conversationId': 'conv-1',
            'providerSyncId': 'p1',
            'messages': [
              {'role': 'user', 'content': 'Hello'},
            ],
            'parameters': {'temperature': 0.7},
          }),
          headers: {'content-type': 'application/json'},
        );
        final response = await handler(request);

        // Should pass validation (not 400); will be 500 without DB.
        expect(
          response.statusCode,
          isNot(400),
          reason: 'Valid input should pass validation',
        );
      },
    );

    test('parameters is optional and defaults to empty map', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: jsonEncode({
          'conversationId': 'conv-1',
          'providerSyncId': 'p1',
          'messages': [
            {'role': 'user', 'content': 'Hello'},
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      // Should pass validation (not 400); will be 500 without DB.
      expect(
        response.statusCode,
        isNot(400),
        reason: 'Missing parameters should be accepted',
      );
    });
  });

  group('GET /tasks/<id> validation', () {
    late Handler handler;

    setUp(() {
      handler = _buildHandler();
    });

    test('returns 400 for invalid UUID format', () async {
      final request = Request('GET', Uri.parse('http://localhost/not-a-uuid'));
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Invalid task id'));
    });

    test('accepts valid UUID format (fails at DB layer)', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/550e8400-e29b-41d4-a716-446655440000'),
      );
      final response = await handler(request);

      // Should pass validation (not 400); will be 500 without DB.
      expect(
        response.statusCode,
        isNot(400),
        reason: 'Valid UUID should pass validation',
      );
    });
  });
}
