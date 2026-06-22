import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_canvas_layout.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Desktop canvas view of the in-progress stage TYPE graph (Ebene 2, ADR-0039
/// §5/§6.5, spec §5 desktop variant).
///
/// This is the SECOND view onto the very same [stageTypeGraphBuilderProvider]
/// the form editor (U7) uses. It holds NO graph state of its own and never
/// re-implements validation or serialization: every structural change routes
/// through the controller's `addEdge` / `updateEdge` / `removeEdge`, and the
/// validation it shows is read from `state.findings` / `state.hasErrors`. Only
/// the client-side position map lives here ([stageTypeGraphCanvasLayoutProvider]).
/// Because both editors mutate the one provider, `toConfig()` serializes
/// identically regardless of which view made the edit — that is the parity
/// guarantee (§9.5).
///
/// Category-aware, mirroring the validation:
///  - **Vorrunde**: each round is ONE block with a single `alle weiter` output
///    port. Dragging it to the next block wires the `AdvanceAllEdge(r -> r+1)`.
///    There are no per-field winner/loser ports (`vorrunde_field_edge_forbidden`).
///  - **KO**: each field is a node with a winner output port and a loser output
///    port; dragging a port onto a target field wires the `WinnerEdge`/`LoserEdge`.
///    A field side that is deliberately left open shows as an OpenEdge warning.
class StageTypeGraphCanvas extends ConsumerWidget {
  const StageTypeGraphCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final state = ref.watch(stageTypeGraphBuilderProvider);
    final controller = ref.read(stageTypeGraphBuilderProvider.notifier);
    final graph = state.graph;

    // Reconcile the position map with the current graph after each build.
    // Deferred to post-frame so we never mutate a provider during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(stageTypeGraphCanvasLayoutProvider.notifier)
          .syncWithGraph(graph);
    });

    final layout = ref.watch(stageTypeGraphCanvasLayoutProvider);
    final positions = layout.isEmpty ? typeAutoLayout(graph) : layout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: graph.rounds.isEmpty
              ? _CanvasEmpty(message: l.stageTypeGraphCanvasEmpty)
              : _TypeCanvasSurface(
                  state: state,
                  controller: controller,
                  positions: positions,
                  tokens: tokens,
                  l: l,
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KubbTokens.space4,
            KubbTokens.space3,
            KubbTokens.space4,
            KubbTokens.space4,
          ),
          child: _ValidationBar(state: state),
        ),
      ],
    );
  }
}

// --- Connection drag (port -> field) ---------------------------------------

/// What an in-progress port drag is offering as its edge kind. Only the KO
/// winner/loser ports and the Vorrunde advance-all output can start a drag.
enum _PortKind { winner, loser, advanceAll }

/// Immutable, client-side connection-gesture state for an in-progress drag.
/// Lives ONLY here in the canvas view's local widget state — never in the
/// domain model, [StageTypeGraphBuilderState], or the layout provider.
@immutable
class _ConnectionDrag {
  const _ConnectionDrag({
    required this.sourceAnchor,
    required this.kind,
    required this.pointer,
  });

  /// Anchor (field id for KO, round key for Vorrunde) the drag started from.
  final String sourceAnchor;

  /// Which port started the drag.
  final _PortKind kind;

  /// Current pointer position in canvas-local coordinates.
  final Offset pointer;

  _ConnectionDrag copyWith({Offset? pointer}) => _ConnectionDrag(
        sourceAnchor: sourceAnchor,
        kind: kind,
        pointer: pointer ?? this.pointer,
      );
}

