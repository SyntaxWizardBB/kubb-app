import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Tone of [AuthPrimaryButton].
///
///   * `primary` — filled with `tokens.primary` / `tokens.onPrimary`.
///   * `danger`  — filled with `KubbTokens.miss` and white text. Used
///     for destructive confirmations (account deletion).
enum AuthButtonTone { primary, danger }

/// Filled primary button used across the auth flows: full width,
/// comfortable touch height, optional inline loading spinner.
// TODO(W2-T4-followup): auf KubbButton (variant primary/danger, size large,
// isLoading) umstellen. Spezialitaet hier ist nur das `width: double.infinity`,
// der Rest deckt sich mit der Brand-Komponente.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.tone = AuthButtonTone.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final AuthButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final isDanger = tone == AuthButtonTone.danger;
    final background = isDanger ? KubbTokens.miss : tokens.primary;
    final foreground = isDanger ? Colors.white : tokens.onPrimary;

    return SizedBox(
      width: double.infinity,
      height: KubbTokens.touchComfortable,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
            ],
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
