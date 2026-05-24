import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/match/presentation/widgets/match_status_pill.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Pre-game lobby. Shows the team rosters and the invitation status of
/// each in-app participant. Auto-redirects to the active screen once
/// every invite has been accepted (status flips to `active`).
///
/// Polling is kept alive by reading [matchPollingProvider] for its side
/// effect — its value isn't otherwise consumed here.
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
    ref.listen<AsyncValue<MatchDetail?>>(
      matchDetailProvider(matchId),
      (_, next) {
        final d = next.value;
        if (d == null) return;
        if (d.match.status == MatchStatus.active ||
            d.match.status == MatchStatus.awaitingResults) {
          context.go('${MatchRoutes.result}/$matchId');
        } else if (d.match.status == MatchStatus.finalized ||
            d.match.status == MatchStatus.voided) {
          context.go('${MatchRoutes.finished}/$matchId');
        }
      },
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => context.go('/')),
        title: const Text('Match-Lobby'),
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
}

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({
    required this.detail,
    required this.myUserId,
    required this.onCancel,
  });

  final MatchDetail detail;
  final String? myUserId;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;

    // Server tags the creator on `match_get`; the cancel RPC enforces
    // the same rule. The button is a UX hint, not a security boundary.
    final canCancel = detail.isCallerCreator(myUserId) &&
        detail.match.status == MatchStatus.pendingInvites;

    final teamA = detail.participants.where((p) => p.teamId == 'A').toList();
    final teamB = detail.participants.where((p) => p.teamId == 'B').toList();

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        Row(
          children: [
            _MetaChip(text: _formatLabel(detail.match.format)),
            const SizedBox(width: KubbTokens.space2),
            _MetaChip(text: _scoringLabel(detail.match.scoring)),
            const Spacer(),
            MatchStatusPill(status: detail.match.status),
          ],
        ),
        const SizedBox(height: KubbTokens.space4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TeamPanel(
                title: 'Team A',
                accent: KubbTokens.meadow600,
                participants: teamA,
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: _TeamPanel(
                title: 'Team B',
                accent: KubbTokens.wood400,
                participants: teamB,
              ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space5),
        if (detail.match.status == MatchStatus.pendingInvites)
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
        if (canCancel) ...[
          const SizedBox(height: KubbTokens.space5),
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: KubbTokens.miss),
              onPressed: onCancel,
              child: const Text('Match abbrechen'),
            ),
          ),
        ],
      ],
    );
  }

  String _formatLabel(MatchFormat f) => 'BO${f.n}';

  String _scoringLabel(MatchScoring s) => switch (s) {
        MatchScoring.wins => 'Sätze',
        MatchScoring.points => 'Punkte',
      };
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
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
            ),
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
