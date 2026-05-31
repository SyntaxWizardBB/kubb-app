import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// `PostgrestBuilder` implements `Future`, so the team repository awaits
/// the builder returned by `rpc`. This fake lets a test resolve that
/// await to a value (or surface an error) without constructing the real
/// builder. We stub only `then`, which is all the `await` desugaring
/// uses.
class _FakeFilterBuilder<T> extends Mock
    implements PostgrestFilterBuilder<T> {
  _FakeFilterBuilder(this._future);
  final Future<T> _future;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    return _future.then(onValue, onError: onError);
  }
}

/// Self-healing coverage for the expired Phase-1 keypair JWT
/// (PGRST303 → re-sign → retry). The team RPCs run on a 1h keypair
/// token with no refresh token (ADR-0010); once it expires PostgREST
/// rejects the call and the user saw the raw "JWT expired" error on
/// "Meine Teams". The repository's `_guard` must re-sign once and retry.
void main() {
  late _MockSupabaseClient client;

  setUp(() {
    client = _MockSupabaseClient();
  });

  PostgrestException expired() => const PostgrestException(
        message: 'JWT expired',
        code: 'PGRST303',
        details: 'Unauthorized',
      );

  test(
    'PGRST303 triggers a single re-sign and the RPC succeeds on retry',
    () async {
      var rpcCalls = 0;
      var reSigns = 0;
      // First call fails with an expired token, the retry (after the
      // re-sign) succeeds.
      when(() => client.rpc<bool>('team_league_window_open')).thenAnswer(
        (_) {
          rpcCalls += 1;
          if (rpcCalls == 1) {
            return _FakeFilterBuilder<bool>(Future<bool>.error(expired()));
          }
          return _FakeFilterBuilder<bool>(Future<bool>.value(true));
        },
      );

      final repo = TeamRepository(
        client: client,
        reSignWireSession: () async {
          reSigns += 1;
          return WireSessionOutcome.keypairResigned;
        },
      );

      final result = await repo.leagueWindowOpen();

      expect(result, isTrue);
      expect(rpcCalls, 2, reason: 'one failed call + one retry');
      expect(reSigns, 1, reason: 're-sign attempted exactly once');
    },
  );

  test(
    'PGRST303 is rethrown when the re-sign cannot recover the session',
    () async {
      var rpcCalls = 0;
      when(() => client.rpc<bool>('team_league_window_open')).thenAnswer((_) {
        rpcCalls += 1;
        return _FakeFilterBuilder<bool>(Future<bool>.error(expired()));
      });

      final repo = TeamRepository(
        client: client,
        reSignWireSession: () async => WireSessionOutcome.failed,
      );

      await expectLater(
        repo.leagueWindowOpen(),
        throwsA(isA<PostgrestException>()),
      );
      expect(rpcCalls, 1, reason: 'no retry when re-sign did not recover');
    },
  );

  test('a second expiry on the retry is not retried again (no loop)',
      () async {
    var rpcCalls = 0;
    when(() => client.rpc<bool>('team_league_window_open')).thenAnswer((_) {
      rpcCalls += 1;
      return _FakeFilterBuilder<bool>(Future<bool>.error(expired()));
    });

    final repo = TeamRepository(
      client: client,
      reSignWireSession: () async => WireSessionOutcome.keypairResigned,
    );

    await expectLater(
      repo.leagueWindowOpen(),
      throwsA(isA<PostgrestException>()),
    );
    expect(rpcCalls, 2, reason: 'original + exactly one retry, then give up');
  });

  test('non-auth PostgrestException is mapped without any re-sign', () async {
    var reSigns = 0;
    when(() => client.rpc<bool>('team_league_window_open')).thenAnswer(
      (_) => _FakeFilterBuilder<bool>(
        Future<bool>.error(
          const PostgrestException(message: 'NOT_POOL_MEMBER', code: '42501'),
        ),
      ),
    );

    final repo = TeamRepository(
      client: client,
      reSignWireSession: () async {
        reSigns += 1;
        return WireSessionOutcome.keypairResigned;
      },
    );

    await expectLater(
      repo.leagueWindowOpen(),
      throwsA(isA<TeamPermissionException>()),
    );
    expect(reSigns, 0, reason: 'permission errors must not trigger a re-sign');
  });
}
