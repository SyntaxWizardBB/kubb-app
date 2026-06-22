import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_binary_choice.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/ko_round_block.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Form-based stage-type-graph editor (Ebene 2, ADR-0039 §1, spec §5 handy
/// variant). Category-aware:
///
/// - **Vorrunde**: shows the plates (constant field count) and the AdvanceAll
///   chain (`alle weiter`, r -> r+1). Granular winner/loser field edges are NOT
///   offered here — the UI mirrors the `vorrunde_field_edge_forbidden`
///   validation.
/// - **KO**: shows the granular winner/loser field edges; an `OpenEdge` is
///   selectable and flagged as a warning.
///
/// It holds NO graph state of its own and never re-implements validation: it
/// reads/mutates ONLY [stageTypeGraphBuilderProvider] and renders
/// `state.findings` / `state.hasErrors` (the single source of truth). Saving is
/// blocked while `hasErrors` is true. The later desktop canvas (U8) mutates the
/// same provider — that is the editor-parity precondition.
class StageTypeGraphBuilderScreen extends StatelessWidget {
  const StageTypeGraphBuilderScreen({super.key, this.onSave});

  /// Optional save callback, handed the serialized config (one key,
  /// `type_graph`). The host (wizard / standalone) decides where it lands.
  final ValueChanged<Map<String, Object?>>? onSave;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.stageTypeGraphEyebrow,
        title: l.stageTypeGraphTitle,
      ),
      body: StageTypeGraphBuilderBody(onSave: onSave),
    );
  }
}

/// Chrome-free editor body so the wizard can host it inline. Reads/mutates only
/// [stageTypeGraphBuilderProvider].
class StageTypeGraphBuilderBody extends ConsumerWidget {
  const StageTypeGraphBuilderBody({super.key, this.onSave});

  final ValueChanged<Map<String, Object?>>? onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stageTypeGraphBuilderProvider);
    final notifier = ref.read(stageTypeGraphBuilderProvider.notifier);
    final isVorrunde = s.graph.category == TypeStageCategory.vorrunde;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space5,
        KubbTokens.space4,
        KubbTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CategorySection(state: s, notifier: notifier),
          const SizedBox(height: KubbTokens.space6),
          _RoundsSection(state: s, notifier: notifier),
          const SizedBox(height: KubbTokens.space6),
          // The KO edge section is hidden for a Vorrunde: there are no granular
          // edges to wire there (spec §4 / vorrunde_field_edge_forbidden).
          if (isVorrunde)
            const _VorrundeEdgesNote()
          else ...[
            _KoEdgesSection(state: s, notifier: notifier),
          ],
          const SizedBox(height: KubbTokens.space6),
          _ValidationPanel(state: s),
          const SizedBox(height: KubbTokens.space5),
          _SaveBar(state: s, notifier: notifier, onSave: onSave),
        ],
      ),
    );
  }
}

// --- Shared section header -------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: tokens.fg,
            ),
          ),
        ),
        ?action,
      ],
    );
  }
}

class _AddIconButton extends StatelessWidget {
  const _AddIconButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(LucideIcons.plus, size: 20),
      color: tokens.fg,
      constraints: const BoxConstraints.tightFor(
        width: KubbTokens.touchMin,
        height: KubbTokens.touchMin,
      ),
      onPressed: onPressed,
    );
  }
}

// --- Category --------------------------------------------------------------

class _CategorySection extends StatefulWidget {
  const _CategorySection({required this.state, required this.notifier});

  final StageTypeGraphBuilderState state;
  final StageTypeGraphBuilderController notifier;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  late int _participantCount;

