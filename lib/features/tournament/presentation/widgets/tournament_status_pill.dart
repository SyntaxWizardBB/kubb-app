import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Small coloured pill mapping a [TournamentStatus] to a short German
/// label. Mirrors the match-status pill so both feature areas share a
/// visual language.
class TournamentStatusPill extends StatelessWidget {
  const TournamentStatusPill({required this.status, super.key});

  final TournamentStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final spec = _specFor(status, l);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space2, vertical: 2),
      decoration: BoxDecoration(
        color: spec.$2,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(spec.$1,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: spec.$3)),
    );
  }

  (String, Color, Color) _specFor(TournamentStatus s, AppLocalizations l) {
    switch (s) {
      case TournamentStatus.draft:
        return (l.tournamentStatusDraft, const Color(0xFFE8EEF5),
            const Color(0xFF1F3A5F));
      case TournamentStatus.published:
        return (l.tournamentStatusPublished, const Color(0xFFFBF2D6),
            const Color(0xFF3D2C00));
      case TournamentStatus.registrationOpen:
        return (l.tournamentStatusRegistrationOpen, KubbTokens.meadow100,
            KubbTokens.meadow700);
      case TournamentStatus.registrationClosed:
        return (l.tournamentStatusRegistrationClosed, const Color(0xFFFBF2D6),
            const Color(0xFF3D2C00));
      case TournamentStatus.live:
        return (l.tournamentStatusLive, KubbTokens.meadow100,
            KubbTokens.meadow700);
      case TournamentStatus.finalized:
        return (l.tournamentStatusFinalized, KubbTokens.meadow100,
            KubbTokens.meadow700);
      case TournamentStatus.aborted:
        return (
          l.tournamentStatusAborted,
          KubbTokens.miss.withValues(alpha: 0.15),
          KubbTokens.miss,
        );
    }
  }
}
