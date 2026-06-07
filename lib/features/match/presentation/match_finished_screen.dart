import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/match/presentation/widgets/match_stage_indicator.dart';

/// Terminal screen for `finalized` or `voided` matches. Replaces the
/// previous redirect into the lobby (which had no branch for either
/// status, leaving the user stuck on the pre-game team panels).
class MatchFinishedScreen extends ConsumerWidget {
  const MatchFinishedScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    ref.watch(matchCdcProvider(matchId));
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
          // W5.1-A: stage indicator directly below the AppBar.
          return Column(
            children: [
              MatchStageIndicator(status: detail.match.status),
              Expanded(child: _FinishedBody(detail: detail)),
            ],
          );
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
        if (!isVoided) ...[
          const SizedBox(height: KubbTokens.space5),
          const _SectionLabel('Halbsatz-Verlauf'),
          const SizedBox(height: KubbTokens.space2),
          const _SetRow(sets: _mockSets),
          const SizedBox(height: KubbTokens.space5),
          const _SectionLabel('Statistik · du vs. Gegner'),
          const SizedBox(height: KubbTokens.space2),
          const _StatsList(rows: _mockStats),
          const SizedBox(height: KubbTokens.space5),
          _PrimaryActionRow(
            onRematch: () => _showSoonSnack(context, 'Revanche kommt bald'),
            onShare: () => _showSoonSnack(context, 'Teilen kommt bald'),
          ),
        ],
        const SizedBox(height: KubbTokens.space5),
        KubbButton(
          variant: KubbButtonVariant.primary,
          size: KubbButtonSize.large,
          onPressed: () => context.go(MatchRoutes.newMatch),
          child: const Text('Neues Match'),
        ),
        const SizedBox(height: KubbTokens.space3),
        KubbButton(
          variant: KubbButtonVariant.ghost,
          onPressed: () => context.go('/training'),
          child: const Text('Zurück zur Übersicht'),
        ),
      ],
    );
  }

  void _showSoonSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    // BH-C-04: Voided-Hero uses stone400 (lighter, semantically correct
    // neutral) instead of the near-black stone700 — see W5.1 hotfix notes
    // and `match-live-screen-spec.md` Z.221 (stone-400 for voided/tie).
    final background = isVoided ? KubbTokens.stone400 : KubbTokens.meadow500;
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
          if (!isVoided) ...[
            _BigScoreRow(scoreA: scoreA, scoreB: scoreB, winner: winner),
            const SizedBox(height: KubbTokens.space3),
            // Meta-Zeile per MatchScreen.jsx Z.234. Backend liefert Dauer/
            // Wurf-Count/ELO-Delta noch nicht (siehe W5.1-Hotfix-Brief),
            // daher Mock-Werte bis das Domain-Feld nachgereicht wird.
            const Text(
              '9:42 min · 28 Würfe · ELO +18',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: KubbTokens.chalk50,
              ),
            ),
          ] else
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
    return Semantics(
      container: true,
      label: 'Endstand ${scoreA ?? '–'} zu ${scoreB ?? '–'}',
      child: Row(
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
      ),
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.value, required this.highlight});

  final int? value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Punkte ${value ?? '–'}',
      child: Text(
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
      ),
    );
  }
}

/// Uppercased section eyebrow used between hero, half-set row and stats
/// list — mirrors the `m.section` style in `MatchScreen.jsx` (Z.237/253).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space1),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: KubbTokens.stone500,
        ),
      ),
    );
  }
}

/// Single half-set entry — mock model until backend exposes per-round
/// scores. `won` drives the win/loss colouring on [_SetRow] cards.
class _SetResult {
  const _SetResult({required this.n, required this.h, required this.a, required this.won});
  final int n;
  final int h;
  final int a;
  final bool won;
}

const List<_SetResult> _mockSets = [
  _SetResult(n: 1, h: 6, a: 4, won: true),
  _SetResult(n: 2, h: 5, a: 6, won: false),
  _SetResult(n: 3, h: 6, a: 3, won: true),
  _SetResult(n: 4, h: 4, a: 6, won: false),
  _SetResult(n: 5, h: 6, a: 5, won: true),
];

