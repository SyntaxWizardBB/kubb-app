// Pure-Dart layout math for bracket visualization (ADR-0016).
// No Flutter imports: this package must remain Flutter-free (ADR-0001).
// Full compute() implementation lands in TASK-M2.1-T8.
import 'package:kubb_domain/src/tournament/bracket.dart';
import 'package:meta/meta.dart';

const double touchMin = 48;

enum BracketPhase { winners, thirdPlace, final_ }

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
  final Map<String, BoxRect> rects;

  static BracketLayout compute(Bracket bracket) =>
      throw UnimplementedError('BracketLayout.compute is implemented in T8');
}
