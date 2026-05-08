import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:lucide_icons/lucide_icons.dart';

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

    ref.listen<AsyncValue<MatchDetail?>>(
      matchDetailProvider(widget.matchId),
      (_, next) {
        final d = next.value;
        if (d == null) return;
        // Capture the round we landed on so we can detect a bump.
        _seenRound ??= d.match.currentRound;

        if (d.match.status == MatchStatus.finalized ||
            d.match.status == MatchStatus.voided) {
          context.go('${MatchRoutes.lobby}/${widget.matchId}');
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
          // after an organizer override). Send back to active.
          context.go('${MatchRoutes.active}/${widget.matchId}');
        }
      },
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(
          onPressed: () =>
              context.go('${MatchRoutes.lobby}/${widget.matchId}'),
        ),
        title: const Text('Warten auf Bestätigung'),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
            return const Center(child: CircularProgressIndicator());
          }
          final inApp = detail.participants
              .where((p) => p.kind == MatchParticipantKind.inApp)
              .toList();
          return Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: KubbTokens.space5),
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
                Container(
                  padding: const EdgeInsets.all(KubbTokens.space3),
                  decoration: BoxDecoration(
                    color: tokens.bgSunken,
                    borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spieler in Runde ${detail.match.currentRound}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tokens.fgMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: KubbTokens.space2),
                      for (final p in inApp) ...[
                        _PlayerWaitRow(participant: p),
                        const SizedBox(height: KubbTokens.space2),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
        const Icon(LucideIcons.clock, size: 16, color: KubbTokens.wood400),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.fg,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space2,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF2D6),
            borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          ),
          child: const Text(
            'wartet',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3D2C00),
            ),
          ),
        ),
      ],
    );
  }
}
