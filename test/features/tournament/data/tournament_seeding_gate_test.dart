import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

/// CF6 (ChangeSpec K19) — the mandatory manual-seeding step on the
/// Vorrunde->KO transition. These tests exercise the in-memory
/// [FakeTournamentRemote], which mirrors the server gate added in migration
/// 20261210000000: when `seeding_mode == manual` and no complete seed list
/// has been committed, `startKoPhase` throws [SeedingRequiredException];
/// after seeding (or for auto seeding) the KO starts normally.
void main() {
  group('CF6 manual-seeding gate (FakeTournamentRemote)', () {
    late FakeTournamentRemote remote;
    late TournamentId tid;
    late List<TournamentParticipantId> pids;
    const organizer = UserId('user-org');
    final players = [for (var i = 1; i <= 4; i++) UserId('user-p$i')];

    Future<void> setup() async {
      remote = FakeTournamentRemote(initialUser: organizer);
      tid = await remote.createTournament(
        displayName: 'CF6 Cup',
        teamSize: 1,
        minParticipants: 4,
        maxParticipants: 4,
        format: TournamentFormat.singleElimination,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const <String>[],
      );
      pids = <TournamentParticipantId>[];
      for (final p in players) {
        remote.currentUser = p;
        pids.add(await remote.registerSingle(tid));
      }
      remote.currentUser = organizer;
      for (final pid in pids) {
        await remote.confirmRegistration(pid);
      }
    }

    KoPhaseConfig manualConfig() => KoPhaseConfig(
          qualifierCount: 4,
          participantCount: 4,
          seedingMode: SeedingMode.manual,
        );

    // seedingMode defaults to SeedingMode.auto — exercises the no-gate path.
    KoPhaseConfig autoConfig() =>
        KoPhaseConfig(qualifierCount: 4, participantCount: 4);

    // (a) manual without seeds -> KO start blocked / seeding_required.
    test('manual seeding without seeds blocks startKoPhase', () async {
      await setup();
      await expectLater(
        () => remote.startKoPhase(tid, manualConfig()),
        throwsA(isA<SeedingRequiredException>()),
      );
      // No KO rows were created.
      final matches = await remote.listMatchesForTournament(tid);
      expect(matches, isEmpty);
    });

    // (b) manual after seeds -> startable.
    test('manual seeding becomes startable once a full seed list is set',
        () async {
      await setup();
      await remote.setSeeding(
        tournamentId: tid,
        seeds: <TournamentParticipantId, int>{
          for (var i = 0; i < pids.length; i++) pids[i]: i + 1,
        },
      );
      await remote.startKoPhase(tid, manualConfig());
      final matches = await remote.listMatchesForTournament(tid);
      // 4 seeds → 2 R1 + 1 final = 3 KO matches.
      expect(matches, hasLength(3));
    });

    // (d) auto -> no gate / no extra step (regression).
    test('auto seeding starts the KO without any seeding step', () async {
      await setup();
      await remote.startKoPhase(tid, autoConfig());
      final matches = await remote.listMatchesForTournament(tid);
      expect(matches, hasLength(3));
    });
  });
}
