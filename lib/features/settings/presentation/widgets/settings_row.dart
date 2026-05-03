import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final fg = danger ? tokens.danger : tokens.fg;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space4,
            vertical: KubbTokens.space3,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tokens.bgSunken,
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                ),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: KubbTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: tokens.fgMuted),
            ],
          ),
        ),
      ),
    );
  }
}
