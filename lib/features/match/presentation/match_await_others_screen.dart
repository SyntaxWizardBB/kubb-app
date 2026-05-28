import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/core/ui/widgets/kubb_skeleton.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/match/presentation/widgets/match_stage_indicator.dart';

/// "Warten auf andere Spieler" — shown after the caller has submitted
/// their own round-result proposal but the rest of the in-app
/// participants haven't yet. Polls [matchDetailProvider] and routes
/// onward when the round is reconciled or the match is finalised.
class MatchAwaitOthersScreen extends ConsumerStatefulWidget {
  const MatchAwaitOthersScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<MatchAwaitOthersScreen> createState() =>
      _MatchAwaitOthersScreenState();
}

class _MatchAwaitOthersScreenState
    extends ConsumerState<MatchAwaitOthersScreen> {
  int? _seenRound;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    ref.watch(matchPollingProvider(widget.matchId));
    final detailAsync = ref.watch(matchDetailProvider(widget.matchId));

    // Listen only on real transitions of (status, currentRound). The
    // polling provider invalidates every second, so an unguarded
    // `context.go` would re-fire forever.
    ref.listen<AsyncValue<MatchDetail?>>(
      matchDetailProvider(widget.matchId),
      (prev, next) {
        final d = next.value;
        if (d == null) return;
        _seenRound ??= d.match.currentRound;

        final prevD = prev?.value;
        final sameStatus = prevD?.match.status == d.match.status;
        final sameRound = prevD?.match.currentRound == d.match.currentRound;
        if (prevD != null && sameStatus && sameRound) return;

        if (d.match.status == MatchStatus.finalized ||
            d.match.status == MatchStatus.voided) {
          context.go('${MatchRoutes.finished}/${widget.matchId}');
          return;
        }
        if (d.match.status == MatchStatus.awaitingResults &&
            d.match.currentRound != _seenRound) {
          // Round advanced — go back to enter the next round's score.
          context.go('${MatchRoutes.result}/${widget.matchId}');
          return;
        }
        if (d.match.status == MatchStatus.active) {
          // Reconciled but we're back in active play (rare but possible
          // after an organizer override). Land on the result screen —
          // the active intermediate is gone in this flow.
          context.go('${MatchRoutes.result}/${widget.matchId}');
        }
      },
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: 'Match',
        title: 'Warten auf Bestätigung',
        // BH-A-04: routing back to the lobby would just re-redirect us
        // here once the lobby's status-listener fires (status is already
        // `awaiting_results`). Send the user home instead so the back
        // gesture actually leaves the await-others screen.
        leading: BackButton(
          color: tokens.fg,
          onPressed: () => context.go('/'),
        ),
      ),
      body: detailAsync.when(
        loading: () => const _AwaitSkeleton(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              'Fehler: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const _AwaitSkeleton();
          }
          final inApp = detail.participants
              .where((p) => p.kind == MatchParticipantKind.inApp)
              .toList();
          // W5.1-A: stage indicator directly below the AppBar.
          return Column(
            children: [
              MatchStageIndicator(status: detail.match.status),
              Expanded(
                child: _AwaitBody(round: detail.match.currentRound, players: inApp),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AwaitBody extends StatelessWidget {
  const _AwaitBody({required this.round, required this.players});

  final int round;
  final List<MatchParticipant> players;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space6,
      ),
      children: [
        const SizedBox(height: KubbTokens.space4),
        const Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        Text(
          'Warten auf andere Spieler…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: tokens.fg,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          'Sobald alle bestätigt haben, geht es automatisch weiter.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: tokens.fgMuted),
        ),
        const SizedBox(height: KubbTokens.space6),
        _WaitingListCard(round: round, players: players),
        const SizedBox(height: KubbTokens.space5),
        Center(
          child: KubbButton(
            variant: KubbButtonVariant.ghost,
            // BH-A-02 / BH-B-02: the underlying push-notification mutation is
            // not wired yet. Until it lands we surface the status as a
            // SnackBar so the button feels alive instead of looking broken.
            // TODO(sprintB-followup): replace stub with real re-notify mutation.
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Benachrichtigung folgt in einem späteren Update',
                  ),
                ),
              );
            },
            child: const Text('Erneut benachrichtigen'),
          ),
        ),
      ],
    );
  }
}

class _WaitingListCard extends StatelessWidget {
  const _WaitingListCard({required this.round, required this.players});

  final int round;
  final List<MatchParticipant> players;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space3,
        KubbTokens.space3,
        KubbTokens.space3,
        KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg + 2),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spieler in Runde $round',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tokens.fgMuted,
              letterSpacing: 0.88,
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          for (var i = 0; i < players.length; i++) ...[
            if (i > 0) const SizedBox(height: KubbTokens.space2),
            _PlayerWaitRow(participant: players[i]),
          ],
        ],
      ),
    );
  }
}

class _PlayerWaitRow extends StatelessWidget {
  const _PlayerWaitRow({required this.participant});
  final MatchParticipant participant;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final name = participant.nickname ?? '…';
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.fg,
            ),
          ),
        ),
        const KubbChip(tone: KubbChipTone.heli, label: 'wartet'),
      ],
    );
  }
}

class _AwaitSkeleton extends StatelessWidget {
  const _AwaitSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        const SizedBox(height: KubbTokens.space5),
        Center(
          child: KubbSkeleton.bar(width: 180, height: 18),
        ),
        const SizedBox(height: KubbTokens.space2),
        Center(
          child: KubbSkeleton.bar(width: 260),
        ),
        const SizedBox(height: KubbTokens.space6),
        KubbSkeleton.row(columns: 2),
        const SizedBox(height: KubbTokens.space3),
        KubbSkeleton.row(columns: 2),
      ],
    );
  }
}
