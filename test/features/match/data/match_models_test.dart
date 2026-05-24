// We exercise the `MatchFormat(int)` constructor directly here; using
// the named constants would defeat the test.
// ignore_for_file: use_named_constants

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/match/data/match_models.dart';

void main() {
  group('MatchFormat', () {
    test('fromWire parses bo1, bo3, bo5 and bo99', () {
      expect(MatchFormat.fromWire('bo1').n, 1);
      expect(MatchFormat.fromWire('bo3').n, 3);
      expect(MatchFormat.fromWire('bo5').n, 5);
      expect(MatchFormat.fromWire('bo99').n, 99);
    });

    test('fromWire throws ArgumentError on unknown or malformed input', () {
      for (final raw in const ['foo', '', 'bo0', 'bo100', 'bo']) {
        expect(
          () => MatchFormat.fromWire(raw),
          throwsA(isA<ArgumentError>()),
          reason: 'expected $raw to be rejected',
        );
      }
    });

    test('toWire roundtrips with fromWire', () {
      for (final n in const [1, 3, 5, 7, 99]) {
        expect(MatchFormat.fromWire('bo$n').toWire(), 'bo$n');
      }
    });

    test('constructor accepts n in 1..99 inclusive', () {
      expect(const MatchFormat(1).n, 1);
      expect(const MatchFormat(99).n, 99);
    });

    test('constructor asserts on n outside 1..99', () {
      expect(() => MatchFormat(0), throwsA(isA<AssertionError>()));
      expect(() => MatchFormat(100), throwsA(isA<AssertionError>()));
    });

    test('setsToWin is ceil(n / 2)', () {
      expect(const MatchFormat(1).setsToWin, 1);
      expect(const MatchFormat(3).setsToWin, 2);
      expect(const MatchFormat(5).setsToWin, 3);
      expect(const MatchFormat(7).setsToWin, 4);
    });

    test('equality is value-based on n', () {
      expect(MatchFormat.bo3, const MatchFormat(3));
      expect(MatchFormat.bo3 == MatchFormat.bo5, isFalse);
    });
  });

  group('MatchStatus', () {
    test('fromWire roundtrips all five values', () {
      const cases = <String, MatchStatus>{
        'pending_invites': MatchStatus.pendingInvites,
        'active': MatchStatus.active,
        'awaiting_results': MatchStatus.awaitingResults,
        'finalized': MatchStatus.finalized,
        'voided': MatchStatus.voided,
      };
      for (final entry in cases.entries) {
        expect(MatchStatus.fromWire(entry.key), entry.value);
      }
    });

    test('fromWire throws ArgumentError on unknown input', () {
      expect(
        () => MatchStatus.fromWire('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('MatchScoring', () {
    test('fromWire and toWire roundtrip', () {
      expect(MatchScoring.fromWire('wins').toWire(), 'wins');
      expect(MatchScoring.fromWire('points').toWire(), 'points');
    });

    test('fromWire throws on unknown raw', () {
      expect(
        () => MatchScoring.fromWire('elo'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('MatchInvitationStatus', () {
    test('fromWire covers all four values', () {
      expect(
        MatchInvitationStatus.fromWire('pending'),
        MatchInvitationStatus.pending,
      );
      expect(
        MatchInvitationStatus.fromWire('accepted'),
        MatchInvitationStatus.accepted,
      );
      expect(
        MatchInvitationStatus.fromWire('declined'),
        MatchInvitationStatus.declined,
      );
      expect(
        MatchInvitationStatus.fromWire('left'),
        MatchInvitationStatus.left,
      );
    });

    test('fromWire throws on unknown raw', () {
      expect(
        () => MatchInvitationStatus.fromWire('ghosted'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('MatchRole', () {
    test('fromWire covers creator, participant and observer', () {
      expect(MatchRole.fromWire('creator'), MatchRole.creator);
      expect(MatchRole.fromWire('participant'), MatchRole.participant);
      expect(MatchRole.fromWire('observer'), MatchRole.observer);
    });

    test('fromWire throws on unknown raw', () {
      expect(
        () => MatchRole.fromWire('referee'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('MatchSummary final result', () {
    Map<String, dynamic> baseRow({
      String status = 'finalized',
      String? winnerTeamId = 'A',
      String? myTeamId = 'A',
      Object? finalScoreA = 6,
      Object? finalScoreB = 3,
      bool includeFinalKeys = true,
    }) {
      final row = <String, dynamic>{
        'match_id': 'match-1',
        'format': 'bo3',
        'scoring': 'wins',
        'status': status,
        'started_at': '2026-05-24T10:00:00.000Z',
        'completed_at': status == 'finalized'
            ? '2026-05-24T11:00:00.000Z'
            : null,
        'my_team_id': myTeamId,
        'opponent_team_size': 2,
        'my_role': 'participant',
      };
      if (includeFinalKeys) {
        row['winner_team_id'] = winnerTeamId;
        row['final_score_a'] = finalScoreA;
        row['final_score_b'] = finalScoreB;
      }
      return row;
    }

    test('fromRow parses winner and final scores on a finalized row', () {
      final s = MatchSummary.fromRow(baseRow());
      expect(s.winnerTeamId, 'A');
      expect(s.finalScoreA, 6);
      expect(s.finalScoreB, 3);
    });

    test('fromRow accepts absence of the new fields (older callers)', () {
      final s = MatchSummary.fromRow(baseRow(includeFinalKeys: false));
      expect(s.winnerTeamId, isNull);
      expect(s.finalScoreA, isNull);
      expect(s.finalScoreB, isNull);
    });

    test('callerOutcome is won when winner matches my team', () {
      final s = MatchSummary.fromRow(baseRow());
      expect(s.callerOutcome, 'won');
    });

    test('callerOutcome is lost when winner is the other team', () {
      final s = MatchSummary.fromRow(baseRow(winnerTeamId: 'B'));
      expect(s.callerOutcome, 'lost');
    });

    test('callerOutcome is tie when finalized without a winner', () {
      final s = MatchSummary.fromRow(
        baseRow(
          winnerTeamId: null,
          finalScoreA: 5,
          finalScoreB: 5,
        ),
      );
      expect(s.callerOutcome, 'tie');
    });

    test('callerOutcome is null while the match is not finalized', () {
      final s = MatchSummary.fromRow(
        baseRow(
          status: 'active',
          winnerTeamId: null,
          finalScoreA: null,
          finalScoreB: null,
        ),
      );
      expect(s.callerOutcome, isNull);
    });
  });

  group('MatchDetail.isCallerCreator', () {
    Map<String, dynamic> sampleRow({String? createdBy = 'user-a'}) {
      return <String, dynamic>{
        'match': <String, dynamic>{
          'match_id': 'match-1',
          'created_by': createdBy,
          'format': 'bo3',
          'scoring': 'wins',
          'status': 'pending_invites',
          'started_at': '2026-05-24T10:00:00.000Z',
          'completed_at': null,
          'current_round': 0,
          'settings': <String, dynamic>{},
        },
        'teams': <dynamic>[],
        'participants': <dynamic>[],
        'own_proposal': null,
        'audit_tail': <dynamic>[],
      };
    }

    test('parses created_by and reports true for the creator', () {
      final detail = MatchDetail.fromRow(sampleRow());
      expect(detail.match.createdByUserId, 'user-a');
      expect(detail.isCallerCreator('user-a'), isTrue);
    });

    test('returns false for a non-creator caller', () {
      final detail = MatchDetail.fromRow(sampleRow());
      expect(detail.isCallerCreator('user-b'), isFalse);
    });

    test('returns false when caller or creator is null', () {
      final knownCreator = MatchDetail.fromRow(sampleRow());
      expect(knownCreator.isCallerCreator(null), isFalse);

      final orphaned = MatchDetail.fromRow(sampleRow(createdBy: null));
      expect(orphaned.match.createdByUserId, isNull);
      expect(orphaned.isCallerCreator('user-a'), isFalse);
    });
  });
}
