// Pure-Dart layout math for bracket visualization (ADR-0016).
// No Flutter imports: this package must remain Flutter-free (ADR-0001).
import 'package:collection/collection.dart';
import 'package:kubb_domain/src/tournament/bracket.dart';
import 'package:meta/meta.dart';

const double touchMin = 48;

@immutable
class LayoutParams {
  const LayoutParams({
    this.boxWidth = 160,
    this.boxHeight = 60,
    this.roundGap = 24,
    this.matchGap = 8,
  });
  final double boxWidth;
  final double boxHeight;
  final double roundGap;
  final double matchGap;
}

@immutable
class Point {
  const Point(this.x, this.y);
  final double x;
  final double y;
  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

@immutable
class BoxRect {
  const BoxRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.phase = BracketPhase.winners,
    this.isBye = false,
  });
  final double x;
  final double y;
  final double width;
  final double height;
  final BracketPhase phase;
  final bool isBye;
  double get right => x + width;
  double get bottom => y + height;
  @override
  bool operator ==(Object other) =>
      other is BoxRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.phase == phase &&
      other.isBye == isBye;
  @override
  int get hashCode => Object.hash(x, y, width, height, phase, isBye);
}

@immutable
class BracketLayout {
  const BracketLayout(this.rects);

  factory BracketLayout.compute(
    Bracket bracket, {
    LayoutParams params = const LayoutParams(),
  }) {
    final rects = <String, BoxRect>{};
    if (bracket is! SingleEliminationBracket) return BracketLayout(rects);
    final winners = bracket.rounds
        .where((r) => r.phase != BracketPhase.thirdPlace)
        .toList();
    if (winners.isEmpty) return BracketLayout(rects);
    final pitch1 = params.boxHeight + params.matchGap;
    final stride = params.boxWidth + params.roundGap;
    final lastR = winners.map((r) => r.number).reduce((a, b) => a > b ? a : b);
    for (final round in winners) {
      final r = round.number;
      final pitchR = pitch1 * (1 << (r - 1));
      final yOffset = (pitchR - pitch1) / 2;
      for (var i = 0; i < round.pairings.length; i++) {
        final p = round.pairings[i];
        rects['r$r-m$i'] = BoxRect(
          x: (r - 1) * stride,
          y: i * pitchR + yOffset,
          width: params.boxWidth,
          height: params.boxHeight,
          phase: r == lastR ? BracketPhase.finals : BracketPhase.winners,
          isBye: p.$1.isBye || p.$2.isBye,
        );
      }
    }
    final third = bracket.rounds
        .where((r) => r.phase == BracketPhase.thirdPlace)
        .firstOrNull;
    if (third != null && third.pairings.isNotEmpty) {
      final p = third.pairings.first;
      rects['third-place'] = BoxRect(
        x: lastR * stride,
        y: 0,
        width: params.boxWidth,
        height: params.boxHeight,
        phase: BracketPhase.thirdPlace,
        isBye: p.$1.isBye || p.$2.isBye,
      );
    }
    return BracketLayout(rects);
  }

  final Map<String, BoxRect> rects;
}
