import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';

void main() {
  group('AuthSession.signedOut', () {
    test('isAuthenticated is false', () {
      expect(const AuthSession.signedOut().isAuthenticated, isFalse);
    });
    test('userId and displayName are null', () {
      const s = AuthSession.signedOut();
      expect(s.userId, isNull);
      expect(s.displayName, isNull);
    });
  });

  group('AuthSession.anonymous', () {
    const session = AuthSession.anonymous(userId: 'u1');

    test('isAuthenticated is false (anon does not count for cloud action)',
        () {
      expect(session.isAuthenticated, isFalse);
    });
    test('userId is exposed', () {
      expect(session.userId, 'u1');
      expect(session.displayName, isNull);
    });
  });

  group('AuthSession.keypair', () {
    const session = AuthSession.keypair(
      userId: 'u1',
      displayName: 'lukas',
      avatarColor: '#FF8800',
    );

    test('isAuthenticated is true', () {
      expect(session.isAuthenticated, isTrue);
    });
    test('isAnonymousKeypair is true', () {
      expect(session.isAnonymousKeypair, isTrue);
    });
    test('exposes userId, displayName, avatarColor', () {
      expect(session.userId, 'u1');
      expect(session.displayName, 'lukas');
      expect(session.maybeWhen(
        keypair: (_, _, color) => color,
        orElse: () => null,
      ), '#FF8800');
    });
  });

  group('AuthSession.oauth', () {
    const session = AuthSession.oauth(
      userId: 'u1',
      displayName: 'lukas',
      provider: AuthProvider.google,
    );

    test('isAuthenticated is true', () {
      expect(session.isAuthenticated, isTrue);
    });
    test('isAnonymousKeypair is false', () {
      expect(session.isAnonymousKeypair, isFalse);
    });
    test('hasKeypairFallback defaults to false', () {
      expect(session.maybeWhen(
        oauth: (_, _, _, _, has) => has,
        orElse: () => null,
      ), isFalse);
    });
    test('hasKeypairFallback can be true', () {
      const upgraded = AuthSession.oauth(
        userId: 'u1',
        displayName: 'lukas',
        provider: AuthProvider.apple,
        hasKeypairFallback: true,
      );
      expect(upgraded.maybeWhen(
        oauth: (_, _, _, _, has) => has,
        orElse: () => null,
      ), isTrue);
    });
  });

  test('equality and hashCode honour all fields', () {
    const a = AuthSession.keypair(userId: 'u', displayName: 'l');
    const b = AuthSession.keypair(userId: 'u', displayName: 'l');
    const c = AuthSession.keypair(userId: 'u', displayName: 'other');

    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(c)));
  });

  test('pattern matching covers all variants exhaustively', () {
    String describe(AuthSession s) => s.when(
          signedOut: () => 'out',
          anonymous: (_) => 'anon',
          keypair: (_, _, _) => 'keypair',
          oauth: (_, _, _, _, _) => 'oauth',
        );

    expect(describe(const AuthSession.signedOut()), 'out');
    expect(describe(const AuthSession.anonymous(userId: 'u')), 'anon');
    expect(
      describe(const AuthSession.keypair(userId: 'u', displayName: 'l')),
      'keypair',
    );
    expect(
      describe(const AuthSession.oauth(
        userId: 'u',
        displayName: 'l',
        provider: AuthProvider.google,
      )),
      'oauth',
    );
  });
}
