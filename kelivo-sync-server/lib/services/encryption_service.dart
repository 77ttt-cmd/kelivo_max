import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:postgres/postgres.dart';

import 'database.dart';

/// Envelope encryption service using AES-256-GCM.
///
/// Architecture:
///   Master Key (from env KMS_MASTER_KEY)
///     └── encrypts per-user DEK (Data Encryption Key)
///           └── encrypts individual sensitive field values
///
/// Encrypted values are stored as:
///   `{"__encrypted": true, "v": "<base64(nonce + ciphertext + mac)>"}`
class EncryptionService {
  static const sensitiveFields = {
    'apiKey',
    'apiKeys',
    'serviceAccountJson',
    'proxyPassword',
    'password',
    'secretAccessKey',
    'accessKeyId',
    'sessionToken',
    'key',
  };

  static const sensitiveCategories = {
    'providers',
    'searchServices',
    'ttsServices',
  };

  static final _algorithm = AesGcm.with256bits();

  /// The master key, lazily loaded from KMS_MASTER_KEY env var.
  static SecretKey? _masterKey;

  /// Returns the master key, reading from environment on first call.
  /// Throws if KMS_MASTER_KEY is not set or invalid.
  static Future<SecretKey> getMasterKey() async {
    if (_masterKey != null) return _masterKey!;

    final envValue = Platform.environment['KMS_MASTER_KEY'];
    if (envValue == null || envValue.isEmpty) {
      throw StateError(
        'KMS_MASTER_KEY environment variable is not set. '
        'Encryption cannot proceed without a master key.',
      );
    }

    final keyBytes = _decodeKey(envValue);
    if (keyBytes.length != 32) {
      throw StateError(
        'KMS_MASTER_KEY must be exactly 32 bytes (256 bits). '
        'Got ${keyBytes.length} bytes.',
      );
    }

    _masterKey = SecretKeyData(keyBytes);
    return _masterKey!;
  }

  /// Allows injecting a master key for testing without env vars.
  static void setMasterKeyForTest(SecretKey key) {
    _masterKey = key;
  }

  /// Resets cached master key (for testing).
  static void resetMasterKey() {
    _masterKey = null;
  }

  /// Decodes a key string that is either hex or base64 encoded.
  static Uint8List _decodeKey(String encoded) {
    // Try hex first (64 hex chars = 32 bytes).
    if (encoded.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(encoded)) {
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = int.parse(encoded.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return bytes;
    }
    // Fall back to base64.
    return base64Decode(encoded);
  }

  /// Gets or creates a per-user DEK (Data Encryption Key).
  ///
  /// If the user already has an encrypted DEK stored, it is decrypted with
  /// the master key and returned. Otherwise a new random DEK is generated,
  /// encrypted with the master key, and stored.
  static Future<SecretKey> getUserDek(int userId) async {
    final masterKey = await getMasterKey();

    // Check if user already has a stored DEK.
    final result = await Database.pool.execute(
      Sql.indexed('SELECT encrypted_dek, dek_nonce FROM users WHERE id = \$1'),
      parameters: [userId],
    );

    if (result.isEmpty) {
      throw StateError('User $userId not found');
    }

    final row = result.first;
    final encryptedDekB64 = row[0] as String?;
    final dekNonceB64 = row[1] as String?;

    if (encryptedDekB64 != null && dekNonceB64 != null) {
      // Decrypt existing DEK.
      final encryptedDek = base64Decode(encryptedDekB64);
      final nonce = base64Decode(dekNonceB64);

      // encryptedDek contains ciphertext + mac (last 16 bytes).
      final macLength = 16;
      final cipherText = encryptedDek.sublist(
        0,
        encryptedDek.length - macLength,
      );
      final mac = Mac(encryptedDek.sublist(encryptedDek.length - macLength));

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      final dekBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: masterKey,
      );
      return SecretKeyData(dekBytes);
    }

    // Generate new DEK.
    final dek = await _algorithm.newSecretKey();
    final dekBytes = await dek.extractBytes();

    // Encrypt DEK with master key.
    final secretBox = await _algorithm.encrypt(dekBytes, secretKey: masterKey);

    // Store: ciphertext + mac concatenated, nonce separately.
    final encryptedDekBytes = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    await Database.pool.execute(
      Sql.indexed(
        'UPDATE users SET encrypted_dek = \$1, dek_nonce = \$2 WHERE id = \$3',
      ),
      parameters: [
        base64Encode(encryptedDekBytes),
        base64Encode(secretBox.nonce),
        userId,
      ],
    );

    return dek;
  }

