import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'package:kelivo_sync_server/models/user.dart';
import 'package:kelivo_sync_server/routes/auth.dart';

void main() {
  group('User model', () {
    test('creates User with all fields', () {
      final now = DateTime.now();
      final user = User(
        id: 1,
        username: 'testuser',
        passwordHash: 'hashed',
        createdAt: now,
      );

      expect(user.id, equals(1));
      expect(user.username, equals('testuser'));
      expect(user.passwordHash, equals('hashed'));
      expect(user.createdAt, equals(now));
    });
  });

  group('Auth routes input validation', () {
    late Router router;

    setUp(() {
      router = authRouter();
    });

    test('POST /auth/register returns 400 for empty body', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/auth/register'),
        body: '{}',
      );
      final response = await router.call(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('required'));
    });

    test('POST /auth/register returns 400 for invalid JSON', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/auth/register'),
        body: 'not json',
      );
      final response = await router.call(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Invalid JSON'));
    });

    test('POST /auth/login returns 400 for empty body', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/auth/login'),
        body: '{}',
      );
      final response = await router.call(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('required'));
    });

    test('POST /auth/login returns 400 for missing password', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/auth/login'),
        body: jsonEncode({'username': 'user'}),
      );
      final response = await router.call(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('required'));
    });

    test('POST /auth/refresh returns 400 for empty body', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/auth/refresh'),
        body: '{}',
      );
      final response = await router.call(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('required'));
    });

    test('POST /auth/refresh returns 400 for invalid JSON', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/auth/refresh'),
        body: 'not json',
      );
      final response = await router.call(request);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Invalid JSON'));
    });
  });
}
