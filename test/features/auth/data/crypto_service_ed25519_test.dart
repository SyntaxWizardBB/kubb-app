import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';

void main() {
  late CryptoService crypto;

  setUp(() {
    crypto = CryptoService();
  });

  test('generateEd25519KeyPair returns 32-byte public and private bytes',
      () async {
    final pair = await crypto.generateEd25519KeyPair();

    expect(pair.publicKey.length, 32);
    expect(pair.privateKey.length, 32);
  });

  test('two consecutive generateEd25519KeyPair calls produce distinct keys',
      () async {
    final a = await crypto.generateEd25519KeyPair();
    final b = await crypto.generateEd25519KeyPair();

    expect(a.publicKey, isNot(equals(b.publicKey)));
    expect(a.privateKey, isNot(equals(b.privateKey)));
  });

  test('signEd25519 produces a 64-byte signature', () async {
    final pair = await crypto.generateEd25519KeyPair();
    final message = Uint8List.fromList(List.generate(32, (i) => i));

    final signature = await crypto.signEd25519(
      privateKey: pair.privateKey,
      message: message,
    );

    expect(signature.length, 64);
  });

  test('verifyEd25519 returns true for the matching public key', () async {
    final pair = await crypto.generateEd25519KeyPair();
    final message = Uint8List.fromList(List.generate(32, (i) => i));
    final signature = await crypto.signEd25519(
      privateKey: pair.privateKey,
      message: message,
    );

    final ok = await crypto.verifyEd25519(
      publicKey: pair.publicKey,
      message: message,
      signature: signature,
    );

    expect(ok, isTrue);
  });

  test('verifyEd25519 returns false for a foreign public key', () async {
    final signer = await crypto.generateEd25519KeyPair();
    final stranger = await crypto.generateEd25519KeyPair();
    final message = Uint8List.fromList(List.generate(32, (i) => i));
    final signature = await crypto.signEd25519(
      privateKey: signer.privateKey,
      message: message,
    );

    final ok = await crypto.verifyEd25519(
      publicKey: stranger.publicKey,
      message: message,
      signature: signature,
    );

    expect(ok, isFalse);
  });

  test('publicKeyFromSeed re-derives the public key from the stored seed',
      () async {
    final pair = await crypto.generateEd25519KeyPair();

    final derived = await crypto.publicKeyFromSeed(pair.privateKey);

    expect(derived, equals(pair.publicKey));
  });

  test('publicKeyFromSeed pairs with signEd25519 for round-trip verify',
      () async {
    final pair = await crypto.generateEd25519KeyPair();
    final message = Uint8List.fromList(List.generate(32, (i) => i + 5));
    final signature = await crypto.signEd25519(
      privateKey: pair.privateKey,
      message: message,
    );

    final derived = await crypto.publicKeyFromSeed(pair.privateKey);
    final ok = await crypto.verifyEd25519(
      publicKey: derived,
      message: message,
      signature: signature,
    );

    expect(ok, isTrue);
  });

  test('verifyEd25519 returns false when the message has been tampered with',
      () async {
    final pair = await crypto.generateEd25519KeyPair();
    final message = Uint8List.fromList(List.generate(32, (i) => i));
    final signature = await crypto.signEd25519(
      privateKey: pair.privateKey,
      message: message,
    );

    final tampered = Uint8List.fromList(message)..[0] ^= 0x01;
    final ok = await crypto.verifyEd25519(
      publicKey: pair.publicKey,
      message: tampered,
      signature: signature,
    );

    expect(ok, isFalse);
  });
}
