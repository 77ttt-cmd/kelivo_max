import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'database.dart';

class TaskService {
  /// Valid status values for generation tasks.
  static const validStatuses = {
    'pending',
    'queued',
    'running',
    'completed',
    'failed',
  };

  /// Creates a new generation task after verifying the provider exists.
  ///
  /// Returns the UUID of the created task.
  /// Throws [ArgumentError] if the provider is not found.
  static Future<String> createTask({
    required int userId,
    required String conversationId,
    required String providerSyncId,
    required List<Map<String, dynamic>> messages,
    required Map<String, dynamic> parameters,
  }) async {
    // Verify the provider exists in change_entries for this user.
    final providerResult = await Database.pool.execute(
      Sql.indexed(
        'SELECT record_id FROM change_entries '
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
      throw ArgumentError('Provider not found: $providerSyncId');
    }

    // Insert the task.
    final result = await Database.pool.execute(
      Sql.indexed(
        'INSERT INTO generation_tasks '
        '(user_id, conversation_id, provider_sync_id, messages, parameters, status) '
        'VALUES (\$1, \$2, \$3, \$4::jsonb, \$5::jsonb, \$6) '
        'RETURNING id',
      ),
      parameters: [
        userId,
        TypedValue(Type.text, conversationId),
        TypedValue(Type.text, providerSyncId),
        TypedValue(Type.text, jsonEncode(messages)),
        TypedValue(Type.text, jsonEncode(parameters)),
        TypedValue(Type.text, 'pending'),
      ],
    );

    return result.first[0] as String;
  }

  /// Updates the status of a task.
  static Future<void> updateTaskStatus(String taskId, String status) async {
    assert(validStatuses.contains(status), 'Invalid status: $status');
    await Database.pool.execute(
      Sql.indexed(
        'UPDATE generation_tasks SET status = \$1, updated_at = NOW() '
        'WHERE id = \$2::uuid',
      ),
      parameters: [
        TypedValue(Type.text, status),
        TypedValue(Type.text, taskId),
      ],
    );
  }

  /// Appends a chunk to result_chunks via JSONB concatenation.
  static Future<void> appendChunk(
    String taskId,
    Map<String, dynamic> chunk,
  ) async {
    await Database.pool.execute(
      Sql.indexed(
        'UPDATE generation_tasks '
        'SET result_chunks = result_chunks || \$1::jsonb, updated_at = NOW() '
        'WHERE id = \$2::uuid',
      ),
      parameters: [
        TypedValue(Type.text, jsonEncode([chunk])),
        TypedValue(Type.text, taskId),
      ],
    );
  }

  /// Marks a task as completed with final content.
  static Future<void> completeTask(String taskId, String finalContent) async {
    await Database.pool.execute(
      Sql.indexed(
        'UPDATE generation_tasks '
        'SET status = \$1, final_content = \$2, updated_at = NOW() '
        'WHERE id = \$3::uuid',
      ),
      parameters: [
        TypedValue(Type.text, 'completed'),
        TypedValue(Type.text, finalContent),
        TypedValue(Type.text, taskId),
      ],
    );
  }

  /// Marks a task as failed with an error message.
  static Future<void> failTask(String taskId, String errorMessage) async {
    await Database.pool.execute(
      Sql.indexed(
        'UPDATE generation_tasks '
        'SET status = \$1, error_message = \$2, updated_at = NOW() '
        'WHERE id = \$3::uuid',
      ),
      parameters: [
        TypedValue(Type.text, 'failed'),
        TypedValue(Type.text, errorMessage),
        TypedValue(Type.text, taskId),
      ],
    );
  }

  /// Fetches up to [limit] pending tasks ordered by creation time.
  ///
  /// Returns a list of maps with keys: id, userId, conversationId,
  /// providerSyncId, messages, parameters.
  static Future<List<Map<String, dynamic>>> getPendingTasks({
    int limit = 10,
  }) async {
    final result = await Database.pool.execute(
      Sql.indexed(
        'SELECT id, user_id, conversation_id, provider_sync_id, '
        'messages, parameters '
        'FROM generation_tasks '
        'WHERE status = \$1 '
        'ORDER BY created_at ASC '
        'LIMIT \$2',
      ),
      parameters: [TypedValue(Type.text, 'pending'), limit],
    );

    return result.map((row) {
      final messagesRaw = row[4];
      final parametersRaw = row[5];
      return <String, dynamic>{
        'id': row[0] as String,
        'userId': row[1] as int,
        'conversationId': row[2] as String,
        'providerSyncId': row[3] as String,
        'messages': messagesRaw is List
            ? messagesRaw
            : jsonDecode(messagesRaw as String),
        'parameters': parametersRaw is Map
            ? Map<String, dynamic>.from(parametersRaw)
            : jsonDecode(parametersRaw as String) as Map<String, dynamic>,
      };
    }).toList();
  }

  /// Retrieves a task by id, scoped to the given user.
  ///
  /// Returns null if the task does not exist or belongs to another user.
  static Future<Map<String, dynamic>?> getTask(
    int userId,
    String taskId,
  ) async {
    final result = await Database.pool.execute(
      Sql.indexed(
        'SELECT id, conversation_id, provider_sync_id, status, '
        'result_chunks, final_content, error_message, created_at, updated_at '
        'FROM generation_tasks '
        'WHERE id = \$1::uuid AND user_id = \$2',
      ),
      parameters: [TypedValue(Type.text, taskId), userId],
    );

    if (result.isEmpty) return null;

    final row = result.first;
    final resultChunksRaw = row[4];
    final List<dynamic> resultChunks;
    if (resultChunksRaw is List) {
      resultChunks = resultChunksRaw;
    } else if (resultChunksRaw is String) {
      resultChunks = jsonDecode(resultChunksRaw) as List<dynamic>;
    } else {
      resultChunks = [];
    }

    return {
      'id': row[0],
      'conversationId': row[1],
      'providerSyncId': row[2],
      'status': row[3],
      'resultChunks': resultChunks,
      'finalContent': row[5],
      'errorMessage': row[6],
      'createdAt': (row[7] as DateTime).toIso8601String(),
      'updatedAt': (row[8] as DateTime).toIso8601String(),
    };
  }
}
