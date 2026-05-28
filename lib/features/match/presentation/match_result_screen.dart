import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/match/presentation/widgets/match_stage_indicator.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Pure validation for a round-result entry. Returns `null` when the
/// inputs form a valid result, otherwise a German message for inline
/// display. Sätze-only — the winner is derived from the score columns,
/// no separate selector. Ties are rejected.
@visibleForTesting
String? validateMatchResult({required int scoreA, required int scoreB}) {
  if (scoreA < 0 || scoreB < 0) {
    return 'Punkte dürfen nicht negativ sein';
  }
  if (scoreA == 0 && scoreB == 0) {
    return 'Score fehlt';
  }
  if (scoreA == scoreB) {
    return 'Score muss eindeutig sein';
  }
  return null;
}

/// Derives the winning team from the score columns. Returns `null` when
/// the score is not yet decided (equal or both zero).
@visibleForTesting
String? deriveWinner(int scoreA, int scoreB) {
  if (scoreA == scoreB) return null;
  return scoreA > scoreB ? 'A' : 'B';
}

/// Set-by-set entry derived from a `proposal_received` audit event.
/// Used by the Halbsatz-Verlauf inset-card.
@visibleForTesting
class HalfsetEntry {
  const HalfsetEntry({
    required this.round,
    required this.scoreA,
    required this.scoreB,
  });

  final int round;
  final int scoreA;
  final int scoreB;
}

/// Reduces the audit tail down to one accepted set per round. We pick the
/// latest `proposal_received` per round — once both sides agree the
/// values converge anyway, and during disagreement the most recent
/// proposal is what advanced the round.
@visibleForTesting
List<HalfsetEntry> extractHalfsetHistory(List<MatchAuditEvent> auditTail) {
  final byRound = <int, HalfsetEntry>{};
  for (final event in auditTail) {
    if (event.kind != 'proposal_received') continue;
    final round = event.payload['round'];
    final scoreA = event.payload['score_a'];
    final scoreB = event.payload['score_b'];
    if (round is! num || scoreA is! num || scoreB is! num) continue;
    byRound[round.toInt()] = HalfsetEntry(
      round: round.toInt(),
      scoreA: scoreA.toInt(),
      scoreB: scoreB.toInt(),
    );
  }
  final entries = byRound.values.toList()
    ..sort((a, b) => a.round.compareTo(b.round));
  return entries;
}

/// Round-result entry. Uses [matchDetailProvider] for the round
/// indicator and pre-fills the score inputs from `ownProposal` when
/// the user is editing a previously-submitted result.
///
/// Submit flow:
///   - On a successful round bump (status `awaitingResults` and the
///     round number advanced) we stay on this screen but reset the
///     inputs for the new round.
///   - On `finalized` / `voided` the user is sent back to the lobby.
///   - Otherwise (own proposal recorded, others still pending) we
///     route to the await-others screen.
class MatchResultScreen extends ConsumerStatefulWidget {
  const MatchResultScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<MatchResultScreen> createState() => _MatchResultScreenState();
}

class _MatchResultScreenState extends ConsumerState<MatchResultScreen> {
  int _scoreA = 0;
  int _scoreB = 0;
  int? _prefilledForRound;
  bool _submitting = false;
  bool _ensuringAwaitingResults = false;

  /// Promotes the match from `active` to `awaiting_results` so the
  /// propose-result RPC accepts the first submission. The server-side
  /// `match_finish_play` is the gatekeeper. Called once per visit, on
  /// the first build where the status is still `active`.
  Future<void> _ensureAwaitingResults(MatchDetail detail) async {
    if (_ensuringAwaitingResults) return;
    if (detail.match.status != MatchStatus.active) return;
    _ensuringAwaitingResults = true;
    try {
      await ref.read(matchActionsProvider).finishPlay(widget.matchId);
    } on Object {
      // Either the match was already awaiting_results (race with the
      // other side) or the server rejected — both surface naturally
      // on the next poll. Silently swallow so the UI does not crash.
    }
  }

