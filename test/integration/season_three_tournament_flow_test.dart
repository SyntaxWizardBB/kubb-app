// Cross-feature flow-test for the 3-Turnier-Saison (TASK-M5.3-T15).
//
// Wiring per `tasks.md` §M5.3-T15:
//   * In-memory fakes of both `SeasonRepository` impls (data-layer
//     writes via `SeasonAdminController`, application-layer read via
//     `seasonStandingsProvider`) share one `_SeasonStore` so the
//     standings reflect what the admin controller just persisted.
//   * `_buildAwards` runs the real `LeaguePointsEngine` over a fixed
//     placement table → identical input must always yield the same
//     `finalPoints` (FR-POINTS-1).
//   * `ProviderContainer` overrides both `seasonRepositoryProvider`s
//     (the data-layer one for the admin controller, the
//     application-layer one for the standings family).
//
// Patrol/`integration_test` would be overkill here — the demo only
// needs a deterministic, schema-shaped flow that proves the engine and
// the aggregator agree on Σ-points per participant.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/season/application/season_admin_controller.dart';
import 'package:kubb_app/features/season/application/season_standings_provider.dart'
    as app_standings;
import 'package:kubb_app/features/season/data/season_repository.dart'
    as data;
import 'package:kubb_domain/kubb_domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// Shared in-memory storage backing both repository fakes. Mirrors the
/// columns the prod repositories touch (`seasons`, `season_tournaments`,
/// plus a synthetic `tournament_points_awards` ledger fed by the test
/// itself).
class _SeasonStore {
  final Map<String, data.Season> seasons = <String, data.Season>{};
  final List<data.SeasonTournament> assignments = <data.SeasonTournament>[];
  final List<TournamentPointsAward> awards = <TournamentPointsAward>[];
  int _seasonCounter = 0;

  String nextSeasonId() => 'season-${++_seasonCounter}';

  Iterable<data.SeasonTournament> forSeason(String seasonId) =>
      assignments.where((a) => a.seasonId == seasonId);
}

class _FakeWriteRepo extends data.SeasonRepository {
  _FakeWriteRepo(this._store)
      : super(client: _MockSupabaseClient());

  final _SeasonStore _store;

  @override
  Future<List<data.Season>> listSeasons() async =>
      _store.seasons.values.toList(growable: false);

  @override
  Future<data.Season?> getSeason(String id) async => _store.seasons[id];

  @override
  Future<String> createSeason({
    required String name,
    String? leagueId,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final id = _store.nextSeasonId();
    _store.seasons[id] = data.Season(
      id: id,
      name: name,
      status: 'planning',
      leagueId: leagueId,
      startsAt: startsAt,
      endsAt: endsAt,
    );
    return id;
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    final s = _store.seasons[id]!;
    _store.seasons[id] = data.Season(
      id: s.id,
      name: s.name,
      status: status,
      leagueId: s.leagueId,
      startsAt: s.startsAt,
      endsAt: s.endsAt,
    );
  }

  @override
  Future<void> assignTournament(
    String seasonId,
    String tournamentId, {
    double tournamentFactor = 1.0,
    double leagueFactor = 1.0,
  }) async {
    _store.assignments.add(data.SeasonTournament(
      seasonId: seasonId,
      tournamentId: tournamentId,
      tournamentFactor: tournamentFactor,
      leagueFactor: leagueFactor,
    ));
  }
}

class _FakeReadRepo extends app_standings.SeasonRepository {
  _FakeReadRepo(this._store) : super(_MockSupabaseClient());

  final _SeasonStore _store;

