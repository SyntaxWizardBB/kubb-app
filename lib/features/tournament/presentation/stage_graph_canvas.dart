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
/// L4b-2: gesture-based port->port edge DRAWING is now supported. Each card has
/// a visible output port (right edge) and input port (left edge). Dragging from
/// an output port draws a temporary preview line; releasing over another card
/// opens the EXISTING `_EdgeDialog` (via `showStageEdgeAddDialog`) seeded with
/// from=source / to=target. Edges are still committed only through that dialog +
/// `controller.addEdge`. Pan/zoom via `InteractiveViewer` is a nice-to-have, not
/// an acceptance criterion.
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

/// Immutable, client-side connection-gesture state for an in-progress port->port
/// drag (L4b-2). Lives ONLY here in the canvas view's local widget state — never
/// in the domain model, `StageGraphBuilderState`, or the layout provider.
@immutable
class _ConnectionDrag {
  const _ConnectionDrag({required this.sourceNodeId, required this.pointer});

  /// Node id whose output port started the drag.
  final String sourceNodeId;

  /// Current pointer position in canvas-local coordinates.
  final Offset pointer;

  _ConnectionDrag copyWith({Offset? pointer}) => _ConnectionDrag(
        sourceNodeId: sourceNodeId,
        pointer: pointer ?? this.pointer,
      );
}

/// Resolves a port-drag release to a target node id, or `null` (none / self).
///
/// PURE & deterministic (no widget context) so it can be unit-tested directly
/// (DoD §17/§23): tests the pointer against each node's box
/// (`positions[id]` + `kStageCanvasNodeWidth × kStageCanvasNodeHeight`). The
/// FIRST hit in [nodeOrder] wins (declaration order = node order on the canvas),
/// matching the topmost-card paint order. Returns `null` when no box is hit or
/// when the only hit is the [sourceNodeId] itself (self-loop guard).
String? resolveConnectionTarget({
  required Offset pointer,
  required String sourceNodeId,
  required List<String> nodeOrder,
  required Map<String, Offset> positions,
}) {
  for (final id in nodeOrder) {
    final pos = positions[id];
    if (pos == null) continue;
    final box = Rect.fromLTWH(
      pos.dx,
      pos.dy,
      kStageCanvasNodeWidth,
      kStageCanvasNodeHeight,
    );
    if (box.contains(pointer)) {
      // Self-loop: target == source -> no edge (DoD §9).
      return id == sourceNodeId ? null : id;
    }
  }
  return null;
}

class _CanvasSurface extends ConsumerStatefulWidget {
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
  ConsumerState<_CanvasSurface> createState() => _CanvasSurfaceState();
}

class _CanvasSurfaceState extends ConsumerState<_CanvasSurface> {
  /// In-progress port->port connection drag, or null when idle. Lives here as
  /// pure view state (DoD §6).
  _ConnectionDrag? _drag;

  /// Source output-port anchor in canvas-local coordinates — kept identical to
  /// `StageGraphEdgePainter`'s `start` anchor so preview and final edge align.
  Offset _outAnchor(String nodeId) {
    final pos = widget.positions[nodeId] ?? Offset.zero;
    return Offset(
      pos.dx + kStageCanvasNodeWidth,
      pos.dy + kStageCanvasNodeHeight / 2,
    );
  }

  void _onPortDragStart(String nodeId, Offset localPointer) {
    setState(() {
      _drag = _ConnectionDrag(sourceNodeId: nodeId, pointer: localPointer);
    });
  }

