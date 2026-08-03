import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encryption-ready security layer.
///
/// MVP ships offline-only and does NOT encrypt by default (keep the MVP loop
/// fast). When encryption is enabled:
///  - A random 256-bit DEK is stored in the OS Keystore via flutter_secure_storage.
///  - Page content / attachments can be encrypted with AES-256-GCM before write.
class SecurityService {
  SecurityService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _dekKey = 'noteflow_dek';
  static const _lockedKey = 'noteflow_vault_locked';

  final FlutterSecureStorage _storage;
  bool _encryptionEnabled = false;

  bool get encryptionEnabled => _encryptionEnabled;

  Future<void> init() async {
    final existing = await _storage.read(key: _dekKey);
    if (existing != null) {
      _encryptionEnabled = true;
    }
  }

  /// Creates the vault DEK if none exists. Idempotent.
  Future<void> ensureVault() async {
    final existing = await _storage.read(key: _dekKey);
    if (existing != null) return;
    final key = SecretKeyData.random(length: 32);
    await _storage.write(key: _dekKey, value: base64Encode(key.bytes));
    await _storage.write(key: _lockedKey, value: 'false');
    _encryptionEnabled = true;
  }

  Future<bool> isLocked() async => await _storage.read(key: _lockedKey) == 'true';

  Future<void> setLocked(bool locked) =>
      _storage.write(key: _lockedKey, value: '$locked');

  Future<SecretKey> _dek() async {
    final dek = await _storage.read(key: _dekKey);
    return SecretKeyData(base64Decode(dek ?? ''));
  }

  /// Persists a DEK in the OS keystore/keychain (R1-7). Used to keep the
  /// random data-encryption key available for biometric unlock without ever
  /// storing the human-readable master password.
  Future<void> storeDek(SecretKey dek) async {
    final dekBytes = await dek.extractBytes();
    await _storage.write(key: _dekKey, value: base64Encode(dekBytes));
    _encryptionEnabled = true;
  }

  /// Reads the DEK from the OS keystore/keychain. Returns `null` when none
  /// has been stored.
  Future<SecretKey?> readDek() async {
    final dekB64 = await _storage.read(key: _dekKey);
    if (dekB64 == null) return null;
    return SecretKeyData(base64Decode(dekB64));
  }

  /// Removes the DEK from the OS keystore/keychain.
  Future<void> clearDek() async {
    await _storage.delete(key: _dekKey);
    await _storage.delete(key: _lockedKey);
    _encryptionEnabled = false;
  }

  /// Encrypts bytes with AES-256-GCM using the vault DEK.
  /// Returns `null` if encryption is not enabled.
  /// Envelope: nonce(12) + ciphertext + mac(16).
  Future<Uint8List?> encryptBytes(Uint8List plaintext) async {
    if (!_encryptionEnabled) return null;
    final key = await _dek();
    final box = await AesGcm.with256bits().encrypt(plaintext, secretKey: key);
    final out = BytesBuilder();
    out.add(box.nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  /// Decrypts an envelope produced by [encryptBytes]. Returns null on failure.
  Future<Uint8List?> decryptBytes(Uint8List envelope) async {
    if (!_encryptionEnabled || envelope.length < 28) return null;
    final key = await _dek();
    final nonce = envelope.sublist(0, 12);
    final cipherText = envelope.sublist(12, envelope.length - 16);
    final mac = envelope.sublist(envelope.length - 16);
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  /// Generates a random secret key (used for future Argon2id KEK flows).
  String randomSecret() => base64Encode(SecretKeyData.random(length: 32).bytes);
}
