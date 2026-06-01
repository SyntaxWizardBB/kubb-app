import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Wizard step (M3.3-T9): pool-phase configuration for hybrid formats.
///
/// Hosts the on/off toggle, group-count and qualifiers-per-group inputs and
/// the grouping-strategy dropdown. Live validation mirrors the domain rules
/// pinned by `generatePools` in `pool_phase.dart`:
///   * `groupCount >= 2`, capped at 16 by the wizard UI for sanity.
///   * `qualifiersPerGroup >= 1` and `<= ceil(maxParticipants / groupCount)`.
///
/// When the toggle is off the parent hides the step entirely and the draft's
/// `poolPhaseConfig` is cleared via `setPoolPhaseConfig(null)`.
class WizardPoolConfigStep extends StatefulWidget {
  const WizardPoolConfigStep({
    required this.draft,
    required this.onConfigChanged,
    required this.onPitchPlanChanged,
    super.key,
  });

  final TournamentConfigDraft draft;
  final ValueChanged<PoolPhaseConfig?> onConfigChanged;

  /// Pushes the (possibly group-assigned) pitch plan back up. Only invoked
  /// when a plan already exists; the per-group assignment section reuses
  /// the existing plan and overrides `groupAssignment`.
  final ValueChanged<PitchPlan> onPitchPlanChanged;

  @override
  State<WizardPoolConfigStep> createState() => _WizardPoolConfigStepState();
}

class _WizardPoolConfigStepState extends State<WizardPoolConfigStep> {
  static const int _groupCountMin = 2;
  static const int _groupCountMax = 16;

  late TextEditingController _groupCountCtrl;
  late TextEditingController _qualifiersCtrl;
  late TextEditingController _seedCtrl;
  late int _groupCount;
  late int _qualifiersPerGroup;
  late PoolGroupingStrategy _strategy;
  int? _randomSeed;

  @override
  void initState() {
    super.initState();
    final existing = widget.draft.poolPhaseConfig;
    _groupCount = existing?.groupCount ?? 4;
    _qualifiersPerGroup = existing?.qualifiersPerGroup ?? 2;
    _strategy = existing?.strategy ?? PoolGroupingStrategy.snake;
    _randomSeed = existing?.randomSeed;
    _groupCountCtrl = TextEditingController(text: '$_groupCount');
    _qualifiersCtrl = TextEditingController(text: '$_qualifiersPerGroup');
    _seedCtrl = TextEditingController(text: _randomSeed?.toString() ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushIfValid());
  }

  @override
  void dispose() {
    _groupCountCtrl.dispose();
    _qualifiersCtrl.dispose();
    _seedCtrl.dispose();
    super.dispose();
  }

  int get _maxQualifiersPerGroup =>
      (widget.draft.maxParticipants + _groupCount - 1) ~/
          math.max(_groupCount, 1);

  bool get _groupCountValid =>
      _groupCount >= _groupCountMin && _groupCount <= _groupCountMax;

  bool get _qualifiersValid =>
      _qualifiersPerGroup >= 1 &&
      _qualifiersPerGroup <= _maxQualifiersPerGroup;

  bool get _isValid => _groupCountValid && _qualifiersValid;

  void _pushIfValid() {
    if (!_isValid) {
      widget.onConfigChanged(null);
      return;
    }
    widget.onConfigChanged(
      PoolPhaseConfig(
        groupCount: _groupCount,
        qualifiersPerGroup: _qualifiersPerGroup,
        strategy: _strategy,
        randomSeed: _strategy == PoolGroupingStrategy.random
            ? _randomSeed
            : null,
      ),
    );
  }

  void _onGroupsTyped(String raw) {
    setState(() => _groupCount = int.tryParse(raw.trim()) ?? 0);
    _pushIfValid();
  }

  void _onQualifiersTyped(String raw) {
    setState(() => _qualifiersPerGroup = int.tryParse(raw.trim()) ?? 0);
    _pushIfValid();
  }

  void _onStrategyChanged(PoolGroupingStrategy? next) {
    if (next == null) return;
    setState(() => _strategy = next);
    _pushIfValid();
  }

  void _onSeedTyped(String raw) {
    final trimmed = raw.trim();
    setState(() => _randomSeed = trimmed.isEmpty ? null : int.tryParse(trimmed));
    _pushIfValid();
  }

  /// Group label for index 0..n: 'A', 'B', 'C', …
  static String _groupLabel(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);

