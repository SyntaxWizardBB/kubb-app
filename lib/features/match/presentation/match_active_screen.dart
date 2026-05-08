import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// "Match läuft" full-screen — shown while the live game is being
/// played out at the table. The only interactive control is the
/// "Match beendet" CTA which moves the match into the result-entry
/// flow via [MatchActions.finishPlay].
class MatchActiveScreen extends ConsumerStatefulWidget {
  const MatchActiveScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<MatchActiveScreen> createState() => _MatchActiveScreenState();
}

class _MatchActiveScreenState extends ConsumerState<MatchActiveScreen> {
  bool _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await ref.read(matchActionsProvider).finishPlay(widget.matchId);
      if (!mounted) return;
      context.go('${MatchRoutes.result}/${widget.matchId}');
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Konnte nicht abschliessen: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    ref.watch(matchPollingProvider(widget.matchId));
    final detailAsync = ref.watch(matchDetailProvider(widget.matchId));

    // Status-driven redirects so the active screen never lingers on a
    // match that has moved on (e.g. someone else triggered finishPlay).
    ref.listen<AsyncValue<MatchDetail?>>(
      matchDetailProvider(widget.matchId),
      (_, next) {
        final d = next.value;
        if (d == null) return;
        if (d.match.status == MatchStatus.awaitingResults) {
          context.go('${MatchRoutes.result}/${widget.matchId}');
        } else if (d.match.status == MatchStatus.finalized ||
            d.match.status == MatchStatus.voided) {
          context.go('${MatchRoutes.lobby}/${widget.matchId}');
        }
      },
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => context.go('/')),
        title: const Text('Match läuft'),
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
          final teamA =
              detail.participants.where((p) => p.teamId == 'A').toList();
          final teamB =
              detail.participants.where((p) => p.teamId == 'B').toList();
          return Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: KubbTokens.space5),
                Text(
                  'Match läuft',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.96,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: KubbTokens.space2),
                Text(
                  'Runde ${detail.match.currentRound}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: tokens.fgMuted),
                ),
                const SizedBox(height: KubbTokens.space6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _RosterCard(
                        title: 'Team A',
                        accent: KubbTokens.meadow600,
                        names: teamA.map(_displayName).toList(),
                      ),
                    ),
                    const SizedBox(width: KubbTokens.space3),
                    Expanded(
                      child: _RosterCard(
                        title: 'Team B',
                        accent: KubbTokens.wood400,
                        names: teamB.map(_displayName).toList(),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: KubbTokens.touchComfortable,
                  child: FilledButton.icon(
                    onPressed: _finishing ? null : _finish,
                    icon: const Icon(LucideIcons.flag, size: 18),
                    label: _finishing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Match beendet'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _displayName(MatchParticipant p) => p.nickname ?? '…';
}

class _RosterCard extends StatelessWidget {
  const _RosterCard({
    required this.title,
    required this.accent,
    required this.names,
  });

  final String title;
  final Color accent;
  final List<String> names;

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
          for (final n in names)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                n,
                style: TextStyle(fontSize: 13, color: tokens.fg),
              ),
            ),
        ],
      ),
    );
  }
}
