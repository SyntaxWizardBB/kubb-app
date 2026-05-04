import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Mandatory disclaimer block per AK-19 / design brief #3.
/// Three explicit warnings — never just a flash modal.
class DisclaimerBlock extends StatelessWidget {
  const DisclaimerBlock({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final bullets = [
      l10n.authDisclaimerNoReset,
      l10n.authDisclaimerPasswordManager,
      l10n.authDisclaimerNoLiability,
    ];

    return Semantics(
      label: l10n.authDisclaimerHeading,
      container: true,
      child: Container(
        padding: EdgeInsets.all(compact ? KubbTokens.space3 : KubbTokens.space4),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF2D6),
          border: Border.all(color: const Color(0xFFD4AE3B), width: 1.5),
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: Color(0xFF5A4500),
                ),
                const SizedBox(width: KubbTokens.space2),
                Text(
                  l10n.authDisclaimerHeading,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5A4500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KubbTokens.space3),
            for (var i = 0; i < bullets.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5A4500),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      bullets[i],
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        fontWeight:
                            i == 0 ? FontWeight.w700 : FontWeight.w400,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                ],
              ),
              if (i < bullets.length - 1)
                const SizedBox(height: KubbTokens.space2),
            ],
          ],
        ),
      ),
    );
  }
}