  @override
  void initState() {
    super.initState();
    // Seed from the round-1 field count (fields * 2 is the participant count
    // round 1 was generated for); fall back to the default.
    final r1 = widget.state.graph.rounds.isEmpty
        ? null
        : widget.state.graph.rounds.first;
    _participantCount = r1 == null
        ? StageTypeGraphBuilderController.defaultParticipantCount
        : r1.fields.length * 2;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l.stageTypeGraphCategorySection),
        const SizedBox(height: KubbTokens.space3),
        KubbBinaryChoice<TypeStageCategory>(
          selected: widget.state.graph.category,
          onChanged: (v) => widget.notifier.resetTo(
            category: v,
            participantCount: _participantCount,
          ),
          options: <KubbChoiceOption<TypeStageCategory>>[
            KubbChoiceOption<TypeStageCategory>(
              value: TypeStageCategory.ko,
              title: l.stageTypeGraphCategoryKo,
            ),
            KubbChoiceOption<TypeStageCategory>(
              value: TypeStageCategory.vorrunde,
              title: l.stageTypeGraphCategoryVorrunde,
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          l.stageTypeGraphCategoryHint,
          style: TextStyle(fontSize: 12, color: tokens.fgMuted, height: 1.4),
        ),
        const SizedBox(height: KubbTokens.space4),
        WizardNumberField(
          label: l.stageTypeGraphParticipantsLabel,
          value: _participantCount,
          min: 2,
          max: 128,
          onChanged: (v) => setState(() => _participantCount = v),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          l.stageTypeGraphParticipantsHint,
          style: TextStyle(fontSize: 12, color: tokens.fgMuted, height: 1.4),
        ),
        const SizedBox(height: KubbTokens.space3),
        SizedBox(
          height: KubbTokens.touchMin,
          child: KubbButton(
            variant: KubbButtonVariant.secondary,
            onPressed: () => widget.notifier.resetTo(
              category: widget.state.graph.category,
              participantCount: _participantCount,
            ),
            child: Text(l.stageTypeGraphRebuildRound1),
          ),
        ),
      ],
    );
  }
}

// --- Rounds ----------------------------------------------------------------

class _RoundsSection extends StatelessWidget {
  const _RoundsSection({required this.state, required this.notifier});

  final StageTypeGraphBuilderState state;
  final StageTypeGraphBuilderController notifier;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rounds = <TypeRound>[...state.graph.rounds]
      ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
    final isVorrunde = state.graph.category == TypeStageCategory.vorrunde;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: l.stageTypeGraphRoundsSection,
          action: _AddIconButton(
            tooltip: l.stageTypeGraphAddRound,
            onPressed: () => _addRound(rounds),
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        for (final round in rounds) ...[
          _RoundTile(
            round: round,
            isVorrunde: isVorrunde,
            onFieldCountChanged: (count) =>
                _setFieldCount(round, count, isVorrunde),
            onPairingChanged: (rule) => notifier.updateRound(
              round.roundNumber,
              _roundWith(round, pairingRule: rule),
            ),
            onFormatChanged: (spec) => notifier.updateRound(
              round.roundNumber,
              _roundWith(round, matchFormat: spec),
            ),
            onDelete: rounds.length <= 1
                ? null
                : () => notifier.removeRound(round.roundNumber),
          ),
          const SizedBox(height: KubbTokens.space2),
        ],
        // Adding a Vorrunde round also wires the mandatory AdvanceAll chain link
        // automatically (the editor mirrors the advance_all_missing rule).
        if (isVorrunde) ...[
          const SizedBox(height: KubbTokens.space2),
          Builder(
            builder: (context) {
              final tokens = Theme.of(context).extension<KubbTokens>()!;
              return Text(
                l.stageTypeGraphAdvanceAllNote,
                style:
                    TextStyle(fontSize: 12, height: 1.3, color: tokens.fgMuted),
              );
            },
          ),
        ],
      ],
    );
  }

  TypeRound _roundWith(
    TypeRound round, {
    List<TypeField>? fields,
    MatchFormatSpec? matchFormat,
    TypePairingRule? pairingRule,
  }) =>
      TypeRound(
        roundNumber: round.roundNumber,
        fields: fields ?? round.fields,
        matchFormat: matchFormat ?? round.matchFormat,
        koMatchup: round.koMatchup,
        koTiebreak: round.koTiebreak,
        pairingRule: pairingRule ?? round.pairingRule,
      );

  void _setFieldCount(TypeRound round, int count, bool isVorrunde) {
    final fields = <TypeField>[
      for (var slot = 1; slot <= count; slot++)
        TypeField(
          id: 'R${round.roundNumber}F$slot',
          roundNumber: round.roundNumber,
          slot: slot,
        ),
    ];
    notifier.updateRound(round.roundNumber, _roundWith(round, fields: fields));
  }

  void _addRound(List<TypeRound> rounds) {
    final isVorrunde = state.graph.category == TypeStageCategory.vorrunde;
    final last = rounds.isEmpty ? null : rounds.last;
    final nextRoundNumber = (last?.roundNumber ?? 0) + 1;
    // KO halves towards the final; Vorrunde keeps the field count constant.
    final lastCount = last?.fields.length ?? 1;
    final count = isVorrunde ? lastCount : (lastCount / 2).ceil().clamp(1, 64);
    final fields = <TypeField>[
      for (var slot = 1; slot <= count; slot++)
        TypeField(
          id: 'R${nextRoundNumber}F$slot',
          roundNumber: nextRoundNumber,
          slot: slot,
        ),
    ];
    notifier.addRound(
      fields: fields,
      matchFormat: StageTypeGraphBuilderController.defaultMatchFormat,
      koMatchup: isVorrunde ? null : KoMatchup.seedHighVsLow,
      koTiebreak: isVorrunde ? null : KoTiebreakMethod.classicKingtossRemoval,
      pairingRule: isVorrunde ? TypePairingRule.groupRoundRobin : null,
    );
    // A Vorrunde round transition is a single AdvanceAllEdge(prev -> new); wire
    // it so the editor satisfies advance_all_missing for the owner.
    if (isVorrunde && last != null) {
      notifier.addEdge(
        AdvanceAllEdge(fromRound: last.roundNumber, toRound: nextRoundNumber),
      );
    }
  }
}

