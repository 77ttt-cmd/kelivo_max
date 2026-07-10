import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/push_service.dart';

Router deviceRouter() {
  final router = Router();

  router.post('/', _registerDeviceHandler);
  router.delete('/<token>', _unregisterDeviceHandler);

  return router;
}

/// POST /api/devices
/// Body: {"platform": "android"|"ios", "pushToken": "..."}
Future<Response> _registerDeviceHandler(Request request) async {
  try {
    final userId = request.context['userId'] as int;

    final Map<String, dynamic> body;
    try {
      final bodyStr = await request.readAsString();
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } on FormatException {
      return Response(
        400,
        body: jsonEncode({'error': 'Invalid JSON body'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final platform = body['platform'] as String?;
    final pushToken = body['pushToken'] as String?;

    if (platform == null || platform.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'platform is required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final validPlatforms = {'android', 'ios'};
    if (!validPlatforms.contains(platform)) {
      return Response(
        400,
        body: jsonEncode({
          'error': 'platform must be one of: ${validPlatforms.join(', ')}',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    if (pushToken == null || pushToken.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'pushToken is required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    await PushService.registerDevice(userId, platform, pushToken);

    return Response(
      201,
      body: jsonEncode({'message': 'Device registered'}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}

/// `DELETE /api/devices/<token>`
Future<Response> _unregisterDeviceHandler(Request request, String token) async {
  try {
    final userId = request.context['userId'] as int;

    final decodedToken = Uri.decodeComponent(token);
    if (decodedToken.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'Token path parameter is required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    await PushService.unregisterDevice(userId, decodedToken);

    return Response.ok(
      jsonEncode({'message': 'Device unregistered'}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}
