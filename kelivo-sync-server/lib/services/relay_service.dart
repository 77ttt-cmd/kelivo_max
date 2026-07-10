import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Manages active WebSocket connections indexed by userId.
///
/// Each user may have multiple concurrent connections (e.g. multiple tabs or
/// devices). Messages are broadcast to all connections of a given user.
///
/// When a user has no active connections, events for that user are silently
/// dropped by [sendToUser]. The offline accumulation strategy relies on the
/// existing chunk persistence in [TaskService] — the client fetches missed
/// data via REST on reconnect.
class RelayService {
  /// `Map<userId, Set<WebSocketChannel>>`
  final Map<int, Set<WebSocketChannel>> _connections = {};

  /// Number of users with at least one active connection.
  int get activeUserCount => _connections.length;

  /// Total number of active WebSocket connections across all users.
  int get totalConnectionCount =>
      _connections.values.fold(0, (sum, s) => sum + s.length);

  /// Register a new connection for a user.
  void addConnection(int userId, WebSocketChannel channel) {
    _connections.putIfAbsent(userId, () => {}).add(channel);
    print(
      'WS: User $userId connected '
      '(${_connections[userId]!.length} total)',
    );
  }

  /// Remove a connection.
  void removeConnection(int userId, WebSocketChannel channel) {
    _connections[userId]?.remove(channel);
    if (_connections[userId]?.isEmpty ?? false) {
      _connections.remove(userId);
    }
    print('WS: User $userId disconnected');
  }

  /// Check if a user has active connections.
  bool isOnline(int userId) => _connections[userId]?.isNotEmpty ?? false;

  /// Return the number of active connections for [userId].
  int connectionCount(int userId) => _connections[userId]?.length ?? 0;

  /// Send a message to all connections of a user.
  ///
  /// Connections that fail during send are automatically removed.
  void sendToUser(int userId, Map<String, dynamic> message) {
    final channels = _connections[userId];
    if (channels == null || channels.isEmpty) return;

    final json = jsonEncode(message);
    final toRemove = <WebSocketChannel>[];

    for (final channel in channels) {
      try {
        channel.sink.add(json);
      } catch (e) {
        print('WS: Failed to send to user $userId: $e');
        toRemove.add(channel);
      }
    }

    for (final ch in toRemove) {
      removeConnection(userId, ch);
    }
  }
}