  void _onPortDragUpdate(Offset localPointer) {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = drag.copyWith(pointer: localPointer));
  }

  Future<void> _onPortDragEnd() async {
    final drag = _drag;
    // Always clear the preview on release (DoD §13), regardless of outcome.
    setState(() => _drag = null);
    if (drag == null) return;

    final target = resolveConnectionTarget(
      pointer: drag.pointer,
      sourceNodeId: drag.sourceNodeId,
      nodeOrder: [for (final n in widget.state.graph.nodes) n.id],
      positions: widget.positions,
    );
    // No target / self-loop -> no dialog, no edge (DoD §8/§9).
    if (target == null) return;
    if (!mounted) return;

    // Reuse the EXISTING edge dialog, only seeded with from/to (DoD §10/§12).
    final edge = await showStageEdgeAddDialog(
      context,
      nodes: widget.state.graph.nodes,
      initialFrom: drag.sourceNodeId,
      initialTo: target,
    );
    if (edge != null) widget.controller.addEdge(edge);
  }

  @override
  Widget build(BuildContext context) {
    final graph = widget.state.graph;
    final positions = widget.positions;
    final tokens = widget.tokens;
    final l = widget.l;

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

    final drag = _drag;

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
                  state: widget.state,
                  controller: widget.controller,
                  tokens: tokens,
                  l: l,
                  onPortDragStart: (pointer) =>
                      _onPortDragStart(node.id, pointer),
                  onPortDragUpdate: _onPortDragUpdate,
                  onPortDragEnd: _onPortDragEnd,
                ),
              // Preview line OVER the cards (above the card layer), unlike the
              // persistent edge layer which stays UNDER the cards (DoD §5/§28).
              // IgnorePointer so it never steals the in-flight pointer stream.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('stageCanvasConnectionPreview'),
                    painter: StageGraphConnectionPreviewPainter(
                      start: drag == null ? null : _outAnchor(drag.sourceNodeId),
                      end: drag?.pointer,
                      lineColor: tokens.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEdge(BuildContext context, int index) async {
    final l = widget.l;
    final edges = widget.state.graph.edges;
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
    if (ok ?? false) widget.controller.removeEdge(index);
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

/// Visible diameter of a port handle (smaller than the 48dp hit target).
const double _kPortVisibleSize = 16;

class _PositionedNodeCard extends ConsumerWidget {
  const _PositionedNodeCard({
    required this.node,
    required this.position,
    required this.state,
    required this.controller,
    required this.tokens,
    required this.l,
    required this.onPortDragStart,
    required this.onPortDragUpdate,
    required this.onPortDragEnd,
  });

  final StageNode node;
  final Offset position;
  final StageGraphBuilderState state;
  final StageGraphBuilderController controller;
  final KubbTokens tokens;
  final AppLocalizations l;

  /// Output-port drag callbacks. The pointer offsets are in CANVAS-LOCAL
  /// coordinates (same space the layout positions / painter anchors use).
  final ValueChanged<Offset> onPortDragStart;
  final ValueChanged<Offset> onPortDragUpdate;
  final VoidCallback onPortDragEnd;

  /// Output-port anchor (right-center) in canvas-local coordinates — kept equal
  /// to `StageGraphEdgePainter`'s `start` anchor so preview/final edge align.
  Offset get _outAnchor => Offset(
        position.dx + kStageCanvasNodeWidth,
        position.dy + kStageCanvasNodeHeight / 2,
      );

  /// Input-port anchor (left-center) in canvas-local coordinates — equal to the
  /// painter's `end` anchor.
  Offset get _inAnchor =>
      Offset(position.dx, position.dy + kStageCanvasNodeHeight / 2);

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

    // A `_PositionedNodeCard` emits the body `Positioned` plus the two port
    // `Positioned`s as siblings of the SAME outer canvas Stack (via a Stack
    // here would re-introduce a circular size constraint). To stay one widget
    // and one Stack child, the body+ports are grouped in a transparent
    // `Positioned.fill` whose own Stack (clip none) lets the port hit boxes
    // extend slightly beyond the card box.
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: position.dx,
            top: position.dy,
            width: kStageCanvasNodeWidth,
            height: kStageCanvasNodeHeight,
            // Raw pointer-move dragging via Listener: it bypasses the gesture
            // arena, so the surrounding scroll views never steal/split the drag
            // delta. Tap (edit) stays on GestureDetector underneath.
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
          ),
          // Input port (left edge, visual affordance only — the drop target is
          // the whole card box, resolved via hit-test on release; DoD §2/§7).
          // Wrapped in IgnorePointer so taps still reach the card/edges.
          _PortHandle(
            anchor: _inAnchor,
            isOutput: false,
            tokens: tokens,
            tooltip: l.stageGraphCanvasInPort,
            widgetKey: Key('stageCanvasInPort_${node.id}'),
          ),
          // Output port (right edge): the connection-drag SOURCE. Placed last
          // so its >=48dp hit box consumes the pointer-down BEFORE the card-body
          // `Listener` underneath — that is exactly why the card-drag and the
          // edge-draw gestures never fight in the arena (L4b-1 uses `Listener`
          // for the card drag to dodge the scroll-view arena; the port sits ON
          // TOP and grabs its own pointer first; DoD §4/§15).
          _PortHandle(
            anchor: _outAnchor,
            isOutput: true,
            tokens: tokens,
            tooltip: l.stageGraphCanvasOutPort,
            widgetKey: Key('stageCanvasOutPort_${node.id}'),
            onDragStart: onPortDragStart,
            onDragUpdate: onPortDragUpdate,
            onDragEnd: onPortDragEnd,
          ),
        ],
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

/// A single port handle: a small visible dot centered inside a >=48dp hit box.
///
/// The hit box (`KubbTokens.touchMin`) is centered on [anchor] (canvas-local),
/// so its top-left lands at `anchor - (touchMin/2, touchMin/2)`. For the OUTPUT
/// port the `Listener` translates each pointer event back to canvas-local space
/// via that known top-left + the event's local position — giving exact
/// alignment with the layout/painter anchors. The INPUT port is purely visual
/// (no gestures) and lets pointers pass through.
class _PortHandle extends StatelessWidget {
  const _PortHandle({
    required this.anchor,
    required this.isOutput,
    required this.tokens,
    required this.tooltip,
    required this.widgetKey,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final Offset anchor;
  final bool isOutput;
  final KubbTokens tokens;
  final String tooltip;
  final Key widgetKey;
  final ValueChanged<Offset>? onDragStart;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    // Hit box top-left in canvas-local coordinates (centered on the anchor).
    final boxTopLeft = anchor - const Offset(
          KubbTokens.touchMin / 2,
          KubbTokens.touchMin / 2,
        );

    final dot = Center(
      child: Container(
        width: _kPortVisibleSize,
        height: _kPortVisibleSize,
        decoration: BoxDecoration(
          color: isOutput ? tokens.primary : tokens.bgRaised,
          shape: BoxShape.circle,
          border: Border.all(
            color: isOutput ? tokens.primary : tokens.lineStrong,
            width: 2,
          ),
        ),
      ),
    );

    final Widget handle;
    if (isOutput) {
      // Raw `Listener` (not GestureDetector) for the same arena-dodging reason
      // L4b-1 uses for the card drag: the surrounding scroll views must not be
      // able to steal/split the drag. Pointer events are translated from the
      // port-local space back to canvas-local space.
      handle = Listener(
        key: widgetKey,
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => onDragStart?.call(boxTopLeft + e.localPosition),
        onPointerMove: (e) => onDragUpdate?.call(boxTopLeft + e.localPosition),
        onPointerUp: (_) => onDragEnd?.call(),
        onPointerCancel: (_) => onDragEnd?.call(),
        child: Tooltip(message: tooltip, child: dot),
      );
    } else {
      // Input port: visual only, never intercepts pointers (the whole card box
      // is the real drop target, resolved on release).
      handle = IgnorePointer(
        key: widgetKey,
        child: Tooltip(message: tooltip, child: dot),
      );
    }

    return Positioned(
      left: boxTopLeft.dx,
      top: boxTopLeft.dy,
      width: KubbTokens.touchMin,
      height: KubbTokens.touchMin,
      child: handle,
    );
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
