import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Inline hint under a name field that surfaces a live uniqueness check
/// (BUG-2). Renders nothing when [isTaken] and [isChecking] are both false,
/// a muted "checking…" line while [isChecking], and a red "name taken" line
/// when [isTaken]. Kept presentation-only so profile / team / club screens
/// can share it regardless of their own availability enum.
class NameAvailabilityHint extends StatelessWidget {
  const NameAvailabilityHint({
    required this.isTaken,
    required this.isChecking,
    required this.takenLabel,
    required this.checkingLabel,
    super.key,
  });

  final bool isTaken;
  final bool isChecking;
  final String takenLabel;
  final String checkingLabel;

  @override
  Widget build(BuildContext context) {
    if (!isTaken && !isChecking) return const SizedBox.shrink();
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          isTaken ? takenLabel : checkingLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isTaken ? FontWeight.w600 : FontWeight.w400,
            color: isTaken ? KubbTokens.miss : tokens.fgMuted,
          ),
        ),
      ),
    );
  }
}
