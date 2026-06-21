/// Typed read/write helpers over the free-form `StageNode.config` map
/// (ADR-0033 §4 / P5.2). One source for how the node-config UI WRITES and the
/// engine/summary READ the per-stage configuration, so the keys never drift.
///
/// Keys (mirroring the classic JSON where one exists):
/// - KO nodes: `ko_matchup`, `ko_tiebreak_method`, `with_reset` (double-elim),
///   `ko_round_formats` (`[MatchFormatSpec.toJson()]`, index 0 = round 1).
/// - Group-phase/round-robin nodes: `groupCount`, `qualifierCount` (per group),
///   `grouping_strategy`, `random_seed`, `group_pitch_assignment` (per-group
///   pitch numbers, mirrors `PitchPlan.groupAssignment`).
/// - Schoch nodes: `rounds`.
///
/// Existing keys stay camelCase (`groupCount`/`qualifierCount`/`rounds`/
/// `with_reset`) to avoid a template-data migration; new keys are snake_case.
///
/// All readers are total: a missing or wrong-typed value yields null/empty/the
/// fallback, never throws — node configs are user data and may be partial.
library;

import 'package:kubb_domain/src/tournament/pool_phase.dart';
import 'package:kubb_domain/src/tournament/tournament_setup.dart';

/// Config key constants — the single spelling shared by readers and writers.
abstract final class StageNodeConfigKeys {
  static const koMatchup = 'ko_matchup';
  static const koTiebreakMethod = 'ko_tiebreak_method';
  static const koRoundFormats = 'ko_round_formats';
  static const withReset = 'with_reset';
  static const groupCount = 'groupCount';
  static const qualifierCount = 'qualifierCount';
  static const groupingStrategy = 'grouping_strategy';
  static const randomSeed = 'random_seed';
  static const groupPitchAssignment = 'group_pitch_assignment';
  static const rounds = 'rounds';
}

// --- KO readers -------------------------------------------------------------

/// The configured KO matchup, or null when unset/invalid.
KoMatchup? koMatchupFromConfig(Map<String, Object?> config) {
  final raw = config[StageNodeConfigKeys.koMatchup];
  if (raw is! String) return null;
  for (final m in KoMatchup.values) {
    if (m.wire == raw) return m;
  }
  return null;
}

/// The configured KO tiebreak method, or null when unset/invalid.
KoTiebreakMethod? koTiebreakMethodFromConfig(Map<String, Object?> config) {
  final raw = config[StageNodeConfigKeys.koTiebreakMethod];
  if (raw is! String) return null;
  for (final m in KoTiebreakMethod.values) {
    if (m.wire == raw) return m;
  }
  return null;
}

/// Whether the double-elim bracket reset is on.
bool koWithResetFromConfig(Map<String, Object?> config) =>
    config[StageNodeConfigKeys.withReset] == true;

/// The per-round KO formats (index 0 = round 1), empty when unset. Malformed
/// entries are skipped rather than throwing.
List<MatchFormatSpec> koRoundFormatsFromConfig(Map<String, Object?> config) {
  final raw = config[StageNodeConfigKeys.koRoundFormats];
  if (raw is! List) return const <MatchFormatSpec>[];
  final out = <MatchFormatSpec>[];
  for (final entry in raw) {
    if (entry is Map) {
      try {
        out.add(MatchFormatSpec.fromJson(Map<String, Object?>.from(entry)));
      } on Object catch (_) {
        // Skip a malformed round entry; partial config must not crash callers.
      }
    }
  }
  return out;
}

// --- Pool readers -----------------------------------------------------------

/// The configured pool grouping strategy, or null when unset/invalid.
PoolGroupingStrategy? poolGroupingStrategyFromConfig(
  Map<String, Object?> config,
) {
  final raw = config[StageNodeConfigKeys.groupingStrategy];
  if (raw is! String) return null;
  for (final s in PoolGroupingStrategy.values) {
    if (s.name == raw) return s;
  }
  return null;
}

/// The configured random seed for `random` grouping, or null.
int? poolRandomSeedFromConfig(Map<String, Object?> config) {
  final raw = config[StageNodeConfigKeys.randomSeed];
  return raw is int ? raw : null;
}

/// Per-group pitch assignment (group label → pitch numbers), empty when unset.
/// Mirrors `PitchPlan.groupAssignment`. Malformed entries (non-string keys,
/// non-list / non-int values) are dropped rather than throwing — node configs
/// are user data and may be partial.
Map<String, List<int>> poolGroupPitchAssignmentFromConfig(
  Map<String, Object?> config,
) {
  final raw = config[StageNodeConfigKeys.groupPitchAssignment];
  if (raw is! Map) return const <String, List<int>>{};
  final out = <String, List<int>>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || value is! List) continue;
    final pitches = <int>[for (final p in value) if (p is int) p];
    if (pitches.isNotEmpty) out[key] = pitches;
  }
  return out;
}

// --- Writers ----------------------------------------------------------------

/// Builds the config map for a KO node. Only set fields are written, so the
/// summary/engine never see empty placeholder keys. [withReset] is meaningful
/// for double-elim only; callers pass it null for single-elim/consolation.
Map<String, Object?> writeKoNodeConfig({
  KoMatchup? matchup,
  KoTiebreakMethod? tiebreakMethod,
  bool? withReset,
  List<MatchFormatSpec> roundFormats = const <MatchFormatSpec>[],
}) {
  return <String, Object?>{
    if (matchup != null) StageNodeConfigKeys.koMatchup: matchup.wire,
    if (tiebreakMethod != null)
      StageNodeConfigKeys.koTiebreakMethod: tiebreakMethod.wire,
    StageNodeConfigKeys.withReset: ?withReset,
    if (roundFormats.isNotEmpty)
      StageNodeConfigKeys.koRoundFormats:
          roundFormats.map((f) => f.toJson()).toList(),
  };
}

/// Builds the config map for a pool/round-robin node. [groupPitchAssignment]
/// maps a group label (A, B, …) to the pitch numbers serving that group; it is
/// only written when non-empty so older graphs without the key stay clean.
Map<String, Object?> writePoolNodeConfig({
  required int groupCount,
  required int qualifierCount,
  PoolGroupingStrategy? strategy,
  int? randomSeed,
  Map<String, List<int>> groupPitchAssignment = const <String, List<int>>{},
}) {
  return <String, Object?>{
    StageNodeConfigKeys.groupCount: groupCount,
    StageNodeConfigKeys.qualifierCount: qualifierCount,
    if (strategy != null) StageNodeConfigKeys.groupingStrategy: strategy.name,
    StageNodeConfigKeys.randomSeed: ?randomSeed,
    if (groupPitchAssignment.isNotEmpty)
      StageNodeConfigKeys.groupPitchAssignment: <String, Object?>{
        for (final e in groupPitchAssignment.entries) e.key: List<int>.of(e.value),
      },
  };
}