/// Resolves a port-drag release to a target field id, or `null` (none / self).
///
/// PURE & deterministic so it can be unit-tested directly: tests the pointer
/// against each field's box. The FIRST hit in [fieldOrder] wins, matching the
/// topmost-card paint order. Returns `null` when no box is hit or when the only
/// hit is the [sourceFieldId] itself (self-loop guard).
String? resolveTypeConnectionTarget({
  required Offset pointer,
  required String sourceFieldId,
  required List<String> fieldOrder,
  required Map<String, Offset> positions,
}) {
  for (final id in fieldOrder) {
    final pos = positions[id];
    if (pos == null) continue;
    final box = Rect.fromLTWH(
      pos.dx,
      pos.dy,
      kTypeCanvasNodeWidth,
      kTypeCanvasNodeHeight,
    );
    if (box.contains(pointer)) {
      return id == sourceFieldId ? null : id;
    }
  }
  return null;
}

// --- Canvas surface --------------------------------------------------------

class _TypeCanvasSurface extends ConsumerStatefulWidget {
  const _TypeCanvasSurface({
    required this.state,
    required this.controller,
    required this.positions,
    required this.tokens,
    required this.l,
  });

  final StageTypeGraphBuilderState state;
  final StageTypeGraphBuilderController controller;
  final Map<String, Offset> positions;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  ConsumerState<_TypeCanvasSurface> createState() => _TypeCanvasSurfaceState();
}

class _TypeCanvasSurfaceState extends ConsumerState<_TypeCanvasSurface> {
  _ConnectionDrag? _drag;

  StageTypeGraph get _graph => widget.state.graph;

  bool get _isVorrunde => _graph.category == TypeStageCategory.vorrunde;

  /// Output-port anchor for a KO field's winner (upper) or loser (lower) port,
  /// on the right edge of the card, in canvas-local coordinates.
  Offset _koOutAnchor(String fieldId, _PortKind kind) {
    final pos = widget.positions[fieldId] ?? Offset.zero;
    final dy = kind == _PortKind.winner
        ? kTypeCanvasNodeHeight * 0.32
        : kTypeCanvasNodeHeight * 0.68;
    return Offset(pos.dx + kTypeCanvasNodeWidth, pos.dy + dy);
  }

  /// Output-port anchor of a Vorrunde round block (right-center).
  Offset _roundOutAnchor(int roundNumber) {
    final pos = widget.positions[typeRoundLayoutKey(roundNumber)] ??
        Offset.zero;
    return Offset(
      pos.dx + kTypeCanvasNodeWidth,
      pos.dy + kTypeCanvasNodeHeight / 2,
    );
  }

  Offset _dragStartAnchor(_ConnectionDrag drag) {
    if (drag.kind == _PortKind.advanceAll) {
      return _roundOutAnchor(int.parse(drag.sourceAnchor.split('_').last));
    }
    return _koOutAnchor(drag.sourceAnchor, drag.kind);
  }

  void _onPortDragStart(String anchor, _PortKind kind, Offset localPointer) {
    setState(() {
      _drag = _ConnectionDrag(
        sourceAnchor: anchor,
        kind: kind,
        pointer: localPointer,
      );
    });
  }

