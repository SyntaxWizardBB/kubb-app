import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  group('TournamentConfigDraft', () {
    test('defaults match spec', () {
      const d = TournamentConfigDraft();
      expect(d.displayName, isNull);
      expect(d.teamSize, 1);
      expect(d.minParticipants, 2);
      expect(d.maxParticipants, 8);
      expect(d.format, TournamentFormat.roundRobin);
      expect(d.setsToWin, 2);
      expect(d.maxSets, 3);
      expect(d.roundTimeSeconds, 1800);
      expect(d.basekubbsPerSide, 5);
      expect(d.tiebreakerOrder, [
        'total_points',
        'buchholz_minus_h2h',
        'direct_comparison',
        'wins',
      ]);
    });

    test('copyWith replaces only provided fields', () {
      const d = TournamentConfigDraft();
      final updated = d.copyWith(displayName: 'Cup 2026', setsToWin: 3);
      expect(updated.displayName, 'Cup 2026');
      expect(updated.setsToWin, 3);
      expect(updated.minParticipants, 2);
      expect(updated.format, TournamentFormat.roundRobin);
    });

    test('value equality and hashCode line up for identical drafts', () {
      const a = TournamentConfigDraft(displayName: 'X');
      const b = TournamentConfigDraft(displayName: 'X');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('value equality differs when a field changes', () {
      const a = TournamentConfigDraft(displayName: 'X');
      const b = TournamentConfigDraft(displayName: 'X', setsToWin: 3);
      expect(a, isNot(equals(b)));
    });
  });

  group('TournamentConfigDraft.validate', () {
    test('valid for a fully filled draft', () {
      const d = TournamentConfigDraft(displayName: 'Cup 2026');
      final v = d.validate();
      expect(v.isValid, isTrue);
      expect(v.issues, isEmpty);
    });

    test('flags empty display name', () {
      const d = TournamentConfigDraft(displayName: '   ');
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Turniername')), isTrue);
    });

    test('flags too short display name', () {
      const d = TournamentConfigDraft(displayName: 'AB');
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Zeichen')), isTrue);
    });

    test('flags too long display name', () {
      final d = TournamentConfigDraft(displayName: 'A' * 100);
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('höchstens')), isTrue);
    });

    test('flags min > max participants', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        minParticipants: 10,
        maxParticipants: 4,
      );
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(
        v.issues.any((i) => i.contains('grösser') || i.contains('Min')),
        isTrue,
      );
    });

    test('flags sets-to-win below 1', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        setsToWin: 0,
      );
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Sätze zum Sieg')), isTrue);
    });

    test('flags max_sets too small for the configured sets_to_win', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        setsToWin: 3,
      );
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Max. Sätze')), isTrue);
    });
  });

  group('TournamentConfigDraft.toMatchFormatConfig', () {
    test('maps to the snake_case wire shape the RPC expects', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        setsToWin: 3,
        maxSets: 5,
        roundTimeSeconds: 1200,
        basekubbsPerSide: 6,
      );
      expect(d.toMatchFormatConfig(), <String, Object?>{
        'sets_to_win': 3,
        'max_sets': 5,
        'round_time_seconds': 1200,
        'basekubbs_per_side': 6,
      });
    });
  });
}
