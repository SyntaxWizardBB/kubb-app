import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Page header for the organiser desktop surface: eyebrow, title, one line of
/// context, and the two standing actions. Wraps the actions under the text on
/// a narrow window rather than letting the row overflow.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.onExport,
    this.onCreateTournament,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback? onExport;
  final VoidCallback? onCreateTournament;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(36, 30, 36, 22),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: KubbTokens.space6,
        runSpacing: KubbTokens.space4,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                    color: tokens.fgMuted,
                  ),
                ),
                const SizedBox(height: KubbTokens.space1 + 2),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 42,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.05,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: KubbTokens.space2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: tokens.fgMuted,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderButton(
                label: l.adminActionExport,
                onPressed: onExport,
              ),
              const SizedBox(width: KubbTokens.space2 + 2),
              _HeaderButton(
                label: l.adminActionCreateTournament,
                onPressed: onCreateTournament,
                primary: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      height: 42,
      child: primary
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: KubbTokens.meadow600,
                foregroundColor: tokens.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space4 + 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.fg,
                backgroundColor: tokens.bgRaised,
                side: const BorderSide(
                  color: KubbTokens.stone200,
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(label),
            ),
    );
  }
}
