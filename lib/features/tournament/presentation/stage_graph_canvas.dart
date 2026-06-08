import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_canvas_layout.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/stage_graph_edge_painter.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Visual canvas view of the in-progress stage graph (ADR-0030 §Editor,
/// Lage 4 — freier DAG-Editor / Offener Punkt 5 Editor-UX).
///
/// This is the SECOND view onto the very same `stageGraphBuilderProvider`
/// (alongside the form-based `StageGraphBuilderScreen`): it renders each node as
/// a positioned card and each edge as a `CustomPaint` arrow, supports dragging
/// cards, and routes every mutation through the EXISTING dialogs + controller.
/// It holds NO graph state of its own; only the client-side position map lives
/// here (`stageGraphCanvasLayoutProvider`). Validation is read from
/// `state.findings` / `state.hasErrors` — the single source of truth.
///
/// SCOPE NOTE (L4b-2): gesture-based port->port edge DRAWING is explicitly NOT
/// part of this phase. Edges are created only via the existing `_EdgeDialog`
/// (reached through `showStageEdgeAddDialog`). Pan/zoom via `InteractiveViewer`
/// is a nice-to-have, not an acceptance criterion.
class StageGraphCanvas extends ConsumerWidget {
  const StageGraphCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final state = ref.watch(stageGraphBuilderProvider);
    final controller = ref.read(stageGraphBuilderProvider.notifier);

    // Reconcile the position map with the current graph after each build:
    // new nodes get an auto-layout slot, removed nodes drop out, manually
    // dragged nodes keep their position. Deferred to post-frame so we never
    // mutate a provider during build.
    final graph = state.graph;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stageGraphCanvasLayoutProvider.notifier).syncWithGraph(graph);
    });

    final layout = ref.watch(stageGraphCanvasLayoutProvider);
    final positions = layout.isEmpty ? autoLayout(graph) : layout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CanvasToolbar(state: state, controller: controller),
        Expanded(
          child: graph.nodes.isEmpty
              ? _CanvasEmpty(message: l.stageGraphCanvasEmpty)
              : _CanvasSurface(
                  state: state,
                  controller: controller,
                  positions: positions,
                  tokens: tokens,
                  l: l,
                ),
        ),
        // Reuse the existing validation panel / findings renderer.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KubbTokens.space4,
            KubbTokens.space3,
            KubbTokens.space4,
            KubbTokens.space4,
          ),
          child: buildStageValidationPanel(state),
        ),
      ],
    );
  }
}

// --- Toolbar (+ Stufe / + Kante) -------------------------------------------

class _CanvasToolbar extends StatelessWidget {
  const _CanvasToolbar({required this.state, required this.controller});

  final StageGraphBuilderState state;
  final StageGraphBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final canAddEdge = state.graph.nodes.length >= 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space3,
        KubbTokens.space4,
        KubbTokens.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: KubbTokens.touchMin,
              child: OutlinedButton.icon(
                key: const Key('stageCanvasAddNode'),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.stageGraphAddNode),
                onPressed: () => _addNode(context),
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: SizedBox(
              height: KubbTokens.touchMin,
              child: OutlinedButton.icon(
                key: const Key('stageCanvasAddEdge'),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.stageGraphAddEdge),
                onPressed: canAddEdge ? () => _addEdge(context) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addNode(BuildContext context) async {
    final existing = state.graph.nodes.map((n) => n.id).toSet();
    final node = await showStageNodeAddDialog(context, existingIds: existing);
    if (node != null) controller.addNode(node);
  }

  Future<void> _addEdge(BuildContext context) async {
    final edge = await showStageEdgeAddDialog(
      context,
      nodes: state.graph.nodes,
    );
    if (edge != null) controller.addEdge(edge);
  }
}

// --- Canvas surface (edges painter under positioned cards) -----------------

class _CanvasSurface extends ConsumerWidget {
  const _CanvasSurface({
    required this.state,
    required this.controller,
    required this.positions,
    required this.tokens,
    required this.l,
  });

  final StageGraphBuilderState state;
  final StageGraphBuilderController controller;
  final Map<String, Offset> positions;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = state.graph;

    // Canvas extent: enough to hold the rightmost / bottommost card.
    var maxX = 0.0;
    var maxY = 0.0;
    for (final pos in positions.values) {
      maxX = pos.dx > maxX ? pos.dx : maxX;
      maxY = pos.dy > maxY ? pos.dy : maxY;
    }
    final canvasSize = Size(
      maxX + kStageCanvasNodeWidth + kStageCanvasPadding,
      maxY + kStageCanvasNodeHeight + kStageCanvasPadding,
    );

    // Two-axis scrolling keeps card drag deltas exact (1:1) and avoids the
    // gesture-coordinate scaling an InteractiveViewer would impose. Pan/zoom
    // was a nice-to-have only (ADR-0030 §Editor, not an acceptance criterion).
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: canvasSize.width,
          height: canvasSize.height,
          child: Stack(
            children: [
              // Edges live UNDER the cards so cards stay tappable/draggable.
              Positioned.fill(
                child: CustomPaint(
                  key: const Key('stageCanvasEdgePainter'),
                  painter: StageGraphEdgePainter(
                    edges: graph.edges,
                    positions: positions,
                    lineColor: tokens.lineStrong,
                    labelColor: tokens.fgMuted,
                    labelOf: (edge) => edgeSelectorLabel(l, edge.selector),
                  ),
                ),
              ),
              // Invisible full-surface hit layer for edge taps (delete).
              Positioned.fill(
                child: _EdgeHitLayer(
                  edges: graph.edges,
                  positions: positions,
                  onTapEdge: (index) => _confirmDeleteEdge(context, index),
                ),
              ),
              for (final node in graph.nodes)
                _PositionedNodeCard(
                  node: node,
                  position: positions[node.id] ?? Offset.zero,
                  state: state,
                  controller: controller,
                  tokens: tokens,
                  l: l,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEdge(BuildContext context, int index) async {
    final edges = state.graph.edges;
    if (index < 0 || index >= edges.length) return;
    final edge = edges[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.stageGraphDeleteEdge),
        content: Text(
          l.stageGraphCanvasDeleteEdge(edge.fromNodeId, edge.toNodeId),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.stageGraphCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.stageGraphDeleteEdge),
          ),
        ],
      ),
    );
    if (ok ?? false) controller.removeEdge(index);
  }
}

