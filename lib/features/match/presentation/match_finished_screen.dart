import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';

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

    final formatLabel = detailAsync.value != null
        ? 'Match · bo${detailAsync.value!.match.format.n}'
        : 'Match';

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: formatLabel,
        title: 'Match beendet',
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
    final isVoided = detail.match.status == MatchStatus.voided;
    final winner = detail.derivedWinner;
    final isTie = !isVoided && winner == null;

    final verdict = isVoided
        ? 'Match abgebrochen'
        : (isTie ? 'Unentschieden' : 'Sieger: ${_teamLabel(winner!)}');

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space6,
      ),
      children: [
        _ScoreHeroCard(
          verdict: verdict,
          scoreA: detail.match.finalScoreA,
          scoreB: detail.match.finalScoreB,
          winner: winner,
          isVoided: isVoided,
        ),
        const SizedBox(height: KubbTokens.space6),
        KubbButton(
          variant: KubbButtonVariant.primary,
          size: KubbButtonSize.large,
          onPressed: () => context.go(MatchRoutes.newMatch),
          child: const Text('Neues Match'),
        ),
        const SizedBox(height: KubbTokens.space3),
        KubbButton(
          variant: KubbButtonVariant.ghost,
          onPressed: () => context.go('/'),
          child: const Text('Zurück zur Übersicht'),
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

/// Meadow-500 hero block — Big-Number score plus verdict eyebrow.
/// Mirrors the `Result` hero in `docs/design/ui_kits/app/MatchScreen.jsx`
/// (resultHero / resultBig styles) and the meadow-500 verdict surface in
/// `SummaryScreen.jsx`.
class _ScoreHeroCard extends StatelessWidget {
  const _ScoreHeroCard({
    required this.verdict,
    required this.scoreA,
    required this.scoreB,
    required this.winner,
    required this.isVoided,
  });

  final String verdict;
  final int? scoreA;
  final int? scoreB;
  final String? winner;
  final bool isVoided;

  @override
  Widget build(BuildContext context) {
    final background = isVoided ? KubbTokens.stone700 : KubbTokens.meadow500;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space5,
        KubbTokens.space6,
        KubbTokens.space5,
        KubbTokens.space5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg + 6),
      ),
      child: Column(
        children: [
          Text(
            verdict.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.96,
              color: KubbTokens.chalk50,
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          if (!isVoided)
            _BigScoreRow(scoreA: scoreA, scoreB: scoreB, winner: winner)
          else
            const Icon(
              Icons.close_rounded,
              color: KubbTokens.chalk50,
              size: 72,
            ),
        ],
      ),
    );
  }
}

class _BigScoreRow extends StatelessWidget {
  const _BigScoreRow({
    required this.scoreA,
    required this.scoreB,
    required this.winner,
  });

  final int? scoreA;
  final int? scoreB;
  final String? winner;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        _BigNumber(value: scoreA, highlight: winner == 'A'),
        const SizedBox(width: KubbTokens.space3),
        const Text(
          ':',
          style: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w600,
            color: KubbTokens.chalk50,
            height: 0.85,
          ),
        ),
        const SizedBox(width: KubbTokens.space3),
        _BigNumber(value: scoreB, highlight: winner == 'B'),
      ],
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.value, required this.highlight});

  final int? value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Text(
      value?.toString() ?? '–',
      style: TextStyle(
        fontSize: 80,
        fontWeight: FontWeight.w800,
        height: 0.85,
        letterSpacing: -2.5,
        color: highlight
            ? KubbTokens.chalk50
            : KubbTokens.chalk50.withValues(alpha: 0.55),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