  void _prefillFromDetail(MatchDetail? detail) {
    if (detail == null) return;
    if (_prefilledForRound == detail.match.currentRound) return;
    final proposal = detail.ownProposal;
    if (proposal != null && proposal.round == detail.match.currentRound) {
      _scoreA = proposal.scoreA;
      _scoreB = proposal.scoreB;
    } else {
      _scoreA = 0;
      _scoreB = 0;
    }
    _prefilledForRound = detail.match.currentRound;
  }

  /// Hard cap for the per-team counter — a team cannot win more sets
  /// than `ceil(n/2)`.
  int _scoreCapFor(MatchDetail detail) => detail.match.format.setsToWin;

  String? _validate() =>
      validateMatchResult(scoreA: _scoreA, scoreB: _scoreB);

  Future<void> _submit(MatchDetail detail) async {
    if (_submitting) return;
    if (_validate() != null) return;
    setState(() => _submitting = true);
    try {
      final response = await ref.read(matchActionsProvider).proposeResult(
            widget.matchId,
            winnerTeamId: deriveWinner(_scoreA, _scoreB),
            scoreA: _scoreA,
            scoreB: _scoreB,
          );
      if (!mounted) return;

      if (response.status == MatchStatus.finalized ||
          response.status == MatchStatus.voided) {
        context.go('${MatchRoutes.finished}/${widget.matchId}');
        return;
      }
      if (response.status == MatchStatus.awaitingResults &&
          response.round > detail.match.currentRound) {
        // Round advanced — reset inputs and stay.
        setState(() {
          _scoreA = 0;
          _scoreB = 0;
          _prefilledForRound = response.round;
        });
        return;
      }
      // Own proposal recorded; waiting for the rest.
      context.go('${MatchRoutes.awaitOthers}/${widget.matchId}');
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Senden fehlgeschlagen: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    ref.watch(matchPollingProvider(widget.matchId));
    final detailAsync = ref.watch(matchDetailProvider(widget.matchId));

    return Scaffold(
      backgroundColor: tokens.bg,
      // BH-A-03: result screen is entered via `context.go`, so the nav
      // stack has nothing to pop back to and `automaticallyImplyLeading`
      // renders no back affordance. Supply an explicit leading that
      // routes home so the user is never trapped on this screen.
      appBar: KubbAppBar(
        eyebrow: 'Resultat',
        title: 'Halbsatz eintragen',
        leading: BackButton(
          color: tokens.fg,
          onPressed: () => context.go('/'),
        ),
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
          // Fire-and-forget — promotes active → awaiting_results so the
          // propose-result RPC will accept the first submission.
          unawaited(_ensureAwaitingResults(detail));
          _prefillFromDetail(detail);
          final validationMsg = _validate();
          final cap = _scoreCapFor(detail);
          final history = extractHalfsetHistory(detail.auditTail);

          final formatLabel = detail.match.format.n == 1
              ? 'Einzelsatz'
              : 'BO${detail.match.format.n} · bis ${detail.match.format.setsToWin} Siege';

          return Column(
            children: [
              // W5.1-A: stage indicator directly below the AppBar.
              MatchStageIndicator(status: detail.match.status),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    KubbTokens.space4,
                    KubbTokens.space4,
                    KubbTokens.space4,
                    KubbTokens.space6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // BH-C-05: dark score strip header at the very top.
                      _ResultScoreStrip(
                        detail: detail,
                        scoreA: _scoreA,
                        scoreB: _scoreB,
                      ),
                      const SizedBox(height: KubbTokens.space4),
                      _SectionHeader(
                        label: 'Aktueller Halbsatz · $formatLabel',
                      ),
                const SizedBox(height: KubbTokens.space2),
                _InsetCard(
                  tokens: tokens,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ScoreColumn(
                          title: 'Team A',
                          accent: KubbTokens.meadow600,
                          value: _scoreA,
                          onIncrement: _scoreA >= cap
                              ? null
                              : () => setState(() => _scoreA += 1),
                          onDecrement: _scoreA == 0
                              ? null
                              : () => setState(() => _scoreA -= 1),
                        ),
                      ),
                      const SizedBox(width: KubbTokens.space3),
                      Expanded(
                        child: _ScoreColumn(
                          title: 'Team B',
                          accent: KubbTokens.wood400,
                          value: _scoreB,
                          onIncrement: _scoreB >= cap
                              ? null
                              : () => setState(() => _scoreB += 1),
                          onDecrement: _scoreB == 0
                              ? null
                              : () => setState(() => _scoreB -= 1),
                        ),
                      ),
                    ],
                  ),
                ),
                if (validationMsg != null) ...[
                  const SizedBox(height: KubbTokens.space3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: KubbChip(
                      tone: KubbChipTone.miss,
                      label: validationMsg,
                      icon: LucideIcons.alertTriangle,
                    ),
                  ),
                ],
                const SizedBox(height: KubbTokens.space5),

                // Halbsatz-Verlauf — Set-by-Set list as inset-card with
                // section header. Empty placeholder while the first
                // round is still being entered.
                const _SectionHeader(
                  label: 'Halbsatz-Verlauf',
                ),
                const SizedBox(height: KubbTokens.space2),
                _HalfsetHistoryCard(
                  history: history,
                  currentRound: detail.match.currentRound,
                ),
                const SizedBox(height: KubbTokens.space5),

                // Liga-Impact-Block — sub-card hinting at the table
                // impact this match will have once finalised. Sprint B
                // polish placeholder; real ELO/Tabellen-Delta follows
                // when the league module wires up.
                const _SectionHeader(
                  label: 'Liga-Hinweis',
                ),
                const SizedBox(height: KubbTokens.space2),
                const _LeagueImpactCard(),
                const SizedBox(height: KubbTokens.space6),

                KubbButton(
                  variant: KubbButtonVariant.primary,
                  size: KubbButtonSize.large,
                  onPressed: _submitting || validationMsg != null
                      ? null
                      : () => _submit(detail),
                  isLoading: _submitting,
                  child: const Text('Bekannt geben'),
                ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(left: KubbTokens.space1),
      child: Text(
        label.toUpperCase(),
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

/// Mobile-kit "Inset-Card" surface — `bgRaised` with a 1px line and the
/// standard 14px radius. See `docs/design/quality-gates/mobile-kit-overview.md`.
class _InsetCard extends StatelessWidget {
  const _InsetCard({
    required this.tokens,
    required this.child,
    this.padding = const EdgeInsets.all(KubbTokens.space3),
  });

  final KubbTokens tokens;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      padding: padding,
      child: child,
    );
  }
}

class _HalfsetHistoryCard extends StatelessWidget {
  const _HalfsetHistoryCard({
    required this.history,
    required this.currentRound,
  });

  final List<HalfsetEntry> history;
  final int currentRound;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    if (history.isEmpty) {
      return _InsetCard(
        tokens: tokens,
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space4,
          vertical: KubbTokens.space4,
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.history,
              size: 16,
              color: tokens.fgMuted,
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: Text(
                'Noch kein Halbsatz erfasst — Runde $currentRound läuft.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: tokens.fgMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _InsetCard(
      tokens: tokens,
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      child: Column(
        children: [
          for (var i = 0; i < history.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.line,
              ),
            _HalfsetRow(entry: history[i]),
          ],
        ],
      ),
    );
  }
}

class _HalfsetRow extends StatelessWidget {
  const _HalfsetRow({required this.entry});

  final HalfsetEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final winner = deriveWinner(entry.scoreA, entry.scoreB);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              'HS ${entry.round}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: tokens.fgMuted,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                _HalfsetScore(
                  score: entry.scoreA,
                  isWinner: winner == 'A',
                  accent: KubbTokens.meadow600,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KubbTokens.space2,
                  ),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tokens.fgMuted,
                    ),
                  ),
                ),
                _HalfsetScore(
                  score: entry.scoreB,
                  isWinner: winner == 'B',
                  accent: KubbTokens.wood400,
                ),
              ],
            ),
          ),
          KubbChip(
            tone: winner == null ? KubbChipTone.neutral : KubbChipTone.hit,
            label: winner == null ? '—' : 'Team $winner',
          ),
        ],
      ),
    );
  }
}

