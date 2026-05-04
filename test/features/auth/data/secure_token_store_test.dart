import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/data/secure_token_store.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage storage;
  late SecureTokenStore store;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    storage = _MockSecureStorage();
    store = SecureTokenStore(storage: storage);
  });

  test('write maps SecureTokenKind to the documented storage key',
      () async {
    when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});

    await store.write(SecureTokenKind.privateKey, 'priv-bytes');
    verify(() => storage.write(
          key: 'auth_private_key',
          value: 'priv-bytes',
        )).called(1);

    await store.write(SecureTokenKind.accessToken, 'jwt');
    verify(() => storage.write(key: 'auth_access_token', value: 'jwt'))
        .called(1);

    await store.write(SecureTokenKind.refreshToken, 'rt');
    verify(() => storage.write(key: 'auth_refresh_token', value: 'rt'))
        .called(1);

    await store.write(SecureTokenKind.oauthToken, 'oa');
    verify(() => storage.write(key: 'auth_oauth_token', value: 'oa'))
        .called(1);
  });

  test('read returns whatever the underlying storage returns', () async {
    when(() => storage.read(key: 'auth_private_key'))
        .thenAnswer((_) async => 'priv-bytes');
    when(() => storage.read(key: 'auth_oauth_token'))
        .thenAnswer((_) async => null);

    expect(await store.read(SecureTokenKind.privateKey), 'priv-bytes');
    expect(await store.read(SecureTokenKind.oauthToken), isNull);
  });

  test('delete forwards the matching storage key', () async {
    when(() => storage.delete(key: any(named: 'key')))
        .thenAnswer((_) async {});

    await store.delete(SecureTokenKind.refreshToken);
    verify(() => storage.delete(key: 'auth_refresh_token')).called(1);
  });

  test('deleteAll wipes every kind exactly once', () async {
    when(() => storage.delete(key: any(named: 'key')))
        .thenAnswer((_) async {});

    await store.deleteAll();

    for (final kind in SecureTokenKind.values) {
      verify(() => storage.delete(key: kind.storageKey)).called(1);
    }
    verifyNoMoreInteractions(storage);
  });
}
