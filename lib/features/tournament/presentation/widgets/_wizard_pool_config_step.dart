import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Wizard step: group-phase (pool) configuration for hybrid formats.
///
/// Hosts the group-count input and the grouping-strategy dropdown. The
/// qualifier-per-group count is no longer an input — it is DERIVED read-only
/// as `koBracketSize / groupCount` (P6_SETUP_WIZARD_SPEC.md Screen 5) and the
/// group count must evenly divide the KO bracket size (divisibility
/// validation). Live validation mirrors the domain rules pinned by
/// `generatePools` in `pool_phase.dart`:
///   * `groupCount >= 2`, capped at 16 by the wizard UI for sanity.
///   * `koBracketSize % groupCount == 0` (so each group sends the same number
///     of qualifiers into the KO bracket).
///
/// When the Vorrunde is not a group phase the parent hides the step entirely
/// and the draft's `poolPhaseConfig` is cleared via `setPoolPhaseConfig(null)`.
class WizardPoolConfigStep extends StatefulWidget {
  const WizardPoolConfigStep({
    required this.draft,
    required this.koBracketSize,
    required this.onConfigChanged,
    required this.onPitchPlanChanged,
    super.key,
  });

  final TournamentConfigDraft draft;

  /// KO bracket size (power of two) the qualifier-per-group count is derived
  /// from. Computed by the wizard from the KO config (which precedes this
  /// step). 0 when the KO size is not yet valid.
  final int koBracketSize;

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
  late TextEditingController _seedCtrl;
  late int _groupCount;
  late PoolGroupingStrategy _strategy;
  int? _randomSeed;

  @override
  void initState() {
    super.initState();
    final existing = widget.draft.poolPhaseConfig;
    _groupCount = existing?.groupCount ?? 4;
    _strategy = existing?.strategy ?? PoolGroupingStrategy.snake;
    _randomSeed = existing?.randomSeed;
    _groupCountCtrl = TextEditingController(text: '$_groupCount');
    _seedCtrl = TextEditingController(text: _randomSeed?.toString() ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushIfValid());
  }

  @override
  void dispose() {
    _groupCountCtrl.dispose();
    _seedCtrl.dispose();
    super.dispose();
  }

  /// Qualifier-per-group count derived read-only from the KO bracket size
  /// (`koBracketSize / groupCount`). 0 when the group count is invalid or
  /// does not evenly divide the bracket size.
  int get _derivedQualifiersPerGroup {
    final size = widget.koBracketSize;
    if (!_groupCountValid || size <= 0 || size % _groupCount != 0) return 0;
    return size ~/ _groupCount;
  }

  bool get _groupCountValid =>
      _groupCount >= _groupCountMin && _groupCount <= _groupCountMax;

  /// The group count must evenly divide the KO bracket size so every group
  /// sends the same number of teams into the KO bracket.
  bool get _divisible =>
      widget.koBracketSize > 0 && widget.koBracketSize % _groupCount == 0;

  bool get _isValid => _groupCountValid && _divisible;

  void _pushIfValid() {
    if (!_isValid) {
      widget.onConfigChanged(null);
      return;
    }
    widget.onConfigChanged(
      PoolPhaseConfig(
        groupCount: _groupCount,
        qualifiersPerGroup: _derivedQualifiersPerGroup,
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
          errorText: !_groupCountValid
              ? 'Wert zwischen $_groupCountMin und $_groupCountMax erforderlich.'
              : (!_divisible
                  ? 'Gruppen müssen die KO-Grösse (${widget.koBracketSize}) glatt teilen.'
                  : null),
        ),
        const SizedBox(height: KubbTokens.space4),
        // Qualifier-per-group is derived read-only from the KO bracket size /
        // group count (P6_SETUP_WIZARD_SPEC.md Screen 5).
        _fieldLabel(tokens, 'Qualifier pro Gruppe'),
        const SizedBox(height: KubbTokens.space2),
        _DerivedValueBox(
          tokens: tokens,
          value: _isValid ? '$_derivedQualifiersPerGroup' : '—',
        ),
        const SizedBox(height: KubbTokens.space5),
        _fieldLabel(tokens, 'Gruppierungsstrategie'),
        const SizedBox(height: KubbTokens.space2),
        DropdownButtonFormField<PoolGroupingStrategy>(
          initialValue: _strategy,
          onChanged: _onStrategyChanged,
          decoration: _outlineDecoration(tokens),
          items: const [
            DropdownMenuItem(
              value: PoolGroupingStrategy.snake,
              child: Text('Snake / Reissverschluss'),
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

/// Read-only display box for a derived value (e.g. qualifier-per-group),
/// styled like a disabled outline field so it reads as non-editable.
class _DerivedValueBox extends StatelessWidget {
  const _DerivedValueBox({required this.tokens, required this.value});

  final KubbTokens tokens;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: tokens.fg,
        ),
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
