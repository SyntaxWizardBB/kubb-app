import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Inline configuration block for the Swiss-System format option in the
/// setup wizard (TASK-M5.3-T10). Lets the organizer pick the number of
/// rounds (default `ceil(log2(n))`, OD-M5-04), surfaces the read-only
/// tiebreak order (Buchholz → Direct-Encounter → Random) and warns when
/// the participant cap exceeds the system's sweet spot of 64 (R-M5-G2).
class SwissConfigSection extends StatelessWidget {
  const SwissConfigSection({
    required this.participantCount,
    required this.rounds,
    required this.onRoundsChanged,
    super.key,
  });

  /// Anchor for default/clamp calculations. Wizard hands in
  /// `draft.maxParticipants`.
  final int participantCount;
  final int rounds;
  final ValueChanged<int> onRoundsChanged;

  static const int roundsMin = 3;
  static const int roundsMax = 9;
  static const int participantSweetSpot = 64;

  /// `ceil(log2(n))`, clamped to [roundsMin, roundsMax]. Falls back to
  /// [roundsMin] for tiny rosters where the formula yields ≤ 2.
  static int defaultRounds(int participantCount) {
    if (participantCount < 2) return roundsMin;
    final raw = (math.log(participantCount) / math.ln2).ceil();
    return raw.clamp(roundsMin, roundsMax);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final overCap = participantCount > participantSweetSpot;
    return Container(
      margin: const EdgeInsets.only(top: KubbTokens.space3),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (overCap) ...[
            Container(
              padding: const EdgeInsets.all(KubbTokens.space2),
              decoration: BoxDecoration(
                color: KubbTokens.miss.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
                border: Border.all(color: KubbTokens.miss),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: KubbTokens.miss),
                  const SizedBox(width: KubbTokens.space2),
                  Expanded(
                    child: Text(
                      'Schweizer System ist optimiert für ≤ '
                      '$participantSweetSpot Teilnehmer.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'Runden',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: tokens.fgMuted,
                  ),
                ),
              ),
              Text(
                '$rounds',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                ),
              ),
            ],
          ),
          Slider(
            value: rounds.toDouble(),
            min: roundsMin.toDouble(),
            max: roundsMax.toDouble(),
            divisions: roundsMax - roundsMin,
            label: '$rounds',
            activeColor: tokens.primary,
            onChanged: (v) => onRoundsChanged(v.round()),
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(
            'Tiebreak: Buchholz → Direct-Encounter → Random',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.fgMuted,
            ),
          ),
        ],
      ),
    );
  }
}