  /// Encrypts a single plaintext value using AES-256-GCM with the given key.
  ///
  /// Returns: base64(nonce + ciphertext + mac)
  static Future<String> _encryptValue(String plaintext, SecretKey key) async {
    final plaintextBytes = utf8.encode(plaintext);
    final secretBox = await _algorithm.encrypt(plaintextBytes, secretKey: key);

    // Pack as: nonce (12 bytes) + ciphertext + mac (16 bytes)
    final packed = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    return base64Encode(packed);
  }

  /// Decrypts a value previously encrypted by [_encryptValue].
  ///
  /// Input: base64(nonce + ciphertext + mac)
  static Future<String> _decryptValue(String encoded, SecretKey key) async {
    final packed = base64Decode(encoded);

    const nonceLength = 12;
    const macLength = 16;

    if (packed.length < nonceLength + macLength) {
      throw FormatException(
        'Encrypted value too short: ${packed.length} bytes',
      );
    }

    final nonce = packed.sublist(0, nonceLength);
    final cipherText = packed.sublist(nonceLength, packed.length - macLength);
    final mac = Mac(packed.sublist(packed.length - macLength));

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plainBytes = await _algorithm.decrypt(secretBox, secretKey: key);

    return utf8.decode(plainBytes);
  }

  /// Encrypts sensitive fields in a payload before storage.
  ///
  /// Only processes fields listed in [sensitiveFields] for categories
  /// listed in [sensitiveCategories]. Non-sensitive fields pass through
  /// unchanged.
  static Future<Map<String, dynamic>> encryptPayload(
    int userId,
    String category,
    Map<String, dynamic> payload,
  ) async {
    if (!sensitiveCategories.contains(category)) {
      return payload;
    }

    final dek = await getUserDek(userId);
    final result = Map<String, dynamic>.from(payload);

    for (final key in payload.keys) {
      if (sensitiveFields.contains(key) && payload[key] != null) {
        final value = payload[key];
        // Skip already-encrypted values.
        if (value is Map && value['__encrypted'] == true) {
          continue;
        }

        final plaintext = value is String ? value : jsonEncode(value);
        final encrypted = await _encryptValue(plaintext, dek);
        result[key] = {'__encrypted': true, 'v': encrypted};
      }
    }

    return result;
  }

  /// Decrypts sensitive fields in a payload for API response.
  ///
  /// Reverses [encryptPayload]. Non-encrypted fields pass through unchanged.
  /// Logs an audit event for each decryption.
  static Future<Map<String, dynamic>> decryptPayload(
    int userId,
    String category,
    Map<String, dynamic> payload,
  ) async {
    if (!sensitiveCategories.contains(category)) {
      return payload;
    }

    final dek = await getUserDek(userId);
    final result = Map<String, dynamic>.from(payload);
    final decryptedFields = <String>[];

    for (final key in payload.keys) {
      final value = payload[key];
      if (value is Map &&
          value['__encrypted'] == true &&
          value['v'] is String) {
        final decrypted = await _decryptValue(value['v'] as String, dek);

        // Try to parse as JSON; if it fails, use the raw string.
        try {
          result[key] = jsonDecode(decrypted);
        } catch (_) {
          result[key] = decrypted;
        }
        decryptedFields.add(key);
      }
    }

    if (decryptedFields.isNotEmpty) {
      print(
        'AUDIT: Decrypted sensitive fields for userId=$userId '
        'category=$category fields=${decryptedFields.join(",")} '
        'at ${DateTime.now().toUtc().toIso8601String()}',
      );
    }

    return result;
  }
}
