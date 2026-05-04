import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/keypair_storage.dart';
import 'package:kubb_app/features/auth/data/secure_token_store.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage backend;
  late SecureTokenStore tokenStore;
  late CryptoService crypto;
  late KeypairStorage storage;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    backend = _MockSecureStorage();
    tokenStore = SecureTokenStore(storage: backend);
    crypto = CryptoService();
    storage = KeypairStorage(crypto: crypto, secureStore: tokenStore);
  });

  test('generate returns a fresh keypair without touching the store',
      () async {
    final pair = await storage.generate();
    expect(pair.privateKey.length, 32);
    expect(pair.publicKey.length, 32);

    verifyNever(() => backend.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ));
  });

  test('save base64-encodes the private key under the documented storage key',
      () async {
    when(() => backend.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});

    final pair = await storage.generate();
    await storage.save(pair.privateKey);

    final captured = verify(() => backend.write(
          key: 'auth_private_key',
          value: captureAny(named: 'value'),
        )).captured.single as String;

    expect(base64Decode(captured), equals(pair.privateKey));
  });

  test('load returns null when no key has ever been saved', () async {
    when(() => backend.read(key: 'auth_private_key'))
        .thenAnswer((_) async => null);

    final loaded = await storage.load();
    expect(loaded, isNull);
  });

  test('load decodes whatever the store returns', () async {
    final original = List.generate(32, (i) => i * 3 % 256);
    when(() => backend.read(key: 'auth_private_key'))
        .thenAnswer((_) async => base64Encode(original));

    final loaded = await storage.load();
    expect(loaded, equals(original));
  });

  test('clear deletes only the private-key entry', () async {
    when(() => backend.delete(key: any(named: 'key')))
        .thenAnswer((_) async {});

    await storage.clear();

    verify(() => backend.delete(key: 'auth_private_key')).called(1);
    verifyNoMoreInteractions(backend);
  });

  test('save then load round-trips the private-key bytes', () async {
    String? stored;
    when(() => backend.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((invocation) async {
      stored = invocation.namedArguments[#value] as String;
    });
    when(() => backend.read(key: 'auth_private_key'))
        .thenAnswer((_) async => stored);

    final pair = await storage.generate();
    await storage.save(pair.privateKey);
    final loaded = await storage.load();

    expect(loaded, equals(pair.privateKey));
  });
}
