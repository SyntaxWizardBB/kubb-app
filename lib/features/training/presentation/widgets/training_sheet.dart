import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class TrainingSheet extends StatelessWidget {
  const TrainingSheet({super.key});

  static Future<void> show(BuildContext context) async => showKubbBottomSheet<void>(
        context,
        builder: (_) => const TrainingSheet(),
        header: const _Header(),
      );

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: KubbTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeCard(
            background: tokens.primary,
            foreground: tokens.onPrimary,
            title: l.modeSniperTitle,
            subtitle: l.modeSniperSubtitle,
            trailing: '8 m',
            onTap: () {
              Navigator.of(context).pop();
              context.go('/training/sniper/config');
            },
          ),
          const SizedBox(height: KubbTokens.space3),
          _ModeCard(
            background: KubbTokens.stone900,
            foreground: KubbTokens.chalk50,
            title: l.modeFinisseurTitle,
            subtitle: l.modeFinisseurSubtitle,
            trailing: '7/3',
            onTap: () {
              Navigator.of(context).pop();
              context.go('/training/finisseur/config');
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.trainingSheetEyebrow.toUpperCase(),
            style: t.labelSmall?.copyWith(
              fontSize: 11, fontWeight: FontWeight.w600,
              letterSpacing: 0.88, color: tokens.fgMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l.trainingSheetTitle,
            style: t.titleLarge?.copyWith(
              fontSize: 22, fontWeight: FontWeight.w700,
              letterSpacing: -0.44, color: tokens.fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.background, required this.foreground,
    required this.title, required this.subtitle,
    required this.trailing, required this.onTap,
  });

  final Color background;
  final Color foreground;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = foreground.withValues(alpha: 0.85);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space5, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.headlineSmall?.copyWith(
                        fontSize: 24, fontWeight: FontWeight.w800,
                        letterSpacing: -0.48, height: 1.1, color: foreground,
                      )),
                      const SizedBox(height: 2),
                      Text(subtitle, style: t.bodyMedium?.copyWith(fontSize: 13, color: muted)),
                    ],
                  ),
                ),
                Text(trailing, style: t.headlineMedium?.copyWith(
                  fontSize: 32, fontWeight: FontWeight.w800,
                  letterSpacing: -0.96, color: foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
