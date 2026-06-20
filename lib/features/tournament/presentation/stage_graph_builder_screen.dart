import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/platform_capabilities.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_binary_choice.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/core/ui/widgets/kubb_labeled_switch.dart';
import 'package:kubb_app/core/ui/widgets/kubb_skeleton.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/ko_round_block.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/save_template_dialog.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Form-based stage-graph builder (ADR-0030 §Editor, guided/composing variant).
///
/// This is the FORM-based layer on top of the same validation engine the later
/// free DAG/canvas editor will use: it renders the in-progress graph as lists
/// (field size, templates, stages, edges) plus a live validation panel and
/// drives every mutation through [stageGraphBuilderProvider]. It deliberately
/// holds NO graph state of its own and never re-implements validation —
/// `state.findings` / `state.hasErrors` are the single source of truth.
/// Editor view selector. Both views share the SAME `stageGraphBuilderProvider`.
enum _EditorView { form, canvas }

/// Standalone stage-graph editor screen. Owns the Scaffold + [KubbAppBar]
/// chrome and delegates the actual editor content to the shared
/// [StageGraphBuilderBody] (embedded: false), so the wizard can host the exact
/// same body inline without duplicating the editor implementation. There is no
/// second editor body — both paths share this one widget and the one
/// `stageGraphBuilderProvider`.
class StageGraphBuilderScreen extends StatelessWidget {
  const StageGraphBuilderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.stageGraphEyebrow,
        title: l.stageGraphTitle,
      ),
      body: const StageGraphBuilderBody(),
    );
  }
}

/// The shared, chrome-free editor body (P2.3). Renders the form/canvas toggle
/// plus the editor content (field-size section, template bar, nodes/edges or
/// empty state, validation panel) WITHOUT any Scaffold / [KubbAppBar] / SafeArea
/// top-chrome of its own. The standalone [StageGraphBuilderScreen] wraps it in
/// the page chrome; the tournament-setup wizard hosts it inline with
/// `embedded: true`.
///
/// It reads/mutates ONLY [stageGraphBuilderProvider] — there is NO second graph
/// state. The [embedded] flag only adjusts insets/scrolling for the inline
/// wizard host; it never forks the editor behaviour or the single source of
/// truth.
class StageGraphBuilderBody extends StatefulWidget {
  const StageGraphBuilderBody({super.key, this.embedded = false});

  /// `true` when hosted inline inside the wizard flow (which already scrolls and
  /// pads). In that case the body must not introduce its own outer scroll view,
  /// so the inline content composes into the wizard's scroll. `false` (default,
  /// standalone screen) keeps the original page layout with the toggle pinned
  /// above an [Expanded] scrolling editor.
  final bool embedded;

  @override
  State<StageGraphBuilderBody> createState() => _StageGraphBuilderBodyState();
}

class _StageGraphBuilderBodyState extends State<StageGraphBuilderBody> {
  _EditorView _view = _EditorView.form;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // P4: the visual drag-and-drop canvas is desktop-only and needs room. On
    // mobile / narrow viewports the guided form editor is used and the toggle
    // is hidden; `effectiveView` clamps a stale `canvas` selection back to form.
    final canvasAvailable = isCanvasAvailable(MediaQuery.sizeOf(context).width);
    final effectiveView = canvasAvailable ? _view : _EditorView.form;
    final toggle = !canvasAvailable
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.fromLTRB(
              widget.embedded ? 0 : KubbTokens.space4,
              widget.embedded ? 0 : KubbTokens.space4,
              widget.embedded ? 0 : KubbTokens.space4,
              0,
            ),
            child: SegmentedButton<_EditorView>(
              segments: [
                ButtonSegment(
                  value: _EditorView.form,
                  icon: const Icon(LucideIcons.list, size: 16),
                  label: Text(l.stageGraphViewForm),
                ),
                ButtonSegment(
                  value: _EditorView.canvas,
                  icon: const Icon(LucideIcons.gitBranch, size: 16),
                  label: Text(l.stageGraphViewCanvas),
                ),
              ],
              selected: <_EditorView>{_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          );

    final body = effectiveView == _EditorView.form
        ? _StageGraphFormView(embedded: widget.embedded)
        : const StageGraphCanvas();

    if (widget.embedded) {
      // Inline host: the wizard already provides the surrounding scroll view, so
      // the form view composes flat (no nested scroll) and the canvas — which
      // needs a bounded height — is given a fixed viewport.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toggle,
          const SizedBox(height: KubbTokens.space4),
          if (effectiveView == _EditorView.form)
            body
          else
            SizedBox(height: 360, child: body),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toggle,
        Expanded(child: body),
      ],
    );
  }
}

/// The original form-based editor body (unchanged behavior), now embedded under
/// the form/canvas toggle. Reads/mutates only `stageGraphBuilderProvider`.
class _StageGraphFormView extends ConsumerWidget {
  const _StageGraphFormView({this.embedded = false});

  /// When embedded in the wizard the surrounding scroll view is provided by the
  /// host, so this view composes flat (no own scroll, no page padding).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stageGraphBuilderProvider);
    final notifier = ref.read(stageGraphBuilderProvider.notifier);

    final isEmpty = s.graph.nodes.isEmpty && s.graph.edges.isEmpty;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The embedded wizard host derives the root capacity from
        // `maxParticipants`, so the field-size input only surfaces in the
        // standalone editor where there is no participant context to seed it.
        if (!embedded) ...[
          _FieldSizeSection(fieldSize: s.fieldSize, notifier: notifier),
          const SizedBox(height: KubbTokens.space6),
        ],
        _TemplateBar(notifier: notifier, graph: s.graph),
        const SizedBox(height: KubbTokens.space6),
        if (isEmpty)
          _EmptyGraphState(notifier: notifier, availablePitches: s.availablePitches)
        else ...[
          _NodesSection(state: s, notifier: notifier),
          const SizedBox(height: KubbTokens.space6),
          _EdgesSection(state: s, notifier: notifier),
        ],
        const SizedBox(height: KubbTokens.space6),
        _ValidationPanel(state: s),
      ],
    );

    // Embedded: the wizard host already scrolls and pads, so compose flat.
    if (embedded) return content;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space5,
        KubbTokens.space4,
        KubbTokens.space8,
      ),
      child: content,
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

// --- Field size ------------------------------------------------------------

class _FieldSizeSection extends StatelessWidget {
  const _FieldSizeSection({required this.fieldSize, required this.notifier});

  final int fieldSize;
  final StageGraphBuilderController notifier;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l.stageGraphFieldSizeSection),
        const SizedBox(height: KubbTokens.space3),
        WizardNumberField(
          label: l.stageGraphFieldSizeLabel,
          value: fieldSize,
          min: 1,
          max: 64,
          onChanged: notifier.setFieldSize,
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          l.stageGraphFieldSizeHint,
          style: TextStyle(fontSize: 12, color: tokens.fgMuted, height: 1.4),
        ),
      ],
    );
  }
}

