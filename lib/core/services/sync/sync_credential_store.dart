import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure credential storage for sync authentication.
///
/// Stores sync password, access token, and refresh token
/// using platform-native secure storage (Keychain on iOS/macOS,
/// EncryptedSharedPreferences on Android, libsecret on Linux,
/// Windows Credential Manager on Windows).
class SyncCredentialStore {
  SyncCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPassword = 'sync_password';
  static const _keyAccessToken = 'sync_access_token';
  static const _keyRefreshToken = 'sync_refresh_token';

  // --- Password ---

  Future<void> savePassword(String password) =>
      _storage.write(key: _keyPassword, value: password);

  Future<String?> readPassword() => _storage.read(key: _keyPassword);

  Future<void> deletePassword() => _storage.delete(key: _keyPassword);

  // --- Access Token ---

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _keyAccessToken, value: token);

  Future<String?> readAccessToken() => _storage.read(key: _keyAccessToken);

  Future<void> deleteAccessToken() => _storage.delete(key: _keyAccessToken);

  // --- Refresh Token ---

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _keyRefreshToken);

  Future<void> deleteRefreshToken() => _storage.delete(key: _keyRefreshToken);

  // --- Bulk Operations ---

  /// Delete all three sync credential keys.
  Future<void> clearAll() async {
    await deletePassword();
    await deleteAccessToken();
    await deleteRefreshToken();
  }
}
