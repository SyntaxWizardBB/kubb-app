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

    test('clearing the club resets league categories (C1)', () {
      // Per P6_SETUP_WIZARD_SPEC Screen 1: a personal tournament (no club) is
      // never league-relevant. Picking a club, ticking a league category and
      // then switching back to personal must drop the categories, otherwise
      // they linger in the draft (the chips are hidden) and would be emitted.
      controller.setClubId('club-1');
      controller.toggleLeagueCategory(LeagueCategory.a);
      expect(state().leagueCategories, <LeagueCategory>[LeagueCategory.a]);

      controller.setClubId(null);
      expect(state().leagueCategories, isEmpty);
      // Defense-in-depth: even if a stale selection survived, the wire payload
      // for a personal tournament carries no league categories.
      expect(state().toSetupConfig()['league_categories'], isEmpty);
    });
  });

  group('setVorrundeType / setKoType mapping', () {
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

    test('groupPhase + consolation => roundRobinThenKo + single + bracket', () {
      controller.setVorrundeType(VorrundeType.groupPhase);
      controller.setKoType(KoType.consolation);
      expect(state().format, TournamentFormat.roundRobinThenKo);
      // Consolation/Trostturnier rides on a single-elimination main bracket
      // (ADR-0028) with the consolation bracket enabled.
      expect(state().bracketType, BracketType.singleElimination);
      expect(state().consolationBracket?.enabled, isTrue);
    });

    test('switching away from consolation clears the consolation bracket', () {
      controller.setKoType(KoType.consolation);
      expect(state().consolationBracket?.enabled, isTrue);
      controller.setKoType(KoType.singleOut);
      expect(state().consolationBracket, isNull);
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
      // Every tournament has a KO stage now: a pure round-robin legacy format
      // maps onto a single-out KO axis (the "kein KO" value is gone).
      expect(state().koType, KoType.singleOut);
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

    test('setKoType resizes the per-round list to the KO round count', () {
      controller.setKoType(KoType.singleOut);
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 4, participantCount: 8));
      // 4 qualifiers => 2 KO rounds.
      expect(state().koRoundFormats, hasLength(2));

      // Switching the KO type keeps a KO stage (no none) and re-derives the
      // per-round list for the unchanged qualifier count.
      controller.setKoType(KoType.doubleOut);
      expect(state().koRoundFormats, hasLength(2));
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