/// Horizontal 5-card row — one card per half-set with win/loss colouring.
/// Mirrors `m.setRow` / `m.setCard{W,L}` in `MatchScreen.jsx` Z.238-251.
class _SetRow extends StatelessWidget {
  const _SetRow({required this.sets});

  final List<_SetResult> sets;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < sets.length; i++) ...[
          if (i > 0) const SizedBox(width: KubbTokens.space2),
          Expanded(child: _SetCard(set: sets[i])),
        ],
      ],
    );
  }
}

class _SetCard extends StatelessWidget {
  const _SetCard({required this.set});

  final _SetResult set;

  @override
  Widget build(BuildContext context) {
    final bg = set.won ? KubbTokens.meadow100 : KubbTokens.stone100;
    final fg = set.won ? KubbTokens.meadow800 : KubbTokens.stone500;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            'HS ${set.n}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${set.h}:${set.a}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single statistic row — label left, home (du) middle-right, away
/// (Gegner) right. `homeBetter` highlights the home value in meadow700
/// with weight 800, per `MatchScreen.jsx` Z.269-278.
class _StatRowData {
  const _StatRowData({
    required this.label,
    required this.home,
    required this.away,
    required this.homeBetter,
  });
  final String label;
  final String home;
  final String away;
  final bool homeBetter;
}

const List<_StatRowData> _mockStats = [
  _StatRowData(label: 'Treffer', home: '18 / 28', away: '14 / 27', homeBetter: true),
  _StatRowData(label: 'Trefferrate', home: '64 %', away: '52 %', homeBetter: true),
  _StatRowData(label: 'Heli erfolg', home: '4 / 5', away: '2 / 3', homeBetter: true),
  _StatRowData(label: 'Strafkubbs', home: '0', away: '2', homeBetter: true),
  _StatRowData(label: 'Längste Streak', home: '5', away: '3', homeBetter: true),
];

/// Inset card listing the home-vs-away comparison rows. Surface uses the
/// theme `bgRaised` token so it lifts against the warm-paper background.
class _StatsList extends StatelessWidget {
  const _StatsList({required this.rows});

  final List<_StatRowData> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space4,
        vertical: KubbTokens.space3,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: KubbTokens.space3, color: tokens.line, thickness: 1),
            _StatRow(data: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.data});

  final _StatRowData data;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final homeStyle = TextStyle(
      fontSize: 13,
      fontWeight: data.homeBetter ? FontWeight.w800 : FontWeight.w700,
      color: data.homeBetter ? KubbTokens.meadow700 : tokens.fg,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final awayStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: tokens.fgMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              data.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.fgMuted,
              ),
            ),
          ),
          Text(data.home, style: homeStyle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
            child: Text(
              '·',
              style: TextStyle(color: tokens.fgSubtle, fontWeight: FontWeight.w700),
            ),
          ),
          Text(data.away, style: awayStyle),
        ],
      ),
    );
  }
}

/// Primary action row directly under the stats list — Revanche (Ghost)
/// and Match teilen (Primary), per `MatchScreen.jsx` Z.261-264. Both
/// actions surface a "kommt bald" SnackBar; the real wiring (duplicate
/// match config, share intent) is tracked separately.
class _PrimaryActionRow extends StatelessWidget {
  const _PrimaryActionRow({required this.onRematch, required this.onShare});

  final VoidCallback onRematch;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: KubbButton(
            variant: KubbButtonVariant.ghost,
            onPressed: onRematch,
            child: const Text('Revanche'),
          ),
        ),
        const SizedBox(width: KubbTokens.space3),
        Expanded(
          child: KubbButton(
            variant: KubbButtonVariant.primary,
            onPressed: onShare,
            child: const Text('Match teilen'),
          ),
        ),
      ],
    );
  }
}