  void _onPortDragUpdate(Offset localPointer) {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = drag.copyWith(pointer: localPointer));
  }

  void _onPortDragEnd() {
    final drag = _drag;
    setState(() => _drag = null);
    if (drag == null) return;

    if (drag.kind == _PortKind.advanceAll) {
      _resolveAdvanceAll(drag);
      return;
    }
    _resolveKoEdge(drag);
  }

  /// A KO winner/loser port drag resolves to a target field and wires the edge
  /// through the controller (the single mutation path).
  void _resolveKoEdge(_ConnectionDrag drag) {
    final target = resolveTypeConnectionTarget(
      pointer: drag.pointer,
      sourceFieldId: drag.sourceAnchor,
      fieldOrder: [for (final f in _graph.allFields) f.id],
      positions: widget.positions,
    );
    if (target == null) return;
    final edge = drag.kind == _PortKind.winner
        ? WinnerEdge(fromFieldId: drag.sourceAnchor, toFieldId: target)
        : LoserEdge(fromFieldId: drag.sourceAnchor, toFieldId: target);
    widget.controller.addEdge(edge);
  }

  /// A Vorrunde advance-all port drag resolves to the next round block and
  /// wires the single `AdvanceAllEdge(r -> r+1)`.
  void _resolveAdvanceAll(_ConnectionDrag drag) {
    final from = int.parse(drag.sourceAnchor.split('_').last);
    final target = _roundBlockAt(drag.pointer);
    if (target == null || target == from) return;
    widget.controller.addEdge(AdvanceAllEdge(fromRound: from, toRound: target));
  }

  int? _roundBlockAt(Offset pointer) {
    for (final round in _graph.rounds) {
      final pos = widget.positions[typeRoundLayoutKey(round.roundNumber)];
      if (pos == null) continue;
      final box = Rect.fromLTWH(
        pos.dx,
        pos.dy,
        kTypeCanvasNodeWidth,
        kTypeCanvasNodeHeight,
      );
      if (box.contains(pointer)) return round.roundNumber;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final positions = widget.positions;
    final tokens = widget.tokens;
    final l = widget.l;

    var maxX = 0.0;
    var maxY = 0.0;
    for (final pos in positions.values) {
      maxX = pos.dx > maxX ? pos.dx : maxX;
      maxY = pos.dy > maxY ? pos.dy : maxY;
    }
    final canvasSize = Size(
      maxX + kTypeCanvasNodeWidth + kTypeCanvasPadding,
      maxY + kTypeCanvasNodeHeight + kTypeCanvasPadding,
    );

    final drag = _drag;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: canvasSize.width,
          height: canvasSize.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  key: const Key('stageTypeCanvasEdgePainter'),
                  painter: _TypeEdgePainter(
                    graph: _graph,
                    positions: positions,
                    lineColor: tokens.lineStrong,
                    warningColor: KubbTokens.heli,
                  ),
                ),
              ),
              Positioned.fill(
                child: _EdgeHitLayer(
                  graph: _graph,
                  positions: positions,
                  onTapEdge: (index) => _confirmDeleteEdge(context, index),
                ),
              ),
              if (_isVorrunde)
                for (final round in _graph.rounds)
                  _RoundBlock(
                    round: round,
                    isLast: _isLastRound(round.roundNumber),
                    position: positions[typeRoundLayoutKey(round.roundNumber)] ??
                        Offset.zero,
                    state: widget.state,
                    tokens: tokens,
                    l: l,
                    onPortDragStart: (pointer) => _onPortDragStart(
                      typeRoundLayoutKey(round.roundNumber),
                      _PortKind.advanceAll,
                      pointer,
                    ),
                    onPortDragUpdate: _onPortDragUpdate,
                    onPortDragEnd: _onPortDragEnd,
                  )
              else
                for (final field in _graph.allFields)
                  _FieldCard(
                    field: field,
                    position: positions[field.id] ?? Offset.zero,
                    state: widget.state,
                    tokens: tokens,
                    l: l,
                    onWinnerDragStart: (pointer) =>
                        _onPortDragStart(field.id, _PortKind.winner, pointer),
                    onLoserDragStart: (pointer) =>
                        _onPortDragStart(field.id, _PortKind.loser, pointer),
                    onPortDragUpdate: _onPortDragUpdate,
                    onPortDragEnd: _onPortDragEnd,
                  ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('stageTypeCanvasConnectionPreview'),
                    painter: _ConnectionPreviewPainter(
                      start: drag == null ? null : _dragStartAnchor(drag),
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

  bool _isLastRound(int roundNumber) {
    var max = 0;
    for (final r in _graph.rounds) {
      if (r.roundNumber > max) max = r.roundNumber;
    }
    return roundNumber == max;
  }

  Future<void> _confirmDeleteEdge(BuildContext context, int index) async {
    final l = widget.l;
    final edges = widget.state.graph.edges;
    if (index < 0 || index >= edges.length) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.stageTypeGraphDeleteEdge),
        content: Text(l.stageTypeGraphCanvasDeleteEdge(_edgeLabel(edges[index]))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.stageTypeGraphCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.stageTypeGraphDeleteEdge),
          ),
        ],
      ),
    );
    if (ok ?? false) widget.controller.removeEdge(index);
  }
}