// --- Template bar ----------------------------------------------------------

class _TemplateBar extends ConsumerStatefulWidget {
  const _TemplateBar({required this.notifier, required this.graph});

  final StageGraphBuilderController notifier;
  final StageGraph graph;

  @override
  ConsumerState<_TemplateBar> createState() => _TemplateBarState();
}

class _TemplateBarState extends ConsumerState<_TemplateBar> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final templatesAsync = ref.watch(stageGraphTemplatesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l.stageGraphTemplatesSection),
        const SizedBox(height: KubbTokens.space3),
        templatesAsync.when(
          loading: () => KubbSkeleton.bar(height: 48),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.stageGraphTemplatesError,
                style: TextStyle(fontSize: 13, color: tokens.fgMuted),
              ),
              const SizedBox(height: KubbTokens.space2),
              SizedBox(
                height: KubbTokens.touchMin,
                child: KubbButton(
                  variant: KubbButtonVariant.secondary,
                  onPressed: () =>
                      ref.invalidate(stageGraphTemplatesProvider),
                  child: Text(l.stageGraphRetry),
                ),
              ),
            ],
          ),
          data: (templates) => _buildData(context, l, tokens, templates),
        ),
      ],
    );
  }

  Widget _buildData(
    BuildContext context,
    AppLocalizations l,
    KubbTokens tokens,
    List<StageGraphTemplate> templates,
  ) {
    // Keep the selection valid against the current list.
    final hasSelection =
        templates.any((t) => t.id == _selectedId) && _selectedId != null;
    final selected = hasSelection ? _selectedId : null;
    final graphEmpty = widget.graph.nodes.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (templates.isEmpty)
          Text(
            l.stageGraphTemplatesEmpty,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l.stageGraphTemplatePickerLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final t in templates)
                DropdownMenuItem<String>(
                  value: t.id,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (t.isSystem) ...[
                        const SizedBox(width: KubbTokens.space2),
                        KubbChip(
                          tone: KubbChipTone.heli,
                          label: l.stageGraphTemplateSystemBadge,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _selectedId = v),
          ),
        const SizedBox(height: KubbTokens.space3),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: KubbTokens.touchMin,
                child: KubbButton(
                  variant: KubbButtonVariant.secondary,
                  onPressed: selected == null
                      ? null
                      : () => _apply(context, l, templates, selected),
                  child: Text(l.stageGraphTemplateApply),
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: SizedBox(
                height: KubbTokens.touchMin,
                child: KubbButton(
                  variant: KubbButtonVariant.primary,
                  onPressed: graphEmpty ? null : () => _save(context, l),
                  child: Text(l.stageGraphTemplateSave),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _apply(
    BuildContext context,
    AppLocalizations l,
    List<StageGraphTemplate> templates,
    String id,
  ) {
    final template = templates.firstWhere((t) => t.id == id);
    widget.notifier.loadFromGraph(template.graph);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.stageGraphTemplateApplied)));
  }

  Future<void> _save(BuildContext context, AppLocalizations l) async {
    final result = await showDialog<SaveTemplateResult>(
      context: context,
      builder: (_) => const SaveTemplateDialog(),
    );
    if (result == null || !context.mounted) return;
    final repo = ref.read(stageGraphTemplatesRepositoryProvider);
    try {
      await repo.saveTemplate(
        name: result.name,
        visibility: result.visibility,
        graph: widget.graph,
      );
      ref.invalidate(stageGraphTemplatesProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.stageGraphTemplateSaved)));
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.stageGraphTemplateSaveError)));
    }
  }
}

// --- Nodes -----------------------------------------------------------------

class _NodesSection extends StatelessWidget {
  const _NodesSection({required this.state, required this.notifier});

  final StageGraphBuilderState state;
  final StageGraphBuilderController notifier;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final nodes = state.graph.nodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: l.stageGraphNodesSection,
          action: _AddIconButton(
            tooltip: l.stageGraphAddNode,
            onPressed: () => _openAddNode(context),
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        for (final node in nodes) ...[
          _NodeTile(
            node: node,
            onEdit: () => _openEditNode(context, node),
            onDelete: () => _confirmDelete(context, node),
          ),
          const SizedBox(height: KubbTokens.space2),
        ],
      ],
    );
  }

  Future<void> _openAddNode(BuildContext context) async {
    final existing = state.graph.nodes.map((n) => n.id).toSet();
    final node = await showDialog<StageNode>(
      context: context,
      builder: (_) => _NodeDialog(
        existingIds: existing,
        availablePitches: state.availablePitches,
      ),
    );
    if (node != null) notifier.addNode(node);
  }

  Future<void> _openEditNode(BuildContext context, StageNode node) async {
    final existing =
        state.graph.nodes.map((n) => n.id).where((id) => id != node.id).toSet();
    final updated = await showDialog<StageNode>(
      context: context,
      builder: (_) => _NodeDialog(
        existingIds: existing,
        initial: node,
        availablePitches: state.availablePitches,
      ),
    );
    if (updated != null) notifier.updateNode(node.id, updated);
  }

  Future<void> _confirmDelete(BuildContext context, StageNode node) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.stageGraphDeleteNode),
        content: Text(l.stageGraphDeleteNodeConfirm(node.id)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.stageGraphCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.stageGraphDeleteNode),
          ),
        ],
      ),
    );
    if (ok ?? false) notifier.removeNode(node.id);
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.onEdit,
    required this.onDelete,
  });

  final StageNode node;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final config = stageNodeConfigSummary(l, node);
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space3,
        KubbTokens.space3,
        KubbTokens.space2,
        KubbTokens.space3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wrap (not Row): on a narrow phone a long type-label chip
                // (e.g. "K.-o. (einfach)") drops below the id instead of
                // overflowing — the chip cannot ellipsize (P4.2).
                Wrap(
                  spacing: KubbTokens.space2,
                  runSpacing: KubbTokens.space1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      node.id,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg,
                      ),
                    ),
                    KubbChip(
                      tone: KubbChipTone.neutral,
                      label: stageNodeTypeLabel(l, node.type),
                    ),
                  ],
                ),
                const SizedBox(height: KubbTokens.space1),
                Text(
                  l.stageGraphSeedingFieldHint(
                    stageSeedingSourceLabel(l, node.seeding),
                  ),
                  style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                ),
                if (config != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    config,
                    style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: l.stageGraphEditNode,
            icon: const Icon(LucideIcons.pencil, size: 18),
            constraints: const BoxConstraints.tightFor(
              width: KubbTokens.touchMin,
              height: KubbTokens.touchMin,
            ),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: l.stageGraphDeleteNode,
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
}

// --- Edges -----------------------------------------------------------------

class _EdgesSection extends StatelessWidget {
  const _EdgesSection({required this.state, required this.notifier});