class _RoundTile extends StatelessWidget {
  const _RoundTile({
    required this.round,
    required this.isVorrunde,
    required this.onFieldCountChanged,
    required this.onPairingChanged,
    required this.onFormatChanged,
    required this.onDelete,
  });

  final TypeRound round;
  final bool isVorrunde;
  final ValueChanged<int> onFieldCountChanged;
  final ValueChanged<TypePairingRule> onPairingChanged;
  final ValueChanged<MatchFormatSpec> onFormatChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      padding: const EdgeInsets.all(KubbTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: KubbTokens.space2,
                  runSpacing: KubbTokens.space1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l.stageTypeGraphRoundTitle(round.roundNumber.toString()),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg,
                      ),
                    ),
                    KubbChip(
                      tone: KubbChipTone.neutral,
                      label: l.stageTypeGraphRoundFieldCount(
                        round.fields.length,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: l.stageTypeGraphDeleteRound,
                  icon: const Icon(LucideIcons.trash2, size: 18),
                  color: KubbTokens.miss,
                  constraints: const BoxConstraints.tightFor(
                    width: KubbTokens.touchMin,
                    height: KubbTokens.touchMin,
                  ),
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: KubbTokens.space3),
          WizardNumberField(
            label: l.stageTypeGraphFieldCountLabel,
            value: round.fields.length,
            min: 1,
            max: 64,
            compact: true,
            onChanged: onFieldCountChanged,
          ),
          if (isVorrunde) ...[
            const SizedBox(height: KubbTokens.space2),
            Text(
              l.stageTypeGraphPlatesHint,
              style: TextStyle(fontSize: 12, height: 1.3, color: tokens.fgMuted),
            ),
            const SizedBox(height: KubbTokens.space3),
            Text(
              l.stageTypeGraphPairingRuleLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: tokens.fgMuted,
              ),
            ),
            const SizedBox(height: KubbTokens.space2),
            KubbBinaryChoice<TypePairingRule>(
              selected: round.pairingRule ?? TypePairingRule.groupRoundRobin,
              onChanged: onPairingChanged,
              options: <KubbChoiceOption<TypePairingRule>>[
                KubbChoiceOption<TypePairingRule>(
                  value: TypePairingRule.groupRoundRobin,
                  title: l.stageTypeGraphPairingGroup,
                ),
                KubbChoiceOption<TypePairingRule>(
                  value: TypePairingRule.schochMonrad,
                  title: l.stageTypeGraphPairingSchoch,
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: KubbTokens.space3),
            Text(
              l.stageTypeGraphRoundFormatLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: tokens.fgMuted,
              ),
            ),
            const SizedBox(height: KubbTokens.space2),
            KoRoundBlock(
              title: l.stageTypeGraphKoConfigLabel,
              spec: round.matchFormat,
              onChanged: onFormatChanged,
            ),
          ],
        ],
      ),
    );
  }
}

