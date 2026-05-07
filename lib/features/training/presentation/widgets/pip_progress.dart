import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';

/// Tone of a single stick pip in the progress row.
enum PipTone { pending, active, done, heli, penalty, king, miss, empty }

/// Horizontal row of six pips that visualise the stick history.
class PipProgress extends StatelessWidget {
  const PipProgress({
    required this.sticks,
    required this.currentIndex,
    super.key,
  });

  final List<StickResult> sticks;
  final int currentIndex;

  PipTone _toneFor(int i) {
    if (i > currentIndex) return PipTone.pending;
    if (i == currentIndex) return PipTone.active;
    final s = sticks[i];
    if (s.heli) return PipTone.heli;
    if (s.penalty1 + s.penalty2 > 0) return PipTone.penalty;
    if (s.king?.hit ?? false) return PipTone.king;
    if (s.fieldHits > 0 || s.eightMHit) return PipTone.done;
    // Past committed stick with zero useful contact = an actual miss
    // (player threw, hit nothing). Distinct from PipTone.empty so the
    // row reads like the Sniper miss/hit tally — see also the "every
    // persisted stick counts" rule in summary/recent.
    return PipTone.miss;
  }

  Color _bgFor(PipTone t, KubbTokens tokens) {
    switch (t) {
      case PipTone.active:
        return KubbTokens.stone900;
      case PipTone.done:
        return tokens.primary;
      case PipTone.heli:
        return KubbTokens.wood300;
      case PipTone.penalty:
        return tokens.danger;
      case PipTone.king:
        return KubbTokens.wood400;
      case PipTone.miss:
        return KubbTokens.miss;
      case PipTone.pending:
      case PipTone.empty:
        return tokens.line;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
      children: List<Widget>.generate(sticks.length, (i) {
        final tone = _toneFor(i);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: i == sticks.length - 1 ? 0 : KubbTokens.space2,
            ),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: _bgFor(tone, tokens),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      }),
    );
  }
}
