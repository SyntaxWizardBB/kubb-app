import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Terminal screen for `finalized` or `voided` matches. Replaces the
/// previous redirect into the lobby (which had no branch for either
/// status, leaving the user stuck on the pre-game team panels).
class MatchFinishedScreen extends ConsumerWidget {
  const MatchFinishedScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    ref.watch(matchPollingProvider(matchId));
    final detailAsync = ref.watch(matchDetailProvider(matchId));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => context.go('/')),
        title: const Text('Match beendet'),
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
          return _FinishedBody(detail: detail);
        },
      ),
    );
  }
}

class _FinishedBody extends StatelessWidget {
  const _FinishedBody({required this.detail});

  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final isVoided = detail.match.status == MatchStatus.voided;
    final winner = detail.derivedWinner;
    final isTie = !isVoided && winner == null;

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        const SizedBox(height: KubbTokens.space4),
        Icon(
          isVoided ? LucideIcons.x : LucideIcons.trophy,
          size: 56,
          color: isVoided ? KubbTokens.miss : KubbTokens.king,
        ),
        const SizedBox(height: KubbTokens.space3),
        Text(
          isVoided
              ? 'Match abgebrochen'
              : (isTie ? 'Unentschieden' : 'Sieger: ${_teamLabel(winner!)}'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: tokens.fg,
          ),
        ),
        if (!isVoided) ...[
          const SizedBox(height: KubbTokens.space5),
          _FinalScoreCard(detail: detail),
        ],
        const SizedBox(height: KubbTokens.space8),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: FilledButton(
            onPressed: () => context.go(MatchRoutes.newMatch),
            child: const Text('Neues Match'),
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: OutlinedButton(
            onPressed: () => context.go('/'),
            child: const Text('Zurück zur Übersicht'),
          ),
        ),
      ],
    );
  }

  String _teamLabel(String teamId) {
    final team = detail.teams.firstWhere(
      (t) => t.teamId == teamId,
      orElse: () => MatchTeam(teamId: teamId, displayName: null),
    );
    return team.displayName ?? 'Team $teamId';
  }
}

class _FinalScoreCard extends StatelessWidget {
  const _FinalScoreCard({required this.detail});

  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final scoreA = detail.match.finalScoreA;
    final scoreB = detail.match.finalScoreB;
    final winner = detail.derivedWinner;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TeamScore(
              label: 'Team A',
              accent: KubbTokens.meadow600,
              score: scoreA,
              highlight: winner == 'A',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space3,
            ),
            child: Text(
              ':',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: tokens.fgMuted,
              ),
            ),
          ),
          Expanded(
            child: _TeamScore(
              label: 'Team B',
              accent: KubbTokens.wood400,
              score: scoreB,
              highlight: winner == 'B',
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamScore extends StatelessWidget {
  const _TeamScore({
    required this.label,
    required this.accent,
    required this.score,
    required this.highlight,
  });

  final String label;
  final Color accent;
  final int? score;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accent,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          score?.toString() ?? '–',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: highlight ? tokens.fg : tokens.fgMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
