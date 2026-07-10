import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'package:kelivo_sync_server/middleware/auth_middleware.dart';

/// Helper: builds a pipeline with authMiddleware protecting a /me endpoint.
Handler _buildProtectedHandler() {
  final router = Router();
  router.get('/me', (Request request) {
    final userId = request.context['userId'] as int;
    return Response.ok(
      jsonEncode({'userId': userId}),
      headers: {'content-type': 'application/json'},
    );
  });

  return const Pipeline()
      .addMiddleware(authMiddleware())
      .addHandler(router.call);
}

/// Helper: creates a signed JWT for testing.
String _createTestToken(int userId, {Duration? expiresIn}) {
  final jwt = JWT({'userId': userId});
  return jwt.sign(
    SecretKey(Platform.environment['JWT_SECRET']!),
    expiresIn: expiresIn ?? const Duration(minutes: 15),
  );
}

void main() {
  late Handler handler;

  setUpAll(() {
    // Ensure JWT_SECRET is set for tests.
    if (Platform.environment['JWT_SECRET'] == null) {
      // dart test doesn't inherit env easily; set a default via the
      // environment map is not possible at runtime, so we rely on the
      // test runner to provide it. For CI, use:
      //   JWT_SECRET=test_secret dart test
      //
      // If not set, skip by throwing.
      throw StateError(
        'JWT_SECRET must be set. Run with: JWT_SECRET=test_secret dart test',
      );
    }
  });

  setUp(() {
    handler = _buildProtectedHandler();
  });

  group('Auth middleware', () {
    test('returns 401 when no Authorization header is present', () async {
      final request = Request('GET', Uri.parse('http://localhost/me'));
      final response = await handler(request);

      expect(response.statusCode, equals(401));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], equals('Unauthorized'));
    });

    test(
      'returns 401 when Authorization header has no Bearer prefix',
      () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/me'),
          headers: {'authorization': 'Basic abc123'},
        );
        final response = await handler(request);

        expect(response.statusCode, equals(401));
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], equals('Unauthorized'));
      },
    );

    test('returns 401 when Bearer token is empty', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/me'),
        headers: {'authorization': 'Bearer '},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(401));
    });

    test('returns 401 when token is malformed / invalid', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/me'),
        headers: {'authorization': 'Bearer not.a.valid.jwt.token'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(401));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], equals('Unauthorized'));
    });

    test('returns 401 when token is signed with wrong secret', () async {
      final jwt = JWT({'userId': 42});
      final wrongToken = jwt.sign(
        SecretKey('wrong_secret_key'),
        expiresIn: const Duration(minutes: 15),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/me'),
        headers: {'authorization': 'Bearer $wrongToken'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(401));
    });

    test('returns 401 when token is expired', () async {
      // Create a token that expires in -1 second (already expired).
      final jwt = JWT({'userId': 1});
      final expiredToken = jwt.sign(
        SecretKey(Platform.environment['JWT_SECRET']!),
        expiresIn: const Duration(seconds: -1),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/me'),
        headers: {'authorization': 'Bearer $expiredToken'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(401));
    });

    test('passes through and attaches userId for a valid token', () async {
      final token = _createTestToken(42);

      final request = Request(
        'GET',
        Uri.parse('http://localhost/me'),
        headers: {'authorization': 'Bearer $token'},
      );
      final response = await handler(request);

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['userId'], equals(42));
    });

    test('different users get their own userId in context', () async {
      final token1 = _createTestToken(1);
      final token2 = _createTestToken(2);

      final request1 = Request(
        'GET',
        Uri.parse('http://localhost/me'),
        headers: {'authorization': 'Bearer $token1'},
      );
      final response1 = await handler(request1);
      final body1 = jsonDecode(await response1.readAsString());
      expect(body1['userId'], equals(1));

      final request2 = Request(
        'GET',
        Uri.parse('http://localhost/me'),
        headers: {'authorization': 'Bearer $token2'},
      );
      final response2 = await handler(request2);
      final body2 = jsonDecode(await response2.readAsString());
      expect(body2['userId'], equals(2));
    });
  });
}
