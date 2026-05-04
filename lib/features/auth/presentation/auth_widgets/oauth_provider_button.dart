import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';

/// Brand-correct OAuth button for Google and Apple, per the design
/// brief #10 / template `auth-shared.jsx`.
///
/// Variants:
///   * `primary`   — filled, white surface for Google (dark text +
///     full multi-color G mark) or black surface for Apple (white
///     glyph + label).
///   * `secondary` — muted chip used on the AccountLinkScreen; brand
///     glyph keeps its color.
class OAuthProviderButton extends StatelessWidget {
  const OAuthProviderButton({
    required this.provider,
    required this.label,
    required this.onPressed,
    this.variant = OAuthButtonVariant.primary,
    this.loading = false,
    super.key,
  });

  final AuthProvider provider;
  final String label;
  final VoidCallback? onPressed;
  final OAuthButtonVariant variant;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isApple = provider == AuthProvider.apple;
    final tokens = Theme.of(context).extension<KubbTokens>()!;

    final (background, foreground, borderColor) = switch ((variant, isApple)) {
      (OAuthButtonVariant.primary, true) => (
          Colors.black,
          Colors.white,
          Colors.transparent,
        ),
      (OAuthButtonVariant.primary, false) => (
          Colors.white,
          const Color(0xFF1F1F1F),
          tokens.lineStrong,
        ),
      (OAuthButtonVariant.secondary, _) => (
          tokens.bgSunken,
          tokens.fg,
          tokens.line,
        ),
    };

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor, width: 1.5),
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        ),
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: KubbTokens.touchComfortable,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space5,
              vertical: KubbTokens.space3,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BrandGlyph(
                  isApple: isApple,
                  darkBackground: variant == OAuthButtonVariant.primary && isApple,
                ),
                const SizedBox(width: KubbTokens.space3),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (loading) ...[
                  const SizedBox(width: KubbTokens.space3),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum OAuthButtonVariant { primary, secondary }

class _BrandGlyph extends StatelessWidget {
  const _BrandGlyph({required this.isApple, required this.darkBackground});

  final bool isApple;
  final bool darkBackground;

  @override
  Widget build(BuildContext context) {
    if (isApple) {
      return Icon(
        Icons.apple,
        size: 22,
        color: darkBackground ? Colors.white : Colors.black,
      );
    }
    // Google "G" — simple coloured circle with G letter, follows
    // brand-mark spirit. Real multi-color SVG would need flutter_svg
    // and an asset; the design brief allows this simpler form for v1.
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Color(0xFFEA4335),
            Color(0xFFFBBC05),
            Color(0xFF34A853),
            Color(0xFF4285F4),
          ],
          stops: [0.0, 0.33, 0.66, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
