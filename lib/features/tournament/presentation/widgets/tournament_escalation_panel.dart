import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_forfeit_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Organizer escalation cockpit (ADR-0031 Phase D5). A self-contained,
/// reusable widget that surfaces the three things that need organizer
/// attention during a live event:
///
///  * **Strittig** — matches in [TournamentMatchStatus.disputed]; each row
///    links into the existing organizer override screen.
///  * **Überfällig** — matches in [TournamentMatchStatus.awaitingResults]
///    (the A-schedule hold isn't carried on [TournamentDetail], so the
///    match-status fallback per the phase-D plan is the source here).
///  * **Nicht eingecheckt** — participants whose registration is confirmed
///    but who carry no on-site check-in ([TournamentParticipant.isCheckedIn]
///    is false). When such a participant sits in a forfeitable match and the
///    tournament is live, the row offers a No-Show→Forfait shortcut that
///    opens the EXISTING [TournamentForfeitSheet] pre-filled with their
///    match side and a fixed reason.
///
/// Data source: this widget reads EXCLUSIVELY from the [TournamentDetail]
/// the detail screen already holds (which is fed by `tournamentDetailProvider`
/// and refreshed over the existing participant/match CDC chain). It opens NO
/// new read/RPC/realtime provider and starts NO new timer — live-ness comes
/// from the detail provider being invalidated by the existing CDC events.
class TournamentEscalationPanel extends ConsumerWidget {
  const TournamentEscalationPanel({
    required this.detail,
    required this.tournamentId,
    required this.canManage,
    super.key,
  });

  /// The already-loaded tournament detail. Single source of truth for the
  /// three escalation lists — no additional fetch is performed.
  final TournamentDetail detail;

  final TournamentId tournamentId;

  /// Whether the caller may run organizer interventions (Creator OR an active
  /// club role in {owner, admin, organizer, referee} — K4). Governs the
  /// override link and the forfeit shortcut visibility on the client; the
  /// server re-checks `tournament_caller_can_manage` in every RPC.
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    // (a) STRITTIG — matches awaiting an organizer override.
    final disputed = detail.matches
        .where((m) => m.status == TournamentMatchStatus.disputed)
        .toList(growable: false);

    // (b) ÜBERFÄLLIG — matches whose results are overdue. The A-schedule hold
    // (RoundStatus.awaitingResults on tournament_round_schedule) is not part
    // of TournamentDetail, so per the phase-D plan we fall back to the match
    // status awaitingResults.
    final overdue = detail.matches
        .where((m) => m.status == TournamentMatchStatus.awaitingResults)
        .toList(growable: false);

    // (c) NICHT EINGECHECKT — confirmed pool members without an on-site
    // check-in. Confirmed = approved (new open-registration model) or the
    // legacy `pending` rows that still count as confirmed-pool; waitlist /
    // withdrawn / rejected never surface here. checkedInAt == null ⇔
    // !isCheckedIn.
    final notCheckedIn = detail.participants
        .where((p) =>
            (p.registrationStatus == TournamentParticipantStatus.approved ||
                p.registrationStatus ==
                    TournamentParticipantStatus.pending) &&
            !p.isCheckedIn)
        .toList(growable: false);