String _edgeLabel(FieldEdge edge) => switch (edge) {
      WinnerEdge(:final fromFieldId, :final toFieldId) =>
        '$fromFieldId → $toFieldId',
      LoserEdge(:final fromFieldId, :final toFieldId) =>
        '$fromFieldId → $toFieldId',
      OpenEdge(:final fromFieldId, :final slot) => '$fromFieldId · ${slot.wire}',
      AdvanceAllEdge(:final fromRound, :final toRound) =>
        'R$fromRound → R$toRound',
    };

// --- Edge painter ----------------------------------------------------------

/// Draws the type-graph edges beneath the cards. KO winner/loser edges run from
/// the field's winner/loser output port to the target field's input port; the
/// Vorrunde `AdvanceAllEdge` runs block-to-block (right-center to left-center).
/// An `OpenEdge` is drawn as a short dangling stub in the warning color.
class _TypeEdgePainter extends CustomPainter {
  _TypeEdgePainter({
    required this.graph,
    required this.positions,
    required this.lineColor,
    required this.warningColor,
  });

  final StageTypeGraph graph;
  final Map<String, Offset> positions;
  final Color lineColor;
  final Color warningColor;

  static const double _arrowSize = 9;

  Offset? _fieldInAnchor(String fieldId) {
    final pos = positions[fieldId];
    if (pos == null) return null;
    return Offset(pos.dx, pos.dy + kTypeCanvasNodeHeight / 2);
  }

  Offset? _fieldOutAnchor(String fieldId, {required bool winner}) {
    final pos = positions[fieldId];
    if (pos == null) return null;
    final dy = winner
        ? kTypeCanvasNodeHeight * 0.32
        : kTypeCanvasNodeHeight * 0.68;
    return Offset(pos.dx + kTypeCanvasNodeWidth, pos.dy + dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    final warnStroke = Paint()
      ..color = warningColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final edge in graph.edges) {
      switch (edge) {
        case WinnerEdge(:final fromFieldId, :final toFieldId):
          _drawLine(
            canvas,
            stroke,
            fill,
            _fieldOutAnchor(fromFieldId, winner: true),
            _fieldInAnchor(toFieldId),
          );
        case LoserEdge(:final fromFieldId, :final toFieldId):
          _drawLine(
            canvas,
            stroke,
            fill,
            _fieldOutAnchor(fromFieldId, winner: false),
            _fieldInAnchor(toFieldId),
          );
        case OpenEdge(:final fromFieldId, :final slot):
          final start = _fieldOutAnchor(
            fromFieldId,
            winner: slot == OpenEdgeSlot.winner,
          );
          if (start == null) continue;
          // A short open stub: it points nowhere, signalling the open side.
          canvas.drawLine(start, start + const Offset(28, 0), warnStroke);
        case AdvanceAllEdge(:final fromRound, :final toRound):
          final from = positions[typeRoundLayoutKey(fromRound)];
          final to = positions[typeRoundLayoutKey(toRound)];
          if (from == null || to == null) continue;
          _drawLine(
            canvas,
            stroke,
            fill,
            Offset(
              from.dx + kTypeCanvasNodeWidth,
              from.dy + kTypeCanvasNodeHeight / 2,
            ),
            Offset(to.dx, to.dy + kTypeCanvasNodeHeight / 2),
          );
      }
    }
  }

  void _drawLine(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Offset? start,
    Offset? end,
  ) {
    if (start == null || end == null) return;
    canvas.drawLine(start, end, stroke);
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final p1 = Offset(
      end.dx - _arrowSize * math.cos(angle - math.pi / 6),
      end.dy - _arrowSize * math.sin(angle - math.pi / 6),
    );
    final p2 = Offset(
      end.dx - _arrowSize * math.cos(angle + math.pi / 6),
      end.dy - _arrowSize * math.sin(angle + math.pi / 6),
    );
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _TypeEdgePainter old) =>
      old.graph != graph ||
      old.positions != positions ||
      old.lineColor != lineColor ||
      old.warningColor != warningColor;
}

