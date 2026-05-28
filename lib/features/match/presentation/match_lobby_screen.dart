import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_status_chip.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Pre-game lobby. Shows the team rosters and the invitation status of
/// each in-app participant. Auto-redirects to the active screen once
/// every invite has been accepted (status flips to `active`).
///
/// Polling is kept alive by reading [matchPollingProvider] for its side
/// effect — its value isn't otherwise consumed here.
///
/// Sprint B / W5-T2: aligned with the mobile-kit `MatchScreen.jsx`
/// lobby tab. Uses [KubbAppBar] (eyebrow `Match · Lobby`), the inset-card
/// pattern with eyebrow section-headers for the "Mitspieler" block, and
/// [KubbButton] primary / ghost variants for the action row.
class MatchLobbyScreen extends ConsumerWidget {
  const MatchLobbyScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    ref.watch(matchPollingProvider(matchId));
    final detailAsync = ref.watch(matchDetailProvider(matchId));
    final myUserId = ref.watch(currentUserIdProvider);

    // Status-driven navigation. Listen so we don't redirect during build.
    // The "active" status is treated as "all invites accepted, time to
    // enter the result" — we route straight to the result screen and
    // skip the no-op active intermediate that used to sit between
    // them. Server-side `match_propose_result` auto-transitions
    // active → awaiting_results on first proposal.
    //
    // Only react to actual status transitions — polling invalidates the
    // provider every second, so listening to every emission would loop
    // `context.go` forever once the match goes active.
    ref.listen<AsyncValue<MatchDetail?>>(
      matchDetailProvider(matchId),
      (prev, next) {
        final prevStatus = prev?.value?.match.status;
        final nextStatus = next.value?.match.status;
        if (nextStatus == null || nextStatus == prevStatus) return;
        if (nextStatus == MatchStatus.active ||
            nextStatus == MatchStatus.awaitingResults) {
          context.go('${MatchRoutes.result}/$matchId');
        } else if (nextStatus == MatchStatus.finalized ||
            nextStatus == MatchStatus.voided) {
          context.go('${MatchRoutes.finished}/$matchId');
        }
      },
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: 'Match · Lobby',
        title: 'Lobby',
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          color: tokens.fg,
          iconSize: 24,
          splashRadius: 24,
          constraints: const BoxConstraints.tightFor(
            width: KubbTokens.touchMin,
            height: KubbTokens.touchMin,
          ),
          onPressed: () => context.go('/'),
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              'Match konnte nicht geladen werden:\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _LobbyBody(
            detail: detail,
            myUserId: myUserId,
            onCancel: () => _runCancel(context, ref),
            onAccept: () => _runAccept(context, ref),
          );
        },
      ),
    );
  }

  Future<void> _runCancel(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(matchActionsProvider).cancelMatch(matchId);
      if (!context.mounted) return;
      context.go('/');
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Abbrechen fehlgeschlagen: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    }
  }

  Future<void> _runAccept(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(matchActionsProvider).acceptInvite(matchId);
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Annehmen fehlgeschlagen: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    }
  }
}

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({
    required this.detail,
    required this.myUserId,
    required this.onCancel,
    required this.onAccept,
  });

  final MatchDetail detail;
  final String? myUserId;
  final VoidCallback onCancel;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    // Server tags the creator on `match_get`; the cancel RPC enforces
    // the same rule. The button is a UX hint, not a security boundary.
    final canCancel = detail.isCallerCreator(myUserId) &&
        detail.match.status == MatchStatus.pendingInvites;

    // The "Bereit" CTA only makes sense while the caller still has a
    // pending invitation row of their own. Once accepted, the lobby is
    // a watch-state until the server flips the match to `active`.
    MatchParticipant? myParticipant;
    if (myUserId != null) {
      for (final p in detail.participants) {
        if (p.userId == myUserId) {
          myParticipant = p;
          break;
        }
      }
    }
    final canAccept = myParticipant != null &&
        myParticipant.invitationStatus == MatchInvitationStatus.pending &&
        detail.match.status == MatchStatus.pendingInvites;

    final teamA = detail.participants.where((p) => p.teamId == 'A').toList();
    final teamB = detail.participants.where((p) => p.teamId == 'B').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space2,
        KubbTokens.space4,
        KubbTokens.space6,
      ),
      children: [
        Row(
          children: [
            _MetaChip(text: _formatLabel(detail.match.format)),
            const Spacer(),
            // W3-T4: central status mapping — distinguishes live (hit),
            // awaiting (heli) and finalized (info) tones instead of the
            // old meadow-everything pill.
            KubbStatusChip.match(status: detail.match.status, l: l),
          ],
        ),
        const SizedBox(height: KubbTokens.space5),
        // Section header in the eyebrow style (`docs/design/quality-gates/
        // mobile-kit-overview.md` §Section-Header). Matches the section
        // labels used inside MatchScreen.jsx → Lobby ("Direkter Vergleich",
        // "Match-Setup").
        const _SectionHeader(text: 'Mitspieler'),
        const SizedBox(height: KubbTokens.space2),
        // Inset card pattern: bgRaised surface, 14dp radius, single-px
        // line border to mirror the mobile-kit `h2hList` / `setupList`
        // surfaces.
        _InsetCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TeamPanel(
                  title: 'Team A',
                  accent: KubbTokens.meadow600,
                  participants: teamA,
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(
                  vertical: KubbTokens.space2,
                ),
                color: tokens.line,
              ),
              Expanded(
                child: _TeamPanel(
                  title: 'Team B',
                  accent: KubbTokens.wood400,
                  participants: teamB,
                ),
              ),
            ],
          ),
        ),
        if (detail.match.status == MatchStatus.pendingInvites) ...[
          const SizedBox(height: KubbTokens.space4),
          Container(
            padding: const EdgeInsets.all(KubbTokens.space3),
            decoration: BoxDecoration(
              color: tokens.bgSunken,
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.clock, size: 16),
                const SizedBox(width: KubbTokens.space2),
                Expanded(
                  child: Text(
                    'Warten auf Annahme aller Einladungen…',
                    style: TextStyle(fontSize: 13, color: tokens.fgMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (canAccept || canCancel) ...[
          const SizedBox(height: KubbTokens.space5),
          if (canAccept)
            KubbButton(
              variant: KubbButtonVariant.primary,
              onPressed: onAccept,
              child: const Text('Bereit'),
            ),
          if (canAccept && canCancel)
            const SizedBox(height: KubbTokens.space2),
          if (canCancel)
            KubbButton(
              variant: KubbButtonVariant.ghost,
              onPressed: onCancel,
              child: const Text('Match abbrechen'),
            ),
        ],
      ],
    );
  }

  String _formatLabel(MatchFormat f) => 'BO${f.n}';
}

/// Inset card surface (`bgRaised` + hairline border, 14dp radius) —
/// canonical pattern from `docs/design/quality-gates/mobile-kit-overview.md`
/// §Inset-Card.
class _InsetCard extends StatelessWidget {
  const _InsetCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.line),
      ),
      padding: const EdgeInsets.all(KubbTokens.space3),
      child: child,
    );
  }
}

