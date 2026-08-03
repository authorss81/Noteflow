import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class EncryptionService {
  static final _algorithm = AesGcm.with256bits();

  /// Derives a key from a master password.
  ///
  /// Uses Argon2id (memory-hard) with a strong parameter set. This is
  /// intentionally CPU/memory expensive: it makes offline brute-forcing of the
  /// master password impractical (R1-2).
  ///
  /// NOTE: Argon2id is supported by the `cryptography` package on VM, Flutter,
  /// and the web (via WASM). Derivation happens only on password set/verify,
  /// not on every keystroke, so the stronger parameters are acceptable even on
  /// a weak CPU.
  static Future<SecretKey> deriveKey(String password, List<int> salt) async {
    const megabytes = 64 * 1024; // 64 MiB (memory is specified in 1kB blocks)
    final argon2id = Argon2id(
      parallelism: 4,
      memory: megabytes,
      iterations: 2,
      hashLength: 32,
    );
    final passwordBytes = utf8.encode(password);
    return argon2id.deriveKey(
      secretKey: SecretKey(passwordBytes),
      nonce: salt,
    );
  }

  /// Legacy PBKDF2 derived key, kept only to migrate/verify pre-Argon2id saved
  /// vaults. New writes always use Argon2id. Marked deprecated so callers use
  /// [deriveKey] unless they explicitly need legacy verification.
  @Deprecated('Migrate to Argon2id deriving via [deriveKey]')
  static Future<SecretKey> deriveKeyLegacyPbkdf2(String password, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 600000,
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

  /// Generates a random 256-bit data-encryption key (DEK).
  static Future<SecretKey> generateDek() async {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return SecretKey(bytes);
  }

  /// Wraps a DEK with a key-encryption key (KEK): returns base64 `AES-GCM(DEK, KEK)`.
  static Future<String> wrapDek(SecretKey dek, SecretKey kek) async {
    final dekBytes = await dek.extractBytes();
    final combined = await encryptBytes(dekBytes, kek);
    return base64.encode(combined);
  }

  /// Unwraps a DEK. Throws on wrong KEK (authentication failure) — this is how
  /// a wrong master password is detected without a verifier oracle.
  static Future<SecretKey> unwrapDek(String wrappedB64, SecretKey kek) async {
    final combined = base64.decode(wrappedB64);
    final dekBytes = await decryptBytes(combined, kek);
    return SecretKey(dekBytes);
  }
}
