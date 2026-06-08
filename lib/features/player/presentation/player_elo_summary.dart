import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/features/player/data/player_elo_ratings.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Renders a player's ELO ratings on a profile screen.
///
/// The tournament block is public and always rendered (with a "noch keine
/// Wertung" hint when the player has no tournament rating yet). The personal
/// block is rendered ONLY when [PlayerEloRatings.personal] is non-null —
/// visibility is decided server-side by RLS (owner / accepted friend), so the
/// mere presence of the `personal` row is the signal to show it. There is no
/// owner/friend check in this widget.
///
/// Pure presentation: the async unwrapping happens in the caller, so this
/// widget is testable without a ProviderScope.
class PlayerEloSummary extends StatelessWidget {
  const PlayerEloSummary({required this.ratings, super.key});

  final PlayerEloRatings ratings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final tournament = ratings.tournament;
    final personal = ratings.personal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.eloSectionLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        if (tournament == null)
          _EloTile(
            label: l.eloTournamentLabel,
            child: Text(
              l.eloNoRating,
              style: TextStyle(fontSize: 14, color: tokens.fgMuted),
            ),
          )
        else
          _EloTile(
            label: l.eloTournamentLabel,
            trailing: tournament.provisional
                ? KubbChip(
                    tone: KubbChipTone.neutral,
                    label: l.eloProvisionalBadge,
                  )
                : null,
            child: _EloValue(value: tournament.elo, games: tournament.games),
          ),
        // Personal block: shown only when RLS returned a `personal` row.
        if (personal != null) ...[
          const SizedBox(height: KubbTokens.space2),
          _EloTile(
            label: l.eloPersonalLabel,
            labelIcon: KubbIcons.lock,
            private: true,
            child: _EloValue(value: personal.elo, games: personal.games),
          ),
        ],
      ],
    );
  }
}

/// A single labelled ELO container, styled like the profile `_StatTile`
/// (bgRaised surface, line border, radiusLg). The private variant gets a
/// sunken surface so the personal ELO reads as visually distinct from the
/// public tournament number.
class _EloTile extends StatelessWidget {
  const _EloTile({
    required this.label,
    required this.child,
    this.labelIcon,
    this.trailing,
    this.private = false,
  });

  final String label;
  final Widget child;
  final IconData? labelIcon;
  final Widget? trailing;
  final bool private;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space4,
        vertical: KubbTokens.space4,
      ),
      decoration: BoxDecoration(
        color: private ? tokens.bgSunken : tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (labelIcon != null) ...[
                      Icon(labelIcon, size: 13, color: tokens.fgMuted),
                      const SizedBox(width: KubbTokens.space1),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.fgMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KubbTokens.space1),
                child,
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: KubbTokens.space2),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// The numeric ELO value plus a muted games-count caption.
class _EloValue extends StatelessWidget {
  const _EloValue({required this.value, required this.games});

  final int value;
  final int games;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: tokens.fg,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: KubbTokens.space2),
        Text(
          l.eloGamesCount(games),
          style: TextStyle(fontSize: 12, color: tokens.fgMuted),
        ),
      ],
    );
  }
}
