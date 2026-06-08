import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_conflict_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Per-set, three-line comparison: basekubbs A, basekubbs B, winner.
/// Differing fields highlight in [KubbTokens.miss] on a chalk
/// background to keep the row scannable on a 380 px viewport.
class ConflictComparisonRow extends StatelessWidget {
  const ConflictComparisonRow({required this.pair, super.key});

  final TournamentSetProposalPair pair;

  // M2a: SetWinner.none (no decisive winner) renders like the absent
  // case ("—") so a king-less group set is not mislabelled as a B win.
  String _winner(SetWinner? w, AppLocalizations l) => switch (w) {
        SetWinner.teamA => l.tournamentMatchKingByA,
        SetWinner.teamB => l.tournamentMatchKingByB,
        SetWinner.none || null => '—',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final a = pair.teamA?.score;
    final b = pair.teamB?.score;
    final both = a != null && b != null;
    final diffA = both && a.basekubbsKnockedByA != b.basekubbsKnockedByA;
    final diffB = both && a.basekubbsKnockedByB != b.basekubbsKnockedByB;
    final diffW = both && a.winner != b.winner;
    return Container(
      key: ValueKey<int>(pair.setNumber),
      margin: const EdgeInsets.only(bottom: KubbTokens.space3),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: t.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: t.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.tournamentConflictSetLabel(pair.setNumber),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: t.fg)),
        const SizedBox(height: KubbTokens.space2),
        _line(t, l.tournamentConflictBasekubbsA,
            a?.basekubbsKnockedByA.toString() ?? '—',
            b?.basekubbsKnockedByA.toString() ?? '—', diffA),
        _line(t, l.tournamentConflictBasekubbsB,
            a?.basekubbsKnockedByB.toString() ?? '—',
            b?.basekubbsKnockedByB.toString() ?? '—', diffB),
        _line(t, l.tournamentConflictSetWinner, _winner(a?.winner, l),
            _winner(b?.winner, l), diffW),
      ]),
    );
  }

  Widget _line(KubbTokens t, String label, String va, String vb, bool diff) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: t.fgMuted,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(flex: 3, child: _cell(t, va, diff)),
        const SizedBox(width: KubbTokens.space2),
        Expanded(flex: 3, child: _cell(t, vb, diff)),
      ]),
    );
  }

  Widget _cell(KubbTokens t, String text, bool diff) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space2, vertical: KubbTokens.space1),
      decoration: BoxDecoration(
        color: diff ? KubbTokens.miss : Colors.transparent,
        borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              fontWeight: diff ? FontWeight.w800 : FontWeight.w600,
              color: diff ? t.bg : t.fg)),
    );
  }
}
