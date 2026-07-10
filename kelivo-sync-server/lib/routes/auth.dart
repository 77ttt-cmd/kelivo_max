import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/auth_service.dart';

Router authRouter() {
  final router = Router();

  router.post('/auth/register', _registerHandler);
  router.post('/auth/login', _loginHandler);
  router.post('/auth/refresh', _refreshHandler);

  return router;
}

Future<Response> _registerHandler(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final username = json['username'] as String?;
    final password = json['password'] as String?;

    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'username and password are required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final userId = await AuthService.register(username, password);

    return Response(
      201,
      body: jsonEncode({'id': userId, 'username': username}),
      headers: {'content-type': 'application/json'},
    );
  } on AuthException catch (e) {
    return Response(
      e.statusCode,
      body: jsonEncode({'error': e.message}),
      headers: {'content-type': 'application/json'},
    );
  } on FormatException {
    return Response(
      400,
      body: jsonEncode({'error': 'Invalid JSON body'}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<Response> _loginHandler(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final username = json['username'] as String?;
    final password = json['password'] as String?;

    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'username and password are required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final tokens = await AuthService.login(username, password);

    return Response.ok(
      jsonEncode(tokens),
      headers: {'content-type': 'application/json'},
    );
  } on AuthException catch (e) {
    return Response(
      e.statusCode,
      body: jsonEncode({'error': e.message}),
      headers: {'content-type': 'application/json'},
    );
  } on FormatException {
    return Response(
      400,
      body: jsonEncode({'error': 'Invalid JSON body'}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<Response> _refreshHandler(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final refreshToken = json['refreshToken'] as String?;

    if (refreshToken == null || refreshToken.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'refreshToken is required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final result = await AuthService.refresh(refreshToken);

    return Response.ok(
      jsonEncode(result),
      headers: {'content-type': 'application/json'},
    );
  } on AuthException catch (e) {
    return Response(
      e.statusCode,
      body: jsonEncode({'error': e.message}),
      headers: {'content-type': 'application/json'},
    );
  } on FormatException {
    return Response(
      400,
      body: jsonEncode({'error': 'Invalid JSON body'}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}