// --- KO field edges --------------------------------------------------------

class _KoEdgesSection extends StatelessWidget {
  const _KoEdgesSection({required this.state, required this.notifier});

  final StageTypeGraphBuilderState state;
  final StageTypeGraphBuilderController notifier;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final fields = state.graph.allFields;
    final canAdd = fields.length >= 2;
    // Only granular field edges (winner/loser/open) are shown here; an
    // AdvanceAllEdge belongs to the Vorrunde and has no KO meaning.
    final edges = <(int, FieldEdge)>[
      for (var i = 0; i < state.graph.edges.length; i++)
        if (state.graph.edges[i] is! AdvanceAllEdge) (i, state.graph.edges[i]),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: l.stageTypeGraphEdgesSection,
          action: _AddIconButton(
            tooltip: l.stageTypeGraphAddEdge,
            onPressed: canAdd ? () => _openAddEdge(context) : null,
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        if (edges.isEmpty)
          Text(
            l.stageTypeGraphEdgesEmpty,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted),
          )
        else
          for (final (index, edge) in edges) ...[
            _EdgeTile(
              edge: edge,
              onEdit: () => _openEditEdge(context, index, edge),
              onDelete: () => notifier.removeEdge(index),
            ),
            const SizedBox(height: KubbTokens.space2),
          ],
      ],
    );
  }

  Future<void> _openAddEdge(BuildContext context) async {
    final edge = await showDialog<FieldEdge>(
      context: context,
      builder: (_) => _KoEdgeDialog(fields: state.graph.allFields),
    );
    if (edge != null) notifier.addEdge(edge);
  }

  Future<void> _openEditEdge(
    BuildContext context,
    int index,
    FieldEdge edge,
  ) async {
    final updated = await showDialog<FieldEdge>(
      context: context,
      builder: (_) =>
          _KoEdgeDialog(fields: state.graph.allFields, initial: edge),
    );
    if (updated != null) notifier.updateEdge(index, updated);
  }
}

class _EdgeTile extends StatelessWidget {
  const _EdgeTile({
    required this.edge,
    required this.onEdit,
    required this.onDelete,
  });

