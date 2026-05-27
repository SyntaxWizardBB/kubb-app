import 'package:kubb_domain/src/tournament/pool.dart';
import 'package:meta/meta.dart';

export 'package:kubb_domain/src/tournament/pairing/buchholz.dart';
export 'package:kubb_domain/src/tournament/pairing/swiss_system.dart';

/// Catalogue of pairing strategies described in FR-PAIR-2. [roundRobin]
/// ships in M0, [swissSystem] in M5; the remaining values are placeholders
/// for later milestones.
enum PairingStrategyKind { roundRobin, swissSystem, oneVsTwo, topVsBottom, danish }

/// Shared pairing output across pool-based (Round-Robin, Swiss) and
/// bracket-based (KO) strategies. Distinct from [PoolPairing] so that
/// bracket strategies can emit pairings without depending on the pool
/// abstraction.
///
/// [repeated] is set to `true` by Swiss-System when backtracking failed to
/// avoid a previously played pairing (R-M5.1-2).
@immutable
final class PlannedPairing {
  const PlannedPairing({
    required this.participantA,
    this.participantB,
    this.repeated = false,
  });

  final String participantA;
  final String? participantB;
  final bool repeated;

  bool get isBye => participantB == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlannedPairing &&
          other.participantA == participantA &&
          other.participantB == participantB &&
          other.repeated == repeated;

  @override
  int get hashCode => Object.hash(participantA, participantB, repeated);
}

/// One planned round emitted by a [PairingStrategy]. [roundNumber] is
/// 1-indexed to match the user-facing "Runde X von Y" labelling.
@immutable
final class PlannedRound {
  const PlannedRound({required this.roundNumber, required this.pairings});

  final int roundNumber;
  final List<PlannedPairing> pairings;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PlannedRound) return false;
    if (other.roundNumber != roundNumber) return false;
    if (other.pairings.length != pairings.length) return false;
    for (var i = 0; i < pairings.length; i++) {
      if (other.pairings[i] != pairings[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(roundNumber, Object.hashAll(pairings));
}

/// Strategy that turns a participant list into a sequence of planned
/// rounds. New strategies (1-vs-2, Top-vs-Bottom, Dänisches System) plug
/// in here in M5.
abstract class PairingStrategy {
  const PairingStrategy();

  PairingStrategyKind get kind;

  List<PlannedRound> plan(List<String> participantIds);
}

/// Thin adapter over [Pool.roundRobin]. Maps the pool's 0-indexed round
/// list to 1-indexed [PlannedRound]s.
final class RoundRobinStrategy implements PairingStrategy {
  const RoundRobinStrategy();

  @override
  PairingStrategyKind get kind => PairingStrategyKind.roundRobin;

  @override
  List<PlannedRound> plan(List<String> participantIds) {
    final pool = Pool.roundRobin(participantIds);
    return List.unmodifiable([
      for (var i = 0; i < pool.rounds.length; i++)
        PlannedRound(
          roundNumber: i + 1,
          pairings: List.unmodifiable([
            for (final p in pool.rounds[i].pairings)
              PlannedPairing(
                participantA: p.participantA,
                participantB: p.participantB,
              ),
          ]),
        ),
    ]);
  }
}
