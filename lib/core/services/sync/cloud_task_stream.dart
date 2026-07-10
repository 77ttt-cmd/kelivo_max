import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:kelivo_max/core/services/sync/sync_api_client.dart';
import 'package:kelivo_max/core/services/sync/sync_credential_store.dart';

/// Connects to the backend WebSocket relay to receive live cloud task events.
///
/// Falls back to polling via [SyncApiClient.getTask] when the WebSocket
/// connection fails or drops.
class CloudTaskStream {
  final String serverUrl;
  final String taskId;
  final SyncCredentialStore credentialStore;
  final SyncApiClient apiClient;

  WebSocketChannel? _channel;
  final _controller = StreamController<CloudTaskEvent>();
  Timer? _pollTimer;
  bool _disposed = false;

  CloudTaskStream({
    required this.serverUrl,
    required this.taskId,
    required this.credentialStore,
    required this.apiClient,
  });

  /// Stream of task events (chunks, completion, failure).
  Stream<CloudTaskEvent> get stream => _controller.stream;

  /// Start listening — tries WebSocket first, falls back to polling.
  Future<void> connect() async {
    try {
      await _connectWebSocket();
    } catch (e) {
      debugPrint('WebSocket connection failed, falling back to polling: $e');
      _startPolling();
    }
  }

  Future<void> _connectWebSocket() async {
    final wsUrl = serverUrl.replaceFirst('http', 'ws');
    _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/tasks'));

    // Send auth token as the first message.
    final token = await credentialStore.readAccessToken();
    if (token != null) {
      _channel!.sink.add(jsonEncode({'token': token}));
    }

    _channel!.stream.listen(
      (message) {
        if (_disposed) return;
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;

          // Only process events for our task.
          if (data['taskId'] != taskId) return;

          final eventType = data['eventType'] as String?;
          switch (eventType) {
            case 'chunk':
              final content = data['content'] as String? ?? '';
              _controller.add(CloudTaskChunk(content));
            case 'completed':
              final finalContent = data['finalContent'] as String? ?? '';
              final totalTokens = data['totalTokens'] as int? ?? 0;
              _controller.add(
                CloudTaskCompleted(finalContent, totalTokens: totalTokens),
              );
              dispose();
            case 'failed':
              final error = data['error'] as String? ?? 'Unknown error';
              _controller.add(CloudTaskFailed(error));
              dispose();
            default:
              break;
          }
        } catch (e) {
          debugPrint('Error parsing WS message: $e');
        }
      },
      onError: (Object e) {
        if (_disposed) return;
        debugPrint('WebSocket error, falling back to polling: $e');
        _channel = null;
        _startPolling();
      },
      onDone: () {
        if (_disposed) return;
        debugPrint('WebSocket closed, falling back to polling');
        _channel = null;
        _startPolling();
      },
    );
  }

  void _startPolling() {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_disposed) return;
      try {
        final task = await apiClient.getTask(taskId);
        if (_disposed) return;
        final status = task['status'] as String?;

        if (status == 'completed') {
          final content = task['finalContent'] as String? ?? '';
          final totalTokens = task['totalTokens'] as int? ?? 0;
          _controller.add(
            CloudTaskCompleted(content, totalTokens: totalTokens),
          );
          dispose();
        } else if (status == 'failed') {
          final error = task['errorMessage'] as String? ?? 'Unknown error';
          _controller.add(CloudTaskFailed(error));
          dispose();
        }
        // pending/running — continue polling
      } catch (e) {
        debugPrint('Polling error: $e');
      }
    });
  }

  /// Release all resources. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _channel?.sink.close();
    _channel = null;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Events emitted by [CloudTaskStream].
sealed class CloudTaskEvent {
  const CloudTaskEvent._();
}

/// Incremental content chunk from a running cloud task.
class CloudTaskChunk extends CloudTaskEvent {
  final String content;
  const CloudTaskChunk(this.content) : super._();
}

/// Cloud task completed successfully.
class CloudTaskCompleted extends CloudTaskEvent {
  final String finalContent;
  final int totalTokens;
  const CloudTaskCompleted(this.finalContent, {this.totalTokens = 0})
    : super._();
}

/// Cloud task failed with an error message.
class CloudTaskFailed extends CloudTaskEvent {
  final String error;
  const CloudTaskFailed(this.error) : super._();
}
