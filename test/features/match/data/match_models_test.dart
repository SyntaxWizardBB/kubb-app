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
}