  @override
  Future<app_standings.SeasonStandings> getSeason(String seasonId) async {
    final tournaments = _store
        .forSeason(seasonId)
        .map((a) => a.tournamentId)
        .toSet();
    final relevant = _store.awards
        .where((a) =>
            a.tournamentId != null && tournaments.contains(a.tournamentId))
        .toList(growable: false);
    final aggregated = SeasonStandingsAggregator.aggregate(relevant);
    final rows = aggregated
        .map((r) => app_standings.SeasonStandingsRow(
              participantId: r.participantId,
              displayName: r.displayName,
              totalPoints: r.totalPoints,
              tournamentCount: r.tournamentCount,
            ))
        .toList(growable: false);
    return app_standings.SeasonStandings(rows: List.unmodifiable(rows));
  }
}

/// Builds one award row per (participant, placement) for a tournament.
/// Outcomes are reconstructed from the placement so the engine derives
/// `base = matches + bonus` deterministically: places 1–4 are modelled
/// as `[win, win, win]`, places 5–7 as `[win, loss, loss]` and the last
/// place as `[bye, loss, loss]` so OD-M5-01-Default's bye-equivalence
/// (place 8) shows up in Σ.
List<TournamentPointsAward> _buildAwards({
  required String seasonId,
  required String tournamentId,
  required List<String> participants,
  required double tournamentFactor,
  required double leagueFactor,
}) {
  const engine = LeaguePointsEngine();
  final standings = <FinalStandingRow>[];
  for (var i = 0; i < participants.length; i++) {
    final placement = i + 1;
    final outcomes = placement <= 4
        ? const [MatchOutcome.win, MatchOutcome.win, MatchOutcome.win]
        : placement < participants.length
            ? const [
                MatchOutcome.win,
                MatchOutcome.loss,
                MatchOutcome.loss,
              ]
            : const [
                MatchOutcome.bye,
                MatchOutcome.loss,
                MatchOutcome.loss,
              ];
    standings.add(FinalStandingRow(
      participantId: participants[i],
      placement: placement,
      outcomes: outcomes,
    ));
  }
  final awards = engine.compute(
    standings: standings,
    config: LeaguePointsConfig(
      tournamentFactor: tournamentFactor,
      leagueFactor: leagueFactor,
    ),
  );
  // The engine returns awards without `tournamentId`/`displayName` so
  // the aggregator can count tournaments. Re-emit them with the season
  // context bolted on; `seasonId` is captured by the test scope and
  // doesn't ride along on the award itself (matches the prod ledger).
  return [
    for (final a in awards)
      TournamentPointsAward(
        participantId: a.participantId,
        displayName: a.participantId,
        tournamentId: tournamentId,
        leagueId: a.leagueId,
        placement: a.placement,
        basePoints: a.basePoints,
        finalPoints: a.finalPoints,
        breakdown: '$seasonId/$tournamentId ${a.breakdown}',
      ),
  ];
}

void main() {
  late _SeasonStore store;
  late ProviderContainer container;

  setUp(() {
    store = _SeasonStore();
    container = ProviderContainer(overrides: [
      data.seasonRepositoryProvider
          .overrideWithValue(_FakeWriteRepo(store)),
      app_standings.seasonRepositoryProvider
          .overrideWithValue(_FakeReadRepo(store)),
    ]);
  });

  tearDown(() => container.dispose());

  test('3-tournament season flow: 8 players, Σ-points sorted desc',
      () async {
    // 1. Liga-Admin creates the season via the admin controller.
    final admin = container.read(seasonAdminControllerProvider.notifier);
    await admin.createSeason(name: 'Frühling 2026 — Liga B');
    final seasonId = store.seasons.keys.single;
    expect(store.seasons[seasonId]!.name, 'Frühling 2026 — Liga B');

    // 2. Assign three tournaments with factors 1.0/1.0 each.
    const tournamentIds = ['t-1', 't-2', 't-3'];
    for (final t in tournamentIds) {
      await admin.assignTournament(seasonId, t);
    }
    expect(store.forSeason(seasonId), hasLength(3));

    // 3. Seed awards for 3 tournaments × 8 players. The participant
    //    order rotates per tournament so the Σ-points spread across
    //    several participants instead of piling on one — needed for
    //    the "8 players in standings" assertion below.
    const players = <String>[
      'p-1', 'p-2', 'p-3', 'p-4', 'p-5', 'p-6', 'p-7', 'p-8',
    ];
    for (var i = 0; i < tournamentIds.length; i++) {
      final rotated = [
        ...players.sublist(i),
        ...players.sublist(0, i),
      ];
      store.awards.addAll(_buildAwards(
        seasonId: seasonId,
        tournamentId: tournamentIds[i],
        participants: rotated,
        tournamentFactor: 1,
        leagueFactor: 1,
      ));
    }
    expect(store.awards, hasLength(3 * 8));

    // 4. seasonStandingsProvider → 8 distinct participants, sorted Σ
    //    desc (OD-M5-06 A).
    final standings = await container
        .read(app_standings.seasonStandingsProvider(seasonId).future);
    expect(standings.rows, hasLength(8));
    final totals = standings.rows.map((r) => r.totalPoints).toList();
    for (var i = 0; i < totals.length - 1; i++) {
      expect(totals[i], greaterThanOrEqualTo(totals[i + 1]),
          reason: 'standings must be sorted Σ-points desc');
    }

    // 5. Top-spieler sanity: place-1 in tournament t-1 is p-1, with
    //    `outcomes=[win, win, win] -> base=9, factors=1.0/1.0`. Across
    //    three tournaments p-1 lands on places 1 / 8 / 7 (rotation:
    //    [1..8], [2..8,1], [3..8,1,2]). Place 8 carries
    //    `[bye, loss, loss] -> base=3` and place 7
    //    `[win, loss, loss] -> base=3` → Σ = 9 + 3 + 3 = 15.
    final p1 =
        standings.rows.singleWhere((r) => r.participantId == 'p-1');
    expect(p1.totalPoints, 15.0);
    expect(p1.tournamentCount, 3);

    // The aggregate Σ across all 8 participants must equal the sum of
    // every award's finalPoints — proves the read-model neither drops
    // rows nor double-counts.
    final expectedSum =
        store.awards.fold<double>(0, (acc, a) => acc + a.finalPoints);
    final actualSum =
        standings.rows.fold<double>(0, (acc, r) => acc + r.totalPoints);
    expect(actualSum, expectedSum);
  });
}