  final FieldEdge edge;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final (label, detail) = _describe(l, edge);
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space3,
        KubbTokens.space2,
        KubbTokens.space2,
        KubbTokens.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 2),
                KubbChip(
                  tone: edge is OpenEdge
                      ? KubbChipTone.heli
                      : KubbChipTone.neutral,
                  label: label,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.stageTypeGraphConfirm,
            icon: const Icon(LucideIcons.pencil, size: 18),
            constraints: const BoxConstraints.tightFor(
              width: KubbTokens.touchMin,
              height: KubbTokens.touchMin,
            ),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: l.stageTypeGraphDeleteEdge,
            icon: const Icon(LucideIcons.trash2, size: 18),
            color: KubbTokens.miss,
            constraints: const BoxConstraints.tightFor(
              width: KubbTokens.touchMin,
              height: KubbTokens.touchMin,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  (String, String) _describe(AppLocalizations l, FieldEdge edge) {
    switch (edge) {
      case WinnerEdge(:final fromFieldId, :final toFieldId):
        return (l.stageTypeGraphEdgeWinner, '$fromFieldId → $toFieldId');
      case LoserEdge(:final fromFieldId, :final toFieldId):
        return (l.stageTypeGraphEdgeLoser, '$fromFieldId → $toFieldId');
      case OpenEdge(:final fromFieldId, :final slot):
        final side = slot == OpenEdgeSlot.winner
            ? l.stageTypeGraphEdgeWinner
            : l.stageTypeGraphEdgeLoser;
        return (l.stageTypeGraphEdgeOpen, '$fromFieldId · $side');
      case AdvanceAllEdge(:final fromRound, :final toRound):
        return ('', 'R$fromRound → R$toRound');
    }
  }
}

class _VorrundeEdgesNote extends StatelessWidget {
  const _VorrundeEdgesNote();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l.stageTypeGraphEdgesSection),
        const SizedBox(height: KubbTokens.space3),
        Container(
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            border: Border(left: BorderSide(color: tokens.line, width: 3)),
            borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
          ),
          padding: const EdgeInsets.all(KubbTokens.space3),
          child: Text(
            l.stageTypeGraphEdgesVorrundeHint,
            style: TextStyle(fontSize: 13, color: tokens.fg, height: 1.35),
          ),
        ),
      ],
    );
  }
}

// --- Validation panel ------------------------------------------------------

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.state});

  final StageTypeGraphBuilderState state;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final hasErrors = state.hasErrors;
    final findings = state.findings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionHeader(title: l.stageTypeGraphValidationSection),
            ),
            KubbChip(
              tone: hasErrors ? KubbChipTone.miss : KubbChipTone.hit,
              icon: hasErrors ? LucideIcons.x : LucideIcons.check,
              label: hasErrors
                  ? l.stageTypeGraphNotSavable
                  : l.stageTypeGraphSavable,
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space3),
        if (findings.isEmpty)
          Text(
            l.stageTypeGraphNoFindings,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted),
          )
        else
          for (final f in findings) ...[
            _FindingTile(finding: f),
            const SizedBox(height: KubbTokens.space2),
          ],
      ],
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});

  final ValidationFinding finding;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final isError = finding.severity == ValidationSeverity.error;
    final accent = isError ? KubbTokens.miss : KubbTokens.heli;
    final label = isError
        ? l.stageTypeGraphSeverityError
        : l.stageTypeGraphSeverityWarning;
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      padding: const EdgeInsets.all(KubbTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KubbChip(
                tone: isError ? KubbChipTone.miss : KubbChipTone.heli,
                label: label,
              ),
              const SizedBox(width: KubbTokens.space2),
              Flexible(
                child: Text(
                  finding.code,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tokens.fgMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(
            finding.message,
            style: TextStyle(fontSize: 13, color: tokens.fg, height: 1.35),
          ),
        ],
      ),
    );
  }
}

// --- Save bar --------------------------------------------------------------

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.state,
    required this.notifier,
    required this.onSave,
  });

  final StageTypeGraphBuilderState state;
  final StageTypeGraphBuilderController notifier;
  final ValueChanged<Map<String, Object?>>? onSave;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: KubbTokens.touchComfortable,
      child: KubbButton(
        variant: KubbButtonVariant.primary,
        size: KubbButtonSize.large,
        // Saving is blocked while there are errors (spec §7: hasTypeErrors
        // gates save/publish).
        onPressed: state.hasErrors || onSave == null
            ? null
            : () => onSave!(notifier.toConfig()),
        child: Text(l.stageTypeGraphSave),
      ),
    );
  }
}

// === KO field-edge dialog ==================================================

/// Granular KO edge kinds offered in the dialog. A Vorrunde never opens this
/// dialog (it has no granular edges), so only the KO kinds appear.
enum _KoEdgeKind { winner, loser, open }

class _KoEdgeDialog extends StatefulWidget {
  const _KoEdgeDialog({required this.fields, this.initial});

  final List<TypeField> fields;
  final FieldEdge? initial;

  @override
  State<_KoEdgeDialog> createState() => _KoEdgeDialogState();
}

