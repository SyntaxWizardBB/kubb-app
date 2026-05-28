// Skeleton-Loading-Widgets (AUDIT §4.3).
//
// Drei Konsumenten — Recent-Sessions, Stats-Charts, Tournament-Standings —
// blenden waehrend `AsyncValue.loading` graue Platzhalter mit Shimmer-Effekt
// ein. Eigene Implementation, bewusst ohne `shimmer`-Paket: ein
// `AnimationController` mit `repeat(reverse: true)` schiebt einen
// `LinearGradient` (stone-200 → chalk-50 → stone-200) ueber die Flaeche.
//
// Animation laeuft 1.2 s linear, kehrt um → 2.4 s Vollzyklus. Pausiert,
// wenn Disable-Animations-Setting greift (MediaQuery `disableAnimations`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

const Duration _kCycle = Duration(milliseconds: 1200);

/// Grauer Shimmer-Platzhalter. Drei Factories decken die Audit-Use-Cases ab:
///
/// * [KubbSkeleton.bar]   – einzelne rechteckige Bar (Text-Zeile).
/// * [KubbSkeleton.row]   – Tabellen-Zeile mit `columns` Bars.
/// * [KubbSkeleton.chart] – Wellen-Pattern fuer Trend-Charts.
class KubbSkeleton extends StatefulWidget {
  const KubbSkeleton._({
    required this.builder,
    required this.semanticsLabel,
    super.key,
  });

  /// Rechteckige Shimmer-Bar. `width=double.infinity` macht eine Full-Width-Bar.
  factory KubbSkeleton.bar({
    Key? key,
    double width = double.infinity,
    double height = 12,
    double radius = KubbTokens.radiusSm,
    String? semanticsLabel,
  }) {
    return KubbSkeleton._(
      key: key,
      semanticsLabel: semanticsLabel ?? 'Lade Inhalt',
      builder: (gradient) => _ShimmerBox(
        width: width,
        height: height,
        radius: radius,
        gradient: gradient,
      ),
    );
  }

  /// Tabellen-Zeile mit [columns] gleich breiten Bars. Erste Spalte schmaler
  /// (Rank/Avatar), letzte etwas breiter — Heuristik fuer die drei
  /// Konsumenten-Tabellen.
  factory KubbSkeleton.row({
    Key? key,
    int columns = 4,
    double height = 14,
    String? semanticsLabel,
  }) {
    assert(columns >= 1, 'columns must be >= 1');
    return KubbSkeleton._(
      key: key,
      semanticsLabel: semanticsLabel ?? 'Lade Zeile',
      builder: (gradient) => _ShimmerRow(
        columns: columns,
        height: height,
        gradient: gradient,
      ),
    );
  }

  /// Wellen-Pattern fuer Trend-/Aggregate-Charts.
  factory KubbSkeleton.chart({
    Key? key,
    double height = 140,
    String? semanticsLabel,
  }) {
    return KubbSkeleton._(
      key: key,
      semanticsLabel: semanticsLabel ?? 'Lade Diagramm',
      builder: (gradient) => _ShimmerChart(
        height: height,
        gradient: gradient,
      ),
    );
  }

  final Widget Function(LinearGradient gradient) builder;
  final String semanticsLabel;

  @override
  State<KubbSkeleton> createState() => _KubbSkeletonState();
}

class _KubbSkeletonState extends State<KubbSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _kCycle);
    // `_maybeStart` liest `MediaQuery` und darf erst nach `initState`
    // laufen — `didChangeDependencies` ist der korrekte Hook.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  void _maybeStart() {
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disable) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0.5;
      return;
    }
    if (!_controller.isAnimating) {
      // repeat() liefert ein TickerFuture, das niemals normal completed.
      // dispose() canceled den Ticker — wir muessen das Future nicht awaiten.
      unawaited(_controller.repeat(reverse: true).orCancel.catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel,
      liveRegion: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final gradient = _shimmerGradient(_controller.value);
          return widget.builder(gradient);
        },
      ),
    );
  }
}

/// stone-200 → chalk-50 → stone-200. Die Position der Highlight-Stops
/// laeuft mit `t` ∈ [0, 1] von links nach rechts ueber die Flaeche.
LinearGradient _shimmerGradient(double t) {
  // Highlight-Mitte bewegt sich von -0.3 → 1.3, damit die helle Zone an
  // beiden Raendern komplett aus dem Frame laeuft (sonst „kleben" Helligkeit
  // an den Kanten).
  final centre = -0.3 + 1.6 * t;
  final left = (centre - 0.3).clamp(0.0, 1.0);
  final right = (centre + 0.3).clamp(0.0, 1.0);
  return LinearGradient(
    colors: const [
      KubbTokens.stone200,
      KubbTokens.chalk50,
      KubbTokens.stone200,
    ],
    stops: [
      0.0,
      // centre kann ausserhalb [0,1] liegen → clamp damit Stops monoton steigen.
      (left + right) / 2,
      1.0,
    ].map((v) => v.clamp(0.0, 1.0)).toList(growable: false),
  );
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.gradient,
  });

  final double width;
  final double height;
  final double radius;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _ShimmerRow extends StatelessWidget {
  const _ShimmerRow({
    required this.columns,
    required this.height,
    required this.gradient,
  });

  final int columns;
  final double height;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    // Flex-Schema: erste Spalte schmaler (Rank), zweite breit (Name),
    // restliche Spalten gleich breit.
    final flexes = <int>[
      if (columns >= 1) 1,
      if (columns >= 2) 4,
      for (var i = 0; i < columns - 2; i++) 2,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
      child: Row(
        children: [
          for (var i = 0; i < columns; i++) ...[
            if (i > 0) const SizedBox(width: KubbTokens.space3),
            Expanded(
              flex: flexes[i],
              child: _ShimmerBox(
                width: double.infinity,
                height: height,
                radius: KubbTokens.radiusSm,
                gradient: gradient,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShimmerChart extends StatelessWidget {
  const _ShimmerChart({required this.height, required this.gradient});

  final double height;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavePainter(gradient: gradient),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.gradient});

  final LinearGradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Drei wellige Linien, leicht versetzt, fuellen die Chart-Flaeche.
    final lanes = [0.30, 0.55, 0.80];
    for (final lane in lanes) {
      final path = Path();
      final baseY = size.height * lane;
      const segments = 24;
      for (var i = 0; i <= segments; i++) {
        final x = size.width * i / segments;
        // Sinus mit Phase pro Lane → keine identischen Linien.
        final phase = lane * 6.28;
        final y = baseY +
            (size.height * 0.06) *
                _sin(i / segments * 6.28 * 2 + phase);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  // Inline-Sinus statt `dart:math` import — minimiert Dependency-Surface
  // und ist genau genug fuer ein Skeleton-Pattern.
  double _sin(double x) {
    // Bhaskara-I-Approximation: max-Fehler ~1.6 %, fuer Skeleton irrelevant.
    // Normalisiere x in [-pi, pi].
    const twoPi = 6.283185307179586;
    var v = x % twoPi;
    if (v > 3.141592653589793) v -= twoPi;
    if (v < -3.141592653589793) v += twoPi;
    final sign = v < 0 ? -1.0 : 1.0;
    final a = v.abs();
    final num = 16 * a * (3.141592653589793 - a);
    final den = 5 * 3.141592653589793 * 3.141592653589793 - 4 * a * (3.141592653589793 - a);
    return sign * num / den;
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.gradient != gradient;
}
