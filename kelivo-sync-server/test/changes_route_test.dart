import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:kelivo_max_sync_server/routes/changes.dart';

/// Builds a handler that simulates auth by injecting userId into context,
/// then delegates to the changesRouter.
///
/// Since the route handler calls ChangelogService which needs a real DB,
/// we test only the parameter validation layer here.
Handler _buildHandler() {
  final inner = changesRouter();

  return (Request request) async {
    // Simulate auth middleware: inject userId into context
    final authedRequest = request.change(context: {'userId': 42});
    return inner.call(authedRequest);
  };
}

void main() {
  late Handler handler;

  setUp(() {
    handler = _buildHandler();
  });

  group('GET /changes parameter validation', () {
    test('returns 400 when categories param is missing', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/changes?since=0'),
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('categories'));
    });

    test('returns 400 when categories param is empty string', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/changes?since=0&categories='),
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('categories'));
    });

    test('returns 400 when categories is only commas', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/changes?since=0&categories=,,,'),
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('categories'));
    });
  });

  group('POST /changes parameter validation', () {
    test('returns 400 when entries array is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/changes'),
        body: jsonEncode({'entries': []}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('entries'));
    });

    test('returns 400 when entries key is missing', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/changes'),
        body: jsonEncode({'foo': 'bar'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('entries'));
    });

    test('returns 400 when category is unknown', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/changes'),
        body: jsonEncode({
          'entries': [
            {
              'category': 'invalidCategory',
              'recordId': 'r1',
              'payload': {},
              'updatedAt': 1700000000000,
            },
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Unknown category'));
      expect(body['error'], contains('invalidCategory'));
    });

    test('returns 400 when category is null', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/changes'),
        body: jsonEncode({
          'entries': [
            {'recordId': 'r1', 'payload': {}, 'updatedAt': 1700000000000},
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Unknown category'));
    });

    test('validates all known categories as accepted', () async {
      // This test only checks validation passes — the DB call will fail
      // since we don't have a DB in this test environment, resulting in 500.
      // The key assertion is that it does NOT return 400 for valid categories.
      final validCategories = [
        'chats',
        'providers',
        'assistants',
        'quickPhrases',
        'mcp',
        'searchServices',
        'ttsServices',
        'settings',
        'files',
      ];

      for (final cat in validCategories) {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/changes'),
          body: jsonEncode({
            'entries': [
              {
                'category': cat,
                'recordId': 'r-$cat',
                'payload': {},
                'updatedAt': 1700000000000,
              },
            ],
          }),
          headers: {'content-type': 'application/json'},
        );
        final response = await handler(request);

        // Should pass validation (not 400); will be 500 without DB.
        expect(
          response.statusCode,
          isNot(400),
          reason: 'Category "$cat" should be accepted by validation',
        );
      }
    });

    test('rejects at first unknown category in mixed entries', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/changes'),
        body: jsonEncode({
          'entries': [
            {
              'category': 'chats',
              'recordId': 'r1',
              'payload': {},
              'updatedAt': 1700000000000,
            },
            {
              'category': 'badCategory',
              'recordId': 'r2',
              'payload': {},
              'updatedAt': 1700000000001,
            },
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('badCategory'));
    });
  });
}
