import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';

/// Creates a [Middleware] that verifies JWT bearer tokens.
///
/// On success, attaches the `userId` (int) from the JWT payload to the
/// request context under the key `'userId'`.
///
/// On failure (missing header, malformed token, expired, bad signature),
/// returns 401 with `{"error": "Unauthorized"}`.
Middleware authMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return _unauthorized();
      }

      final token = authHeader.substring('Bearer '.length).trim();
      if (token.isEmpty) {
        return _unauthorized();
      }

      final secret = Platform.environment['JWT_SECRET'];
      if (secret == null || secret.isEmpty) {
        // Server misconfiguration — still return 401 to the client,
        // but this is a server-side error in practice.
        return _unauthorized();
      }

      try {
        final jwt = JWT.verify(token, SecretKey(secret));
        final payload = jwt.payload as Map<String, dynamic>;
        final userId = payload['userId'] as int;

        final updatedRequest = request.change(context: {'userId': userId});
        return innerHandler(updatedRequest);
      } on JWTExpiredException {
        return _unauthorized();
      } on JWTException {
        return _unauthorized();
      } catch (_) {
        return _unauthorized();
      }
    };
  };
}

Response _unauthorized() {
  return Response(
    401,
    body: jsonEncode({'error': 'Unauthorized'}),
    headers: {'content-type': 'application/json'},
  );
}
