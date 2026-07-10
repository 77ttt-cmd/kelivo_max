import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart';

import 'database.dart';

class AuthService {
  static String get _jwtSecret {
    final secret = Platform.environment['JWT_SECRET'];
    if (secret == null || secret.isEmpty) {
      throw StateError('JWT_SECRET environment variable is not set');
    }
    return secret;
  }

  /// Register a new user. Returns the user id.
  /// Throws [AuthException] with status 409 if username already exists.
  static Future<int> register(String username, String password) async {
    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());

    try {
      final result = await Database.pool.execute(
        Sql.named(
          'INSERT INTO users (username, password_hash) '
          'VALUES (@username, @passwordHash) RETURNING id',
        ),
        parameters: {'username': username, 'passwordHash': passwordHash},
      );
      return result.first[0] as int;
    } on ServerException catch (e) {
      // PostgreSQL unique_violation error code is 23505
      if (e.message.contains('unique') ||
          e.message.contains('duplicate') ||
          e.message.contains('23505')) {
        throw AuthException(409, 'Username already exists');
      }
      rethrow;
    }
  }

  /// Login with username and password.
  /// Returns a map with accessToken and refreshToken.
  /// Throws [AuthException] with status 401 if credentials are invalid.
  static Future<Map<String, String>> login(
    String username,
    String password,
  ) async {
    final result = await Database.pool.execute(
      Sql.named(
        'SELECT id, password_hash FROM users WHERE username = @username',
      ),
      parameters: {'username': username},
    );

    if (result.isEmpty) {
      throw AuthException(401, 'Invalid username or password');
    }

    final row = result.first;
    final userId = row[0] as int;
    final storedHash = row[1] as String;

    if (!BCrypt.checkpw(password, storedHash)) {
      throw AuthException(401, 'Invalid username or password');
    }

    final accessToken = _generateAccessToken(userId);
    final refreshToken = _generateRefreshToken();
    final expiresAt = DateTime.now().toUtc().add(const Duration(days: 30));

    await Database.pool.execute(
      Sql.named(
        'INSERT INTO refresh_tokens (user_id, token, expires_at) '
        'VALUES (@userId, @token, @expiresAt)',
      ),
      parameters: {
        'userId': userId,
        'token': refreshToken,
        'expiresAt': expiresAt,
      },
    );

    return {'accessToken': accessToken, 'refreshToken': refreshToken};
  }

  /// Refresh an access token using a refresh token.
  /// Returns a map with the new accessToken.
  /// Throws [AuthException] with status 401 if refresh token is invalid or expired.
  static Future<Map<String, String>> refresh(String refreshToken) async {
    final result = await Database.pool.execute(
      Sql.named(
        'SELECT user_id, expires_at FROM refresh_tokens WHERE token = @token',
      ),
      parameters: {'token': refreshToken},
    );

    if (result.isEmpty) {
      throw AuthException(401, 'Invalid refresh token');
    }

    final row = result.first;
    final userId = row[0] as int;
    final expiresAt = row[1] as DateTime;

    if (expiresAt.isBefore(DateTime.now().toUtc())) {
      // Clean up expired token
      await Database.pool.execute(
        Sql.named('DELETE FROM refresh_tokens WHERE token = @token'),
        parameters: {'token': refreshToken},
      );
      throw AuthException(401, 'Refresh token expired');
    }

    final accessToken = _generateAccessToken(userId);
    return {'accessToken': accessToken};
  }

  static String _generateAccessToken(int userId) {
    final jwt = JWT({'userId': userId});
    return jwt.sign(
      SecretKey(_jwtSecret),
      expiresIn: const Duration(minutes: 15),
    );
  }

  static String _generateRefreshToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return sha256.convert(bytes).toString();
  }
}

class AuthException implements Exception {
  final int statusCode;
  final String message;

  AuthException(this.statusCode, this.message);

  @override
  String toString() => 'AuthException($statusCode): $message';
}
