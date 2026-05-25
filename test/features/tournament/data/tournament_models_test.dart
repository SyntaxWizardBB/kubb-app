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
}) =>
    <String, dynamic>{
      'participant_id': 'p-1',
      'user_id': 'u-1',
      'nickname': 'alice',
      'registration_status': status,
      'seed': seed,
      'registered_at': '2026-05-24T10:00:00.000Z',
      'responded_at': respondedAt,
    };

Map<String, dynamic> _matchRow({String status = 'scheduled'}) =>
    <String, dynamic>{
      'match_id': 'm-1',
      'tournament_id': 't-1',
      'round_number': 1,
      'match_number_in_round': 2,
      'participant_a_id': 'p-1',
      'participant_b_id': 'p-2',
      'status': status,
      'consensus_round': 0,
      'started_at': null,
      'completed_at': null,
    };

void main() {
  group('TournamentDetailHeader.fromRow', () {
    test('parses required fields, defaults dates to null in draft', () {
      final h = TournamentDetailHeader.fromRow(_headerRow());
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
      final h = TournamentDetailHeader.fromRow(
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
      final h = TournamentDetailHeader.fromRow(
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

  group('TournamentParticipant.fromRow', () {
    test('parses pending participant with no responded_at and no seed', () {
      final p = TournamentParticipant.fromRow(_participantRow());
      expect(p.participantId, 'p-1');
      expect(p.userId, 'u-1');
      expect(p.registrationStatus, TournamentParticipantStatus.pending);
      expect(p.seed, isNull);
      expect(p.respondedAt, isNull);
      expect(p.displayLabel, 'alice');
    });

    test('parses approved participant with seed and responded_at', () {
      final p = TournamentParticipant.fromRow(_participantRow(
        status: 'approved',
        seed: 3,
        respondedAt: '2026-05-24T11:00:00.000Z',
      ));
      expect(p.registrationStatus, TournamentParticipantStatus.approved);
      expect(p.seed, 3);
      expect(p.respondedAt, isNotNull);
    });
  });

  group('TournamentDetail.fromRow', () {
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
      final d = TournamentDetail.fromRow(sample());
      expect(d.participants, hasLength(1));
      expect(d.matches, hasLength(1));
      expect(d.matches.first.status, TournamentMatchStatus.scheduled);
      expect(d.matches.first.matchId.value, 'm-1');
      expect(d.auditTail.single.kind, 'tournament.published');
    });

    test('isCallerCreator handles null inputs defensively', () {
      final known = TournamentDetail.fromRow(sample());
      expect(known.isCallerCreator('user-a'), isTrue);
      expect(known.isCallerCreator('other'), isFalse);
      expect(known.isCallerCreator(null), isFalse);

      final orphan = TournamentDetail.fromRow(sample(createdBy: null));
      expect(orphan.isCallerCreator('user-a'), isFalse);
    });
  });
}
