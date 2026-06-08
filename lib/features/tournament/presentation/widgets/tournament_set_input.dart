import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Per-set input row used by the match-detail score-entry screen.
/// Stepper for each team's basekubbs plus a 3-way Königsstoss toggle.
/// Touch targets are at least 60dp tall — see handoff §7.1.
class TournamentSetInput extends StatelessWidget {
  const TournamentSetInput({
    required this.setNumber,
    required this.participantAName,
    required this.participantBName,
    required this.basekubbsA,
    required this.basekubbsB,
    required this.king,
    required this.maxBasekubbs,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final int setNumber;

  /// M1: the REAL resolved display names of the two duelling sides
  /// (side A = `participantADisplayName`, side B = `participantBDisplayName`,
  /// localized "Unbekannt" fallback). The detail screen resolves these via
  /// the central `ParticipantName` helper and hands them in so the stepper
  /// labels and the king tri-toggle show the real names instead of the
  /// generic 'Team A'/'Team B'. Pure display — the stepper / touch-target /
  /// SetWinner-emit logic is unchanged.
  final String participantAName;
  final String participantBName;

  final int basekubbsA;
  final int basekubbsB;

  /// `null` = König nicht gefällt / Zeitablauf.
  final SetWinner? king;
  final int maxBasekubbs;
  final bool enabled;
  final ValueChanged<TournamentSetInputValue> onChanged;

  void _emit({int? a, int? b, SetWinner? k, bool setKing = false}) {
    onChanged(TournamentSetInputValue(
      basekubbsA: a ?? basekubbsA,
      basekubbsB: b ?? basekubbsB,
      king: setKing ? k : king,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          l.tournamentMatchSetLabel(setNumber),
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: tokens.fg),
        ),
        const SizedBox(height: KubbTokens.space3),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Stepper(
              // M1: real side-A name instead of the generic
              // 'Basekubbs Team A' label.
              label: participantAName,
              value: basekubbsA,
              accent: KubbTokens.meadow600,
              max: maxBasekubbs,
              enabled: enabled,
              onChanged: (v) => _emit(a: v),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: _Stepper(
              // M1: real side-B name instead of the generic
              // 'Basekubbs Team B' label.
              label: participantBName,
              value: basekubbsB,
              accent: KubbTokens.wood400,
              max: maxBasekubbs,
              enabled: enabled,
              onChanged: (v) => _emit(b: v),
            ),
          ),
        ]),
        const SizedBox(height: KubbTokens.space3),
        Text(
          l.tournamentMatchKingLabel,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: tokens.fgMuted),
        ),
        const SizedBox(height: KubbTokens.space2),
        // Sprint A W3-T2: tri-toggle for the per-set king-outcome
        // (Team A / Team B / Keiner). The "Keiner" option encodes a
        // `KingTimedOut` set per R11-F-01 and lands on the wire as
        // `set_king_outcome = 'timed_out'`; the parent screen maps it
        // into the [KingOutcome] sealed class before submitting.
        Row(children: [
          Expanded(
            child: _ToggleBtn(
              // M1: real side-A name instead of 'Team A'. The emit
              // logic (SetWinner.teamA) is unchanged.
              label: participantAName,
              selected: king == SetWinner.teamA,
              accent: KubbTokens.meadow600,
              onPressed: enabled ? () => _emit(k: SetWinner.teamA, setKing: true) : null,
            ),
          ),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: _ToggleBtn(
              // M1: real side-B name instead of 'Team B'. The emit
              // logic (SetWinner.teamB) is unchanged.
              label: participantBName,
              selected: king == SetWinner.teamB,
              accent: KubbTokens.wood400,
              onPressed: enabled ? () => _emit(k: SetWinner.teamB, setKing: true) : null,
            ),
          ),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: _ToggleBtn(
              label: l.setKingOutcomeNone,
              selected: king == null,
              accent: tokens.fgMuted,
              onPressed: enabled ? () => _emit(setKing: true) : null,
            ),
          ),
        ]),
      ]),
    );
  }
}

@immutable
class TournamentSetInputValue {
  const TournamentSetInputValue({
    required this.basekubbsA,
    required this.basekubbsB,
    required this.king,
  });
  final int basekubbsA;
  final int basekubbsB;
  final SetWinner? king;
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.accent,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });
  final String label;
  final int value;
  final Color accent;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: tokens.fgMuted)),
      const SizedBox(height: KubbTokens.space2),
      Container(
        height: 64,
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          border: Border.all(color: accent, width: 2),
        ),
        alignment: Alignment.center,
        child: Text('$value',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ),
      const SizedBox(height: KubbTokens.space2),
      Row(children: [
        Expanded(
          child: _IconBtn(
            icon: LucideIcons.minus,
            onPressed: enabled && value > 0 ? () => onChanged(value - 1) : null,
          ),
        ),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: _IconBtn(
            icon: LucideIcons.plus,
            onPressed:
                enabled && value < max ? () => onChanged(value + 1) : null,
          ),
        ),
      ]),
    ]);
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      height: KubbTokens.touchComfortable,
      child: Material(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              border: Border.all(color: tokens.line, width: 1.5),
            ),
            child: Icon(icon,
                size: 22,
                color: onPressed == null ? tokens.fgSubtle : tokens.fg),
          ),
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      height: KubbTokens.touchComfortable,
      child: Material(
        color: selected ? accent : tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              border: Border.all(
                color: selected ? accent : tokens.line,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : tokens.fg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
