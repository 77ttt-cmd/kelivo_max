import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/sync/sync_credential_store.dart';

/// Result of a pull-changes request.
class PullChangesResult {
  final List<Map<String, dynamic>> entries;
  final int latestSeq;
  final bool hasMore;

  PullChangesResult({
    required this.entries,
    required this.latestSeq,
    required this.hasMore,
  });
}

/// Result of a push-changes request.
class PushChangesResult {
  final int accepted;
  final List<String> skipped;
  final int latestSeq;

  PushChangesResult({
    required this.accepted,
    required this.skipped,
    required this.latestSeq,
  });
}

/// API client for communication with the Kelivo sync server.
///
/// Wraps HTTP calls to the backend:
///   - Auth: POST /auth/register, POST /auth/login, POST /auth/refresh
///   - Data: GET /api/changes
///   - Files: GET /api/files/:hash, GET /api/files/exists
///
/// Authenticated endpoints automatically retry once on 401 by refreshing
/// the access token.
class SyncApiClient {
  final String serverUrl;
  final SyncCredentialStore _credentialStore;
  final http.Client _httpClient;

  SyncApiClient({
    required this.serverUrl,
    required this._credentialStore,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Register a new user account.
  Future<void> register(String username, String password) async {
    final response = await _httpClient.post(
      Uri.parse('$serverUrl/auth/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode != 201) {
      throw SyncApiException(response.statusCode, _parseError(response));
    }
  }

  /// Login and persist tokens via [SyncCredentialStore].
  Future<void> login(String username, String password) async {
    final response = await _httpClient.post(
      Uri.parse('$serverUrl/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode != 200) {
      throw SyncApiException(response.statusCode, _parseError(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _credentialStore.saveAccessToken(body['accessToken'] as String);
    await _credentialStore.saveRefreshToken(body['refreshToken'] as String);
  }

  /// Refresh the access token using the stored refresh token.
  ///
  /// Returns `true` when the token was successfully refreshed.
  Future<bool> refreshToken() async {
    final refreshToken = await _credentialStore.readRefreshToken();
    if (refreshToken == null) return false;

    final response = await _httpClient.post(
      Uri.parse('$serverUrl/auth/refresh'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (response.statusCode != 200) return false;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _credentialStore.saveAccessToken(body['accessToken'] as String);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Sync Data
  // ---------------------------------------------------------------------------

  /// Pull change entries from the server since the given cursor.
  Future<PullChangesResult> pullChanges(
    int since,
    List<SyncCategory> categories,
  ) async {
    final cats = categories.map((c) => c.toKey()).join(',');
    final response = await _authenticatedGet(
      '/api/changes?since=$since&categories=$cats',
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = (body['entries'] as List).cast<Map<String, dynamic>>();
    return PullChangesResult(
      entries: entries,
      latestSeq: body['latestSeq'] as int? ?? since,
      hasMore: body['hasMore'] as bool? ?? false,
    );
  }

  /// Push local changes to the server.
  ///
  /// Returns accepted count, skipped record IDs, and new latestSeq.
  Future<PushChangesResult> pushChanges(
    List<Map<String, dynamic>> entries,
  ) async {
    final response = await authenticatedPost('/api/changes', {
      'entries': entries,
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PushChangesResult(
      accepted: body['accepted'] as int? ?? 0,
      skipped: (body['skipped'] as List?)?.cast<String>() ?? [],
      latestSeq: body['latestSeq'] as int? ?? 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------------

  /// Download a file by its SHA-256 hash.
  Future<Uint8List> downloadFile(String hash) async {
    final response = await _authenticatedGet('/api/files/$hash');
    return response.bodyBytes;
  }

  /// Upload a file to the sync server.
  ///
  /// The file content is base64-encoded and sent as JSON to POST /api/files.
  /// Returns `true` if newly stored, `false` if the server already had it.
  Future<bool> uploadFile({
    required String hash,
    required String path,
    required List<int> bytes,
    String contentType = 'application/octet-stream',
  }) async {
    final response = await authenticatedPost('/api/files', {
      'hash': hash,
      'path': path,
      'contentType': contentType,
      'content': base64Encode(bytes),
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return !(body['existed'] as bool? ?? false);
  }

  /// Check which file hashes already exist on the server.
  Future<Map<String, bool>> checkFilesExist(List<String> hashes) async {
    final hashParam = hashes.join(',');
    final response = await _authenticatedGet(
      '/api/files/exists?hashes=$hashParam',
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body.map((k, v) => MapEntry(k, v as bool));
  }

  // ---------------------------------------------------------------------------
  // Cloud Execution Tasks
  // ---------------------------------------------------------------------------

  /// Submit a generation task to the cloud.
  ///
  /// Returns the server-assigned task ID that can be used to poll for results
  /// via [getTask] or consumed via WebSocket (P4-C2).
  Future<String> submitTask({
    required String conversationId,
    required String providerSyncId,
    required List<Map<String, dynamic>> messages,
    required Map<String, dynamic> parameters,
  }) async {
    final response = await authenticatedPost('/api/tasks', {
      'conversationId': conversationId,
      'providerSyncId': providerSyncId,
      'messages': messages,
      'parameters': parameters,
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['taskId'] as String;
  }

  /// Get task status and results.
  ///
  /// The returned map contains at least `status` (`pending`, `running`,
  /// `completed`, or `failed`).  When `completed`, it includes
  /// `finalContent`.  When `failed`, it includes `errorMessage`.
  Future<Map<String, dynamic>> getTask(String taskId) async {
    final response = await _authenticatedGet('/api/tasks/$taskId');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Authenticated requests (public for push usage by downstream tasks)
  // ---------------------------------------------------------------------------

  /// Authenticated POST with one automatic 401-retry.
  Future<http.Response> authenticatedPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    var response = await _doPost(path, body);
    if (response.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        response = await _doPost(path, body);
      }
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw SyncApiException(response.statusCode, _parseError(response));
    }
    return response;
  }

  // ---------------------------------------------------------------------------
  // Device Registration (Push Notifications)
  // ---------------------------------------------------------------------------

  /// Register device push token.
  Future<void> registerDevice(String platform, String pushToken) async {
    await authenticatedPost('/api/devices', {
      'platform': platform,
      'pushToken': pushToken,
    });
  }

  /// Unregister device push token.
  Future<void> unregisterDevice(String pushToken) async {
    var response = await _doDelete('/api/devices/$pushToken');
    if (response.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        response = await _doDelete('/api/devices/$pushToken');
      }
    }
    // 200 or 204 are both acceptable for a successful delete.
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw SyncApiException(response.statusCode, _parseError(response));
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Authenticated GET with one automatic 401-retry.
  Future<http.Response> _authenticatedGet(String path) async {
    var response = await _doGet(path);
    if (response.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        response = await _doGet(path);
      }
    }
    if (response.statusCode != 200) {
      throw SyncApiException(response.statusCode, _parseError(response));
    }
    return response;
  }

  Future<http.Response> _doGet(String path) async {
    final token = await _credentialStore.readAccessToken();
    return _httpClient.get(
      Uri.parse('$serverUrl$path'),
      headers: {if (token != null) 'authorization': 'Bearer $token'},
    );
  }

  Future<http.Response> _doPost(String path, Map<String, dynamic> body) async {
    final token = await _credentialStore.readAccessToken();
    return _httpClient.post(
      Uri.parse('$serverUrl$path'),
      headers: {
        if (token != null) 'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _doDelete(String path) async {
    final token = await _credentialStore.readAccessToken();
    return _httpClient.delete(
      Uri.parse('$serverUrl$path'),
      headers: {if (token != null) 'authorization': 'Bearer $token'},
    );
  }

  String _parseError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? 'Unknown error';
    } catch (_) {
      return response.body;
    }
  }

  /// Release the underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }
}

/// Exception thrown by [SyncApiClient] on non-success HTTP responses.
class SyncApiException implements Exception {
  final int statusCode;
  final String message;

  SyncApiException(this.statusCode, this.message);

  @override
  String toString() => 'SyncApiException($statusCode): $message';
}
