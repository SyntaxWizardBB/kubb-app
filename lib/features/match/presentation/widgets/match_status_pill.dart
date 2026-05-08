import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/data/match_models.dart';

/// Small coloured pill that maps a [MatchStatus] to a short German
/// label. Mirrors the inbox-tile kind pills so all "status chip" UI
/// across the app reads visually similar.
class MatchStatusPill extends StatelessWidget {
  const MatchStatusPill({required this.status, super.key});

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: spec.bg,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(
        spec.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: spec.fg,
        ),
      ),
    );
  }

  _PillSpec _specFor(MatchStatus status) {
    switch (status) {
      case MatchStatus.pendingInvites:
        return const _PillSpec(
          label: 'Einladungen offen',
          bg: Color(0xFFFBF2D6),
          fg: Color(0xFF3D2C00),
        );
      case MatchStatus.active:
        return const _PillSpec(
          label: 'Läuft',
          bg: KubbTokens.meadow100,
          fg: KubbTokens.meadow700,
        );
      case MatchStatus.awaitingResults:
        return const _PillSpec(
          label: 'Warten auf Resultat',
          bg: Color(0xFFE8EEF5),
          fg: Color(0xFF1F3A5F),
        );
      case MatchStatus.finalized:
        return const _PillSpec(
          label: 'Abgeschlossen',
          bg: KubbTokens.meadow100,
          fg: KubbTokens.meadow700,
        );
      case MatchStatus.voided:
        return _PillSpec(
          label: 'Abgebrochen',
          bg: KubbTokens.miss.withValues(alpha: 0.15),
          fg: KubbTokens.miss,
        );
    }
  }
}

class _PillSpec {
  const _PillSpec({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;
}
