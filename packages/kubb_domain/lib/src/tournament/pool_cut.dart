import 'package:kubb_domain/src/tournament/pool_phase.dart';
import 'package:kubb_domain/src/tournament/tiebreaker.dart';
import 'package:meta/meta.dart';

/// Result of [selectQualifiers] (ADR-0019 §2-§4, OD-M3-03/05).
@immutable
class CutResult {
  const CutResult(this.qualifiers, this.tieResolutionNeeded);
  final List<String> qualifiers;
  final List<TieResolutionNeeded> tieResolutionNeeded;
}

/// Marker for ties the chain cannot break cross-pool (OD-M3-05).
@immutable
class TieResolutionNeeded {
  const TieResolutionNeeded(this.participantIds, this.criterion);
  final List<String> participantIds;
  final String criterion;
}

/// Top-N qualifier cut. Stub — implemented in TASK-M3.3-T4.
CutResult selectQualifiers(List<List<ParticipantStats>> pools,
        PoolPhaseConfig config, TiebreakerChain chain) =>
    throw UnimplementedError('TASK-M3.3-T4');
