import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

import 'database.dart';
import 'encryption_service.dart';
import 'task_service.dart';

/// Callback type for notifying about task events (chunks, completion, failure).
typedef TaskEventCallback =
    void Function(
      String taskId,
      int userId,
      String eventType,
      Map<String, dynamic> data,
    );

/// Background worker that polls for pending generation tasks and executes them.
///
/// For each pending task the dispatcher:
/// 1. Sets it to 'running'
/// 2. Looks up the provider config from change_entries by providerSyncId
/// 3. Decrypts the API key via [EncryptionService]
/// 4. Makes a streaming HTTP request to the AI provider (OpenAI-compatible)
/// 5. Appends chunks to the task as they arrive
/// 6. On completion, writes final_content
/// 7. On error, marks the task as failed
class StreamDispatcher {
  Timer? _pollTimer;

  /// Maximum number of concurrent task executions.
  final int maxConcurrent;

  int _running = 0;

  /// Optional callback invoked on each task event.
  TaskEventCallback? onTaskEvent;

  StreamDispatcher({this.maxConcurrent = 5});

  /// Whether the dispatcher is currently running.
  bool get isRunning => _pollTimer != null;

  /// Number of currently executing tasks.
  int get runningCount => _running;

  /// Starts polling for pending tasks every [interval].
  void start({Duration interval = const Duration(seconds: 5)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _poll());
    print(
      'StreamDispatcher started, polling every ${interval.inSeconds}s, '
      'max concurrent: $maxConcurrent',
    );
  }

  /// Stops the polling timer. In-flight tasks will finish naturally.
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    print('StreamDispatcher stopped');
  }

  Future<void> _poll() async {
    if (_running >= maxConcurrent) return;

    try {
      final tasks = await TaskService.getPendingTasks(
        limit: maxConcurrent - _running,
      );
      for (final task in tasks) {
        _running++;
        _executeTask(task).whenComplete(() => _running--);
      }
    } catch (e) {
      print('StreamDispatcher poll error: $e');
    }
  }

  Future<void> _executeTask(Map<String, dynamic> task) async {
    final taskId = task['id'] as String;
    final userId = task['userId'] as int;

    try {
      await TaskService.updateTaskStatus(taskId, 'running');
      _notifyEvent(taskId, userId, 'status', {'status': 'running'});

      // Look up provider config from change_entries.
      final providerSyncId = task['providerSyncId'] as String;
      final providerResult = await Database.pool.execute(
        Sql.indexed(
          'SELECT payload FROM change_entries '
          'WHERE user_id = \$1 AND category = \$2 AND record_id = \$3 '
          'AND deleted_at IS NULL',
        ),
        parameters: [
          userId,
          TypedValue(Type.text, 'providers'),
          TypedValue(Type.text, providerSyncId),
        ],
      );

      if (providerResult.isEmpty) {
        await TaskService.failTask(taskId, 'Provider config not found');
        _notifyEvent(taskId, userId, 'failed', {
          'error': 'Provider config not found',
        });
        return;
      }

      // Parse the provider payload.
      final payloadRaw = providerResult.first[0];
      final Map<String, dynamic> encryptedPayload;
      if (payloadRaw is Map) {
        encryptedPayload = Map<String, dynamic>.from(payloadRaw);
      } else if (payloadRaw is String) {
        encryptedPayload = jsonDecode(payloadRaw) as Map<String, dynamic>;
      } else {
        encryptedPayload = <String, dynamic>{};
      }

      // Decrypt sensitive fields (e.g. apiKey).
      final decryptedPayload = await EncryptionService.decryptPayload(
        userId,
        'providers',
        encryptedPayload,
      );

      final apiKey = decryptedPayload['apiKey'] as String? ?? '';
      final apiBaseUrl = decryptedPayload['apiBaseUrl'] as String? ?? '';
      final parameters =
          task['parameters'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final model = parameters['model'] as String? ?? '';

      if (apiKey.isEmpty) {
        await TaskService.failTask(
          taskId,
          'API key not found in provider config',
        );
        _notifyEvent(taskId, userId, 'failed', {'error': 'API key not found'});
        return;
      }

      // Build the streaming request to an OpenAI-compatible endpoint.
      final messages = task['messages'] as List;
      final requestBody = jsonEncode(<String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': true,
        ...parameters,
      });

      final baseUrl = apiBaseUrl.isNotEmpty
          ? apiBaseUrl
          : 'https://api.openai.com';
      final uri = Uri.parse('$baseUrl/v1/chat/completions');
      final client = HttpClient();

      try {
        final request = await client.postUrl(uri);
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('Authorization', 'Bearer $apiKey');
        request.write(requestBody);

        final response = await request.close();

        if (response.statusCode != 200) {
          final body = await response.transform(utf8.decoder).join();
          await TaskService.failTask(
            taskId,
            'Provider returned ${response.statusCode}: $body',
          );
          _notifyEvent(taskId, userId, 'failed', {
            'error': 'Provider error: ${response.statusCode}',
          });
          return;
        }

        // Parse SSE stream.
        final contentBuffer = StringBuffer();

        await for (final rawChunk in response.transform(utf8.decoder)) {
          final lines = rawChunk.split('\n');
          for (final line in lines) {
            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6).trim();
            if (data == '[DONE]') continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final choices = json['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final delta =
                    (choices[0] as Map<String, dynamic>)['delta']
                        as Map<String, dynamic>?;
                final content = delta?['content'] as String?;
                if (content != null) {
                  contentBuffer.write(content);
                  final chunk = <String, dynamic>{
                    'content': content,
                    'ts': DateTime.now().millisecondsSinceEpoch,
                  };
                  await TaskService.appendChunk(taskId, chunk);
                  _notifyEvent(taskId, userId, 'chunk', chunk);
                }
              }
            } catch (_) {
              // Skip malformed SSE data lines.
            }
          }
        }

        final finalContent = contentBuffer.toString();
        await TaskService.completeTask(taskId, finalContent);
        _notifyEvent(taskId, userId, 'completed', {
          'finalContent': finalContent,
        });
      } finally {
        client.close();
      }
    } catch (e) {
      await TaskService.failTask(taskId, e.toString());
      _notifyEvent(taskId, userId, 'failed', {'error': e.toString()});
    }
  }

  void _notifyEvent(
    String taskId,
    int userId,
    String eventType,
    Map<String, dynamic> data,
  ) {
    onTaskEvent?.call(taskId, userId, eventType, data);
  }
}
