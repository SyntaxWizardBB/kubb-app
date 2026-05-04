import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';

void main() {
  late CryptoService crypto;
  late Uint8List key;
  late Uint8List nonce;

  setUp(() {
    crypto = CryptoService();
    key = Uint8List.fromList(List.generate(32, (i) => i));
    nonce = Uint8List.fromList(List.generate(24, (i) => 200 - i));
  });

  test('encrypt then decrypt round-trips the plaintext', () async {
    final plaintext = Uint8List.fromList(
      'private-key-seed-bytes-pretend-this-is-32-bytes'.codeUnits,
    );

    final ciphertext = await crypto.encryptXChaCha20(
      key: key,
      plaintext: plaintext,
      nonce: nonce,
    );
    expect(ciphertext.length, plaintext.length + 16);

    final decrypted = await crypto.decryptXChaCha20(
      key: key,
      ciphertext: ciphertext,
      nonce: nonce,
    );
    expect(decrypted, equals(plaintext));
  });

  test('decrypt with the wrong key throws SecretBoxAuthenticationError',
      () async {
    final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
    final ciphertext = await crypto.encryptXChaCha20(
      key: key,
      plaintext: plaintext,
      nonce: nonce,
    );

    final wrongKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

    await expectLater(
      crypto.decryptXChaCha20(
        key: wrongKey,
        ciphertext: ciphertext,
        nonce: nonce,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('decrypt with a tampered ciphertext throws SecretBoxAuthenticationError',
      () async {
    final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
    final ciphertext = await crypto.encryptXChaCha20(
      key: key,
      plaintext: plaintext,
      nonce: nonce,
    );

    final tampered = Uint8List.fromList(ciphertext)..[0] ^= 0x01;

    await expectLater(
      crypto.decryptXChaCha20(
        key: key,
        ciphertext: tampered,
        nonce: nonce,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('decrypt with a wrong nonce throws SecretBoxAuthenticationError',
      () async {
    final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
    final ciphertext = await crypto.encryptXChaCha20(
      key: key,
      plaintext: plaintext,
      nonce: nonce,
    );

    final wrongNonce = Uint8List.fromList(List.generate(24, (i) => i));

    await expectLater(
      crypto.decryptXChaCha20(
        key: key,
        ciphertext: ciphertext,
        nonce: wrongNonce,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('decrypt with a too-short ciphertext throws ArgumentError', () async {
    await expectLater(
      crypto.decryptXChaCha20(
        key: key,
        ciphertext: Uint8List.fromList([1, 2, 3]),
        nonce: nonce,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
