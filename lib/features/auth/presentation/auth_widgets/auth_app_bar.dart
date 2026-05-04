import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Slim top bar for single-page auth screens: back button + an
/// eyebrow/title pair on the left.
///
/// Used by AccountLink, PassphraseChange and EditProfile screens.
class AuthAppBar extends StatelessWidget {
  const AuthAppBar({
    required this.eyebrow,
    required this.title,
    required this.onBack,
    super.key,
  });

  final String eyebrow;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: KubbTokens.space2),
      child: Row(
        children: [
          SizedBox(
            width: KubbTokens.touchMin,
            height: KubbTokens.touchMin,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.authCommonBack,
            ),
          ),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.fgMuted,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KubbTokens.touchMin),
        ],
      ),
    );
  }
}
