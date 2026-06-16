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

  group('Schoch auto single-pool config', () {
    test('selecting Schoch auto-inits a single-pool pool_phase_config', () {
      // K12: the default group-phase draft now seeds a 4-group config; switch
      // to Schoch to verify the single-pool backfill replaces it.
      controller.setVorrundeType(VorrundeType.schoch);
      final pool = state().poolPhaseConfig;
      expect(pool, isNotNull);
      // Exactly one pool holding all participants (user requirement).
      expect(pool!.groupCount, 1);
      expect(pool.strategy, PoolGroupingStrategy.seeded);
      // No KO config yet => minimum-bracket fallback.
      expect(pool.qualifiersPerGroup, 2);
    });

    test('setKoConfig syncs qualifiers_per_group for the Schoch single pool',
        () {
      controller.setVorrundeType(VorrundeType.schoch);
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 8, participantCount: 16));
      final pool = state().poolPhaseConfig;
      expect(pool!.groupCount, 1);
      expect(pool.qualifiersPerGroup, 8);
    });

    test('setFormat(swissThenKo) also auto-inits the single pool', () {
      controller.setFormat(TournamentFormat.swissThenKo);
      final pool = state().poolPhaseConfig;
      expect(pool!.groupCount, 1);
    });

    test('toSetupConfig emits a non-null single-pool config for Schoch', () {
      controller.setVorrundeType(VorrundeType.schoch);
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 4, participantCount: 8));
      final wire =
          state().toSetupConfig()['pool_phase_config'] as Map<String, Object?>?;
      expect(wire, isNotNull);
      expect(wire!['group_count'], 1);
      expect(wire['qualifiers_per_group'], 4);
      expect(wire['strategy'], 'seeded');
    });

    test('switching Schoch -> groupPhase seeds the default group config', () {
      controller.setVorrundeType(VorrundeType.schoch);
      expect(state().poolPhaseConfig?.groupCount, 1);
      controller.setVorrundeType(VorrundeType.groupPhase);
      // K12: the group phase configures groups inline (default group_count 4);
      // the invalid single pool (group_count == 1) must not linger.
      expect(state().poolPhaseConfig?.groupCount, 4);
    });
  });

  group('K12 group-phase grouping (setPoolGrouping)', () {
    test('default group-phase draft seeds a 4-group config', () {
      // The bare default draft is a group phase → a 4-group config is seeded.
      expect(state().poolPhaseConfig?.groupCount, 4);
      expect(state().poolPhaseConfig?.strategy, PoolGroupingStrategy.snake);
    });

    test('setPoolGrouping stores group count + strategy + seed', () {
      controller.setPoolGrouping(
        groupCount: 8,
        strategy: PoolGroupingStrategy.random,
        randomSeed: 42,
      );
      final pool = state().poolPhaseConfig!;
      expect(pool.groupCount, 8);
      expect(pool.strategy, PoolGroupingStrategy.random);
      expect(pool.randomSeed, 42);
    });

    test('qualifiers-per-group is derived from the KO bracket size', () {
      // KO size 8, 4 groups → 2 qualifiers per group (derived, K12).
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 8, participantCount: 16));
      controller.setPoolGrouping(
        groupCount: 4,
        strategy: PoolGroupingStrategy.snake,
      );
      expect(state().poolPhaseConfig?.qualifiersPerGroup, 2);
    });

    test('setKoConfig re-derives qualifiers-per-group for the group phase', () {
      // Choose the group count first (KO size unknown → provisional 1), then
      // commit the KO config; the qualifier count must re-derive.
      controller.setPoolGrouping(
        groupCount: 4,
        strategy: PoolGroupingStrategy.snake,
      );
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 8, participantCount: 16));
      expect(state().poolPhaseConfig?.groupCount, 4);
      expect(state().poolPhaseConfig?.qualifiersPerGroup, 2);
    });

    test('toSetupConfig emits a valid group pool_phase_config', () {
      controller
          .setKoConfig(KoPhaseConfig(qualifierCount: 8, participantCount: 16));
      controller.setPoolGrouping(
        groupCount: 4,
        strategy: PoolGroupingStrategy.seeded,
      );
      final wire =
          state().toSetupConfig()['pool_phase_config'] as Map<String, Object?>?;
      expect(wire, isNotNull);
      expect(wire!['group_count'], 4);
      expect(wire['qualifiers_per_group'], 2);
      expect(wire['strategy'], 'seeded');
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

    // V2-A: the prelim "Sätze zum Sieg" field wires onto setSetsToWin.
    group('setSetsToWin (prelim sets-to-win, V2-A)', () {
      test('sets the prelim sets_to_win and emits it via toMatchFormatConfig',
          () {
        // Default draft starts at setsToWin 2 — the field must override it.
        expect(state().setsToWin, 2);
        controller.setSetsToWin(3);
        expect(state().setsToWin, 3);
        // It is no longer the silent default of 2 in the wire payload.
        expect(state().toMatchFormatConfig()['sets_to_win'], 3);
      });

      test('auto-clamps maxSets to >= 2*setsToWin-1 (consistency)', () {
        // From the default maxSets (2), choosing setsToWin 3 must lift maxSets
        // to at least 2*3-1 = 5 so a series can actually be decided.
        controller.setSetsToWin(3);
        expect(state().setsToWin, 3);
        expect(state().maxSets, greaterThanOrEqualTo(5));
        // A pre-existing larger maxSets is preserved (not lowered).
        controller.setMaxSets(7);
        controller.setSetsToWin(2);
        expect(state().maxSets, 7);
      });

      test('clamps to setsToWinMax (4)', () {
        controller.setSetsToWin(99);
        expect(state().setsToWin, TournamentConfigDraft.setsToWinMax);
        expect(state().setsToWin, 4);
      });
    });
  });

  group('participant limits (K09/K10)', () {
    test('K10: setMaxParticipants accepts up to 1000', () {
      controller.setMaxParticipants(1000);
      expect(state().maxParticipants, 1000);
      expect(TournamentConfigDraft.participantsHardMax, 1000);
    });

    test('K10: setMaxParticipants clamps above 1000 to the hard max', () {
      controller.setMaxParticipants(5000);
      expect(state().maxParticipants, 1000);
    });

    test('K09: minParticipants floor is the non-zero internal sanity bound', () {
      // K09 removed the user-facing minimum. The internal floor is just a
      // sanity bound (participantsHardMin == 1), never surfaced in the UI.
      expect(TournamentConfigDraft.participantsHardMin, 1);
      controller.setMinParticipants(0);
      expect(state().minParticipants, TournamentConfigDraft.participantsHardMin);
    });
  });

  group('stage-graph format axis setters (P2.1, P21-08)', () {
    StageGraph graphFixture() => StageGraph(
          nodes: <StageNode>[
            StageNode(
              id: 'n1',
              type: StageNodeType.pool,
              seeding: StageSeedingSource.fromElo,
            ),
          ],
          edges: const <StageEdge>[],
        );

    test('setFormatMode mutates only formatMode', () {
      expect(state().formatMode, TournamentFormatMode.classic);
      controller.setFormatMode(TournamentFormatMode.stageGraph);
      expect(state().formatMode, TournamentFormatMode.stageGraph);
    });

    test('setStageGraph sets the graph; clearStageGraph nulls it', () {
      final g = graphFixture();
      controller.setStageGraph(g);
      expect(state().stageGraph, g);
      controller.clearStageGraph();
      expect(state().stageGraph, isNull);
      expect(state().appliedTemplateId, isNull);
    });

    test('toggling the mode does not discard the classic axis nor the graph',
        () {
      controller.setVorrundeType(VorrundeType.schoch);
      controller.setKoType(KoType.singleOut);
      controller.setStageGraph(graphFixture());
      final vorrunde = state().vorrundeType;

      controller.setFormatMode(TournamentFormatMode.stageGraph);
      controller.setFormatMode(TournamentFormatMode.classic);

      expect(state().vorrundeType, vorrunde);
      expect(state().koType, KoType.singleOut);
      expect(state().stageGraph, isNotNull);
    });
  });
}