/// Draws the temporary connection preview while a port drag is in flight.
class _ConnectionPreviewPainter extends CustomPainter {
  _ConnectionPreviewPainter({
    required this.start,
    required this.end,
    required this.lineColor,
  });

  final Offset? start;
  final Offset? end;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final from = start;
    final to = end;
    if (from == null || to == null) return;
    final stroke = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, stroke);
  }

  @override
  bool shouldRepaint(covariant _ConnectionPreviewPainter old) =>
      old.start != start || old.end != end || old.lineColor != lineColor;
}

// --- Edge hit layer (tap-to-delete) ----------------------------------------

class _EdgeHitLayer extends StatelessWidget {
  const _EdgeHitLayer({
    required this.graph,
    required this.positions,
    required this.onTapEdge,
  });

  final StageTypeGraph graph;
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

  /// Returns the index of the first edge whose drawn segment is within
  /// tolerance of [point], or `null`. Declaration order = edge index, matching
  /// the controller's `removeEdge(index)`. OpenEdges have no full segment and
  /// are skipped (delete them in the form list).
  int? _edgeAt(Offset point) {
    for (var i = 0; i < graph.edges.length; i++) {
      final segment = _segmentOf(graph.edges[i]);
      if (segment == null) continue;
      if (_distanceToSegment(point, segment.$1, segment.$2) <= _hitTolerance) {
        return i;
      }
    }
    return null;
  }

  (Offset, Offset)? _segmentOf(FieldEdge edge) {
    switch (edge) {
      case WinnerEdge(:final fromFieldId, :final toFieldId):
        return _fieldSegment(fromFieldId, toFieldId, winner: true);
      case LoserEdge(:final fromFieldId, :final toFieldId):
        return _fieldSegment(fromFieldId, toFieldId, winner: false);
      case OpenEdge():
        return null;
      case AdvanceAllEdge(:final fromRound, :final toRound):
        final from = positions[typeRoundLayoutKey(fromRound)];
        final to = positions[typeRoundLayoutKey(toRound)];
        if (from == null || to == null) return null;
        return (
          Offset(
            from.dx + kTypeCanvasNodeWidth,
            from.dy + kTypeCanvasNodeHeight / 2,
          ),
          Offset(to.dx, to.dy + kTypeCanvasNodeHeight / 2),
        );
    }
  }