  final StageGraphBuilderState state;
  final StageGraphBuilderController notifier;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final edges = state.graph.edges;
    final nodes = state.graph.nodes;
    final canAddEdge = nodes.length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: l.stageGraphEdgesSection,
          action: _AddIconButton(
            tooltip: l.stageGraphAddEdge,
            onPressed: canAddEdge ? () => _openAddEdge(context) : null,
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        if (!canAddEdge && edges.isEmpty)
          Text(
            l.stageGraphEdgesNeedNodes,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted),
          )
        else if (edges.isEmpty)
          Text(
            l.stageGraphEdgesEmpty,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted),
          )
        else
          for (var i = 0; i < edges.length; i++) ...[
            _EdgeTile(
              edge: edges[i],
              onEdit: () => _openEditEdge(context, i, edges[i]),
              onDelete: () => notifier.removeEdge(i),
            ),
            const SizedBox(height: KubbTokens.space2),
          ],
        // P3.3: a stage may have MORE than one outgoing edge (winners into the
        // main bracket AND early losers into a side cup). Make that affordance
        // discoverable once edges are possible.
        if (canAddEdge) ...[
          const SizedBox(height: KubbTokens.space2),
          Text(
            l.stageGraphEdgesMultiHint,
            style: TextStyle(fontSize: 12, height: 1.3, color: tokens.fgMuted),
          ),
        ],
      ],
    );
  }

  Future<void> _openAddEdge(BuildContext context) async {
    final edge = await showDialog<StageEdge>(
      context: context,
      builder: (_) => _EdgeDialog(nodes: state.graph.nodes),
    );
    if (edge != null) notifier.addEdge(edge);
  }

  Future<void> _openEditEdge(
    BuildContext context,
    int index,
    StageEdge edge,
  ) async {
    final updated = await showDialog<StageEdge>(
      context: context,
      builder: (_) => _EdgeDialog(nodes: state.graph.nodes, initialEdge: edge),
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

  final StageEdge edge;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
                  '${edge.fromNodeId} → ${edge.toNodeId}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 2),
                // Wrap (not Row): the seeding-mode chip drops below the
                // selector label on a narrow phone instead of overflowing.
                Wrap(
                  spacing: KubbTokens.space2,
                  runSpacing: KubbTokens.space1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      edgeSelectorLabel(l, edge.selector),
                      style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                    ),
                    KubbChip(
                      tone: KubbChipTone.neutral,
                      label: stageSeedingInLabel(l, edge.seedingIn),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.stageGraphEditEdge,
            icon: const Icon(LucideIcons.pencil, size: 18),
            constraints: const BoxConstraints.tightFor(
              width: KubbTokens.touchMin,
              height: KubbTokens.touchMin,
            ),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: l.stageGraphDeleteEdge,
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
}

// --- Validation panel ------------------------------------------------------

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.state});

  final StageGraphBuilderState state;

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
            Expanded(child: _SectionHeader(title: l.stageGraphValidationSection)),
            KubbChip(
              tone: hasErrors ? KubbChipTone.miss : KubbChipTone.hit,
              icon: hasErrors ? LucideIcons.x : LucideIcons.check,
              label:
                  hasErrors ? l.stageGraphNotPlayable : l.stageGraphPlayable,
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space3),
        if (findings.isEmpty)
          Text(
            l.stageGraphNoFindings,
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
    // Errors use the danger/miss surface; warnings use the amber heli tone.
    // No hard-coded colors: both come from KubbTokens / the chip palette.
    final accent = isError ? KubbTokens.miss : KubbTokens.heli;
    final label =
        isError ? l.stageGraphSeverityError : l.stageGraphSeverityWarning;
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

// --- Empty state -----------------------------------------------------------

class _EmptyGraphState extends StatelessWidget {
  const _EmptyGraphState({
    required this.notifier,
    this.availablePitches = const <int>[],
  });

  final StageGraphBuilderController notifier;
  final List<int> availablePitches;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return KubbEmptyState(
      title: l.stageGraphEmptyTitle,
      body: l.stageGraphEmptyBody,
      cta: SizedBox(
        height: KubbTokens.touchComfortable,
        child: KubbButton(
          variant: KubbButtonVariant.primary,
          size: KubbButtonSize.large,
          onPressed: () => _openAddNode(context),
          child: Text(l.stageGraphAddNode),
        ),
      ),
    );
  }

  Future<void> _openAddNode(BuildContext context) async {
    final node = await showDialog<StageNode>(
      context: context,
      builder: (_) => _NodeDialog(
        existingIds: const <String>{},
        availablePitches: availablePitches,
      ),
    );
    if (node != null) notifier.addNode(node);
  }
}

// --- Add-action icon button ------------------------------------------------

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

// === Dialogs ===============================================================

/// Add/edit dialog for a [StageNode]. Builds the node and pops it; the caller
/// routes the result into `addNode` / `updateNode`.
/// Responsive content width for the editor dialogs (ADR-0033 P4.2). Caps at the
/// roomy-desktop 360, but on a phone — where the guided form is the ONLY editor
/// — it shrinks to fit: AlertDialog reserves ~80dp of horizontal inset, so a
/// fixed 360 would overflow a 360dp screen. Clamps to a sane minimum.
double _stageDialogWidth(BuildContext context) {
  // AlertDialog reserves its inset padding (~40dp each side) AND its content
  // padding (~24dp each side); subtract both so the fixed-width content never
  // exceeds the dialog's own constraints on a phone.
  final available = MediaQuery.sizeOf(context).width - 128;
  return available.clamp(220.0, 360.0);
}

/// Muted explanatory caption used inside the node/edge config dialogs to label
/// what a setting means (P3.2 — e.g. "qualifiers count PER GROUP", selector
/// semantics). Plain caption styling from [KubbTokens]; no hardcoded colors.
class _DialogHint extends StatelessWidget {
  const _DialogHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: KubbTokens.space2),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, height: 1.3, color: tokens.fgMuted),
      ),
    );
  }
}

class _NodeDialog extends StatefulWidget {
  const _NodeDialog({
    required this.existingIds,
    this.initial,
    this.availablePitches = const <int>[],
  });

  /// Ids already used by OTHER nodes — used for duplicate detection.
  final Set<String> existingIds;
  final StageNode? initial;

  /// Pitch numbers the organizer can assign per group (pool / round-robin
  /// nodes). Empty when no pitch plan is configured (standalone editor), in
  /// which case the per-group pitch assignment section is hidden.
  final List<int> availablePitches;

  @override
  State<_NodeDialog> createState() => _NodeDialogState();
}

