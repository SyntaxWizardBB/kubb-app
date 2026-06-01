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
    };

Map<String, dynamic> _matchRow({
  String status = 'scheduled',
  Object? aDisplayName = 'Alice',
  Object? bDisplayName = 'Bob',
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
  });
}