  (Offset, Offset)? _fieldSegment(
    String fromId,
    String toId, {
    required bool winner,
  }) {
    final from = positions[fromId];
    final to = positions[toId];
    if (from == null || to == null) return null;
    final dy = winner
        ? kTypeCanvasNodeHeight * 0.32
        : kTypeCanvasNodeHeight * 0.68;
    return (
      Offset(from.dx + kTypeCanvasNodeWidth, from.dy + dy),
      Offset(to.dx, to.dy + kTypeCanvasNodeHeight / 2),
    );
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

// --- KO field card ---------------------------------------------------------

const double _kPortVisibleSize = 14;

class _FieldCard extends ConsumerWidget {
  const _FieldCard({
    required this.field,
    required this.position,
    required this.state,
    required this.tokens,
    required this.l,
    required this.onWinnerDragStart,
    required this.onLoserDragStart,
    required this.onPortDragUpdate,
    required this.onPortDragEnd,
  });

  final TypeField field;
  final Offset position;
  final StageTypeGraphBuilderState state;
  final KubbTokens tokens;
  final AppLocalizations l;
  final ValueChanged<Offset> onWinnerDragStart;
  final ValueChanged<Offset> onLoserDragStart;
  final ValueChanged<Offset> onPortDragUpdate;
  final VoidCallback onPortDragEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severity = _severityForField(field.id, state.findings);
    final borderColor = switch (severity) {
      _Severity.error => KubbTokens.miss,
      _Severity.warning => KubbTokens.heli,
      _Severity.none => tokens.line,
    };
    final borderWidth = severity == _Severity.none ? 1.0 : 2.0;

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: position.dx,
            top: position.dy,
            width: kTypeCanvasNodeWidth,
            height: kTypeCanvasNodeHeight,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerMove: (e) => ref
                  .read(stageTypeGraphCanvasLayoutProvider.notifier)
                  .moveBy(field.id, e.delta),
              child: Container(
                key: severity == _Severity.error
                    ? Key('stageTypeCanvasFieldError_${field.id}')
                    : Key('stageTypeCanvasField_${field.id}'),
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
                      field.id,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.stageTypeGraphCanvasFieldRound(
                        field.roundNumber.toString(),
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: tokens.fgSubtle),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _PortHandle(
            anchor: Offset(position.dx, position.dy + kTypeCanvasNodeHeight / 2),
            tokens: tokens,
            filled: false,
            tooltip: l.stageTypeGraphCanvasInPort,
            widgetKey: Key('stageTypeCanvasInPort_${field.id}'),
          ),
          _PortHandle(
            anchor: Offset(
              position.dx + kTypeCanvasNodeWidth,
              position.dy + kTypeCanvasNodeHeight * 0.32,
            ),
            tokens: tokens,
            filled: true,
            tooltip: l.stageTypeGraphCanvasWinnerPort,
            widgetKey: Key('stageTypeCanvasWinnerPort_${field.id}'),
            onDragStart: onWinnerDragStart,
            onDragUpdate: onPortDragUpdate,
            onDragEnd: onPortDragEnd,
          ),
          _PortHandle(
            anchor: Offset(
              position.dx + kTypeCanvasNodeWidth,
              position.dy + kTypeCanvasNodeHeight * 0.68,
            ),
            tokens: tokens,
            filled: false,
            tooltip: l.stageTypeGraphCanvasLoserPort,
            widgetKey: Key('stageTypeCanvasLoserPort_${field.id}'),
            onDragStart: onLoserDragStart,
            onDragUpdate: onPortDragUpdate,
            onDragEnd: onPortDragEnd,
          ),
        ],
      ),
    );
  }
}

// --- Vorrunde round block --------------------------------------------------

class _RoundBlock extends ConsumerWidget {
  const _RoundBlock({
    required this.round,
    required this.isLast,
    required this.position,
    required this.state,
    required this.tokens,
    required this.l,
    required this.onPortDragStart,
    required this.onPortDragUpdate,
    required this.onPortDragEnd,
  });

  final TypeRound round;
  final bool isLast;
  final Offset position;
  final StageTypeGraphBuilderState state;
  final KubbTokens tokens;
  final AppLocalizations l;
  final ValueChanged<Offset> onPortDragStart;
  final ValueChanged<Offset> onPortDragUpdate;
  final VoidCallback onPortDragEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasError = _roundHasError(round.roundNumber, state.findings);
    final borderColor = hasError ? KubbTokens.miss : tokens.line;
    final borderWidth = hasError ? 2.0 : 1.0;

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: position.dx,
            top: position.dy,
            width: kTypeCanvasNodeWidth,
            height: kTypeCanvasNodeHeight,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerMove: (e) => ref
                  .read(stageTypeGraphCanvasLayoutProvider.notifier)
                  .moveBy(typeRoundLayoutKey(round.roundNumber), e.delta),
              child: Container(
                key: hasError
                    ? Key('stageTypeCanvasRoundError_${round.roundNumber}')
                    : Key('stageTypeCanvasRound_${round.roundNumber}'),
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
                      l.stageTypeGraphRoundTitle(round.roundNumber.toString()),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.stageTypeGraphRoundFieldCount(round.fields.length),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: tokens.fgSubtle),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLast
                          ? l.stageTypeGraphCanvasVorrundeTerminal
                          : l.stageTypeGraphCanvasAdvanceAll,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tokens.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _PortHandle(
            anchor: Offset(position.dx, position.dy + kTypeCanvasNodeHeight / 2),
            tokens: tokens,
            filled: false,
            tooltip: l.stageTypeGraphCanvasInPort,
            widgetKey: Key('stageTypeCanvasRoundInPort_${round.roundNumber}'),
          ),
          // The single "alle weiter" output. The last round is terminal and has
          // no advance-all port (nothing to advance into).
          if (!isLast)
            _PortHandle(
              anchor: Offset(
                position.dx + kTypeCanvasNodeWidth,
                position.dy + kTypeCanvasNodeHeight / 2,
              ),
              tokens: tokens,
              filled: true,
              tooltip: l.stageTypeGraphCanvasAdvanceAll,
              widgetKey:
                  Key('stageTypeCanvasAdvancePort_${round.roundNumber}'),
              onDragStart: onPortDragStart,
              onDragUpdate: onPortDragUpdate,
              onDragEnd: onPortDragEnd,
            ),
        ],
      ),
    );
  }
}

