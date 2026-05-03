import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: KubbTokens.space2,
              bottom: KubbTokens.space2,
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: tokens.fgMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: tokens.bgRaised,
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
