// ADR-0031 Phase B, Block B1c — tournamentAdminCardRefFromRow.
//
// Decodes a `tournament_list_administrable` RPC row (migration
// 20261255000000) into a TournamentAdminCardRef. Covers:
//  * a full row WITH a schedule (currentRound/scheduleStatus/remainingSeconds/
//    pausedAt populated),
//  * a row with the schedule columns NULL (LEFT-JOIN-NULL path) — those four
//    fields decode to null while the match counts still decode,
//  * format/status decode from the snake_case wire.

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_models.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  test('decodes a full row with an active schedule', () {
    final row = <String, dynamic>{
      'tournament_id': 't-1',
      'display_name': 'Liga A',
      'format': 'swiss',
      'status': 'live',
      'current_round': 3,
      'schedule_status': 'running',
      'paused_at': '2026-06-09T12:00:00.000Z',
      'remaining_seconds': 420,
      'open_match_count': 5,
      'disputed_match_count': 2,
    };

    final ref = tournamentAdminCardRefFromRow(row);

    expect(
      ref,
      TournamentAdminCardRef(
        tournamentId: const TournamentId('t-1'),
        displayName: 'Liga A',
        format: TournamentFormat.swiss,
        status: TournamentStatus.live,
        currentRound: 3,
        scheduleStatus: RoundStatus.running,
        remainingSeconds: 420,
        openMatchCount: 5,
        disputedMatchCount: 2,
        pausedAt: DateTime.parse('2026-06-09T12:00:00.000Z'),
      ),
    );
    // Explicit field assertions so a regression localises fast.
    expect(ref.currentRound, 3);
    expect(ref.scheduleStatus, RoundStatus.running);
    expect(ref.remainingSeconds, 420);
    expect(ref.pausedAt, DateTime.parse('2026-06-09T12:00:00.000Z'));
  });

  test('NULL-schedule row (LEFT-JOIN-NULL) decodes schedule fields to null',
      () {
    final row = <String, dynamic>{
      'tournament_id': 't-2',
      'display_name': 'Liga C',
      'format': 'round_robin',
      'status': 'published',
      'current_round': null,
      'schedule_status': null,
      'paused_at': null,
      'remaining_seconds': null,
      'open_match_count': 8,
      'disputed_match_count': 0,
    };

    final ref = tournamentAdminCardRefFromRow(row);

    expect(ref.tournamentId, const TournamentId('t-2'));
    expect(ref.currentRound, isNull);
    expect(ref.scheduleStatus, isNull);
    expect(ref.remainingSeconds, isNull);
    expect(ref.pausedAt, isNull);
    // Match counts are unaffected by the missing schedule row.
    expect(ref.openMatchCount, 8);
    expect(ref.disputedMatchCount, 0);
  });

  test('format and status decode from the snake_case wire', () {
    final row = <String, dynamic>{
      'tournament_id': 't-3',
      'display_name': 'KO Cup',
      'format': 'single_elimination',
      'status': 'published',
      'current_round': null,
      'schedule_status': null,
      'paused_at': null,
      'remaining_seconds': null,
      'open_match_count': null,
      'disputed_match_count': null,
    };

    final ref = tournamentAdminCardRefFromRow(row);

    expect(ref.format, TournamentFormat.singleElimination);
    expect(ref.status, TournamentStatus.published);
    // NULL counts fall back to the 0 default.
    expect(ref.openMatchCount, 0);
    expect(ref.disputedMatchCount, 0);
  });
}
