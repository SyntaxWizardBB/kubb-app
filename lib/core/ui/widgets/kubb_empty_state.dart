import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Zentrales Empty-State-Widget fuer leere Listen.
///
/// Quelle:
/// - `docs/design/AUDIT.md` §4.2 — Empty-States bekommen "kleinen K+Crown
///   vignette + ein Satz + Action-CTA".
/// - `docs/bug-hunt-2026-q3/master-report.md` R18-F-14 (Re-Hit Maengel #1):
///   Empty-States waren zu spartanisch (nur Text), kein CTA, keine
///   visuelle Differenzierung. Mit diesem Widget loesen wir das pro
///   Erst-Nutzer-Pfad konsistent.
///
/// Layout:
/// 1. K+Crown-Vignette (96 dp, [KubbTokens.stone400] tinted, Opacity 0.6).
///    Die Vignette wird vom [KubbCrownVignette]-Painter gezeichnet und
///    folgt der Silhouette aus `docs/design/assets/logo-monogram.svg`
///    (gekreuzte Hoelzer + Koenigsstueck mit Krone), ohne die Holz-/
///    Gold-Gradienten — wir zeigen nur die Stein-getoente Form.
/// 2. [title] in 22 dp / FontWeight.w700.
/// 3. [body] in 14 dp / [KubbTokens.fgMuted].
/// 4. Optional [cta] (typisch `KubbButton(variant: primary, ...)`).
class KubbEmptyState extends StatelessWidget {
  const KubbEmptyState({
    required this.title,
    required this.body,
    super.key,
    this.vignette,
    this.cta,
  });

  /// Ueberschreibbare Vignette. Wenn `null`, wird die Default-K+Crown-
  /// Silhouette gezeichnet ([KubbCrownVignette]).
  final Widget? vignette;
  final String title;
  final String body;
  final Widget? cta;

  /// Default-Vignette-Groesse in dp (siehe AUDIT §4.2: "klein").
  static const double vignetteSize = 96;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final effectiveVignette = vignette ??
        const SizedBox(
          width: vignetteSize,
          height: vignetteSize,
          child: KubbCrownVignette(),
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KubbTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            effectiveVignette,
            const SizedBox(height: KubbTokens.space4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: tokens.fg,
              ),
            ),
            const SizedBox(height: KubbTokens.space2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: tokens.fgMuted,
              ),
            ),
            if (cta != null) ...[
              const SizedBox(height: KubbTokens.space5),
              cta!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Stein-getoente K+Crown-Silhouette als CustomPainter.
///
/// Die Form folgt `docs/design/assets/logo-monogram.svg`:
/// gekreuzte diagonale Hoelzer + senkrechtes Koenigsstueck + Krone mit
/// drei Zacken plus Mittelkreuz. Anders als das Vollfarb-Logo zeichnen
/// wir nur die Silhouette in [KubbTokens.stone400] mit Opacity 0.6 —
/// damit die Vignette als "kleines Markenzeichen" und nicht als
/// Hero-Logo wirkt (AUDIT §4.2).
class KubbCrownVignette extends StatelessWidget {
  const KubbCrownVignette({super.key, this.tint, this.opacity = 0.6});

  /// Tint-Farbe. Default = [KubbTokens.stone400].
  final Color? tint;

  /// Opacity ueber dem Tint. Default 0.6 — siehe Task-Spec.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final color = (tint ?? KubbTokens.stone400).withValues(alpha: opacity);
    return CustomPaint(
      painter: _CrownVignettePainter(color: color),
    );
  }
}

class _CrownVignettePainter extends CustomPainter {
  _CrownVignettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // SVG-Viewbox ist 240x240; wir skalieren proportional auf die
    // verfuegbare Flaeche und zentrieren.
    final scale =
        size.shortestSide / 240.0; // longestSide waere asymmetrisch
    final dx = (size.width - 240 * scale) / 2;
    final dy = (size.height - 240 * scale) / 2;

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // SVG hat insgesamt eine `translate(-8, 0)` auf alle Gruppen. Wir
    // ziehen das einmal ab, um die Original-Koordinaten beizubehalten.
    canvas.translate(-8, 0);

    // --- Gekreuzte Hoelzer (zwei Latten, je um +/-44 Grad gedreht) ---
    final stickRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(92, 132, 120, 32),
      const Radius.circular(4),
    );
    for (final rot in <double>[-44, 44]) {
      canvas
        ..save()
        ..translate(100, 148)
        ..rotate(rot * 3.1415926535 / 180.0)
        ..translate(-100, -148)
        ..drawRRect(stickRect, fill)
        ..restore();
    }

    // --- Senkrechtes Koenigsstueck (King) ---
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(44, 78, 60, 148),
        const Radius.circular(5),
      ),
      fill,
    );

    // --- Krone (drei Zacken + Plattform + Mittelkreuz) ---
    // Linker Zacken
    final left = Path()
      ..moveTo(38, 62)
      ..lineTo(50, 26)
      ..lineTo(64, 62)
      ..close();
    // Rechter Zacken
    final right = Path()
      ..moveTo(84, 62)
      ..lineTo(98, 26)
      ..lineTo(110, 62)
      ..close();
    // Mittlerer Zacken
    final mid = Path()
      ..moveTo(60, 62)
      ..lineTo(74, 12)
      ..lineTo(88, 62)
      ..close();
    canvas
      ..drawPath(left, fill)
      ..drawPath(right, fill)
      ..drawPath(mid, fill)
      ..drawCircle(const Offset(50, 26), 4, fill)
      ..drawCircle(const Offset(98, 26), 4, fill)
      // Mittelkreuz (vertikaler + horizontaler Balken)
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(71, 6, 6, 14),
          const Radius.circular(1.2),
        ),
        fill,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(67, 10, 14, 6),
          const Radius.circular(1.2),
        ),
        fill,
      )
      // Plattform der Krone
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(32, 60, 84, 22),
          const Radius.circular(4),
        ),
        fill,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _CrownVignettePainter old) =>
      old.color != color;
}
