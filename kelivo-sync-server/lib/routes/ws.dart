import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:kelivo_max_sync_server/services/relay_service.dart';

/// Creates a shelf [Handler] that upgrades requests to WebSocket connections.
///
/// Authentication is performed via the first message sent by the client.
/// The client must send `{"token": "<jwt>"}` as its first message. If the
/// token is valid, the connection is registered with [relay] and an
/// `{"status": "authenticated", "userId": <id>}` response is sent back.
///
/// After authentication, the server pushes task events to the client.
/// The client does not send further data messages over this connection.
Handler wsHandler(RelayService relay) {
  return webSocketHandler((WebSocketChannel channel, String? protocol) {
    int? userId;

    channel.stream.listen(
      (message) {
        if (userId != null) {
          // Already authenticated — ignore client data messages.
          return;
        }

        // First message must be auth: {"token": "..."}
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          final token = data['token'] as String?;
          if (token == null) {
            channel.sink.add(jsonEncode({'error': 'Token required'}));
            channel.sink.close();
            return;
          }

          final jwtSecret = Platform.environment['JWT_SECRET'] ?? '';
          if (jwtSecret.isEmpty) {
            channel.sink.add(jsonEncode({'error': 'Server misconfigured'}));
            channel.sink.close();
            return;
          }

          final jwt = JWT.verify(token, SecretKey(jwtSecret));
          final payload = jwt.payload as Map<String, dynamic>;
          userId = payload['userId'] as int;
          relay.addConnection(userId!, channel);
          channel.sink.add(
            jsonEncode({'status': 'authenticated', 'userId': userId}),
          );
        } on JWTExpiredException {
          channel.sink.add(jsonEncode({'error': 'Token expired'}));
          channel.sink.close();
        } on JWTException {
          channel.sink.add(jsonEncode({'error': 'Authentication failed'}));
          channel.sink.close();
        } catch (e) {
          channel.sink.add(jsonEncode({'error': 'Authentication failed'}));
          channel.sink.close();
        }
      },
      onDone: () {
        if (userId != null) {
          relay.removeConnection(userId!, channel);
        }
      },
      onError: (e) {
        if (userId != null) {
          relay.removeConnection(userId!, channel);
        }
      },
    );
  });
}
