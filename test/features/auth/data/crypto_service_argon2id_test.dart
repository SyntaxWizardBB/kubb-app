import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';

/// Tiny Argon2id parameters that keep the unit tests fast. Production
/// uses [Argon2idParams.platformDefault] which is much heavier — the
/// wrapper logic is what matters here, not the algorithm strength.
const _testParams = Argon2idParams(
  memoryKiB: 8,
  iterations: 1,
  parallelism: 1,
);

void main() {
  late CryptoService crypto;

  setUp(() {
    crypto = CryptoService();
  });

  test('derived key has the requested hash length', () async {
    final key = await crypto.deriveKeyArgon2id(
      passphrase: 'correct-horse-battery-staple'.codeUnits,
      salt: Uint8List.fromList(List.generate(16, (i) => i)),
      params: _testParams,
    );

    expect(key.length, 32);
  });

  test('hash length parameter is honoured', () async {
    final key = await crypto.deriveKeyArgon2id(
      passphrase: 'pw'.codeUnits,
      salt: Uint8List.fromList(List.generate(16, (i) => i)),
      params: const Argon2idParams(
        memoryKiB: 8,
        iterations: 1,
        parallelism: 1,
        hashLength: 64,
      ),
    );

    expect(key.length, 64);
  });

  test('derivation is deterministic for the same passphrase, salt and params',
      () async {
    final passphrase = 'lukas-passphrase'.codeUnits;
    final salt = Uint8List.fromList(List.generate(16, (i) => i * 7));

    final a = await crypto.deriveKeyArgon2id(
      passphrase: passphrase,
      salt: salt,
      params: _testParams,
    );
    final b = await crypto.deriveKeyArgon2id(
      passphrase: passphrase,
      salt: salt,
      params: _testParams,
    );

    expect(a, equals(b));
  });

  test('different passphrases produce different keys', () async {
    final salt = Uint8List.fromList(List.generate(16, (i) => i));

    final a = await crypto.deriveKeyArgon2id(
      passphrase: 'first'.codeUnits,
      salt: salt,
      params: _testParams,
    );
    final b = await crypto.deriveKeyArgon2id(
      passphrase: 'second'.codeUnits,
      salt: salt,
      params: _testParams,
    );

    expect(a, isNot(equals(b)));
  });

  test('different salts produce different keys for the same passphrase',
      () async {
    final passphrase = 'pw'.codeUnits;

    final a = await crypto.deriveKeyArgon2id(
      passphrase: passphrase,
      salt: Uint8List.fromList(List.generate(16, (i) => i)),
      params: _testParams,
    );
    final b = await crypto.deriveKeyArgon2id(
      passphrase: passphrase,
      salt: Uint8List.fromList(List.generate(16, (i) => i + 1)),
      params: _testParams,
    );

    expect(a, isNot(equals(b)));
  });

  group('Argon2idParams', () {
    test('toJson round-trips with default hashLength implicit', () {
      const params = Argon2idParams(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 4,
      );
      final json = params.toJson();
      expect(json, {'algo': 'argon2id', 'm': 65536, 't': 3, 'p': 4});

      final parsed = Argon2idParams.fromJson(json);
      expect(parsed.memoryKiB, 65536);
      expect(parsed.iterations, 3);
      expect(parsed.parallelism, 4);
      expect(parsed.hashLength, 32);
    });

    test('toJson includes hashLength when non-default', () {
      const params = Argon2idParams(
        memoryKiB: 32768,
        iterations: 3,
        parallelism: 4,
        hashLength: 64,
      );
      final json = params.toJson();
      expect(json['l'], 64);

      final parsed = Argon2idParams.fromJson(json);
      expect(parsed.hashLength, 64);
    });

    test('platformDefault picks the right memory parameter for this platform',
        () {
      final params = Argon2idParams.platformDefault();
      expect(params.iterations, 3);
      expect(params.parallelism, kIsWeb ? 1 : 4);
      expect(params.hashLength, 32);
      expect(params.memoryKiB, kIsWeb ? 32768 : 65536);
    });
  });

  test('production-default Argon2id derivation completes in reasonable time',
      () async {
    final stopwatch = Stopwatch()..start();
    final key = await crypto.deriveKeyArgon2id(
      passphrase: 'production-passphrase-example'.codeUnits,
      salt: Uint8List.fromList(List.generate(16, (i) => i)),
      params: Argon2idParams.platformDefault(),
    );
    stopwatch.stop();

    expect(key.length, 32);
    // Soft sanity check — prints rather than fails on regression so the
    // test stays robust across hardware classes.
    if (stopwatch.elapsed.inSeconds > 5) {
      // print is intentional here — we want a stderr-visible warning
      // when the KDF regresses on this host without failing the suite.
      // ignore: avoid_print
      print(
        'WARN: Argon2id with platform-default params took '
        '${stopwatch.elapsed.inMilliseconds}ms on this host — '
        'consider revisiting parameters per the spike doc.',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
