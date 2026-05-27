import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/supabase/anon_session.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

import '../../../fixtures/auth/fake_supabase_auth_adapter.dart';

void main() {
  late FakeSupabaseAuthAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    adapter = FakeSupabaseAuthAdapter();
    container = ProviderContainer(
      overrides: [
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await adapter.dispose();
  });

  AnonSessionBootstrapper sut() =>
      container.read(anonSessionBootstrapperProvider);

  test('signs in anonymously when no session is present', () async {
    expect(adapter.currentState.kind, AuthAdapterKind.signedOut);

    await sut().ensureAnonSession();

    expect(adapter.anonymousCount, 1);
    expect(adapter.currentState.kind, AuthAdapterKind.anonymous);
  });

  test('no-op when an anonymous session is already cached', () async {
    await adapter.signInAnonymously();
    expect(adapter.anonymousCount, 1);

    await sut().ensureAnonSession();

    expect(adapter.anonymousCount, 1);
  });

  test('no-op when an authenticated keypair session is present', () async {
    await adapter.signInAnonymously();
    await adapter.attachKeypair(
      nickname: 'foo',
      publicKey: List<int>.filled(32, 1),
    );
    expect(adapter.currentState.kind, AuthAdapterKind.keypair);

    await sut().ensureAnonSession();

    expect(adapter.anonymousCount, 1);
    expect(adapter.currentState.kind, AuthAdapterKind.keypair);
  });

  test('concurrent calls share a single sign-in', () async {
    final bootstrapper = sut();

    await Future.wait<void>(<Future<void>>[
      bootstrapper.ensureAnonSession(),
      bootstrapper.ensureAnonSession(),
      bootstrapper.ensureAnonSession(),
    ]);

    expect(adapter.anonymousCount, 1);
  });

  test('failure clears the in-flight cache so retry attempts again',
      () async {
    final bootstrapper = sut();
    adapter.throwOnNextCall = StateError('network down');

    await expectLater(
      bootstrapper.ensureAnonSession(),
      throwsA(isA<StateError>()),
    );
    expect(adapter.anonymousCount, 0);

    await bootstrapper.ensureAnonSession();

    expect(adapter.anonymousCount, 1);
    expect(adapter.currentState.kind, AuthAdapterKind.anonymous);
  });
}
