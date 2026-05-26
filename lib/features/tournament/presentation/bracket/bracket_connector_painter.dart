// BracketConnectorPainter (ADR-0016).
//
// Renders orthogonal "elbow" connector lines linking each winners-bracket match
// box to its two parents in the previous round. Splits into two layers:
//
//   * Base layer ([BracketConnectorPainter]): stable connector graph; repaints
//     only when the layout identity changes.
//   * Highlight layer ([BracketHighlightPainter]): foreground overlay bound to
//     a [ValueListenable<String?>] so hover/current-match selection invalidates
//     only this layer (`repaint:` short-circuits parent rebuilds).
//
// Viewport-culling kicks in for 32+ team brackets (>=16 first-round matches);
// below that threshold the `clipRect` overhead outweighs the savings.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_domain/kubb_domain.dart';

const int _cullThreshold = 16;

/// Base layer that draws every parent->child connector once per layout.
class BracketConnectorPainter extends CustomPainter {
  BracketConnectorPainter({
    required this.layout,
    required this.color,
    this.strokeWidth = 1.5,
  });

  final BracketLayout layout;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rects = layout.rects;
    if (rects.isEmpty) return;
    if (_firstRoundCount(rects) >= _cullThreshold) {
      canvas.clipRect(Offset.zero & size);
    }
    final paint = _paint(color, strokeWidth);
    for (final entry in rects.entries) {
      final key = entry.key;
      if (key == 'third-place') continue; // side-branch, no parent lines.
      final pair = _parents(rects, key);
      if (pair == null) continue;
      _elbow(canvas, paint, pair.$1, entry.value);
      _elbow(canvas, paint, pair.$2, entry.value);
    }
  }

  @override
  bool shouldRepaint(BracketConnectorPainter old) =>
      !identical(old.layout.rects, layout.rects) ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// Overlay layer that highlights the connector pair feeding one selected match.
class BracketHighlightPainter extends CustomPainter {
  BracketHighlightPainter({
    required this.layout,
    required this.highlightedMatchId,
    required this.color,
    this.strokeWidth = 2.5,
  }) : super(repaint: highlightedMatchId);

  final BracketLayout layout;
  final ValueListenable<String?> highlightedMatchId;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final key = highlightedMatchId.value;
    if (key == null || key == 'third-place') return;
    final child = layout.rects[key];
    if (child == null) return;
    final pair = _parents(layout.rects, key);
    if (pair == null) return;
    final paint = _paint(color, strokeWidth);
    _elbow(canvas, paint, pair.$1, child);
    _elbow(canvas, paint, pair.$2, child);
  }

  @override
  bool shouldRepaint(BracketHighlightPainter old) =>
      !identical(old.layout.rects, layout.rects) ||
      old.highlightedMatchId != highlightedMatchId ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

Paint _paint(Color color, double strokeWidth) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = strokeWidth
  ..isAntiAlias = true;

void _elbow(Canvas canvas, Paint paint, BoxRect parent, BoxRect child) {
  final startX = parent.right;
  final startY = parent.y + parent.height / 2;
  final endX = child.x;
  final endY = child.y + child.height / 2;
  final midX = startX + (endX - startX) / 2;
  final path = Path()
    ..moveTo(startX, startY)
    ..lineTo(midX, startY)
    ..lineTo(midX, endY)
    ..lineTo(endX, endY);
  canvas.drawPath(path, paint);
}

/// Returns `(parentA, parentB)` for a child match box, or `null` for
/// round-1 boxes / the third-place side-branch / malformed keys.
(BoxRect, BoxRect)? _parents(Map<String, BoxRect> rects, String key) {
  // Key shape: "r<round>-m<index>" — round is 1-indexed, index is 0-indexed.
  if (!key.startsWith('r')) return null;
  final dash = key.indexOf('-m');
  if (dash < 2) return null;
  final round = int.tryParse(key.substring(1, dash));
  final index = int.tryParse(key.substring(dash + 2));
  if (round == null || index == null || round <= 1) return null;
  final a = rects['r${round - 1}-m${index * 2}'];
  final b = rects['r${round - 1}-m${index * 2 + 1}'];
  if (a == null || b == null) return null;
  return (a, b);
}

int _firstRoundCount(Map<String, BoxRect> rects) {
  var count = 0;
  for (final key in rects.keys) {
    if (key.startsWith('r1-m')) count++;
  }
  return count;
}

/// Convenience accessor: prefers the kubb token line color, falls back to
/// the Material outline. Useful for callers that don't import tokens directly.
Color defaultConnectorColor(BuildContext context) =>
    Theme.of(context).extension<KubbTokens>()?.line ??
    Theme.of(context).colorScheme.outline;