    final hasAnything =
        disputed.isNotEmpty || overdue.isNotEmpty || notCheckedIn.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.tournamentEscalationTitle.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: tokens.fgMuted,
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          if (!hasAnything)
            KubbEmptyState(
              title: l.tournamentEscalationEmptyTitle,
              body: l.tournamentEscalationEmptyBody,
            )
          else ...[
            if (disputed.isNotEmpty)
              _Section(
                heading: l.tournamentEscalationDisputedHeading,
                icon: LucideIcons.alertTriangle,
                tint: KubbTokens.miss,
                children: [
                  for (final m in disputed)
                    _MatchRow(
                      tokens: tokens,
                      l: l,
                      match: m,
                      // Override entry is the disputed-row action; gated on
                      // canManage so non-managers only see the flag.
                      action: canManage
                          ? _RowAction(
                              icon: LucideIcons.gavel,
                              label: l.tournamentEscalationOverrideAction,
                              tint: KubbTokens.miss,
                              onTap: () => context.push(
                                TournamentRoutes.override(
                                  tournamentId.value,
                                  m.matchId.value,
                                ),
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            if (overdue.isNotEmpty) ...[
              if (disputed.isNotEmpty)
                const SizedBox(height: KubbTokens.space3),
              _Section(
                heading: l.tournamentEscalationOverdueHeading,
                icon: LucideIcons.clock,
                tint: KubbTokens.wood400,
                children: [
                  for (final m in overdue)
                    _MatchRow(tokens: tokens, l: l, match: m),
                ],
              ),
            ],
            if (notCheckedIn.isNotEmpty) ...[
              if (disputed.isNotEmpty || overdue.isNotEmpty)
                const SizedBox(height: KubbTokens.space3),
              _Section(
                heading: l.tournamentEscalationNotCheckedInHeading,
                icon: LucideIcons.userX,
                tint: tokens.fgMuted,
                children: _notCheckedInRows(context, tokens, l, notCheckedIn),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Builds the not-checked-in rows, attaching the No-Show→Forfait shortcut
  /// where eligible. The shortcut is offered only when the tournament is
  /// [TournamentStatus.live] AND the participant sits in a forfeitable match
  /// ([TournamentMatchStatus.scheduled] | awaitingResults | disputed). Only
  /// ONE side per match is ever offered: once a match has produced a forfeit
  /// CTA, the other (also-absent) side renders without one.
  List<Widget> _notCheckedInRows(
    BuildContext context,
    KubbTokens tokens,
    AppLocalizations l,
    List<TournamentParticipant> notCheckedIn,
  ) {
    final isLive = detail.tournament.status == TournamentStatus.live;
    final offeredMatchIds = <String>{};
    final rows = <Widget>[];
    for (final p in notCheckedIn) {
      _ForfeitTarget? target;
      if (canManage && isLive) {
        target = _forfeitTargetFor(p, offeredMatchIds);
        if (target != null) offeredMatchIds.add(target.matchId.value);
      }
      rows.add(
        _ParticipantRow(
          tokens: tokens,
          l: l,
          participant: p,
          action: target == null
              ? null
              : _RowAction(
                  icon: LucideIcons.userX,
                  label: l.tournamentEscalationForfeitAction,
                  tint: tokens.fgMuted,
                  onTap: () => TournamentForfeitSheet.show(
                    context,
                    matchId: target!.matchId,
                    initialAbsentSide: target.absentSide,
                    initialReason: l.tournamentEscalationNoShowReason,
                  ),
                ),
        ),
      );
    }
    return rows;
  }

  /// Finds the first forfeitable match the participant sits in that has not
  /// already produced a forfeit offer, and the side they occupy. Returns
  /// null when there is no eligible match (so no shortcut is shown).
  _ForfeitTarget? _forfeitTargetFor(
    TournamentParticipant p,
    Set<String> offeredMatchIds,
  ) {
    final pid = p.participantId;
    for (final m in detail.matches) {
      if (offeredMatchIds.contains(m.matchId.value)) continue;
      if (m.status != TournamentMatchStatus.scheduled &&
          m.status != TournamentMatchStatus.awaitingResults &&
          m.status != TournamentMatchStatus.disputed) {
        continue;
      }
      if (m.participantA?.value == pid) {
        return _ForfeitTarget(m.matchId, ForfeitAbsentSide.a);
      }
      if (m.participantB?.value == pid) {
        return _ForfeitTarget(m.matchId, ForfeitAbsentSide.b);
      }
    }
    return null;
  }
}

/// The match + side the No-Show shortcut will pre-fill the forfeit sheet with.
@immutable
class _ForfeitTarget {
  const _ForfeitTarget(this.matchId, this.absentSide);
  final TournamentMatchId matchId;
  final ForfeitAbsentSide absentSide;
}

/// Visual + behavioural description of a row's trailing action button.
@immutable
class _RowAction {
  const _RowAction({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.heading,
    required this.icon,
    required this.tint,
    required this.children,
  });

  final String heading;
  final IconData icon;
  final Color tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: tint),
            const SizedBox(width: KubbTokens.space2),
            Text(
              heading,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
              ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space1),
        ...children,
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.tokens,
    required this.l,
    required this.match,
    this.action,
  });

  final KubbTokens tokens;
  final AppLocalizations l;
  final TournamentMatchRef match;
  final _RowAction? action;

  @override
  Widget build(BuildContext context) {
    final a = match.participantADisplayName ?? '?';
    final b = match.participantBDisplayName ?? '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$a — $b',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                Text(
                  l.tournamentEscalationMatchLabel(
                    match.roundNumber,
                    match.matchNumberInRound,
                  ),
                  style: TextStyle(fontSize: 11, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
          if (action != null) _ActionButton(action: action!),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.tokens,
    required this.l,
    required this.participant,
    this.action,
  });

  final KubbTokens tokens;
  final AppLocalizations l;
  final TournamentParticipant participant;
  final _RowAction? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              participant.displayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
              ),
            ),
          ),
          if (action != null) _ActionButton(action: action!),
        ],
      ),
    );
  }
}

/// Trailing action button. Constrained to a >= 48 dp touch target.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});
  final _RowAction action;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
      child: TextButton.icon(
        onPressed: action.onTap,
        icon: Icon(action.icon, size: 16, color: action.tint),
        label: Text(
          action.label,
          style: TextStyle(color: action.tint, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
