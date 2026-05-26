import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Wire-format tiebreaker keys consumed by the `tournament_create` RPC.
/// Mirrors `TiebreakerCriterion` snake_case identifiers (7 entries).
const List<String> _kAllCriteria = <String>[
  'total_points',
  'buchholz_minus_h2h',
  'median_buchholz',
  'kubb_difference',
  'direct_comparison',
  'wins',
  'random',
];

/// Preset chains (OD-M2-03 Empfehlung C). "Standard" mirrors the M1 default
/// in [TournamentConfigDraft]; "Schweizer-konform" follows the canonical
/// Swiss chain (Buchholz family + Median + Direct, then Wins/Diff).
const List<String> _kPresetStandard = <String>[
  'total_points',
  'buchholz_minus_h2h',
  'direct_comparison',
  'wins',
];
const List<String> _kPresetSwiss = <String>[
  'total_points',
  'buchholz_minus_h2h',
  'median_buchholz',
  'direct_comparison',
  'wins',
  'kubb_difference',
];

enum _TiebreakerPreset { standard, swiss, custom }

const Map<String, String> _kCriterionLabelsDe = <String, String>{
  'total_points': 'Gesamtpunkte',
  'buchholz_minus_h2h': 'Buchholz minus H2H',
  'median_buchholz': 'Median-Buchholz',
  'kubb_difference': 'Kubb-Differenz',
  'direct_comparison': 'Direkter Vergleich',
  'wins': 'Anzahl Siege',
  'random': 'Zufall',
};

/// Wizard step 6 helper: preset selector plus optional drag-reorder editor
/// for [TournamentConfigDraft.tiebreakerOrder]. Stateless — the wizard owns
/// the draft and re-builds via [onChanged].
class WizardTiebreakerStep extends StatelessWidget {
  const WizardTiebreakerStep({
    required this.order,
    required this.onChanged,
    super.key,
  });

  final List<String> order;
  final ValueChanged<List<String>> onChanged;

  _TiebreakerPreset get _preset {
    if (_listEq(order, _kPresetStandard)) return _TiebreakerPreset.standard;
    if (_listEq(order, _kPresetSwiss)) return _TiebreakerPreset.swiss;
    return _TiebreakerPreset.custom;
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _onPreset(_TiebreakerPreset? p) {
    switch (p) {
      case _TiebreakerPreset.standard:
        onChanged(List<String>.unmodifiable(_kPresetStandard));
      case _TiebreakerPreset.swiss:
        onChanged(List<String>.unmodifiable(_kPresetSwiss));
      case _TiebreakerPreset.custom:
        // Switching to Custom seeds the editor with all 7 criteria so the
        // organizer can immediately drag-reorder the full chain.
        onChanged(List<String>.unmodifiable(_kAllCriteria));
      case null:
        return;
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    final next = List<String>.from(order);
    final to = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(to, next.removeAt(oldIndex));
    onChanged(List<String>.unmodifiable(next));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final preset = _preset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<_TiebreakerPreset>(
          initialValue: preset,
          items: const [
            DropdownMenuItem(
              value: _TiebreakerPreset.standard,
              child: Text('Standard'),
            ),
            DropdownMenuItem(
              value: _TiebreakerPreset.swiss,
              child: Text('Schweizer-konform'),
            ),
            DropdownMenuItem(
              value: _TiebreakerPreset.custom,
              child: Text('Custom'),
            ),
          ],
          onChanged: _onPreset,
        ),
        if (preset == _TiebreakerPreset.custom) ...[
          const SizedBox(height: KubbTokens.space3),
          Text(
            l10n.tournamentWizardTiebreakerHint,
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          ),
          const SizedBox(height: KubbTokens.space2),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.length,
            onReorder: _onReorder,
            itemBuilder: (context, i) {
              final key = order[i];
              return Container(
                key: ValueKey<String>(key),
                margin: const EdgeInsets.only(bottom: KubbTokens.space2),
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space3,
                  vertical: KubbTokens.space3,
                ),
                decoration: BoxDecoration(
                  color: tokens.bgRaised,
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                  border: Border.all(color: tokens.line),
                ),
                child: Row(
                  children: [
                    Text(
                      '${i + 1}.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: tokens.fgMuted,
                      ),
                    ),
                    const SizedBox(width: KubbTokens.space3),
                    Expanded(
                      child: Text(_kCriterionLabelsDe[key] ?? key),
                    ),
                    Icon(Icons.drag_handle, color: tokens.fgMuted),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: KubbTokens.space2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _onPreset(_TiebreakerPreset.standard),
              child: Text(l10n.tournamentWizardTiebreakerResetButton),
            ),
          ),
        ],
      ],
    );
  }
}
