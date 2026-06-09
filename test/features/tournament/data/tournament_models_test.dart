// The explicit `null` arguments in the classic-path schedule test contrast
// it against the stage / paused rows — that is intentional.
// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_models.dart';
import 'package:kubb_domain/kubb_domain.dart';

Map<String, dynamic> _headerRow({
  String status = 'draft',
  String? createdBy = 'user-a',
  String? startedAt,
  String? completedAt,
  String? publishedAt,
  Object? cfg = const <String, dynamic>{'rounds_per_match': 'bo3'},
  Object? tiebreaker = const <String>['wins', 'kubb_diff'],
  Object? bye = 0,
  Object? forfeit = 0,
}) =>
    <String, dynamic>{
      'tournament_id': 't-1',
      'display_name': 'Spring Cup',
      'created_by': createdBy,
      'team_size': 1,
      'min_participants': 4,
      'max_participants': 8,
      'format': 'round_robin',
      'scoring': 'ekc',
      'match_format_config': cfg,
      'tiebreaker_order': tiebreaker,
      'bye_points': bye,
      'forfeit_points': forfeit,
      'status': status,
      'published_at': publishedAt,
      'started_at': startedAt,
      'completed_at': completedAt,
    };

Map<String, dynamic> _participantRow({
  String status = 'pending',
  Object? seed,
  String? respondedAt,
  Object? displayName = 'Alice',
  // `true` -> include the key with a timestamp, `false` -> include with NULL,
  // omitted (null sentinel via [includeCheckedIn]) -> drop the key entirely so
  // old RPC/CDC payloads without the column can be exercised.
  String? checkedInAt,
  bool includeCheckedIn = true,
}) =>
    <String, dynamic>{
      'participant_id': 'p-1',
      'user_id': 'u-1',
      'nickname': 'alice',
      'display_name': displayName,
      'registration_status': status,
      'seed': seed,
      'registered_at': '2026-05-24T10:00:00.000Z',
      'responded_at': respondedAt,
      if (includeCheckedIn) 'checked_in_at': checkedInAt,
    };

Map<String, Object?> _participantCdcRow({
  String status = 'confirmed',
  Object? seed,
  String? respondedAt,
  String? checkedInAt,
  bool includeCheckedIn = true,
}) =>
    <String, Object?>{
      // Raw `tournament_participants` table row: PK is `id`, and there are no
      // joined nickname/display_name columns on the CDC wire.
      'id': 'p-9',
      'tournament_id': 't-1',
      'user_id': 'u-9',
      'registration_status': status,
      'seed': seed,
      'registered_at': '2026-05-24T10:00:00.000Z',
      'responded_at': respondedAt,
      if (includeCheckedIn) 'checked_in_at': checkedInAt,
    };

Map<String, dynamic> _matchRow({
  String status = 'scheduled',
  Object? aDisplayName = 'Alice',
  Object? bDisplayName = 'Bob',
  Object? setsWonA,
  Object? setsWonB,
}) =>
    <String, dynamic>{
      'match_id': 'm-1',
      'tournament_id': 't-1',
      'round_number': 1,
      'match_number_in_round': 2,
      'participant_a_id': 'p-1',
      'participant_b_id': 'p-2',
      'participant_a_display_name': aDisplayName,
      'participant_b_display_name': bDisplayName,
      'status': status,
      'consensus_round': 0,
      'started_at': null,
      'completed_at': null,
      'sets_won_a': ?setsWonA,
      'sets_won_b': ?setsWonB,
    };

