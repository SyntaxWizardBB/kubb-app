import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
  String? _winner; // 'A', 'B' or null=tie (only valid for points scoring)
  int? _prefilledForRound;
  bool _submitting = false;

  void _prefillFromDetail(MatchDetail? detail) {
    if (detail == null) return;
    if (_prefilledForRound == detail.match.currentRound) return;
    final proposal = detail.ownProposal;
    if (proposal != null && proposal.round == detail.match.currentRound) {
      _scoreA = proposal.scoreA;
      _scoreB = proposal.scoreB;
      _winner = proposal.winnerTeamId;
    } else {
      _scoreA = 0;
      _scoreB = 0;
      _winner = null;
    }
    _prefilledForRound = detail.match.currentRound;
  }

  int _maxRoundsFor(MatchFormat format) => format.n;

  Future<void> _submit(MatchDetail detail) async {
    if (_submitting) return;
    if (detail.match.scoring == MatchScoring.wins && _winner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Sieger auswählen.'),
          backgroundColor: KubbTokens.miss,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final response = await ref.read(matchActionsProvider).proposeResult(
            widget.matchId,
            winnerTeamId: _winner,
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
          _winner = null;
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
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(
          onPressed: () => context.go('${MatchRoutes.lobby}/${widget.matchId}'),
        ),
        title: const Text('Resultat'),
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
          _prefillFromDetail(detail);
          final maxRounds = _maxRoundsFor(detail.match.format);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Runde ${detail.match.currentRound} / $maxRounds',
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
                        onIncrement: () => setState(() => _scoreA += 1),
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
                        onIncrement: () => setState(() => _scoreB += 1),
                        onDecrement: _scoreB == 0
                            ? null
                            : () => setState(() => _scoreB -= 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KubbTokens.space5),
                Text(
                  'Sieger',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.88,
                    color: tokens.fgMuted,
                  ),
                ),
                const SizedBox(height: KubbTokens.space2),
                _WinnerSegmented(
                  selected: _winner,
                  allowTie: detail.match.scoring == MatchScoring.points,
                  onSelected: (v) => setState(() => _winner = v),
                ),
                const SizedBox(height: KubbTokens.space8),
                SizedBox(
                  height: KubbTokens.touchComfortable,
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _submit(detail),
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
  final VoidCallback onIncrement;
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

class _WinnerSegmented extends StatelessWidget {
  const _WinnerSegmented({
    required this.selected,
    required this.allowTie,
    required this.onSelected,
  });

  final String? selected;
  final bool allowTie;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <(String?, String)>[
      ('A', 'Team A'),
      ('B', 'Team B'),
      if (allowTie) (null, 'Unentschieden'),
    ];
    return Wrap(
      spacing: KubbTokens.space2,
      runSpacing: KubbTokens.space2,
      children: options
          .map((opt) => _SegmentBtn(
                label: opt.$2,
                selected: selected == opt.$1,
                onTap: () => onSelected(opt.$1),
              ))
          .toList(),
    );
  }
}

class _SegmentBtn extends StatelessWidget {
  const _SegmentBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Material(
      color: selected ? tokens.primary : tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space4,
            vertical: KubbTokens.space2,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? tokens.primary : tokens.line,
            ),
            borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? tokens.onPrimary : tokens.fg,
            ),
          ),
        ),
      ),
    );
  }
}
