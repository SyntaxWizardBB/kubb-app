import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Match-point mode for league-eligible tournaments (FR-POINTS-8). Maps to
/// `tournament_config.points_mode` on the create RPC.
enum LeaguePointsMode { globalFormula, customPoints }

/// Lightweight option shape for the season dropdown — keeps this widget free
/// of repo/provider imports (the wizard maps season rows into this).
class SeasonOption {
  const SeasonOption({required this.id, required this.label});
  final String id;
  final String label;
}

/// Combined wizard step "Liga & Punkte" (R-M5.3-2). Picks the match-point
/// mode (FR-POINTS-8), assigns an open season (FR-CFG-16) and shows the
/// immutable 3-1-0 default (OD-M5-02). Custom-points is dataset-only in M5 —
/// scoring still uses 3-1-0 until a platform admin approves (FR-POINTS-10).
class WizardLeaguePointsStep extends StatelessWidget {
  const WizardLeaguePointsStep({
    required this.pointsMode,
    required this.onPointsModeChanged,
    required this.seasonId,
    required this.onSeasonChanged,
    this.availableSeasons = const <SeasonOption>[],
    super.key,
  });

  final LeaguePointsMode pointsMode;
  final ValueChanged<LeaguePointsMode> onPointsModeChanged;
  final String? seasonId;
  final ValueChanged<String?> onSeasonChanged;
  final List<SeasonOption> availableSeasons;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final labelStyle = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w700,
      letterSpacing: 0.4, color: tokens.fgMuted,
    );
    final hint = TextStyle(fontSize: 12, height: 1.4, color: tokens.fgMuted);
    final hasSeasons = availableSeasons.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Punkte-Modus', style: labelStyle),
        const SizedBox(height: KubbTokens.space2),
        RadioGroup<LeaguePointsMode>(
          groupValue: pointsMode,
          onChanged: (m) => m == null ? null : onPointsModeChanged(m),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RadioListTile<LeaguePointsMode>(value: LeaguePointsMode.globalFormula,
                contentPadding: EdgeInsets.zero, title: Text('Globale Formel')),
            RadioListTile<LeaguePointsMode>(value: LeaguePointsMode.customPoints,
                contentPadding: EdgeInsets.zero, title: Text('Eigene Punkte')),
          ]),
        ),
        if (pointsMode == LeaguePointsMode.customPoints)
          Padding(padding: const EdgeInsets.only(top: KubbTokens.space2), child: Text(
            'Eigene Punkte müssen vom Plattform-Admin freigegeben werden.', style: hint)),
        const SizedBox(height: KubbTokens.space4),
        Text('Saison', style: labelStyle),
        const SizedBox(height: KubbTokens.space2),
        DropdownButtonFormField<String?>(
          initialValue: seasonId,
          onChanged: hasSeasons ? onSeasonChanged : null,
          items: [
            const DropdownMenuItem<String?>(child: Text('(keine Zuordnung)')),
            for (final s in availableSeasons)
              DropdownMenuItem<String?>(value: s.id, child: Text(s.label)),
          ],
        ),
        if (!hasSeasons)
          Padding(padding: const EdgeInsets.only(top: KubbTokens.space2),
              child: Text('Keine Saisonen verfügbar.', style: hint)),
        const SizedBox(height: KubbTokens.space4),
        Text('Match-Punkte (Standard 3-1-0)', style: labelStyle),
        const SizedBox(height: KubbTokens.space2),
        Container(
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            border: Border.all(color: tokens.line),
          ),
          child: const Column(children: [
            _PointsRow(label: 'Sieg', value: '3'),
            _PointsRow(label: 'Unentschieden', value: '1'),
            _PointsRow(label: 'Niederlage', value: '0'),
          ]),
        ),
      ],
    );
  }
}

class _PointsRow extends StatelessWidget {
  const _PointsRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
    child: Row(children: [
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ]),
  );
}
