import 'dart:math';

final Random _random = Random.secure();

/// Generates a random 128-bit hex id (32 chars) using OS entropy.
///
/// Replaces `DateTime.now().microsecondsSinceEpoch.toRadixString(36)`, which
/// collides when ids are created in the same microsecond and silently
/// overwrites existing rows (CORR-35).
String newId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
