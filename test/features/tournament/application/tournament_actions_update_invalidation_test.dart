import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// V2-B2 C12: a successful (live) edit through [TournamentActions.update
/// Tournament] must invalidate at least the detail AND the match-list
/// provider, because the server may have regenerated the unplayed pairings.
/// We assert this by counting the remote fetches each provider triggers:
/// after the update the providers re-read, so each backing call fires twice.
class _CountingRemote implements TournamentRemote {
  int detailCalls = 0;
  int listMatchesCalls = 0;

  @override
  Future<void> updateTournament({
    required TournamentId id,
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
    Map<String, Object?> setup = const <String, Object?>{},
  }) async {
    // No-op: success path. Invalidation is the behaviour under test.
  }

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    detailCalls += 1;
    return null;
  }

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async {
    listMatchesCalls += 1;
    return const <TournamentMatchRef>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// T1: a successful [TournamentActions.organizerOverride] must invalidate the
/// affected match-detail provider so the acting device flips to `overridden`
/// without waiting for the realtime CDC echo / the 30 s fallback poll. We
/// assert it by counting the `getMatch` reads the detail provider triggers.
class _OverrideCountingRemote implements TournamentRemote {
  int getMatchCalls = 0;

  @override
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  }) async {
    // No-op: success path. Invalidation is the behaviour under test.
  }

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async {
    getMatchCalls += 1;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test(
      'V2-B2: a successful updateTournament invalidates detail AND match list '
      '(providers re-fetch)', () async {
    const id = TournamentId('t-live-edit');
    final remote = _CountingRemote();
    final container = ProviderContainer(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);

    // Subscribe so the providers fetch once and stay alive.
    final detailSub =
        container.listen(tournamentDetailProvider(id), (_, _) {});
    addTearDown(detailSub.close);
    final listSub =
        container.listen(tournamentMatchListProvider(id), (_, _) {});
    addTearDown(listSub.close);

    await container.read(tournamentDetailProvider(id).future);
    await container.read(tournamentMatchListProvider(id).future);
    expect(remote.detailCalls, 1);
    expect(remote.listMatchesCalls, 1);

    // A valid draft so update passes client-side validation.
    final start = DateTime(2026, 8, 1, 10);
    final draft =
        const TournamentConfigDraft(displayName: 'Live-Edit').copyWith(
      clubChoiceMade: true,
      location: 'Esp',
      venueAddress: 'Sportplatz Esp, Fislisbach',
      eventStartsAt: start,
      registrationClosesAt: start.subtract(const Duration(days: 7)),
      checkinUntil: start.subtract(const Duration(minutes: 30)),
    );
    await container
        .read(tournamentActionsProvider)
        .updateTournament(id, draft);

    // Invalidation forces a fresh read on next watch.
    await container.read(tournamentDetailProvider(id).future);
    await container.read(tournamentMatchListProvider(id).future);

    expect(remote.detailCalls, 2,
        reason: 'detail provider must be invalidated after a live edit');
    expect(remote.listMatchesCalls, 2,
        reason: 'match list must be invalidated (server may have recomputed)');
  });

  test(
      'T1: a successful organizerOverride invalidates the match detail '
      '(provider re-fetches)', () async {
    const matchId = TournamentMatchId('m-override');
    final remote = _OverrideCountingRemote();
    final container = ProviderContainer(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);

    final detailSub =
        container.listen(tournamentMatchDetailProvider(matchId), (_, _) {});
    addTearDown(detailSub.close);

    await container.read(tournamentMatchDetailProvider(matchId).future);
    expect(remote.getMatchCalls, 1);

    await container.read(tournamentActionsProvider).organizerOverride(
          matchId: matchId,
          finalSetScores: const <SetScore>[],
          reason: 'no-show, entered on site',
        );

    // Invalidation forces a fresh read on next watch.
    await container.read(tournamentMatchDetailProvider(matchId).future);
    expect(remote.getMatchCalls, 2,
        reason: 'match detail must be invalidated after an organizer override');
  });
}
