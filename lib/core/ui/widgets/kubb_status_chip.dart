import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Central mapping from lifecycle enums (match / tournament-match /
/// tournament) to a [KubbChip] with the right semantic [KubbChipTone]
/// and a localised label.
///
/// Sprint B / W3-T4 — addressing Mängel-Report #1 ("Chips wirken alle
/// gleich") and the Re-Hit family R10-F-06: status chips across the
/// match-detail, tournament-list and match-lobby screens used to all
/// share the meadow palette, so the user could not visually distinguish
/// e.g. a finished match from a live one. The factory constructors here
/// pin a stable tone per status so the three screens are guaranteed to
/// agree.
///
/// Tone choices (single source of truth):
///   * `live` / `running`       → [KubbChipTone.hit]      (meadow-100)
///   * `awaiting` / `scheduled` → [KubbChipTone.heli]     (wood-100)
///   * `disputed`               → [KubbChipTone.penalty]  (penalty surface)
///   * `finished` / `finalized` → [KubbChipTone.info]     (meadow-500 solid)
///   * `draft`                  → [KubbChipTone.neutral]  (stone-100)
///   * `cancelled` / `voided`   → [KubbChipTone.miss]     (miss surface)
class KubbStatusChip extends StatelessWidget {
  const KubbStatusChip._({
    required this.tone,
    required this.label,
    super.key,
  });

  /// Status chip for a free (non-tournament) match.
  factory KubbStatusChip.match({
    required MatchStatus status,
    required AppLocalizations l,
    Key? key,
  }) {
    final (tone, label) = _matchSpec(status, l);
    return KubbStatusChip._(tone: tone, label: label, key: key);
  }

  /// Status chip for a tournament match.
  factory KubbStatusChip.tournamentMatch({
    required TournamentMatchStatus status,
    required AppLocalizations l,
    Key? key,
  }) {
    final (tone, label) = _tournamentMatchSpec(status, l);
    return KubbStatusChip._(tone: tone, label: label, key: key);
  }

  /// Status chip for a tournament (lifecycle as a whole).
  factory KubbStatusChip.tournament({
    required TournamentStatus status,
    required AppLocalizations l,
    Key? key,
  }) {
    final (tone, label) = _tournamentSpec(status, l);
    return KubbStatusChip._(tone: tone, label: label, key: key);
  }

  final KubbChipTone tone;
  final String label;

  @override
  Widget build(BuildContext context) =>
      KubbChip(tone: tone, label: label);

  static (KubbChipTone, String) _matchSpec(
    MatchStatus s,
    AppLocalizations l,
  ) {
    switch (s) {
      case MatchStatus.pendingInvites:
        return (KubbChipTone.neutral, l.statusMatchWaiting);
      case MatchStatus.active:
        return (KubbChipTone.hit, l.statusMatchLive);
      case MatchStatus.awaitingResults:
        return (KubbChipTone.heli, l.statusMatchWaiting);
      case MatchStatus.finalized:
        return (KubbChipTone.info, l.statusMatchFinished);
      case MatchStatus.voided:
        return (KubbChipTone.miss, l.statusMatchVoided);
    }
  }

  static (KubbChipTone, String) _tournamentMatchSpec(
    TournamentMatchStatus s,
    AppLocalizations l,
  ) {
    switch (s) {
      case TournamentMatchStatus.scheduled:
        return (KubbChipTone.heli, l.statusMatchWaiting);
      case TournamentMatchStatus.awaitingResults:
        return (KubbChipTone.heli, l.statusMatchWaiting);
      case TournamentMatchStatus.disputed:
        return (KubbChipTone.penalty, l.statusMatchDisputed);
      case TournamentMatchStatus.finalized:
        return (KubbChipTone.info, l.statusMatchFinished);
      case TournamentMatchStatus.overridden:
        return (KubbChipTone.info, l.statusMatchOverridden);
      case TournamentMatchStatus.voided:
        return (KubbChipTone.miss, l.statusMatchVoided);
    }
  }

  static (KubbChipTone, String) _tournamentSpec(
    TournamentStatus s,
    AppLocalizations l,
  ) {
    switch (s) {
      case TournamentStatus.draft:
        return (KubbChipTone.neutral, l.statusTournamentDraft);
      case TournamentStatus.published:
        return (KubbChipTone.heli, l.statusTournamentPublished);
      case TournamentStatus.registrationOpen:
        return (KubbChipTone.heli, l.statusTournamentRegistrationOpen);
      case TournamentStatus.registrationClosed:
        return (KubbChipTone.heli, l.statusTournamentRegistrationClosed);
      case TournamentStatus.live:
        return (KubbChipTone.hit, l.statusTournamentRunning);
      case TournamentStatus.finalized:
        return (KubbChipTone.info, l.statusTournamentFinished);
      case TournamentStatus.aborted:
        return (KubbChipTone.miss, l.statusTournamentCancelled);
    }
  }
}
