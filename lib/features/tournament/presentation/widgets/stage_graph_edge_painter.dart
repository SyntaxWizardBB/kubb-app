import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_canvas_layout.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Draws the stage-graph edges as connecting arrows beneath the node cards
/// (ADR-0030 §Editor, Lage 4). One line+arrow per [StageEdge], from the right
/// edge of the source card to the left edge of the target card, based on the
/// shared layout positions and the named box geometry.
///
/// Edges that reference a node without a position (mid-reconcile / dangling)
/// are skipped. Edge labels (selector short label) are optional and rendered
/// at the line midpoint.
class StageGraphEdgePainter extends CustomPainter {
  StageGraphEdgePainter({
    required this.edges,
    required this.positions,
    required this.lineColor,
    required this.labelColor,
    required this.labelOf,
  });

  /// Edges in declaration order.
  final List<StageEdge> edges;

  /// Node-id -> top-left position of its card (same map the cards use).
  final Map<String, Offset> positions;

  /// Stroke color (from tokens).
  final Color lineColor;

  /// Edge-label text color (from tokens).
  final Color labelColor;

  /// Localized short label for an edge's selector, or `null` to draw no label.
  final String? Function(StageEdge edge) labelOf;

  static const double _nodeWidth = kStageCanvasNodeWidth;
  static const double _nodeHeight = kStageCanvasNodeHeight;
  static const double _arrowSize = 9;

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

    for (final edge in edges) {
      final from = positions[edge.fromNodeId];
      final to = positions[edge.toNodeId];
      if (from == null || to == null) continue;

      // Anchor: source right-center -> target left-center.
      final start = Offset(from.dx + _nodeWidth, from.dy + _nodeHeight / 2);
      final end = Offset(to.dx, to.dy + _nodeHeight / 2);

      canvas.drawLine(start, end, stroke);
      _drawArrowHead(canvas, fill, start, end);
      _drawLabel(canvas, edge, start, end);
    }
  }

  void _drawArrowHead(Canvas canvas, Paint fill, Offset start, Offset end) {
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

  void _drawLabel(Canvas canvas, StageEdge edge, Offset start, Offset end) {
    final text = labelOf(edge);
    if (text == null || text.isEmpty) return;
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: labelColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, mid - Offset(tp.width / 2, tp.height + 2));
  }

  @override
  bool shouldRepaint(covariant StageGraphEdgePainter old) =>
      old.edges != edges ||
      old.positions != positions ||
      old.lineColor != lineColor ||
      old.labelColor != labelColor;
}
