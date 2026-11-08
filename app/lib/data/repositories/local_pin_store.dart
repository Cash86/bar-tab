import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'server_config_repository_impl.dart';

/// Keeps a salted PBKDF2 hash of the admin PIN on the tablet, so the admin
/// can be verified offline (re-pairing). The PIN itself is never stored.
class LocalPinStore {
  LocalPinStore(this._store, {this.iterations = 20000, Random? random})
    : _random = random ?? Random.secure();

  static const key = 'admin_pin_local';
  static const _version = 'v1';
  static const _saltLength = 16;
  static const _hashBits = 256;

  final ConfigStore _store;
  final int iterations;
  final Random _random;

  Future<List<int>> _derive(String pin, List<int> salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _hashBits,
    );
    final secret = await pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    return secret.extractBytes();
  }

  /// Stores the hash of [pin] under a fresh salt.
  Future<void> remember(String pin) async {
    final salt = [for (var i = 0; i < _saltLength; i++) _random.nextInt(256)];
    final hash = await _derive(pin, salt, iterations);
    await _store.write(
      key,
      [_version, iterations, base64Encode(salt), base64Encode(hash)].join(r'$'),
    );
  }

  Future<bool> hasPin() async => (await _store.read(key)) != null;

  /// False for a wrong PIN, no stored PIN and an unreadable stored value.
  Future<bool> verify(String pin) async {
    try {
      final stored = await _store.read(key);
      if (stored == null) return false;
      final parts = stored.split(r'$');
      if (parts.length != 4 || parts[0] != _version) return false;
      final count = int.parse(parts[1]);
      if (count < 1) return false;
      final salt = base64Decode(parts[2]);
      final expected = base64Decode(parts[3]);
      final actual = await _derive(pin, salt, count);
      return _constantTimeEquals(actual, expected);
    } on FormatException {
      return false;
    }
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
