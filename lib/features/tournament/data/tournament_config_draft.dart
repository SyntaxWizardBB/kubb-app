import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:kubb_domain/kubb_domain.dart';

/// Outcome of [TournamentConfigDraft.validate]. Mirrors the record-style
/// surface that `MatchConfigDraft.validate` exposes so the wizard can use
/// the same `isValid` / `issues` access pattern.
typedef TournamentConfigValidation = ({bool isValid, List<String> issues});

/// Mutable wizard state for the tournament setup flow. The shape mirrors
/// the parameters of `TournamentRemote.createTournament` so the actions
/// provider can hand the draft straight to the RPC layer.
@immutable
class TournamentConfigDraft {
  const TournamentConfigDraft({
    this.displayName,
    this.teamSize = 1,
    this.minParticipants = 2,
    this.maxParticipants = 8,
    this.format = TournamentFormat.roundRobin,
    this.setsToWin = 2,
    this.maxSets = 3,
    this.roundTimeSeconds = 1800,
    this.basekubbsPerSide = 5,
    this.tiebreakerOrder = const <String>[
      'total_points',
      'buchholz_minus_h2h',
      'direct_comparison',
      'wins',
    ],
  });

  /// Visible name of the tournament. Null while the organizer hasn't
  /// typed anything yet; validate() flags both null and empty input.
  final String? displayName;
  final int teamSize;
  final int minParticipants;
  final int maxParticipants;
  final TournamentFormat format;
  final int setsToWin;
  final int maxSets;
  final int roundTimeSeconds;
  final int basekubbsPerSide;
  final List<String> tiebreakerOrder;

  static const int displayNameMinChars = 3;
  static const int displayNameMaxChars = 60;
  static const int participantsHardMin = 2;
  static const int participantsHardMax = 64;
  static const int setsToWinMin = 1;
  static const int setsToWinMax = 4;

  TournamentConfigDraft copyWith({
    String? displayName,
    int? teamSize,
    int? minParticipants,
    int? maxParticipants,
    TournamentFormat? format,
    int? setsToWin,
    int? maxSets,
    int? roundTimeSeconds,
    int? basekubbsPerSide,
    List<String>? tiebreakerOrder,
  }) {
    return TournamentConfigDraft(
      displayName: displayName ?? this.displayName,
      teamSize: teamSize ?? this.teamSize,
      minParticipants: minParticipants ?? this.minParticipants,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      format: format ?? this.format,
      setsToWin: setsToWin ?? this.setsToWin,
      maxSets: maxSets ?? this.maxSets,
      roundTimeSeconds: roundTimeSeconds ?? this.roundTimeSeconds,
      basekubbsPerSide: basekubbsPerSide ?? this.basekubbsPerSide,
      tiebreakerOrder: tiebreakerOrder ?? this.tiebreakerOrder,
    );
  }

  TournamentConfigValidation validate() {
    final issues = <String>[];
    final name = displayName?.trim() ?? '';
    if (name.isEmpty) {
      issues.add('Turniername fehlt.');
    } else if (name.length < displayNameMinChars) {
      issues.add('Turniername muss mindestens $displayNameMinChars Zeichen haben.');
    } else if (name.length > displayNameMaxChars) {
      issues.add('Turniername darf höchstens $displayNameMaxChars Zeichen haben.');
    }

    if (minParticipants < participantsHardMin) {
      issues.add('Mindestens $participantsHardMin Teilnehmer.');
    }
    if (maxParticipants > participantsHardMax) {
      issues.add('Höchstens $participantsHardMax Teilnehmer.');
    }
    if (minParticipants > maxParticipants) {
      issues.add('Min. Teilnehmer darf nicht grösser als Max. sein.');
    }

    if (setsToWin < setsToWinMin || setsToWin > setsToWinMax) {
      issues.add('Sätze zum Sieg muss zwischen $setsToWinMin und $setsToWinMax liegen.');
    }
    final requiredMaxSets = 2 * setsToWin - 1;
    if (maxSets < requiredMaxSets) {
      issues.add('Max. Sätze muss mindestens $requiredMaxSets sein.');
    }

    if (roundTimeSeconds < 60) {
      issues.add('Rundenzeit muss mindestens eine Minute sein.');
    }

    if (basekubbsPerSide < 1) {
      issues.add('Basiskubbs pro Seite muss mindestens 1 sein.');
    }

    return (isValid: issues.isEmpty, issues: issues);
  }

  /// Shape consumed by the `tournament_create` RPC's
  /// `p_match_format_config` parameter. Kept as a plain map so the wire
  /// contract can evolve without a Dart migration.
  Map<String, Object?> toMatchFormatConfig() {
    return <String, Object?>{
      'sets_to_win': setsToWin,
      'max_sets': maxSets,
      'round_time_seconds': roundTimeSeconds,
      'basekubbs_per_side': basekubbsPerSide,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentConfigDraft &&
          other.displayName == displayName &&
          other.teamSize == teamSize &&
          other.minParticipants == minParticipants &&
          other.maxParticipants == maxParticipants &&
          other.format == format &&
          other.setsToWin == setsToWin &&
          other.maxSets == maxSets &&
          other.roundTimeSeconds == roundTimeSeconds &&
          other.basekubbsPerSide == basekubbsPerSide &&
          listEquals(other.tiebreakerOrder, tiebreakerOrder);

  @override
  int get hashCode => Object.hash(
        displayName,
        teamSize,
        minParticipants,
        maxParticipants,
        format,
        setsToWin,
        maxSets,
        roundTimeSeconds,
        basekubbsPerSide,
        Object.hashAll(tiebreakerOrder),
      );
}