class _KoEdgeDialogState extends State<_KoEdgeDialog> {
  late _KoEdgeKind _kind;
  late String _from;
  late String _to;
  OpenEdgeSlot _slot = OpenEdgeSlot.winner;

  @override
  void initState() {
    super.initState();
    final ids = widget.fields.map((f) => f.id).toList();
    _from = ids.isNotEmpty ? ids.first : '';
    _to = ids.length > 1 ? ids[1] : (ids.isNotEmpty ? ids.first : '');
    final initial = widget.initial;
    switch (initial) {
      case WinnerEdge(:final fromFieldId, :final toFieldId):
        _kind = _KoEdgeKind.winner;
        _from = fromFieldId;
        _to = toFieldId;
      case LoserEdge(:final fromFieldId, :final toFieldId):
        _kind = _KoEdgeKind.loser;
        _from = fromFieldId;
        _to = toFieldId;
      case OpenEdge(:final fromFieldId, :final slot):
        _kind = _KoEdgeKind.open;
        _from = fromFieldId;
        _slot = slot;
      case AdvanceAllEdge():
      case null:
        _kind = _KoEdgeKind.winner;
    }
  }

  void _confirm() {
    final FieldEdge edge;
    switch (_kind) {
      case _KoEdgeKind.winner:
        edge = WinnerEdge(fromFieldId: _from, toFieldId: _to);
      case _KoEdgeKind.loser:
        edge = LoserEdge(fromFieldId: _from, toFieldId: _to);
      case _KoEdgeKind.open:
        edge = OpenEdge(fromFieldId: _from, slot: _slot);
    }
    Navigator.of(context).pop(edge);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ids = widget.fields.map((f) => f.id).toList();
    final isOpen = _kind == _KoEdgeKind.open;
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? l.stageTypeGraphAddEdge
            : l.stageTypeGraphConfirm,
      ),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 128).clamp(220.0, 360.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<_KoEdgeKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.stageTypeGraphEdgeKindLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: _KoEdgeKind.winner,
                    child: Text(l.stageTypeGraphEdgeWinner),
                  ),
                  DropdownMenuItem(
                    value: _KoEdgeKind.loser,
                    child: Text(l.stageTypeGraphEdgeLoser),
                  ),
                  DropdownMenuItem(
                    value: _KoEdgeKind.open,
                    child: Text(l.stageTypeGraphEdgeOpen),
                  ),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              if (isOpen) ...[
                const SizedBox(height: KubbTokens.space2),
                Text(
                  l.stageTypeGraphEdgeOpenWarning,
                  style: const TextStyle(
                    color: KubbTokens.heli,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: KubbTokens.space3),
              _fieldDropdown(
                label: l.stageTypeGraphEdgeFromField,
                value: _from,
                ids: ids,
                onChanged: (v) => setState(() => _from = v),
              ),
              if (isOpen) ...[
                const SizedBox(height: KubbTokens.space3),
                DropdownButtonFormField<OpenEdgeSlot>(
                  initialValue: _slot,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l.stageTypeGraphEdgeSlotLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: OpenEdgeSlot.winner,
                      child: Text(l.stageTypeGraphEdgeWinner),
                    ),
                    DropdownMenuItem(
                      value: OpenEdgeSlot.loser,
                      child: Text(l.stageTypeGraphEdgeLoser),
                    ),
                  ],
                  onChanged: (v) => setState(() => _slot = v ?? _slot),
                ),
              ] else ...[
                const SizedBox(height: KubbTokens.space3),
                _fieldDropdown(
                  label: l.stageTypeGraphEdgeToField,
                  value: _to,
                  ids: ids,
                  onChanged: (v) => setState(() => _to = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.stageTypeGraphCancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l.stageTypeGraphConfirm),
        ),
      ],
    );
  }

  Widget _fieldDropdown({
    required String label,
    required String value,
    required List<String> ids,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: ids.contains(value) ? value : (ids.isEmpty ? null : ids.first),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final id in ids)
          DropdownMenuItem<String>(
            value: id,
            child: Text(id, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
