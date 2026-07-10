import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/task_service.dart';

Router taskRouter() {
  final router = Router();

  router.post('/', _createTaskHandler);
  router.get('/<id>', _getTaskHandler);

  return router;
}

Future<Response> _createTaskHandler(Request request) async {
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

    final conversationId = body['conversationId'] as String?;
    final providerSyncId = body['providerSyncId'] as String?;
    final messages = body['messages'] as List?;
    final parameters = body['parameters'] as Map<String, dynamic>?;

    if (conversationId == null || conversationId.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'conversationId is required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    if (providerSyncId == null || providerSyncId.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'providerSyncId is required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    if (messages == null || messages.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'error': 'messages is required and must not be empty',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final typedMessages = messages.cast<Map<String, dynamic>>();

    try {
      final taskId = await TaskService.createTask(
        userId: userId,
        conversationId: conversationId,
        providerSyncId: providerSyncId,
        messages: typedMessages,
        parameters: parameters ?? {},
      );

      return Response(
        201,
        body: jsonEncode({'taskId': taskId}),
        headers: {'content-type': 'application/json'},
      );
    } on ArgumentError catch (e) {
      return Response(
        404,
        body: jsonEncode({'error': e.message}),
        headers: {'content-type': 'application/json'},
      );
    }
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<Response> _getTaskHandler(Request request, String id) async {
  try {
    final userId = request.context['userId'] as int;

    // Basic UUID format validation.
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (!uuidPattern.hasMatch(id)) {
      return Response(
        400,
        body: jsonEncode({'error': 'Invalid task id format'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final task = await TaskService.getTask(userId, id);

    if (task == null) {
      return Response.notFound(
        jsonEncode({'error': 'Task not found'}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(task),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}