  /// Toggles [pitch] in the assignment list of [label] and pushes the
  /// updated pitch plan. A pitch may belong to several groups (the
  /// organiser can share fields), so this only flips the one group.
  void _togglePitchForGroup(PitchPlan plan, String label, int pitch) {
    final next = <String, List<int>>{
      for (final entry in plan.groupAssignment.entries)
        entry.key: List<int>.of(entry.value),
    };
    final current = next.putIfAbsent(label, () => <int>[]);
    if (current.contains(pitch)) {
      current.remove(pitch);
    } else {
      current
        ..add(pitch)
        ..sort();
    }
    if (current.isEmpty) next.remove(label);
    widget.onPitchPlanChanged(plan.copyWith(groupAssignment: next));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(tokens, 'Anzahl Gruppen'),
        const SizedBox(height: KubbTokens.space2),
        _intField(
          tokens: tokens,
          controller: _groupCountCtrl,
          onChanged: _onGroupsTyped,
          errorText: _groupCountValid
              ? null
              : 'Wert zwischen $_groupCountMin und $_groupCountMax erforderlich.',
        ),
        const SizedBox(height: KubbTokens.space4),
        _fieldLabel(tokens, 'Qualifier pro Gruppe'),
        const SizedBox(height: KubbTokens.space2),
        _intField(
          tokens: tokens,
          controller: _qualifiersCtrl,
          onChanged: _onQualifiersTyped,
          errorText: _qualifiersValid
              ? null
              : 'Max. $_maxQualifiersPerGroup bei ${widget.draft.maxParticipants} Teilnehmern.',
        ),
        const SizedBox(height: KubbTokens.space5),
        _fieldLabel(tokens, 'Grouping-Strategie'),
        const SizedBox(height: KubbTokens.space2),
        DropdownButtonFormField<PoolGroupingStrategy>(
          initialValue: _strategy,
          onChanged: _onStrategyChanged,
          decoration: _outlineDecoration(tokens),
          items: const [
            DropdownMenuItem(
              value: PoolGroupingStrategy.snake,
              child: Text('Snake (Schweizer-Liga)'),
            ),
            DropdownMenuItem(
              value: PoolGroupingStrategy.seeded,
              child: Text('Seeded (Blockweise)'),
            ),
            DropdownMenuItem(
              value: PoolGroupingStrategy.random,
              child: Text('Random (deterministisch)'),
            ),
          ],
        ),
        if (_strategy == PoolGroupingStrategy.random) ...[
          const SizedBox(height: KubbTokens.space4),
          _fieldLabel(tokens, 'Random-Seed (optional)'),
          const SizedBox(height: KubbTokens.space2),
          _intField(
            tokens: tokens,
            controller: _seedCtrl,
            onChanged: _onSeedTyped,
            allowEmpty: true,
          ),
        ],
        ..._pitchAssignmentSection(tokens),
      ],
    );
  }

  /// "Pitch-Zuteilung pro Gruppe" — only rendered when a pitch plan with
  /// available pitches exists and the group count is valid. For each group
  /// label (A, B, …) the organiser multi-selects which pitch numbers serve
  /// that group.
  List<Widget> _pitchAssignmentSection(KubbTokens tokens) {
    final plan = widget.draft.pitchPlan;
    if (plan == null || !_groupCountValid) return const <Widget>[];
    final pitches = plan.availablePitches();
    if (pitches.isEmpty) return const <Widget>[];
    final l10n = AppLocalizations.of(context);
    return <Widget>[
      const SizedBox(height: KubbTokens.space6),
      _fieldLabel(tokens, l10n.tournamentWizardPoolPitchAssignmentLabel),
      const SizedBox(height: KubbTokens.space2),
      Text(
        l10n.tournamentWizardPoolPitchAssignmentHint,
        style: TextStyle(fontSize: 11, height: 1.35, color: tokens.fgSubtle),
      ),
      const SizedBox(height: KubbTokens.space3),
      for (var g = 0; g < _groupCount; g++) ...[
        if (g > 0) const SizedBox(height: KubbTokens.space4),
        Builder(
          builder: (context) {
            final label = _groupLabel(g);
            final assigned = plan.groupAssignment[label] ?? const <int>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tournamentWizardPoolGroupLabel(label),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: KubbTokens.space2),
                Wrap(
                  spacing: KubbTokens.space2,
                  runSpacing: KubbTokens.space2,
                  children: [
                    for (final pitch in pitches)
                      _PitchAssignChip(
                        label: '$pitch',
                        selected: assigned.contains(pitch),
                        onTap: () => _togglePitchForGroup(plan, label, pitch),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    ];
  }

  Widget _fieldLabel(KubbTokens tokens, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: tokens.fgMuted,
      ),
    );
  }

  Widget _intField({
    required KubbTokens tokens,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? errorText,
    bool allowEmpty = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged,
      decoration: _outlineDecoration(tokens).copyWith(errorText: errorText),
    );
  }

  InputDecoration _outlineDecoration(KubbTokens tokens) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
    );
    return InputDecoration(border: border, enabledBorder: border);
  }
}

/// Toggle row "Pool-Phase aktivieren" rendered before the actual config
/// fields. Lives outside [WizardPoolConfigStep] because the parent wizard
/// needs to hide the step body when it's off.
class WizardPoolToggle extends StatelessWidget {
  const WizardPoolToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Pool-Phase aktivieren',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Compact multi-select chip for a single pitch number in the per-group
/// pitch-assignment grid. Mirrors the wizard's `_SelectChip` pattern but
/// stays local to this step (numeric, denser layout).
class _PitchAssignChip extends StatelessWidget {
  const _PitchAssignChip({
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
    return InkWell(
      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space4,
          vertical: KubbTokens.space2,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          border: Border.all(
            color: selected ? tokens.primary : tokens.line,
            width: 1.5,
          ),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : tokens.fg,
            ),
          ),
        ),
      ),
    );
  }
}