/// Eyebrow-style section header — see `docs/design/quality-gates/
/// mobile-kit-overview.md` §Section-Header.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.88,
          color: tokens.fgMuted,
        ),
      ),
    );
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
        horizontal: KubbTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tokens.fg,
        ),
      ),
    );
  }
}

class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    required this.title,
    required this.accent,
    required this.participants,
  });

  final String title;
  final Color accent;
  final List<MatchParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 14, color: accent),
              const SizedBox(width: KubbTokens.space2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          for (final p in participants) ...[
            _ParticipantRow(participant: p),
            const SizedBox(height: KubbTokens.space2),
          ],
          if (participants.isEmpty)
            Text(
              '–',
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});
  final MatchParticipant participant;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final name = _displayName(participant);
    final (icon, color) = _statusIcon(participant);

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
            ),
          ),
        ),
      ],
    );
  }

  String _displayName(MatchParticipant p) => p.nickname ?? '…';

  (IconData, Color) _statusIcon(MatchParticipant p) {
    switch (p.invitationStatus) {
      case MatchInvitationStatus.accepted:
        return (LucideIcons.check, KubbTokens.meadow600);
      case MatchInvitationStatus.pending:
        return (LucideIcons.clock, KubbTokens.wood400);
      case MatchInvitationStatus.declined:
        return (LucideIcons.x, KubbTokens.miss);
      case MatchInvitationStatus.left:
        return (LucideIcons.userMinus, KubbTokens.miss);
    }
  }
}
