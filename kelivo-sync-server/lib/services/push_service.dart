import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'database.dart';

/// Manages device push token registration and push notification delivery.
///
/// **Architecture decision — no FCM dependency:**
///
/// ~40 % of users are in mainland China where Google Play Services (and thus
/// FCM) are unavailable. Instead of depending on FCM we use:
///
/// - **iOS (all regions):** Direct APNs HTTP/2 with JWT token-based auth.
///   Apple services work normally in China.
/// - **Android (all regions):** The client maintains a WebSocket connection
///   (via foreground service when backgrounded). When the server finishes a
///   cloud task the chunk/completion event reaches the client through the
///   WebSocket relay, and the client shows a *local* notification via
///   `flutter_local_notifications`. No external push channel is needed.
///   If the app is fully killed, the result is recovered on next launch via
///   `ChatService.recoverCloudTasks`.
///
/// Environment variables for APNs:
/// - `APNS_KEY_ID`    — 10-char Key ID from Apple Developer portal.
/// - `APNS_TEAM_ID`   — 10-char Team ID from Apple Developer portal.
/// - `APNS_KEY_P8`    — Raw `.p8` private key content (including header).
/// - `APNS_BUNDLE_ID` — App bundle id (e.g. `com.example.kelivo`).
/// - `APNS_SANDBOX`   — `true` to use the sandbox endpoint.
class PushService {
  // ---------------------------------------------------------------------------
  // Device registration
  // ---------------------------------------------------------------------------

  /// Register a device push token for a user.
  static Future<void> registerDevice(
    int userId,
    String platform,
    String pushToken,
  ) async {
    await Database.pool.execute(
      r'''INSERT INTO devices (user_id, platform, push_token)
          VALUES ($1, $2, $3)
          ON CONFLICT (user_id, push_token)
          DO UPDATE SET platform = EXCLUDED.platform''',
      parameters: [userId, platform, pushToken],
    );
  }

  /// Unregister a device push token.
  static Future<void> unregisterDevice(int userId, String pushToken) async {
    await Database.pool.execute(
      r'DELETE FROM devices WHERE user_id = $1 AND push_token = $2',
      parameters: [userId, pushToken],
    );
  }

  /// Get all device tokens for a user.
  static Future<List<Map<String, String>>> getDeviceTokens(int userId) async {
    final result = await Database.pool.execute(
      r'SELECT platform, push_token FROM devices WHERE user_id = $1',
      parameters: [userId],
    );
    return result
        .map(
          (row) => {
            'platform': row[0] as String,
            'pushToken': row[1] as String,
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Notification dispatch
  // ---------------------------------------------------------------------------

  /// Send push notification to a user's registered devices.
  ///
  /// - **iOS devices** receive a real APNs push.
  /// - **Android devices** are skipped — they rely on the WebSocket relay
  ///   (online) or `recoverCloudTasks` on next app launch (offline). This
  ///   avoids any dependency on Google/FCM which is blocked in China.
  static Future<void> sendPushNotification({
    required int userId,
    required String taskId,
    required String conversationId,
    required String title,
    required String body,
  }) async {
    final devices = await getDeviceTokens(userId);

    for (final device in devices) {
      final platform = device['platform']!;
      final token = device['pushToken']!;

      try {
        if (platform == 'ios') {
          await _sendApns(token, taskId, conversationId, title, body);
        }
        // Android: intentionally skipped — see class doc.
      } catch (e) {
        print('Push notification failed for $platform token: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // APNs HTTP/2 direct (JWT token-based auth)
  // ---------------------------------------------------------------------------

  static String get _apnsKeyId => Platform.environment['APNS_KEY_ID'] ?? '';
  static String get _apnsTeamId => Platform.environment['APNS_TEAM_ID'] ?? '';
  static String get _apnsKeyP8 => Platform.environment['APNS_KEY_P8'] ?? '';
  static String get _apnsBundleId =>
      Platform.environment['APNS_BUNDLE_ID'] ?? '';
  static bool get _apnsSandbox =>
      Platform.environment['APNS_SANDBOX'] == 'true';

  /// Build a short-lived JWT for APNs token-based authentication.
  ///
  /// See: https://developer.apple.com/documentation/usernotifications/
  ///      establishing-a-token-based-connection-to-apns
  static String _buildApnsJwt() {
    final keyId = _apnsKeyId;
    final teamId = _apnsTeamId;
    final keyP8 = _apnsKeyP8;

    if (keyId.isEmpty || teamId.isEmpty || keyP8.isEmpty) {
      throw StateError(
        'APNs not configured. Set APNS_KEY_ID, APNS_TEAM_ID, and APNS_KEY_P8.',
      );
    }

    final now = DateTime.now().toUtc();
    final jwt = JWT(
      {'iss': teamId, 'iat': now.millisecondsSinceEpoch ~/ 1000},
      header: {'alg': 'ES256', 'kid': keyId},
    );
    return jwt.sign(ECPrivateKey(keyP8), algorithm: JWTAlgorithm.ES256);
  }

  /// Send a push notification directly via the APNs HTTP/2 API.
  ///
  /// Dart's `HttpClient` negotiates HTTP/2 via ALPN when connecting to an
  /// HTTP/2-only server like `api.push.apple.com`.
  static Future<void> _sendApns(
    String deviceToken,
    String taskId,
    String conversationId,
    String title,
    String body,
  ) async {
    final bundleId = _apnsBundleId;
    if (bundleId.isEmpty) {
      print('APNS_BUNDLE_ID not configured, skipping APNs push');
      return;
    }

    final host = _apnsSandbox
        ? 'api.sandbox.push.apple.com'
        : 'api.push.apple.com';

    final jwt = _buildApnsJwt();

    final payload = jsonEncode({
      'aps': {
        'alert': {'title': title, 'body': body},
        'sound': 'default',
        'mutable-content': 1,
      },
      'taskId': taskId,
      'conversationId': conversationId,
    });

    final client = HttpClient();
    try {
      final url = Uri.parse('https://$host/3/device/$deviceToken');
      final req = await client.postUrl(url);
      req.headers.set('authorization', 'bearer $jwt');
      req.headers.set('apns-topic', bundleId);
      req.headers.set('apns-push-type', 'alert');
      req.headers.set('apns-priority', '10');
      req.headers.set('apns-expiration', '0');
      req.headers.set('content-type', 'application/json');
      req.write(payload);

      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();

      if (resp.statusCode != 200) {
        print(
          'APNs push failed (${resp.statusCode}): $respBody '
          '(device=$deviceToken)',
        );
      }
    } finally {
      client.close();
    }
  }
}