class _NodeDialogState extends State<_NodeDialog> {
  late final TextEditingController _idController;
  late StageNodeType _type;
  late StageSeedingSource _seeding;
  int _groupCount = 4;
  int _qualifierCount = 2;
  int _rounds = 5;
  int _slots = 8;
  // Double-elim only: with bracket reset the lower-bracket winner must beat the
  // upper-bracket winner TWICE (engine reads config['with_reset']).
  bool _withReset = false;
  // P5.5 §4: full per-node KO config (matchup / tiebreak method / per-round
  // format) and pool grouping — written via the kubb_domain stage-node-config
  // writers so the keys stay in lockstep with the engine/summary readers.
  KoMatchup _matchup = KoMatchup.seedHighVsLow;
  KoTiebreakMethod _tiebreak = KoTiebreakMethod.classicKingtossRemoval;
  List<MatchFormatSpec> _koRounds = const <MatchFormatSpec>[];
  PoolGroupingStrategy _grouping = PoolGroupingStrategy.snake;
  int _randomSeed = 0;
  // Per-group pitch assignment (group label → pitch numbers) for pool nodes.
  Map<String, List<int>> _groupPitchAssignment = const <String, List<int>>{};
  String? _idError;

  /// Sensible default for a freshly-added KO round (Bo3, 30 min, no tiebreak),
  /// matching the wizard's bare fallback. Self-contained so the stage builder
  /// stays decoupled from the wizard draft.
  static const MatchFormatSpec _defaultKoRound = MatchFormatSpec(
    setsToWin: 2,
    maxSets: 3,
    timeLimitSeconds: 1800,
    tiebreakEnabled: false,
  );

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _idController = TextEditingController(text: initial?.id ?? '');
    _type = initial?.type ?? StageNodeType.pool;
    _seeding = initial?.seeding ?? StageSeedingSource.asRouted;
    final config = initial?.config ?? const <String, Object?>{};
    _groupCount = _readInt(config['groupCount'], _groupCount);
    _qualifierCount = _readInt(config['qualifierCount'], _qualifierCount);
    _rounds = _readInt(config['rounds'], _rounds);
    _slots = _readInt(config['slots'], _slots);
    _withReset = koWithResetFromConfig(config);
    _matchup = koMatchupFromConfig(config) ?? _matchup;
    _tiebreak = koTiebreakMethodFromConfig(config) ?? _tiebreak;
    final fmts = koRoundFormatsFromConfig(config);
    _koRounds = fmts.isNotEmpty
        ? List<MatchFormatSpec>.of(fmts)
        : <MatchFormatSpec>[_defaultKoRound, _defaultKoRound, _defaultKoRound];
    _grouping = poolGroupingStrategyFromConfig(config) ?? _grouping;
    _randomSeed = poolRandomSeedFromConfig(config) ?? _randomSeed;
    _groupPitchAssignment = <String, List<int>>{
      for (final e in poolGroupPitchAssignmentFromConfig(config).entries)
        e.key: List<int>.of(e.value),
    };
  }

  static int _readInt(Object? value, int fallback) =>
      value is int ? value : fallback;

  /// Grows/shrinks the per-round format list to [count], seeding new rounds with
  /// the default. Keeps existing per-round edits.
  void _setKoRoundCount(int count) {
    setState(() {
      if (count > _koRounds.length) {
        _koRounds = <MatchFormatSpec>[
          ..._koRounds,
          for (var i = _koRounds.length; i < count; i++) _defaultKoRound,
        ];
      } else if (count < _koRounds.length) {
        _koRounds = _koRounds.sublist(0, count);
      }
    });
  }

  /// Group label for index 0..n: 'A', 'B', 'C', …
  static String _groupLabel(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);

  /// Inverse of [_groupLabel]: the 0-based index of a single-letter group
  /// label, or a large sentinel for anything unexpected so stale keys are
  /// dropped on save.
  static int _groupIndexOf(String label) =>
      label.length == 1 ? label.codeUnitAt(0) - 'A'.codeUnitAt(0) : 1 << 30;

  /// Toggles [pitch] in the assignment list of group [label]. A pitch may serve
  /// several groups, so this only flips the one group.
  void _togglePitchForGroup(String label, int pitch) {
    setState(() {
      final next = <String, List<int>>{
        for (final e in _groupPitchAssignment.entries)
          e.key: List<int>.of(e.value),
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
      _groupPitchAssignment = next;
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  void _confirm() {
    final l = AppLocalizations.of(context);
    final id = _idController.text.trim();
    if (id.isEmpty) {
      setState(() => _idError = l.stageGraphErrorIdEmpty);
      return;
    }
    if (widget.existingIds.contains(id)) {
      setState(() => _idError = l.stageGraphErrorIdDuplicate);
      return;
    }
    final node = StageNode(
      id: id,
      type: _type,
      seeding: _seeding,
      config: _buildConfig(),
    );
    Navigator.of(context).pop(node);
  }

  /// Builds the type-relevant config keys via the kubb_domain writers (P5.5).
  Map<String, Object?> _buildConfig() {
    switch (_type) {
      case StageNodeType.pool:
      case StageNodeType.roundRobin:
        return writePoolNodeConfig(
          groupCount: _groupCount,
          qualifierCount: _qualifierCount,
          strategy: _grouping,
          // The seed only matters for the random strategy; drop it otherwise.
          randomSeed:
              _grouping == PoolGroupingStrategy.random ? _randomSeed : null,
          // Only keep assignments for groups that still exist (group count may
          // have shrunk after an assignment was made).
          groupPitchAssignment: <String, List<int>>{
            for (final e in _groupPitchAssignment.entries)
              if (_groupIndexOf(e.key) < _groupCount && e.value.isNotEmpty)
                e.key: e.value,
          },
        );
      case StageNodeType.swiss:
        return <String, Object?>{'rounds': _rounds};
      case StageNodeType.shootoutQuali:
        return <String, Object?>{'slots': _slots};
      case StageNodeType.doubleElim:
        return writeKoNodeConfig(
          matchup: _matchup,
          tiebreakMethod: _tiebreak,
          withReset: _withReset,
          roundFormats: _koRounds,
        );
      case StageNodeType.singleElim:
      case StageNodeType.consolation:
        return writeKoNodeConfig(
          matchup: _matchup,
          tiebreakMethod: _tiebreak,
          roundFormats: _koRounds,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isEdit = widget.initial != null;
    return AlertDialog(
      title: Text(isEdit ? l.stageGraphEditNode : l.stageGraphAddNode),
      content: SizedBox(
        width: _stageDialogWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('stageGraphNodeIdField'),
                controller: _idController,
                // The id is the edge anchor: renaming it in edit mode would
                // leave incident edges pointing at the old id (orphans). Lock
                // it on edit so ids stay stable; create a new node to change it.
                readOnly: isEdit,
                decoration: InputDecoration(
                  labelText: l.stageGraphFieldId,
                  errorText: _idError,
                  helperText: isEdit ? l.stageGraphFieldIdLockedHint : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_idError != null) setState(() => _idError = null);
                },
              ),
              const SizedBox(height: KubbTokens.space3),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<StageNodeType>(
                      initialValue: _type,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l.stageGraphFieldType,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final t in selectableStageNodeTypes)
                          DropdownMenuItem<StageNodeType>(
                            value: t,
                            child: Text(stageNodeTypeLabel(l, t)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? _type),
                    ),
                  ),
                  InfoIconButton(
                    title: l.stageGraphNodeTypeInfoTitle,
                    message: stageNodeTypeInfo(l, _type),
                  ),
                ],
              ),
              const SizedBox(height: KubbTokens.space3),
              DropdownButtonFormField<StageSeedingSource>(
                initialValue: _seeding,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.stageGraphFieldSeeding,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final src in StageSeedingSource.values)
                    DropdownMenuItem<StageSeedingSource>(
                      value: src,
                      child: Text(stageSeedingSourceLabel(l, src)),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _seeding = v ?? _seeding),
              ),
              ..._configFields(l),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.stageGraphCancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l.stageGraphConfirm),
        ),
      ],
    );
  }

  List<Widget> _configFields(AppLocalizations l) {
    final fields = <Widget>[];
    switch (_type) {
      case StageNodeType.pool:
      case StageNodeType.roundRobin:
        fields
          ..add(WizardNumberField(
            label: l.stageGraphConfigGroupCount,
            value: _groupCount,
            min: 1,
            max: 32,
            onChanged: (v) => setState(() => _groupCount = v),
          ))
          ..add(_DialogHint(l.stageGraphConfigGroupCountHint))
          ..add(WizardNumberField(
            label: l.stageGraphConfigQualifierCount,
            value: _qualifierCount,
            min: 1,
            max: 64,
            onChanged: (v) => setState(() => _qualifierCount = v),
          ))
          // P3.2: the recurring confusion — qualifiers are PER GROUP, not a
          // total across all groups. Spell it out at the field.
          ..add(_DialogHint(l.stageGraphConfigQualifierHint))
          // P5.5: how participants are distributed across the groups.
          ..add(Row(
            children: [
              Expanded(child: _fieldLabel(l.tournamentWizardPoolStrategyLabel)),
              InfoIconButton(
                title: l.stageGraphGroupingInfoTitle,
                message: _groupingInfo(l, _grouping),
              ),
            ],
          ))
          ..add(DropdownButtonFormField<PoolGroupingStrategy>(
            initialValue: _grouping,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final s in PoolGroupingStrategy.values)
                DropdownMenuItem<PoolGroupingStrategy>(
                  value: s,
                  child: Text(_groupingLabel(l, s)),
                ),
            ],
            onChanged: (v) => setState(() => _grouping = v ?? _grouping),
          ));
        if (_grouping == PoolGroupingStrategy.random) {
          fields.add(WizardNumberField(
            label: l.stageGraphConfigRandomSeed,
            value: _randomSeed,
            min: 0,
            max: 999999,
            onChanged: (v) => setState(() => _randomSeed = v),
          ));
        }
        final pitchSection = _pitchAssignmentField(l);
        if (pitchSection != null) fields.add(pitchSection);
      case StageNodeType.swiss:
        fields
          ..add(WizardNumberField(
            label: l.stageGraphConfigRounds,
            value: _rounds,
            min: 1,
            max: 20,
            onChanged: (v) => setState(() => _rounds = v),
          ))
          ..add(_DialogHint(l.stageGraphConfigSwissHint));
      case StageNodeType.shootoutQuali:
        fields.add(WizardNumberField(
          label: l.stageGraphConfigSlots,
          value: _slots,
          min: 1,
          max: 64,
          onChanged: (v) => setState(() => _slots = v),
        ));
      case StageNodeType.doubleElim:
        fields.addAll(_koConfigFields(l, includeReset: true));
      case StageNodeType.singleElim:
      case StageNodeType.consolation:
        fields.addAll(_koConfigFields(l, includeReset: false));
    }
    return [
      for (final field in fields) ...[
        const SizedBox(height: KubbTokens.space3),
        field,
      ],
    ];
  }

  /// "Pitch-Zuteilung pro Gruppe" — only built when pitches are available and
  /// the group count is sane. For each group A..N the organizer multi-selects
  /// the pitch numbers serving that group; a pitch may serve several groups.
  /// Returns null (section omitted, no error) when there are no pitches to
  /// assign — e.g. the standalone editor with no pitch-plan context.
  Widget? _pitchAssignmentField(AppLocalizations l) {
    final pitches = widget.availablePitches;
    if (pitches.isEmpty || _groupCount < 1) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(l.tournamentWizardPoolPitchAssignmentLabel),
        _DialogHint(l.tournamentWizardPoolPitchAssignmentHint),
        for (var g = 0; g < _groupCount; g++) ...[
          const SizedBox(height: KubbTokens.space3),
          Builder(
            builder: (context) {
              final tokens = Theme.of(context).extension<KubbTokens>()!;
              final label = _groupLabel(g);
              final assigned =
                  _groupPitchAssignment[label] ?? const <int>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.tournamentWizardPoolGroupLabel(label),
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
                          onTap: () => _togglePitchForGroup(label, pitch),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  /// Full per-node KO config (P5.5 §4): matchup, tiebreak method, optional
  /// bracket reset, and a per-round format list (reusing the classic
  /// [KoRoundBlock] editor). Round count is explicit because a stage KO node's
  /// size depends on routing and is not known at config time; the engine reads
  /// `ko_round_formats[round-1]` with a fallback beyond the list.
  List<Widget> _koConfigFields(AppLocalizations l, {required bool includeReset}) {
    return <Widget>[
      if (includeReset)
        KubbLabeledSwitch(
          title: l.stageGraphConfigWithReset,
          subtitle: l.stageGraphConfigWithResetHint,
          value: _withReset,
          onChanged: (v) => setState(() => _withReset = v),
        ),
      _fieldLabel(l.tournamentWizardKoMatchupLabel),
      KubbBinaryChoice<KoMatchup>(
        selected: _matchup,
        onChanged: (v) => setState(() => _matchup = v),
        options: <KubbChoiceOption<KoMatchup>>[
          KubbChoiceOption<KoMatchup>(
            value: KoMatchup.seedHighVsLow,
            title: l.tournamentWizardKoMatchupHighLow,
          ),
          KubbChoiceOption<KoMatchup>(
            value: KoMatchup.oneVsTwo,
            title: l.tournamentWizardKoMatchupOneTwo,
          ),
        ],
      ),
      _fieldLabel(l.tournamentWizardKoTiebreakMethodLabel),
      KubbBinaryChoice<KoTiebreakMethod>(
        selected: _tiebreak,
        onChanged: (v) => setState(() => _tiebreak = v),
        options: <KubbChoiceOption<KoTiebreakMethod>>[
          KubbChoiceOption<KoTiebreakMethod>(
            value: KoTiebreakMethod.classicKingtossRemoval,
            title: l.tournamentWizardKoTiebreakClassic,
          ),
          KubbChoiceOption<KoTiebreakMethod>(
            value: KoTiebreakMethod.mightyFinisherShootout,
            title: l.tournamentWizardKoTiebreakMighty,
          ),
        ],
      ),
      WizardNumberField(
        label: l.stageGraphConfigKoRoundCount,
        value: _koRounds.length,
        min: 1,
        max: 8,
        onChanged: _setKoRoundCount,
      ),
      for (var i = 0; i < _koRounds.length; i++)
        KoRoundBlock(
          key: ValueKey<int>(i),
          title: l.stageGraphConfigKoRoundTitle((i + 1).toString()),
          spec: _koRounds[i],
          onChanged: (spec) => setState(() {
            _koRounds = <MatchFormatSpec>[..._koRounds]..[i] = spec;
          }),
        ),
    ];
  }

  Widget _fieldLabel(String text) => Builder(
        builder: (context) {
          final tokens = Theme.of(context).extension<KubbTokens>()!;
          return Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: tokens.fgMuted,
            ),
          );
        },
      );

  static String _groupingLabel(AppLocalizations l, PoolGroupingStrategy s) =>
      switch (s) {
        PoolGroupingStrategy.snake => l.tournamentWizardPoolStrategySnake,
        PoolGroupingStrategy.seeded => l.tournamentWizardPoolStrategySeeded,
        PoolGroupingStrategy.random => l.tournamentWizardPoolStrategyRandom,
      };

  static String _groupingInfo(AppLocalizations l, PoolGroupingStrategy s) =>
      switch (s) {
        PoolGroupingStrategy.snake => l.stageGraphGroupingInfoSnake,
        PoolGroupingStrategy.seeded => l.stageGraphGroupingInfoSeeded,
        PoolGroupingStrategy.random => l.stageGraphGroupingInfoRandom,
      };
}

/// Selector kinds offered in the edge dialog (parallel to [EdgeSelector]).
enum _SelectorKind { topK, ranks, losersOfRounds, winners, nonQualifiers }

/// Add/edit dialog for a [StageEdge].
class _EdgeDialog extends StatefulWidget {
  const _EdgeDialog({
    required this.nodes,
    this.initialFrom,
    this.initialTo,
    this.initialEdge,
  });

  final List<StageNode> nodes;

  /// Optional pre-selected `from` node id (L4b-2 gesture seed). When null the
  /// dialog keeps its original default (`nodes.first`). Additive & optional —
  /// the toolbar / form-view call sites stay unchanged. Ignored when
  /// [initialEdge] is given (the edge carries its own `from`).
  final String? initialFrom;

  /// Optional pre-selected `to` node id (L4b-2 gesture seed). When null the
  /// dialog keeps its original default (`nodes[1]` / `nodes.first`). Ignored
  /// when [initialEdge] is given.
  final String? initialTo;

  /// Existing edge to edit. When non-null every field (from, to, selector kind
  /// and its parameters, seeding) is pre-filled from it and the dialog runs in
  /// edit mode (different title). When null the dialog runs in add mode.
  final StageEdge? initialEdge;

  @override
  State<_EdgeDialog> createState() => _EdgeDialogState();
}

class _EdgeDialogState extends State<_EdgeDialog> {
  late String _from;
  late String _to;
  _SelectorKind _kind = _SelectorKind.topK;
  StageSeedingIn _seedingIn = StageSeedingIn.orderPreserving;
  int _k = 2;
  int _rankFrom = 1;
  int _rankTo = 2;
  late final TextEditingController _roundsController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ids = widget.nodes.map((n) => n.id).toSet();
    final edit = widget.initialEdge;
    // Use the optional gesture seed when it points at a known node; otherwise
    // fall back to the UNCHANGED default selection (nodes.first / nodes[1]).
    // In edit mode the existing edge's endpoints take precedence.
    final seedFrom = edit?.fromNodeId ?? widget.initialFrom;
    final seedTo = edit?.toNodeId ?? widget.initialTo;
    _from = (seedFrom != null && ids.contains(seedFrom))
        ? seedFrom
        : widget.nodes.first.id;
    _to = (seedTo != null && ids.contains(seedTo))
        ? seedTo
        : (widget.nodes.length > 1
            ? widget.nodes[1].id
            : widget.nodes.first.id);
    var roundsText = '1';
    if (edit != null) {
      _seedingIn = edit.seedingIn;
      switch (edit.selector) {
        case final TopK s:
          _kind = _SelectorKind.topK;
          _k = s.k;
        case final Ranks s:
          _kind = _SelectorKind.ranks;
          _rankFrom = s.from;
          _rankTo = s.to;
        case final LosersOfRounds s:
          _kind = _SelectorKind.losersOfRounds;
          final sorted = s.rounds.toList()..sort();
          roundsText = sorted.join(', ');
        case Winners():
          _kind = _SelectorKind.winners;
        case NonQualifiers():
          _kind = _SelectorKind.nonQualifiers;
      }
    }
    _roundsController = TextEditingController(text: roundsText);
  }

  @override
  void dispose() {
    _roundsController.dispose();
    super.dispose();
  }

  void _confirm() {
    final l = AppLocalizations.of(context);
    if (_from == _to) {
      setState(() => _error = l.stageGraphErrorSameNode);
      return;
    }
    final EdgeSelector selector;
    switch (_kind) {
      case _SelectorKind.topK:
        selector = TopK(_k);
      case _SelectorKind.ranks:
        if (_rankFrom > _rankTo) {
          setState(() => _error = l.stageGraphErrorRankOrder);
          return;
        }
        selector = Ranks(_rankFrom, _rankTo);
      case _SelectorKind.losersOfRounds:
        final rounds = _parseRounds(_roundsController.text);
        if (rounds.isEmpty) {
          setState(() => _error = l.stageGraphErrorRoundsEmpty);
          return;
        }
        selector = LosersOfRounds(rounds);
      case _SelectorKind.winners:
        selector = const Winners();
      case _SelectorKind.nonQualifiers:
        selector = const NonQualifiers();
    }
    Navigator.of(context).pop(
      StageEdge(
        fromNodeId: _from,
        toNodeId: _to,
        selector: selector,
        seedingIn: _seedingIn,
      ),
    );
  }

  /// Parses a comma-separated list of positive ints into a set.
  static Set<int> _parseRounds(String raw) {
    final result = <int>{};
    for (final part in raw.split(',')) {
      final n = int.tryParse(part.trim());
      if (n != null && n >= 1) result.add(n);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.initialEdge == null
            ? l.stageGraphAddEdge
            : l.stageGraphEditEdge,
      ),
      content: SizedBox(
        width: _stageDialogWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _nodeDropdown(
                label: l.stageGraphEdgeFrom,
                value: _from,
                onChanged: (v) => setState(() {
                  _from = v;
                  _error = null;
                }),
              ),
              const SizedBox(height: KubbTokens.space3),
              _nodeDropdown(
                label: l.stageGraphEdgeTo,
                value: _to,
                onChanged: (v) => setState(() {
                  _to = v;
                  _error = null;
                }),
              ),
              const SizedBox(height: KubbTokens.space3),
              DropdownButtonFormField<_SelectorKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.stageGraphEdgeSelectorLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final k in _SelectorKind.values)
                    DropdownMenuItem<_SelectorKind>(
                      value: k,
                      child: Text(_selectorKindLabel(l, k)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _kind = v ?? _kind;
                  _error = null;
                }),
              ),
              // P3.2: explain what the chosen selector actually forwards.
              _DialogHint(_selectorKindHint(l, _kind)),
              ..._selectorParams(l),
              const SizedBox(height: KubbTokens.space3),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<StageSeedingIn>(
                      initialValue: _seedingIn,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l.stageGraphEdgeSeedingInLabel,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final si in StageSeedingIn.values)
                          DropdownMenuItem<StageSeedingIn>(
                            value: si,
                            child: Text(stageSeedingInLabel(l, si)),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _seedingIn = v ?? _seedingIn),
                    ),
                  ),
                  InfoIconButton(
                    title: l.stageGraphSeedingInInfoTitle,
                    message: stageSeedingInInfo(l, _seedingIn),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: KubbTokens.space3),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: KubbTokens.miss,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.stageGraphCancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l.stageGraphConfirm),
        ),
      ],
    );
  }

  Widget _nodeDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final n in widget.nodes)
          DropdownMenuItem<String>(
            value: n.id,
            child: Text(n.id, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  List<Widget> _selectorParams(AppLocalizations l) {
    switch (_kind) {
      case _SelectorKind.topK:
        return [
          const SizedBox(height: KubbTokens.space3),
          WizardNumberField(
            label: l.stageGraphSelectorK,
            value: _k,
            min: 1,
            max: 64,
            onChanged: (v) => setState(() => _k = v),
          ),
        ];
      case _SelectorKind.ranks:
        return [
          const SizedBox(height: KubbTokens.space3),
          WizardNumberField(
            label: l.stageGraphSelectorRankFrom,
            value: _rankFrom,
            min: 1,
            max: 64,
            onChanged: (v) => setState(() => _rankFrom = v),
          ),
          const SizedBox(height: KubbTokens.space3),
          WizardNumberField(
            label: l.stageGraphSelectorRankTo,
            value: _rankTo,
            min: 1,
            max: 64,
            onChanged: (v) => setState(() => _rankTo = v),
          ),
        ];
      case _SelectorKind.losersOfRounds:
        return [
          const SizedBox(height: KubbTokens.space3),
          TextField(
            controller: _roundsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l.stageGraphSelectorRoundsLabel,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ];
      case _SelectorKind.winners:
      case _SelectorKind.nonQualifiers:
        return const <Widget>[];
    }
  }

  String _selectorKindLabel(AppLocalizations l, _SelectorKind kind) {
    switch (kind) {
      case _SelectorKind.topK:
        return l.stageGraphSelectorK;
      case _SelectorKind.ranks:
        return '${l.stageGraphSelectorRankFrom} / ${l.stageGraphSelectorRankTo}';
      case _SelectorKind.losersOfRounds:
        return l.stageGraphSelectorRoundsLabel;
      case _SelectorKind.winners:
        return l.stageGraphSelectorWinners;
      case _SelectorKind.nonQualifiers:
        return l.stageGraphSelectorNonQualifiers;
    }
  }

  /// One-line explanation of what a selector forwards (P3.2). Makes the
  /// side-cup feed (LosersOfRounds) discoverable.
  String _selectorKindHint(AppLocalizations l, _SelectorKind kind) {
    switch (kind) {
      case _SelectorKind.topK:
        return l.stageGraphSelectorHintTopK;
      case _SelectorKind.ranks:
        return l.stageGraphSelectorHintRanks;
      case _SelectorKind.losersOfRounds:
        return l.stageGraphSelectorHintLosers;
      case _SelectorKind.winners:
        return l.stageGraphSelectorHintWinners;
      case _SelectorKind.nonQualifiers:
        return l.stageGraphSelectorHintNonQualifiers;
    }
  }
}


// === Shared editor entry points (reused by the canvas view) ================
//
// Thin wrappers that expose the EXISTING dialogs and the existing validation
// panel to the alternative canvas view (`stage_graph_canvas.dart`) WITHOUT
// duplicating their behavior or signatures. The dialogs/panel themselves stay
// private; these helpers are the single, additive seam (ADR-0030 §Editor).

/// Opens the existing add-node dialog and returns the built [StageNode], or
/// `null` if cancelled. [existingIds] are the ids already used by OTHER nodes.
Future<StageNode?> showStageNodeAddDialog(
  BuildContext context, {
  required Set<String> existingIds,
  List<int> availablePitches = const <int>[],
}) =>
    showDialog<StageNode>(
      context: context,
      builder: (_) => _NodeDialog(
        existingIds: existingIds,
        availablePitches: availablePitches,
      ),
    );

/// Opens the existing edit-node dialog seeded with [initial] and returns the
/// updated [StageNode], or `null` if cancelled. [existingIds] are the ids of
/// the OTHER nodes (for duplicate detection); the id field stays locked on edit.
Future<StageNode?> showStageNodeEditDialog(
  BuildContext context, {
  required StageNode initial,
  required Set<String> existingIds,
  List<int> availablePitches = const <int>[],
}) =>
    showDialog<StageNode>(
      context: context,
      builder: (_) => _NodeDialog(
        existingIds: existingIds,
        initial: initial,
        availablePitches: availablePitches,
      ),
    );

/// Opens the existing add-edge dialog and returns the built [StageEdge], or
/// `null` if cancelled. [initialFrom]/[initialTo] are OPTIONAL gesture seeds
/// (L4b-2 port->port drag): when given (and pointing at known nodes) the dialog
/// pre-selects them; when omitted the dialog keeps its original default
/// selection, so the toolbar/form-view call sites stay functionally identical.
Future<StageEdge?> showStageEdgeAddDialog(
  BuildContext context, {
  required List<StageNode> nodes,
  String? initialFrom,
  String? initialTo,
}) =>
    showDialog<StageEdge>(
      context: context,
      builder: (_) => _EdgeDialog(
        nodes: nodes,
        initialFrom: initialFrom,
        initialTo: initialTo,
      ),
    );

/// Opens the add-edge dialog seeded with the existing [initial] edge so every
/// field (from, to, selector + parameters, seeding) is pre-filled, and returns
/// the updated [StageEdge], or `null` if cancelled.
Future<StageEdge?> showStageEdgeEditDialog(
  BuildContext context, {
  required List<StageNode> nodes,
  required StageEdge initial,
}) =>
    showDialog<StageEdge>(
      context: context,
      builder: (_) => _EdgeDialog(nodes: nodes, initialEdge: initial),
    );

/// Builds the existing validation panel for a given builder [state]. Reuses the
/// single findings renderer — no second formatter.
Widget buildStageValidationPanel(StageGraphBuilderState state) =>
    _ValidationPanel(state: state);

// === Localized label mappers ==============================================

/// Stage types offered when adding a new node. A curated subset of
/// [StageNodeType.values]: round-robin and shoot-out-quali stay in the model
/// (existing graphs and templates still render them via [stageNodeTypeLabel])
/// but are not picked for fresh stages.
const List<StageNodeType> selectableStageNodeTypes = [
  StageNodeType.pool,
  StageNodeType.swiss,
  StageNodeType.singleElim,
  StageNodeType.doubleElim,
  StageNodeType.consolation,
];

/// Localized label for a [StageNodeType].
String stageNodeTypeLabel(AppLocalizations l, StageNodeType type) {
  switch (type) {
    case StageNodeType.pool:
      return l.stageGraphNodeTypePool;
    case StageNodeType.roundRobin:
      return l.stageGraphNodeTypeRoundRobin;
    case StageNodeType.swiss:
      return l.stageGraphNodeTypeSwiss;
    case StageNodeType.singleElim:
      return l.stageGraphNodeTypeSingleElim;
    case StageNodeType.doubleElim:
      return l.stageGraphNodeTypeDoubleElim;
    case StageNodeType.consolation:
      return l.stageGraphNodeTypeConsolation;
    case StageNodeType.shootoutQuali:
      return l.stageGraphNodeTypeShootoutQuali;
  }
}

/// Localized explainer text for a [StageNodeType] — what the type does to the
/// matches. Surfaced via the type-picker info button.
String stageNodeTypeInfo(AppLocalizations l, StageNodeType type) {
  switch (type) {
    case StageNodeType.pool:
      return l.stageGraphNodeTypeInfoPool;
    case StageNodeType.roundRobin:
      return l.stageGraphNodeTypeInfoRoundRobin;
    case StageNodeType.swiss:
      return l.stageGraphNodeTypeInfoSwiss;
    case StageNodeType.singleElim:
      return l.stageGraphNodeTypeInfoSingleElim;
    case StageNodeType.doubleElim:
      return l.stageGraphNodeTypeInfoDoubleElim;
    case StageNodeType.consolation:
      return l.stageGraphNodeTypeInfoConsolation;
    case StageNodeType.shootoutQuali:
      return l.stageGraphNodeTypeInfoShootoutQuali;
  }
}

/// Localized explainer text for a [StageSeedingIn] — what the seeding mode does
/// to the participants entering the target stage. Surfaced via the edge-dialog
/// info button.
String stageSeedingInInfo(AppLocalizations l, StageSeedingIn si) {
  switch (si) {
    case StageSeedingIn.orderPreserving:
      return l.stageGraphSeedingInInfoOrderPreserving;
    case StageSeedingIn.reseedBySourceRank:
      return l.stageGraphSeedingInInfoReseedBySourceRank;
    case StageSeedingIn.manual:
      return l.stageGraphSeedingInInfoManual;
  }
}

/// Localized label for a [StageSeedingSource].
String stageSeedingSourceLabel(AppLocalizations l, StageSeedingSource src) {
  switch (src) {
    case StageSeedingSource.fromElo:
      return l.stageGraphSeedingFromElo;
    case StageSeedingSource.fromPrevRanking:
      return l.stageGraphSeedingFromPrevRanking;
    case StageSeedingSource.manual:
      return l.stageGraphSeedingManual;
    case StageSeedingSource.asRouted:
      return l.stageGraphSeedingAsRouted;
  }
}

/// Localized label for a [StageSeedingIn].
String stageSeedingInLabel(AppLocalizations l, StageSeedingIn si) {
  switch (si) {
    case StageSeedingIn.orderPreserving:
      return l.stageGraphSeedingInOrderPreserving;
    case StageSeedingIn.reseedBySourceRank:
      return l.stageGraphSeedingInReseedBySourceRank;
    case StageSeedingIn.manual:
      return l.stageGraphSeedingInManual;
  }
}

/// Localized short label for an [EdgeSelector].
String edgeSelectorLabel(AppLocalizations l, EdgeSelector selector) {
  switch (selector) {
    case TopK(:final k):
      return l.stageGraphSelectorTopK(k);
    case Ranks(:final from, :final to):
      return l.stageGraphSelectorRanks(from, to);
    case LosersOfRounds(:final rounds):
      final sorted = rounds.toList()..sort();
      return l.stageGraphSelectorLosers(sorted.join(', '));
    case Winners():
      return l.stageGraphSelectorWinners;
    case NonQualifiers():
      return l.stageGraphSelectorNonQualifiers;
  }
}

/// Compact config summary for a node tile (only present keys).
/// Localized one-line summary of a stage node's configured fields, or null when
/// nothing is set. Shared by the node tile and the wizard summary (§8: no silent
/// omission — every configured key surfaces) so both render identically.
String? stageNodeConfigSummary(AppLocalizations l, StageNode node) {
  final parts = <String>[];
  final cfg = node.config;
  final g = cfg['groupCount'];
  if (g is int) parts.add('${l.stageGraphConfigGroupCount}: $g');
  final q = cfg['qualifierCount'];
  if (q is int) parts.add('${l.stageGraphConfigQualifierCount}: $q');
  // P5.5: pool grouping strategy.
  final grouping = poolGroupingStrategyFromConfig(cfg);
  if (grouping != null) {
    parts.add(switch (grouping) {
      PoolGroupingStrategy.snake => l.tournamentWizardPoolStrategySnake,
      PoolGroupingStrategy.seeded => l.tournamentWizardPoolStrategySeeded,
      PoolGroupingStrategy.random => l.tournamentWizardPoolStrategyRandom,
    });
  }
  final pitchAssignment = poolGroupPitchAssignmentFromConfig(cfg);
  if (pitchAssignment.isNotEmpty) {
    parts.add(l.stageGraphConfigGroupPitchSummary(pitchAssignment.length));
  }
  final r = cfg['rounds'];
  if (r is int) parts.add('${l.stageGraphConfigRounds}: $r');
  final s = cfg['slots'];
  if (s is int) parts.add('${l.stageGraphConfigSlots}: $s');
  if (koWithResetFromConfig(cfg)) parts.add(l.stageGraphConfigWithReset);
  // P5.5: full KO config — matchup, tiebreak method, per-round count.
  final matchup = koMatchupFromConfig(cfg);
  if (matchup != null) {
    parts.add(switch (matchup) {
      KoMatchup.seedHighVsLow => l.tournamentWizardKoMatchupHighLow,
      KoMatchup.oneVsTwo => l.tournamentWizardKoMatchupOneTwo,
    });
  }
  final tiebreak = koTiebreakMethodFromConfig(cfg);
  if (tiebreak != null) {
    parts.add(switch (tiebreak) {
      KoTiebreakMethod.classicKingtossRemoval =>
        l.tournamentWizardKoTiebreakClassic,
      KoTiebreakMethod.mightyFinisherShootout =>
        l.tournamentWizardKoTiebreakMighty,
    });
  }
  final koRounds = koRoundFormatsFromConfig(cfg);
  if (koRounds.isNotEmpty) {
    parts.add('${l.stageGraphConfigKoRoundCount}: ${koRounds.length}');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Compact multi-select chip for a single pitch number in the per-group
/// pitch-assignment grid of the pool node dialog. Mirrors the classic pool
/// step's chip (numeric, dense) but stays local to this screen.
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