// --- Port handle -----------------------------------------------------------

class _PortHandle extends StatelessWidget {
  const _PortHandle({
    required this.anchor,
    required this.tokens,
    required this.filled,
    required this.tooltip,
    required this.widgetKey,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final Offset anchor;
  final KubbTokens tokens;
  final bool filled;
  final String tooltip;
  final Key widgetKey;
  final ValueChanged<Offset>? onDragStart;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;

  bool get _isOutput => onDragStart != null;

  @override
  Widget build(BuildContext context) {
    final boxTopLeft = anchor -
        const Offset(KubbTokens.touchMin / 2, KubbTokens.touchMin / 2);

    final dot = Center(
      child: Container(
        width: _kPortVisibleSize,
        height: _kPortVisibleSize,
        decoration: BoxDecoration(
          color: filled ? tokens.primary : tokens.bgRaised,
          shape: BoxShape.circle,
          border: Border.all(
            color: filled ? tokens.primary : tokens.lineStrong,
            width: 2,
          ),
        ),
      ),
    );

    final Widget handle;
    if (_isOutput) {
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

// --- Validation bar --------------------------------------------------------

class _ValidationBar extends StatelessWidget {
  const _ValidationBar({required this.state});

  final StageTypeGraphBuilderState state;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final hasErrors = state.hasErrors;
    final accent = hasErrors ? KubbTokens.miss : KubbTokens.meadow500;
    final errors =
        state.findings.where((f) => f.severity == ValidationSeverity.error);
    final warnings =
        state.findings.where((f) => f.severity == ValidationSeverity.warning);
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      padding: const EdgeInsets.all(KubbTokens.space3),
      child: Row(
        children: [
          Icon(
            hasErrors ? Icons.close : Icons.check,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              hasErrors
                  ? l.stageTypeGraphCanvasErrors(errors.length)
                  : warnings.isEmpty
                      ? l.stageTypeGraphSavable
                      : l.stageTypeGraphCanvasWarnings(warnings.length),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Helpers ---------------------------------------------------------------

enum _Severity { none, warning, error }

/// Highest severity of findings that name [fieldId] via `edgeFrom` (error wins).
_Severity _severityForField(String fieldId, List<ValidationFinding> findings) {
  var result = _Severity.none;
  for (final f in findings) {
    if (f.edgeFrom != fieldId) continue;
    if (f.severity == ValidationSeverity.error) return _Severity.error;
    result = _Severity.warning;
  }
  return result;
}

/// Whether any error finding mentions [roundNumber] in its message. Vorrunde
/// findings (`vorrunde_not_constant`, `advance_all_missing`) reference rounds by
/// number, so the block lights up when its round is the offending one.
bool _roundHasError(int roundNumber, List<ValidationFinding> findings) {
  for (final f in findings) {
    if (f.severity != ValidationSeverity.error) continue;
    if (f.message.contains('round $roundNumber ') ||
        f.message.contains('round $roundNumber.')) {
      return true;
    }
  }
  return false;
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
