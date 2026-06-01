import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_status_chip.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// One row inside the tournament-list. Composes display name, status
/// pill, format chip and participant counter into a tappable card.
class TournamentCard extends StatelessWidget {
  const TournamentCard({
    required this.summary,
    required this.onTap,
    this.onDetails,
    this.onRegister,
    this.onWithdraw,
    this.isRegistered = false,
    super.key,
  });

  final TournamentSummaryRef summary;
  final VoidCallback onTap;

  /// Optional per-tile "Details" action. When provided, an explicit
  /// "Details" button is rendered in the tile footer alongside the
  /// register/withdraw toggle (P6 spec L123). The whole-card [onTap]
  /// keeps working as a redundant tap-target.
  final VoidCallback? onDetails;

  /// Per-tile "Anmelden" action — invoked when the caller is not yet
  /// registered ([isRegistered] is false).
  final VoidCallback? onRegister;

  /// Per-tile "Abmelden" action — invoked when the caller is already
  /// registered ([isRegistered] is true).
  final VoidCallback? onWithdraw;

  /// Whether the caller already holds a registration for this
  /// tournament. Drives the register/withdraw toggle label and action.
  final bool isRegistered;

  /// True when this tile should render its action footer. The footer is
  /// opt-in: callers that pass no actions (e.g. the registrations list)
  /// keep the bare card.
  bool get _hasActions =>
      onDetails != null || onRegister != null || onWithdraw != null;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(summary.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: tokens.fg)),
                  ),
                  const SizedBox(width: KubbTokens.space2),
                  // W3-T4: central status mapping — `live` paints in the
                  // hit-tone (meadow-100), `draft` in neutral stone-100,
                  // `aborted` in the miss surface, etc.
                  KubbStatusChip.tournament(status: summary.status, l: l),
                ],
              ),
              const SizedBox(height: KubbTokens.space2),
              Row(
                children: [
                  _MetaChip(text: formatLabel(summary.format, l)),
                  const SizedBox(width: KubbTokens.space2),
                  _MetaChip(
                      text: l.tournamentListParticipantCount(
                          summary.participantCount)),
                ],
              ),
              if (_hasActions) ...[
                const SizedBox(height: KubbTokens.space3),
                _actions(context, tokens, l),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(
      BuildContext context, KubbTokens tokens, AppLocalizations l) {
    return Row(
      children: [
        if (onDetails != null)
          Expanded(
            child: SizedBox(
              height: KubbTokens.touchMin,
              child: OutlinedButton(
                onPressed: onDetails,
                child: Text(l.tournamentCardDetails),
              ),
            ),
          ),
        if (onDetails != null && (onRegister != null || onWithdraw != null))
          const SizedBox(width: KubbTokens.space2),
        if (isRegistered && onWithdraw != null)
          Expanded(
            child: SizedBox(
              height: KubbTokens.touchMin,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: KubbTokens.miss),
                onPressed: onWithdraw,
                child: Text(l.tournamentDetailActionWithdraw),
              ),
            ),
          )
        else if (!isRegistered && onRegister != null)
          Expanded(
            child: SizedBox(
              height: KubbTokens.touchMin,
              child: FilledButton(
                onPressed: onRegister,
                child: Text(l.tournamentDetailActionRegister),
              ),
            ),
          ),
      ],
    );
  }
}

/// Maps the domain enum to its German label. Lives next to the card
/// because both the list and the detail header surface it.
String formatLabel(TournamentFormat f, AppLocalizations l) {
  switch (f) {
    case TournamentFormat.roundRobin:
      return l.tournamentFormatRoundRobin;
    case TournamentFormat.singleElimination:
      return l.tournamentFormatSingleElimination;
    case TournamentFormat.schoch:
      return l.tournamentFormatSchoch;
    case TournamentFormat.swiss:
      return l.tournamentFormatSwiss;
    case TournamentFormat.roundRobinThenKo:
      return l.tournamentFormatRoundRobinKo;
    case TournamentFormat.schochThenKo:
      return l.tournamentFormatSchochKo;
    case TournamentFormat.swissThenKo:
      return l.tournamentFormatSwissKo;
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space2, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: tokens.fg)),
    );
  }
}
