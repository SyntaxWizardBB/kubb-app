// Demo seeder script for the Swiss League season (M5.3-T16).
//
// Generates a deterministic 20-minute demo dataset:
//   * 8 demo player profiles (Demo Spieler 1..8)
//   * 1 league id ("Demo Liga B")
//   * 1 season "Frühling 2026 — Liga B" (status=open)
//   * 3 Swiss-system tournaments (3 rounds, 8 players, status=finalized)
//   * 24 season_standings_awards rows computed by LeaguePointsEngine
//
// Usage:
//   dart run scripts/demo_swiss_league.dart \
//     --supabase-url=http://127.0.0.1:54321 \
//     --supabase-key=<service_role_key> \
//     [--drop]
//
// `--drop` removes existing demo rows (matched by the tag-marker embedded
// in nickname/name/breakdown) before seeding, making the run idempotent.
// `season_standings_awards` is append-only at DB level; if the trigger
// blocks deletion, run `supabase db reset` instead for a full wipe.

import 'dart:io';

import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

const _kDemoTag = 'demo:swiss-league-2026';
const _kPlayerCount = 8;
const _kRounds = 3;

String _arg(List<String> args, String key) {
  final pref = '--$key=';
  final hit = args.firstWhere((a) => a.startsWith(pref), orElse: () => '');
  return hit.isEmpty ? '' : hit.substring(pref.length);
}

Future<void> main(List<String> args) async {
  final url = _arg(args, 'supabase-url');
  final key = _arg(args, 'supabase-key');
  final drop = args.contains('--drop');
  if (url.isEmpty || key.isEmpty) {
    stderr.writeln('Missing --supabase-url and/or --supabase-key.');
    exitCode = 64;
    return;
  }

  final client = SupabaseClient(url, key);
  if (drop) await _drop(client);

  final players = await _seedPlayers(client);
  final leagueId = const Uuid().v4();
  final seasonId = await _seedSeason(client, leagueId);
  final tournaments = <String>[];
  for (var i = 1; i <= 3; i++) {
    final tId = await _seedTournament(client, i, players, seasonId);
    tournaments.add(tId);
    await _seedAwards(client, seasonId, leagueId, tId, players);
  }
  stdout.writeln('Demo seeded: season=$seasonId, '
      'tournaments=${tournaments.length}, awards=${3 * _kPlayerCount}.');
  await client.dispose();
}

Future<void> _drop(SupabaseClient c) async {
  // Best-effort cleanup. season_standings_awards is append-only — if the
  // trigger blocks the cascade, surface a hint and continue.
  try {
    await c.from('seasons').delete().like('name', '%$_kDemoTag%');
    await c.from('tournaments').delete().like('display_name', '$_kDemoTag%');
    final stale = await c
        .from('user_profiles')
        .select('user_id')
        .like('nickname', 'Demo Spieler%');
    for (final row in (stale as List).cast<Map<String, dynamic>>()) {
      await c.auth.admin.deleteUser(row['user_id'] as String);
    }
  } on PostgrestException catch (e) {
    stderr.writeln('--drop hit ${e.code}: ${e.message}. '
        'Use `supabase db reset` for a full wipe.');
  }
}

Future<List<Map<String, String>>> _seedPlayers(SupabaseClient c) async {
  final out = <Map<String, String>>[];
  for (var i = 1; i <= _kPlayerCount; i++) {
    final email = 'demo-spieler-$i@kubb.local';
    final user = await c.auth.admin.createUser(AdminUserAttributes(
      email: email,
      password: 'demo-$_kDemoTag-$i',
      emailConfirm: true,
      userMetadata: {'tag': _kDemoTag},
    ));
    final uid = user.user!.id;
    await c.from('user_profiles').upsert({
      'user_id': uid,
      'nickname': 'Demo Spieler $i',
      'avatar_color': '#3B82F6',
      'onboarding_completed': true,
    });
    out.add({'user_id': uid, 'name': 'Demo Spieler $i'});
  }
  return out;
}

Future<String> _seedSeason(SupabaseClient c, String leagueId) async {
  final row = await c.from('seasons').insert({
    'name': 'Frühling 2026 — Liga B [$_kDemoTag]',
    'league_id': leagueId,
    'status': 'open',
    'starts_at': '2026-03-01',
    'ends_at': '2026-06-30',
  }).select('id').single();
  return row['id'] as String;
}

Future<String> _seedTournament(
  SupabaseClient c,
  int idx,
  List<Map<String, String>> players,
  String seasonId,
) async {
  final t = await c.from('tournaments').insert({
    'display_name': '$_kDemoTag Turnier $idx',
    'team_size': 1,
    'min_participants': _kPlayerCount,
    'max_participants': _kPlayerCount,
    'format': 'swiss',
    'scoring': 'ekc',
    'match_format': {'sets_to_win': 2},
    'status': 'finalized',
    'completed_at': DateTime.now().toUtc().toIso8601String(),
  }).select('id').single();
  final tId = t['id'] as String;
  await c.from('season_tournaments').insert({
    'season_id': seasonId,
    'tournament_id': tId,
  });
  // Register participants and finalize 12 matches (4 per round × 3 rounds).
  final parts = <String>[];
  for (var i = 0; i < players.length; i++) {
    final p = await c.from('tournament_participants').insert({
      'tournament_id': tId,
      'user_id': players[i]['user_id'],
      'registration_status': 'confirmed',
      'seed': i + 1,
    }).select('id').single();
    parts.add(p['id'] as String);
  }
  for (var r = 1; r <= _kRounds; r++) {
    for (var m = 0; m < _kPlayerCount ~/ 2; m++) {
      final a = parts[m];
      final b = parts[_kPlayerCount - 1 - m];
      // Deterministic: lower seed (Player 1 etc.) wins.
      await c.from('tournament_matches').insert({
        'tournament_id': tId,
        'round_number': r,
        'match_number_in_round': m + 1,
        'participant_a': a,
        'participant_b': b,
        'status': 'finalized',
        'winner_participant': a,
        'final_score_a': 18,
        'final_score_b': 12,
        'finalized_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }
  return tId;
}

Future<void> _seedAwards(
  SupabaseClient c,
  String seasonId,
  String leagueId,
  String tournamentId,
  List<Map<String, String>> players,
) async {
  // Player 1 wins all 3, Player 8 loses all 3 — deterministic Stufung.
  final standings = [
    for (var i = 0; i < _kPlayerCount; i++)
      FinalStandingRow(
        participantId: players[i]['user_id']!,
        placement: i + 1,
        outcomes: List.filled(_kRounds, i < 4 ? MatchOutcome.win : MatchOutcome.loss),
      ),
  ];
  const engine = LeaguePointsEngine();
  final awards = engine.compute(
    standings: standings,
    config: const LeaguePointsConfig(placementBonus: [10, 7, 5, 3, 2, 1]),
    leagueId: leagueId,
  );
  for (final a in awards) {
    await c.from('season_standings_awards').insert({
      'season_id': seasonId,
      'league_id': leagueId,
      'tournament_id': tournamentId,
      'participant_id': a.participantId,
      'placement': a.placement,
      'base_points': a.basePoints,
      'final_points': a.finalPoints,
      'breakdown': '[$_kDemoTag] ${a.breakdown}',
    });
  }
}