// --- Edge hit layer (tap-to-delete) ----------------------------------------

/// Transparent layer that turns a tap near an edge line into the edge index.
/// Sits under the cards (cards are added after it) so card gestures win.
class _EdgeHitLayer extends StatelessWidget {
  const _EdgeHitLayer({
    required this.edges,
    required this.positions,
    required this.onTapEdge,
  });

  final List<StageEdge> edges;
  final Map<String, Offset> positions;
  final ValueChanged<int> onTapEdge;

  static const double _hitTolerance = 12;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        final index = _edgeAt(details.localPosition);
        if (index != null) onTapEdge(index);
      },
    );
  }

  /// Returns the index of the first edge whose segment is within tolerance of
  /// [point], or `null` if none. Declaration order = edge index.
  int? _edgeAt(Offset point) {
    for (var i = 0; i < edges.length; i++) {
      final from = positions[edges[i].fromNodeId];
      final to = positions[edges[i].toNodeId];
      if (from == null || to == null) continue;
      final start = Offset(
        from.dx + kStageCanvasNodeWidth,
        from.dy + kStageCanvasNodeHeight / 2,
      );
      final end = Offset(to.dx, to.dy + kStageCanvasNodeHeight / 2);
      if (_distanceToSegment(point, start, end) <= _hitTolerance) return i;
    }
    return null;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }
}

// --- Positioned, draggable node card ---------------------------------------

class _PositionedNodeCard extends ConsumerWidget {
  const _PositionedNodeCard({
    required this.node,
    required this.position,
    required this.state,
    required this.controller,
    required this.tokens,
    required this.l,
  });

  final StageNode node;
  final Offset position;
  final StageGraphBuilderState state;
  final StageGraphBuilderController controller;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severity = _severityFor(node.id, state.findings);
    final borderColor = switch (severity) {
      _NodeSeverity.error => KubbTokens.miss,
      _NodeSeverity.warning => KubbTokens.heli,
      _NodeSeverity.none => tokens.line,
    };
    final borderWidth = severity == _NodeSeverity.none ? 1.0 : 2.0;
    final config = _nodeConfigSummary(node);

    return Positioned(
      left: position.dx,
      top: position.dy,
      width: kStageCanvasNodeWidth,
      height: kStageCanvasNodeHeight,
      // Raw pointer-move dragging via Listener: it bypasses the gesture arena,
      // so the surrounding scroll views never steal/split the drag delta. Tap
      // (edit) stays on GestureDetector underneath.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerMove: (e) => ref
            .read(stageGraphCanvasLayoutProvider.notifier)
            .moveBy(node.id, e.delta),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openEdit(context),
          child: Container(
            key: severity == _NodeSeverity.error
                ? Key('stageCanvasNodeError_${node.id}')
                : Key('stageCanvasNode_${node.id}'),
            decoration: BoxDecoration(
              color: tokens.bgRaised,
              border: Border.all(color: borderColor, width: borderWidth),
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space3,
              vertical: KubbTokens.space2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  node.id,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stageNodeTypeLabel(l, node.type),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.fgMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  config == null
                      ? stageSeedingSourceLabel(l, node.seeding)
                      : '${stageSeedingSourceLabel(l, node.seeding)} · $config',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: tokens.fgSubtle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEdit(BuildContext context) async {
    final existing = state.graph.nodes
        .map((n) => n.id)
        .where((id) => id != node.id)
        .toSet();
    final updated = await showStageNodeEditDialog(
      context,
      initial: node,
      existingIds: existing,
    );
    if (updated != null) controller.updateNode(node.id, updated);
  }
}

// --- Empty state -----------------------------------------------------------

class _CanvasEmpty extends StatelessWidget {
  const _CanvasEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KubbTokens.space6),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: tokens.fgMuted, height: 1.4),
        ),
      ),
    );
  }
}

// --- Helpers ---------------------------------------------------------------

enum _NodeSeverity { none, warning, error }

/// Derives a node's highest severity from the builder findings (error wins over
/// warning). Only findings whose `nodeId` matches contribute.
_NodeSeverity _severityFor(String nodeId, List<ValidationFinding> findings) {
  var result = _NodeSeverity.none;
  for (final f in findings) {
    if (f.nodeId != nodeId) continue;
    if (f.severity == ValidationSeverity.error) return _NodeSeverity.error;
    result = _NodeSeverity.warning;
  }
  return result;
}

/// Compact config summary for a node card (only present, known keys). Mirrors
/// the form view's summary so both views read identically.
String? _nodeConfigSummary(StageNode node) {
  final parts = <String>[];
  final g = node.config['groupCount'];
  if (g is int) parts.add('groupCount: $g');
  final q = node.config['qualifierCount'];
  if (q is int) parts.add('qualifierCount: $q');
  final r = node.config['rounds'];
  if (r is int) parts.add('rounds: $r');
  final s = node.config['slots'];
  if (s is int) parts.add('slots: $s');
  return parts.isEmpty ? null : parts.join(' · ');
}
