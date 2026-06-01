// Test fixtures interleave notifier mutations to read back derived state;
// suppressing this lint keeps the call-site readable as a story.
// ignore_for_file: cascade_invocations
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  late ProviderContainer container;
  late TournamentConfigController controller;

  TournamentConfigDraft state() =>
      container.read(tournamentConfigControllerProvider);

  setUp(() {
    container = ProviderContainer();
    controller = container.read(tournamentConfigControllerProvider.notifier);
  });

  tearDown(() => container.dispose());

  group('setClubId', () {
    test('sets the organizing club and clears it back to personal', () {
      expect(state().clubId, isNull);
      controller.setClubId('club-1');
      expect(state().clubId, 'club-1');
      controller.setClubId(null);
      expect(state().clubId, isNull);
    });
  });

  group('setVorrundeType / setKoType mapping', () {
    test('groupPhase + none => roundRobin (single bracket)', () {
      controller.setVorrundeType(VorrundeType.groupPhase);
      controller.setKoType(KoType.none);
      expect(state().format, TournamentFormat.roundRobin);
      expect(state().bracketType, BracketType.singleElimination);
    });

    test('groupPhase + singleOut => roundRobinThenKo + single', () {
      controller.setVorrundeType(VorrundeType.groupPhase);
      controller.setKoType(KoType.singleOut);
      expect(state().format, TournamentFormat.roundRobinThenKo);
      expect(state().bracketType, BracketType.singleElimination);
    });

    test('groupPhase + doubleOut => roundRobinThenKo + double', () {
      controller.setVorrundeType(VorrundeType.groupPhase);
      controller.setKoType(KoType.doubleOut);
      expect(state().format, TournamentFormat.roundRobinThenKo);
      expect(state().bracketType, BracketType.doubleElimination);
    });

    test('schoch + none => swiss', () {
      controller.setVorrundeType(VorrundeType.schoch);
      controller.setKoType(KoType.none);
      expect(state().format, TournamentFormat.swiss);
      expect(state().bracketType, BracketType.singleElimination);
    });

    test('schoch + singleOut => swissThenKo + single', () {
      controller.setVorrundeType(VorrundeType.schoch);
      controller.setKoType(KoType.singleOut);
      expect(state().format, TournamentFormat.swissThenKo);
      expect(state().bracketType, BracketType.singleElimination);
    });

    test('schoch + doubleOut => swissThenKo + double', () {
      controller.setVorrundeType(VorrundeType.schoch);
      controller.setKoType(KoType.doubleOut);
      expect(state().format, TournamentFormat.swissThenKo);
      expect(state().bracketType, BracketType.doubleElimination);
    });

    test('setFormat keeps the two-axis selection in sync', () {
      controller.setFormat(TournamentFormat.swissThenKo);
      expect(state().vorrundeType, VorrundeType.schoch);
      expect(state().koType, KoType.singleOut);

      controller.setFormat(TournamentFormat.roundRobin);
      expect(state().vorrundeType, VorrundeType.groupPhase);
      expect(state().koType, KoType.none);
    });
  });

  group('per-KO-round format list', () {
    test('resizes on qualifier change via setKoConfig', () {
      controller.setKoType(KoType.singleOut);
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 8, participantCount: 16));
      // 8 qualifiers => 3 KO rounds.
      expect(state().koRoundFormats, hasLength(3));

      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 4, participantCount: 16));
      // 4 qualifiers => 2 KO rounds, first entry preserved.
      expect(state().koRoundFormats, hasLength(2));
    });

    test('setKoType(none) empties the per-round list', () {
      controller.setKoType(KoType.singleOut);
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 4, participantCount: 8));
      expect(state().koRoundFormats, isNotEmpty);

      controller.setKoType(KoType.none);
      expect(state().koRoundFormats, isEmpty);
    });

    test('setKoRoundFormat replaces a single round in place', () {
      controller.setKoType(KoType.singleOut);
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 4, participantCount: 8));
      const finalSpec = MatchFormatSpec(
        setsToWin: 3,
        maxSets: 5,
        timeLimitSeconds: 3600,
        finalNoTiebreak: true,
      );
      controller.setKoRoundFormat(1, finalSpec);
      expect(state().koRoundFormats[1], finalSpec);
      // Index 0 untouched.
      expect(state().koRoundFormats[0], isNot(finalSpec));
    });

    test('setKoRoundFormat ignores out-of-range indices', () {
      controller.setKoType(KoType.singleOut);
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 4, participantCount: 8));
      final before = state().koRoundFormats;
      controller.setKoRoundFormat(
        9,
        const MatchFormatSpec(setsToWin: 1, maxSets: 1, timeLimitSeconds: 600),
      );
      expect(state().koRoundFormats, before);
    });
  });
}
