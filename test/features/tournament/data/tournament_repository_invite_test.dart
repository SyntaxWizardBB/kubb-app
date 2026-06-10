import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// `rpc<void>` returns a `PostgrestFilterBuilder` that the repository awaits;
/// this fake resolves the await to a value without building the real one.
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

/// Spaßturnier "auf Einladung": verifies the repository maps each invite action
/// onto the exact server RPC name + param names from migration `20261272…`:
/// `tournament_invite_user(p_tournament_id, p_user_id)`,
/// `tournament_invitation_respond(p_invitation_id, p_accept)`,
/// `tournament_revoke_invitation(p_invitation_id)`.
void main() {
  late _MockSupabaseClient client;
  late TournamentRepository repo;

  setUp(() {
    client = _MockSupabaseClient();
    repo = TournamentRepository(
      client: client,
      realtime: FakeRealtimeChannel(),
    );
  });

  test('inviteUser calls tournament_invite_user with p_tournament_id / '
      'p_user_id', () async {
    Map<String, dynamic>? captured;
    when(
      () => client.rpc<void>('tournament_invite_user',
          params: any(named: 'params')),
    ).thenAnswer((inv) {
      captured =
          inv.namedArguments[#params] as Map<String, dynamic>?;
      return _FakeFilterBuilder<void>(Future<void>.value());
    });

    await repo.inviteUser(const TournamentId('t-1'), const UserId('u-9'));

    expect(captured, {'p_tournament_id': 't-1', 'p_user_id': 'u-9'});
  });

  test('respondInvitation calls tournament_invitation_respond with '
      'p_invitation_id / p_accept', () async {
    Map<String, dynamic>? captured;
    when(
      () => client.rpc<void>('tournament_invitation_respond',
          params: any(named: 'params')),
    ).thenAnswer((inv) {
      captured =
          inv.namedArguments[#params] as Map<String, dynamic>?;
      return _FakeFilterBuilder<void>(Future<void>.value());
    });

    await repo.respondInvitation('inv-1', accept: true);

    expect(captured, {'p_invitation_id': 'inv-1', 'p_accept': true});
  });

  test('revokeInvitation calls tournament_revoke_invitation with '
      'p_invitation_id', () async {
    Map<String, dynamic>? captured;
    when(
      () => client.rpc<void>('tournament_revoke_invitation',
          params: any(named: 'params')),
    ).thenAnswer((inv) {
      captured =
          inv.namedArguments[#params] as Map<String, dynamic>?;
      return _FakeFilterBuilder<void>(Future<void>.value());
    });

    await repo.revokeInvitation('inv-1');

    expect(captured, {'p_invitation_id': 'inv-1'});
  });
}
