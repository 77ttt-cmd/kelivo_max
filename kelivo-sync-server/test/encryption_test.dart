import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import 'package:kelivo_max_sync_server/services/encryption_service.dart';

void main() {
  // A deterministic 32-byte test master key (hex-encoded).
  const testMasterKeyHex =
      'aabbccdd11223344aabbccdd11223344aabbccdd11223344aabbccdd11223344';

  late SecretKey testKey;

  setUp(() async {
    testKey = SecretKeyData(_hexDecode(testMasterKeyHex));
    EncryptionService.setMasterKeyForTest(testKey);
  });

  tearDown(() {
    EncryptionService.resetMasterKey();
  });

  group('EncryptionService field-level encrypt/decrypt', () {
    test('encrypt and decrypt round-trip for a string value', () async {
      final algorithm = AesGcm.with256bits();
      final dek = await algorithm.newSecretKey();

      // Simulate what encryptPayload does for a single field.
      const plaintext = 'sk-my-secret-api-key-12345';
      final encrypted = await _encryptValue(plaintext, dek);

      // Encrypted value should be a base64 string.
      expect(encrypted, isNotEmpty);
      expect(() => base64Decode(encrypted), returnsNormally);

      // Decrypt and verify.
      final decrypted = await _decryptValue(encrypted, dek);
      expect(decrypted, equals(plaintext));
    });

    test('encrypt and decrypt round-trip for JSON value', () async {
      final algorithm = AesGcm.with256bits();
      final dek = await algorithm.newSecretKey();

      final jsonValue = jsonEncode(['key1', 'key2', 'key3']);
      final encrypted = await _encryptValue(jsonValue, dek);
      final decrypted = await _decryptValue(encrypted, dek);
      expect(decrypted, equals(jsonValue));

      // Parse back to list.
      final parsed = jsonDecode(decrypted) as List;
      expect(parsed, equals(['key1', 'key2', 'key3']));
    });

    test(
      'different encryptions of same plaintext produce different ciphertexts',
      () async {
        final algorithm = AesGcm.with256bits();
        final dek = await algorithm.newSecretKey();

        const plaintext = 'same-value';
        final enc1 = await _encryptValue(plaintext, dek);
        final enc2 = await _encryptValue(plaintext, dek);

        // Due to random nonce, ciphertexts should differ.
        expect(enc1, isNot(equals(enc2)));

        // But both decrypt to the same value.
        expect(await _decryptValue(enc1, dek), equals(plaintext));
        expect(await _decryptValue(enc2, dek), equals(plaintext));
      },
    );

    test('decryption with wrong key fails', () async {
      final algorithm = AesGcm.with256bits();
      final dek1 = await algorithm.newSecretKey();
      final dek2 = await algorithm.newSecretKey();

      const plaintext = 'secret';
      final encrypted = await _encryptValue(plaintext, dek1);

      expect(
        () => _decryptValue(encrypted, dek2),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('encrypted value too short throws FormatException', () async {
      final algorithm = AesGcm.with256bits();
      final dek = await algorithm.newSecretKey();

      // Less than 28 bytes (12 nonce + 16 mac minimum).
      final tooShort = base64Encode(Uint8List(10));

      expect(
        () => _decryptValue(tooShort, dek),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('EncryptionService payload encryption', () {
    test('sensitive fields in sensitive category are encrypted', () async {
      final payload = {
        'name': 'My OpenAI Provider',
        'apiKey': 'sk-real-key-12345',
        'model': 'gpt-4',
        'baseUrl': 'https://api.openai.com',
      };

      // We can't call encryptPayload directly without DB, so test the
      // wrapper logic manually.
      final result = await _encryptPayloadFields(payload, testKey);

      // 'name', 'model', 'baseUrl' should pass through unchanged.
      expect(result['name'], equals('My OpenAI Provider'));
      expect(result['model'], equals('gpt-4'));
      expect(result['baseUrl'], equals('https://api.openai.com'));

      // 'apiKey' should be encrypted.
      expect(result['apiKey'], isA<Map>());
      final encApiKey = result['apiKey'] as Map;
      expect(encApiKey['__encrypted'], isTrue);
      expect(encApiKey['v'], isA<String>());

      // Decrypt it back.
      final decrypted = await _decryptValue(encApiKey['v'] as String, testKey);
      expect(decrypted, equals('sk-real-key-12345'));
    });

    test('multiple sensitive fields are all encrypted', () async {
      final payload = {
        'name': 'AWS Provider',
        'accessKeyId': 'AKIAIOSFODNN7EXAMPLE',
        'secretAccessKey': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        'sessionToken': 'FwoGZXIvYXdzEBYaDHqa0AP',
        'region': 'us-east-1',
      };

      final result = await _encryptPayloadFields(payload, testKey);

      // Non-sensitive fields.
      expect(result['name'], equals('AWS Provider'));
      expect(result['region'], equals('us-east-1'));

      // Sensitive fields.
      for (final field in ['accessKeyId', 'secretAccessKey', 'sessionToken']) {
        expect(result[field], isA<Map>(), reason: '$field should be encrypted');
        final enc = result[field] as Map;
        expect(enc['__encrypted'], isTrue, reason: '$field.__encrypted');
      }
    });

    test('null sensitive field values are not encrypted', () async {
      final payload = {'name': 'Provider', 'apiKey': null, 'model': 'gpt-4'};

      final result = await _encryptPayloadFields(payload, testKey);
      expect(result['apiKey'], isNull);
      expect(result['name'], equals('Provider'));
    });

    test('already encrypted fields are not double-encrypted', () async {
      final alreadyEncrypted = {'__encrypted': true, 'v': 'someBase64Value'};
      final payload = {'apiKey': alreadyEncrypted, 'name': 'Provider'};

      final result = await _encryptPayloadFields(payload, testKey);
      // Should pass through unchanged.
      expect(result['apiKey'], equals(alreadyEncrypted));
    });

    test(
      'non-string sensitive values are JSON-encoded before encryption',
      () async {
        final payload = {
          'apiKeys': ['key1', 'key2', 'key3'],
          'name': 'Multi-key Provider',
        };

        final result = await _encryptPayloadFields(payload, testKey);

        expect(result['apiKeys'], isA<Map>());
        final enc = result['apiKeys'] as Map;
        expect(enc['__encrypted'], isTrue);

        // Decrypt and parse back.
        final decrypted = await _decryptValue(enc['v'] as String, testKey);
        final parsed = jsonDecode(decrypted) as List;
        expect(parsed, equals(['key1', 'key2', 'key3']));
      },
    );

    test('decrypt payload round-trip preserves all fields', () async {
      final original = {
        'name': 'My Provider',
        'apiKey': 'sk-secret-123',
        'password': 'p@ssw0rd!',
        'model': 'gpt-4',
        'baseUrl': 'https://api.example.com',
      };

      // Encrypt.
      final encrypted = await _encryptPayloadFields(original, testKey);

      // Decrypt.
      final decrypted = await _decryptPayloadFields(encrypted, testKey);

      expect(decrypted['name'], equals('My Provider'));
      expect(decrypted['apiKey'], equals('sk-secret-123'));
      expect(decrypted['password'], equals('p@ssw0rd!'));
      expect(decrypted['model'], equals('gpt-4'));
      expect(decrypted['baseUrl'], equals('https://api.example.com'));
    });
  });

  group('EncryptionService category filtering', () {
    test('non-sensitive categories pass through unchanged', () {
      // Verify category list.
      expect(
        EncryptionService.sensitiveCategories,
        containsAll(['providers', 'searchServices', 'ttsServices']),
      );

      // These categories should NOT trigger encryption.
      for (final cat in ['chats', 'assistants', 'settings', 'files', 'mcp']) {
        expect(
          EncryptionService.sensitiveCategories.contains(cat),
          isFalse,
          reason: '"$cat" should not be a sensitive category',
        );
      }
    });

    test('sensitiveFields contains all required fields', () {
      const expected = {
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
      expect(EncryptionService.sensitiveFields, equals(expected));
    });
  });

  group('Master key decoding', () {
    test('hex-encoded 32-byte key is accepted', () async {
      EncryptionService.resetMasterKey();
      // We can't test getMasterKey() directly (reads env), but the
      // setMasterKeyForTest path validates that the key is usable.
      final hexKey =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final bytes = _hexDecode(hexKey);
      expect(bytes.length, equals(32));

      final key = SecretKeyData(bytes);
      EncryptionService.setMasterKeyForTest(key);

      final retrieved = await EncryptionService.getMasterKey();
      final retrievedBytes = await retrieved.extractBytes();
      expect(retrievedBytes, equals(bytes));
    });
  });

  group('DEK encryption with master key', () {
    test('DEK encrypt/decrypt round-trip with master key', () async {
      final algorithm = AesGcm.with256bits();
      final masterKey = testKey;

      // Generate a random DEK.
      final dek = await algorithm.newSecretKey();
      final dekBytes = await dek.extractBytes();
      expect(dekBytes.length, equals(32));

      // Encrypt DEK with master key.
      final secretBox = await algorithm.encrypt(dekBytes, secretKey: masterKey);

      // Pack as stored in DB: ciphertext + mac.
      final stored = Uint8List.fromList([
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);
      final nonce = secretBox.nonce;

      // Decrypt DEK from stored form.
      const macLength = 16;
      final cipherText = stored.sublist(0, stored.length - macLength);
      final mac = Mac(stored.sublist(stored.length - macLength));

      final restoredBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      final restoredDekBytes = await algorithm.decrypt(
        restoredBox,
        secretKey: masterKey,
      );

      expect(restoredDekBytes, equals(dekBytes));
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers — mirror EncryptionService private methods for unit testing.
// ---------------------------------------------------------------------------

Uint8List _hexDecode(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

final _algorithm = AesGcm.with256bits();

Future<String> _encryptValue(String plaintext, SecretKey key) async {
  final plaintextBytes = utf8.encode(plaintext);
  final secretBox = await _algorithm.encrypt(plaintextBytes, secretKey: key);

  final packed = Uint8List.fromList([
    ...secretBox.nonce,
    ...secretBox.cipherText,
    ...secretBox.mac.bytes,
  ]);
  return base64Encode(packed);
}

Future<String> _decryptValue(String encoded, SecretKey key) async {
  final packed = base64Decode(encoded);

  const nonceLength = 12;
  const macLength = 16;

  if (packed.length < nonceLength + macLength) {
    throw FormatException('Encrypted value too short: ${packed.length} bytes');
  }

  final nonce = packed.sublist(0, nonceLength);
  final cipherText = packed.sublist(nonceLength, packed.length - macLength);
  final mac = Mac(packed.sublist(packed.length - macLength));

  final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
  final plainBytes = await _algorithm.decrypt(secretBox, secretKey: key);

  return utf8.decode(plainBytes);
}

/// Simulates EncryptionService.encryptPayload without DB access.
Future<Map<String, dynamic>> _encryptPayloadFields(
  Map<String, dynamic> payload,
  SecretKey dek,
) async {
  final result = Map<String, dynamic>.from(payload);

  for (final key in payload.keys) {
    if (EncryptionService.sensitiveFields.contains(key) &&
        payload[key] != null) {
      final value = payload[key];
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

/// Simulates EncryptionService.decryptPayload without DB access.
Future<Map<String, dynamic>> _decryptPayloadFields(
  Map<String, dynamic> payload,
  SecretKey dek,
) async {
  final result = Map<String, dynamic>.from(payload);

  for (final key in payload.keys) {
    final value = payload[key];
    if (value is Map && value['__encrypted'] == true && value['v'] is String) {
      final decrypted = await _decryptValue(value['v'] as String, dek);
      try {
        result[key] = jsonDecode(decrypted);
      } catch (_) {
        result[key] = decrypted;
      }
    }
  }

  return result;
}
