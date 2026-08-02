import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class EncryptionService {
  static final _algorithm = AesGcm.with256bits();

  /// Derives a key using PBKDF2 with SHA256.
  static Future<SecretKey> deriveKey(String password, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 1000, // Efficient for weak CPUs and web
      bits: 256,
    );
    final passwordBytes = utf8.encode(password);
    return pbkdf2.deriveKey(
      secretKey: SecretKey(passwordBytes),
      nonce: salt,
    );
  }

  /// Encrypts a string (e.g. strokesJson) using a derived key.
  static Future<String> encrypt(String plaintext, SecretKey secretKey) async {
    final clearBytes = utf8.encode(plaintext);
    final secretBox = await _algorithm.encrypt(
      clearBytes,
      secretKey: secretKey,
    );
    // AES-GCM standard combines: 12-byte nonce, 16-byte mac, and ciphertext
    final combined = <int>[
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];
    return base64.encode(combined);
  }

  /// Decrypts a combined ciphertext string.
  static Future<String> decrypt(String combinedBase64, SecretKey secretKey) async {
    final combined = base64.decode(combinedBase64);
    if (combined.length < 28) {
      throw ArgumentError('Invalid ciphertext payload length.');
    }
    final nonce = combined.sublist(0, 12);
    final macBytes = combined.sublist(12, 28);
    final ciphertext = combined.sublist(28);

    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(macBytes),
    );
    final decryptedBytes = await _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    return utf8.decode(decryptedBytes);
  }

  static Future<List<int>> encryptBytes(List<int> clearBytes, SecretKey secretKey) async {
    final secretBox = await _algorithm.encrypt(
      clearBytes,
      secretKey: secretKey,
    );
    return [
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];
  }

  static Future<List<int>> decryptBytes(List<int> combined, SecretKey secretKey) async {
    if (combined.length < 28) {
      throw ArgumentError('Invalid ciphertext payload length.');
    }
    final nonce = combined.sublist(0, 12);
    final macBytes = combined.sublist(12, 28);
    final ciphertext = combined.sublist(28);

    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(macBytes),
    );
    return await _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
  }
}