class _HalfsetScore extends StatelessWidget {
  const _HalfsetScore({
    required this.score,
    required this.isWinner,
    required this.accent,
  });

  final int score;
  final bool isWinner;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Text(
      '$score',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: isWinner ? accent : tokens.fgMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _LeagueImpactCard extends StatelessWidget {
  const _LeagueImpactCard();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return _InsetCard(
      tokens: tokens,
      padding: const EdgeInsets.all(KubbTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KubbChip(
                tone: KubbChipTone.info,
                label: 'Tabellen-Auswirkung',
                icon: LucideIcons.trendingUp,
              ),
              const SizedBox(width: KubbTokens.space2),
              const KubbChip(
                tone: KubbChipTone.info,
                label: 'Vorschau · Demo',
              ),
              const Spacer(),
              Icon(
                LucideIcons.trophy,
                size: 18,
                color: tokens.fgMuted,
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space3),
          Text(
            'Sobald beide Seiten den Halbsatz bestätigen, fliesst das '
            'Ergebnis in deine Saison-Tabelle und das Head-to-Head ein.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: tokens.fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({
    required this.title,
    required this.accent,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String title;
  final Color accent;
  final int value;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: tokens.bgRaised,
              borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
              border: Border.all(color: accent, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          Row(
            children: [
              Expanded(
                child: _StepBtn(
                  icon: LucideIcons.minus,
                  onPressed: onDecrement,
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
              Expanded(
                child: _StepBtn(
                  icon: LucideIcons.plus,
                  onPressed: onIncrement,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      height: 48,
      child: Material(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              border: Border.all(color: tokens.line, width: 1.5),
            ),
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null ? tokens.fgSubtle : tokens.fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// Stone-900 hero strip above the current-set editor. Shows the overall
/// set-wins per team (derived from accepted half-set history) plus a
/// live indicator. Real-time wiring follows in M4.
class _ResultScoreStrip extends StatelessWidget {
  const _ResultScoreStrip({
    required this.detail,
    required this.scoreA,
    required this.scoreB,
  });

  final MatchDetail detail;
  final int scoreA;
  final int scoreB;

  @override
  Widget build(BuildContext context) {
    var winsA = 0;
    var winsB = 0;
    for (final h in extractHalfsetHistory(detail.auditTail)) {
      final w = deriveWinner(h.scoreA, h.scoreB);
      if (w == 'A') winsA += 1;
      if (w == 'B') winsB += 1;
    }
    final teams = {for (final t in detail.teams) t.teamId: t};
    final nameA = teams['A']?.displayName ?? 'Team A';
    final nameB = teams['B']?.displayName ?? 'Team B';
    const muted = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.88,
      color: KubbTokens.chalk50,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(KubbTokens.space4, KubbTokens.space4,
          KubbTokens.space4, KubbTokens.space3),
      decoration: BoxDecoration(
        color: KubbTokens.stone900,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(child: _StripTeam(name: nameA, leading: true)),
          Text('$winsA:$winsB',
              style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: KubbTokens.chalk50,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()])),
          Expanded(child: _StripTeam(name: nameB, leading: false)),
        ]),
        const SizedBox(height: KubbTokens.space2),
        Row(children: [
          Expanded(
              child: Text(
                  'Halbsatz ${detail.match.currentRound} / ${detail.match.format.n}',
                  style: muted)),
          const Text('● LIVE läuft…',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.88,
                  color: KubbTokens.miss)),
        ]),
      ]),
    );
  }
}

class _StripTeam extends StatelessWidget {
  const _StripTeam({required this.name, required this.leading});
  final String name;
  final bool leading;
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final avatar = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
          color: KubbTokens.stone700, shape: BoxShape.circle),
      child: Text(initial,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: KubbTokens.chalk50)),
    );
    final label = Flexible(
      child: Text(name,
          textAlign: leading ? TextAlign.left : TextAlign.right,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KubbTokens.chalk50)),
    );
    return Row(
      mainAxisAlignment:
          leading ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: leading
          ? [avatar, const SizedBox(width: 8), label]
          : [label, const SizedBox(width: 8), avatar],
    );
  }
}
