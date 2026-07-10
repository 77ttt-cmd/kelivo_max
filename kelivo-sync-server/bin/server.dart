import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:kelivo_sync_server/middleware/auth_middleware.dart';
import 'package:kelivo_sync_server/routes/auth.dart';
import 'package:kelivo_sync_server/routes/changes.dart';
import 'package:kelivo_sync_server/routes/devices.dart';
import 'package:kelivo_sync_server/routes/files.dart';
import 'package:kelivo_sync_server/routes/health.dart';
import 'package:kelivo_sync_server/routes/tasks.dart';
import 'package:kelivo_sync_server/routes/ws.dart';
import 'package:kelivo_sync_server/services/database.dart';
import 'package:kelivo_sync_server/services/push_service.dart';
import 'package:kelivo_sync_server/services/relay_service.dart';
import 'package:kelivo_sync_server/services/stream_dispatcher.dart';

void main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final host = Platform.environment['HOST'] ?? '0.0.0.0';

  // Initialize database
  await Database.init();
  await Database.createTables();
  print('Database initialized');

  // Start background stream dispatcher for generation tasks.
  final dispatcher = StreamDispatcher(maxConcurrent: 5);
  dispatcher.start();

  // Initialize relay service and wire dispatcher events to WebSocket clients.
  final relay = RelayService();
  dispatcher.onTaskEvent = (taskId, userId, eventType, data) {
    // Always relay via WebSocket if user is online.
    relay.sendToUser(userId, {
      'taskId': taskId,
      'eventType': eventType,
      ...data,
    });

    // Send push notification for terminal events when user is offline.
    if (!relay.isOnline(userId)) {
      if (eventType == 'completed') {
        PushService.sendPushNotification(
          userId: userId,
          taskId: taskId,
          conversationId: data['conversationId'] as String? ?? '',
          title: 'Generation Complete',
          body: 'Your cloud generation task has finished.',
        );
      } else if (eventType == 'failed') {
        PushService.sendPushNotification(
          userId: userId,
          taskId: taskId,
          conversationId: data['conversationId'] as String? ?? '',
          title: 'Generation Failed',
          body: data['error'] as String? ?? 'An error occurred.',
        );
      }
    }
  };

  // --- Public routes (no auth required) ---
  final router = Router();

  // Health check
  router.get('/health', healthHandler);

  // Auth routes
  router.mount('/', authRouter().call);

  // WebSocket endpoint — auth is handled in-band via first message
  router.get('/ws/tasks', wsHandler(relay));

  // --- Protected routes (JWT auth required) ---
  final protectedRouter = Router();

  // GET /me — returns the authenticated user's id (useful for token validation)
  protectedRouter.get('/me', (Request request) {
    final userId = request.context['userId'] as int;
    return Response.ok(
      jsonEncode({'userId': userId}),
      headers: {'content-type': 'application/json'},
    );
  });

  // Changes (changelog pull)
  protectedRouter.mount('/', changesRouter().call);

  // File routes (download, exists check)
  protectedRouter.mount('/files/', fileRouter().call);

  // Task routes (generation task submission and status)
  protectedRouter.mount('/tasks/', taskRouter().call);

  // Device routes (push token registration)
  protectedRouter.mount('/devices/', deviceRouter().call);

  final protectedHandler = const Pipeline()
      .addMiddleware(authMiddleware())
      .addHandler(protectedRouter.call);

  // Mount protected routes
  router.mount('/api/', protectedHandler);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, host, port);
  print('Server running on http://${server.address.host}:${server.port}');
}
