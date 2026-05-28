import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
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
      appBar: KubbAppBar(
        title: 'Resultat',
        leading: BackButton(
          onPressed: () => context.go('${MatchRoutes.lobby}/${widget.matchId}'),
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
          return SingleChildScrollView(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  detail.match.format.n == 1
                      ? 'Resultat'
                      : 'BO${detail.match.format.n} — bis ${detail.match.format.setsToWin} Siege',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: KubbTokens.space5),
                Row(
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
                const SizedBox(height: KubbTokens.space8),
                if (validationMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: KubbTokens.space3),
                    child: Text(
                      validationMsg,
                      style: const TextStyle(
                        fontSize: 12,
                        color: KubbTokens.miss,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                SizedBox(
                  height: KubbTokens.touchComfortable,
                  child: FilledButton(
                    onPressed: _submitting || validationMsg != null
                        ? null
                        : () => _submit(detail),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Resultat einreichen'),
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