void main() {
  group('tournamentDetailHeaderFromRow', () {
    test('parses required fields, defaults dates to null in draft', () {
      final h = tournamentDetailHeaderFromRow(_headerRow());
      expect(h.tournamentId, 't-1');
      expect(h.displayName, 'Spring Cup');
      expect(h.createdByUserId, 'user-a');
      expect(h.teamSize, 1);
      expect(h.minParticipants, 4);
      expect(h.maxParticipants, 8);
      expect(h.format, TournamentFormat.roundRobin);
      expect(h.scoring, TournamentScoring.ekc);
      expect(h.status, TournamentStatus.draft);
      expect(h.publishedAt, isNull);
      expect(h.startedAt, isNull);
      expect(h.completedAt, isNull);
      expect(h.tiebreakerOrder, ['wins', 'kubb_diff']);
      expect(h.matchFormatConfig['rounds_per_match'], 'bo3');
    });

    test('parses timestamps when the tournament is live', () {
      final h = tournamentDetailHeaderFromRow(
        _headerRow(
          status: 'live',
          publishedAt: '2026-05-24T08:00:00.000Z',
          startedAt: '2026-05-24T10:00:00.000Z',
        ),
      );
      expect(h.status, TournamentStatus.live);
      expect(h.publishedAt, isNotNull);
      expect(h.startedAt!.year, 2026);
      expect(h.completedAt, isNull);
    });

    test('falls back to empty config/tiebreaker on null wire values', () {
      final h = tournamentDetailHeaderFromRow(
        _headerRow(cfg: null, tiebreaker: null),
      );
      expect(h.matchFormatConfig, isEmpty);
      expect(h.tiebreakerOrder, isEmpty);
    });

    test('round-trips every format via fromWire / toWire', () {
      for (final f in TournamentFormat.values) {
        expect(
          TournamentFormatWire.fromWire(f.toWire()),
          f,
          reason: 'format $f',
        );
      }
    });

    test('rejects unknown status wire values', () {
      expect(
        () => TournamentStatusWire.fromWire('garbage'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('tournamentParticipantFromRow', () {
    test('parses pending participant with no responded_at and no seed', () {
      final p = tournamentParticipantFromRow(_participantRow());
      expect(p.participantId, 'p-1');
      expect(p.userId, 'u-1');
      expect(p.registrationStatus, TournamentParticipantStatus.pending);
      expect(p.seed, isNull);
      expect(p.respondedAt, isNull);
      expect(p.displayName, 'Alice');
      // displayLabel now prefers the server-projected display_name
      // (W3-T4) over the nickname-only fallback.
      expect(p.displayLabel, 'Alice');
    });

    test('parses approved participant with seed and responded_at', () {
      final p = tournamentParticipantFromRow(_participantRow(
        status: 'approved',
        seed: 3,
        respondedAt: '2026-05-24T11:00:00.000Z',
      ));
      expect(p.registrationStatus, TournamentParticipantStatus.approved);
      expect(p.seed, 3);
      expect(p.respondedAt, isNotNull);
    });

    test('maps the DB wire value "confirmed" onto approved (auto-confirm)',
        () {
      // Regression: the open-registration model stores `confirmed`, but the
      // domain enum has no `confirmed` member — a `.name` lookup threw
      // "Invalid argument: confirmed" on every confirmed participant once
      // self-registration auto-confirmed, crashing the detail screen.
      final p = tournamentParticipantFromRow(_participantRow(
        status: 'confirmed',
      ));
      expect(p.registrationStatus, TournamentParticipantStatus.approved);
    });

    test('maps the DB wire value "waitlist" onto waitlist', () {
      final p = tournamentParticipantFromRow(_participantRow(
        status: 'waitlist',
      ));
      expect(p.registrationStatus, TournamentParticipantStatus.waitlist);
    });

    test('W3-T4: falls back to nickname when display_name absent on wire',
        () {
      final p = tournamentParticipantFromRow(_participantRow(displayName: null));
      expect(p.displayName, isNull);
      expect(p.displayLabel, 'alice');
    });

    // ADR-0031 Phase D, Block D3: checked_in_at presence projection.
    test('D3: parses checked_in_at into checkedInAt + isCheckedIn', () {
      final p = tournamentParticipantFromRow(_participantRow(
        checkedInAt: '2026-06-09T08:30:00.000Z',
      ));
      expect(p.checkedInAt, DateTime.utc(2026, 6, 9, 8, 30));
      expect(p.isCheckedIn, isTrue);
    });

    test('D3: checked_in_at NULL decodes to null (not checked in)', () {
      final p = tournamentParticipantFromRow(_participantRow());
      expect(p.checkedInAt, isNull);
      expect(p.isCheckedIn, isFalse);
    });

    test('D3: missing checked_in_at key decodes to null (older wire)', () {
      final p = tournamentParticipantFromRow(
        _participantRow(includeCheckedIn: false),
      );
      expect(p.checkedInAt, isNull);
      expect(p.isCheckedIn, isFalse);
    });
  });

  group('tournamentParticipantFromCdcRow (ADR-0031 Phase D, Block D3)', () {
    test('maps raw table id -> participantId and parses checked_in_at', () {
      final p = tournamentParticipantFromCdcRow(_participantCdcRow(
        checkedInAt: '2026-06-09T08:30:00.000Z',
      ));
      expect(p.participantId, 'p-9');
      expect(p.userId, 'u-9');
      expect(p.registrationStatus, TournamentParticipantStatus.approved);
      expect(p.checkedInAt, DateTime.utc(2026, 6, 9, 8, 30));
      expect(p.isCheckedIn, isTrue);
    });

    test('checked_in_at NULL on the CDC wire decodes to null', () {
      final p = tournamentParticipantFromCdcRow(_participantCdcRow());
      expect(p.checkedInAt, isNull);
      expect(p.isCheckedIn, isFalse);
    });

    test('missing checked_in_at key on CDC wire decodes to null', () {
      final p = tournamentParticipantFromCdcRow(
        _participantCdcRow(includeCheckedIn: false),
      );
      expect(p.checkedInAt, isNull);
      expect(p.isCheckedIn, isFalse);
    });
  });

  group('tournamentMatchRefFromRow (W3-T4)', () {
    test('parses participant display names from the RPC envelope', () {
      final m = tournamentMatchRefFromRow(_matchRow());
      expect(m.participantADisplayName, 'Alice');
      expect(m.participantBDisplayName, 'Bob');
    });

    test('leaves display names null when the RPC omits them', () {
      final m = tournamentMatchRefFromRow(_matchRow(
        aDisplayName: null,
        bDisplayName: null,
      ));
      expect(m.participantADisplayName, isNull);
      expect(m.participantBDisplayName, isNull);
    });

    test('FF2/B2: parses sets_won_a/_b when present', () {
      final m = tournamentMatchRefFromRow(_matchRow(
        setsWonA: 2,
        setsWonB: 1,
      ));
      expect(m.setsWonA, 2);
      expect(m.setsWonB, 1);
    });

    test('FF2/B2: leaves set wins null when the RPC omits them', () {
      final m = tournamentMatchRefFromRow(_matchRow());
      expect(m.setsWonA, isNull);
      expect(m.setsWonB, isNull);
    });
  });

  group('tournamentDetailFromRow', () {
    Map<String, dynamic> sample({String? createdBy = 'user-a'}) =>
        <String, dynamic>{
          'tournament': _headerRow(createdBy: createdBy),
          'participants': <dynamic>[_participantRow()],
          'matches': <dynamic>[_matchRow()],
          'audit_tail': <dynamic>[
            <String, dynamic>{
              'kind': 'tournament.published',
              'actor_user_id': 'user-a',
              'payload': <String, dynamic>{},
              'at': '2026-05-24T09:00:00.000Z',
            },
          ],
        };

    test('parses header + lists, mapping match status correctly', () {
      final d = tournamentDetailFromRow(sample());
      expect(d.participants, hasLength(1));
      expect(d.matches, hasLength(1));
      expect(d.matches.first.status, TournamentMatchStatus.scheduled);
      expect(d.matches.first.matchId.value, 'm-1');
      expect(d.auditTail.single.kind, 'tournament.published');
    });

    test('isCallerCreator handles null inputs defensively', () {
      final known = tournamentDetailFromRow(sample());
      expect(known.isCallerCreator('user-a'), isTrue);
      expect(known.isCallerCreator('other'), isFalse);
      expect(known.isCallerCreator(null), isFalse);

      final orphan = tournamentDetailFromRow(sample(createdBy: null));
      expect(orphan.isCallerCreator('user-a'), isFalse);
    });
  });

  group('koMatchRowFromRow (read-path phase mapping, ADR-0027 §4)', () {
    Map<String, dynamic> koRow({
      required String phase,
      int round = 1,
      Object? position = 1,
      String? a = 'p-1',
      String? b = 'p-2',
      String? winner,
      String status = 'scheduled',
    }) =>
        <String, dynamic>{
          'round_number': round,
          'bracket_position': position,
          'phase': phase,
          'participant_a': a,
          'participant_b': b,
          'winner_participant': winner,
          'status': status,
        };

    test('maps single-elim phases', () {
      expect(
        koMatchRowFromRow(koRow(phase: 'ko'))!.phase,
        BracketPhase.winners,
      );
      expect(
        koMatchRowFromRow(koRow(phase: 'final'))!.phase,
        BracketPhase.finals,
      );
      expect(
        koMatchRowFromRow(koRow(phase: 'third_place'))!.phase,
        BracketPhase.thirdPlace,
      );
    });

    test('maps the four double-elim phases', () {
      expect(koMatchRowFromRow(koRow(phase: 'wb'))!.phase, BracketPhase.wb);
      expect(koMatchRowFromRow(koRow(phase: 'lb'))!.phase, BracketPhase.lb);
      expect(
        koMatchRowFromRow(koRow(phase: 'grand_final'))!.phase,
        BracketPhase.grandFinal,
      );
      expect(
        koMatchRowFromRow(koRow(phase: 'grand_final_reset'))!.phase,
        BracketPhase.grandFinalReset,
      );
    });

    test('drops group rows by returning null', () {
      expect(koMatchRowFromRow(koRow(phase: 'group')), isNull);
    });

    test('drops rows without a bracket_position', () {
      expect(koMatchRowFromRow(koRow(phase: 'wb', position: null)), isNull);
    });

    test('bracketFromMatches builds a DoubleEliminationBracket from de rows',
        () {
      // Minimal N=2 double-elim shape: one WB-R1 pairing + an empty GF.
      final rows = <KoMatchRow>[
        koMatchRowFromRow(koRow(phase: 'wb'))!,
        koMatchRowFromRow(
          koRow(phase: 'grand_final', a: null, b: null),
        )!,
      ];
      final bracket = bracketFromMatches(rows);
      expect(bracket, isA<DoubleEliminationBracket>());
      final de = bracket as DoubleEliminationBracket;
      expect(de.wbRounds, hasLength(1));
      expect(de.grandFinal.phase, BracketPhase.grandFinal);
    });

    test('bracketFromMatches still builds single-elim when no de phases', () {
      final rows = <KoMatchRow>[
        koMatchRowFromRow(koRow(phase: 'final'))!,
      ];
      expect(bracketFromMatches(rows), isA<SingleEliminationBracket>());
    });

    test('maps the two consolation phases (ADR-0028 §7.3)', () {
      expect(
        koMatchRowFromRow(koRow(phase: 'consolation'))!.phase,
        BracketPhase.consolation,
      );
      expect(
        koMatchRowFromRow(koRow(phase: 'consolation_third_place'))!.phase,
        BracketPhase.consolationThirdPlace,
      );
    });

    test('bracketFromMatches builds a ConsolationBracket from consolation rows',
        () {
      final rows = <KoMatchRow>[
        koMatchRowFromRow(koRow(phase: 'consolation'))!,
        koMatchRowFromRow(
          koRow(phase: 'consolation', round: 2, a: null, b: null),
        )!,
        koMatchRowFromRow(
          koRow(phase: 'consolation_third_place', a: null, b: null),
        )!,
      ];
      final bracket = bracketFromMatches(rows);
      expect(bracket, isA<ConsolationBracket>());
      final c = bracket as ConsolationBracket;
      expect(c.rounds, hasLength(2));
      expect(c.thirdPlace, isNotNull);
      expect(c.thirdPlace!.phase, BracketPhase.consolationThirdPlace);
    });
  });

  // ADR-0031 Block A3c — tournament_round_schedule CDC parser.
  group('tournamentRoundScheduleRefFromCdcRow', () {
    Map<String, Object?> scheduleRow({
      Object? stageNodeId,
      String status = 'running',
      Object? tiebreakAfterSeconds = 120,
      Object? pausedAt,
      Object? pausedAccumSeconds = 0,
    }) =>
        <String, Object?>{
          'tournament_id': 't-1',
          'stage_node_id': stageNodeId,
          'round_number': 2,
          'phase': 'ko',
          'status': status,
          'published_at': '2026-06-01T12:00:00.000Z',
          'starts_at': '2026-06-01T12:05:00.000Z',
          'ends_at': '2026-06-01T12:35:00.000Z',
          'break_seconds': 300,
          'match_seconds': 1800,
          'tiebreak_after_seconds': tiebreakAfterSeconds,
          'paused_at': pausedAt,
          'paused_accum_seconds': pausedAccumSeconds,
        };

    test('maps all schedule fields from the raw CDC row', () {
      final ref = tournamentRoundScheduleRefFromCdcRow(
        scheduleRow(stageNodeId: 'node-7', pausedAt: '2026-06-01T12:10:00.000Z',
            pausedAccumSeconds: 45),
      );
      expect(ref.tournamentId, const TournamentId('t-1'));
      expect(ref.stageNodeId, 'node-7');
      expect(ref.roundNumber, 2);
      expect(ref.phase, 'ko');
      expect(ref.status, RoundStatus.running);
      expect(ref.publishedAt, DateTime.utc(2026, 6, 1, 12));
      expect(ref.startsAt, DateTime.utc(2026, 6, 1, 12, 5));
      expect(ref.endsAt, DateTime.utc(2026, 6, 1, 12, 35));
      expect(ref.breakSeconds, 300);
      expect(ref.matchSeconds, 1800);
      expect(ref.tiebreakAfterSeconds, 120);
      expect(ref.pausedAt, DateTime.utc(2026, 6, 1, 12, 10));
      expect(ref.pausedAccumSeconds, 45);
    });

    test('classic path: NULL stage_node_id / paused_at / tiebreak decode', () {
      final ref = tournamentRoundScheduleRefFromCdcRow(
        scheduleRow(
          stageNodeId: null,
          tiebreakAfterSeconds: null,
          pausedAt: null,
        ),
      );
      expect(ref.stageNodeId, isNull);
      expect(ref.tiebreakAfterSeconds, isNull);
      expect(ref.pausedAt, isNull);
      expect(ref.pausedAccumSeconds, 0);
    });

    test('maps every status string onto its RoundStatus value', () {
      const expected = <String, RoundStatus>{
        'published': RoundStatus.published,
        'call': RoundStatus.call,
        'running': RoundStatus.running,
        'awaiting_results': RoundStatus.awaitingResults,
        'completed': RoundStatus.completed,
      };
      for (final entry in expected.entries) {
        final ref =
            tournamentRoundScheduleRefFromCdcRow(scheduleRow(status: entry.key));
        expect(ref.status, entry.value, reason: entry.key);
      }
    });
  });
}
