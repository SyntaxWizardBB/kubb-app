import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppSettingsModal extends ConsumerWidget {
  const AppSettingsModal({super.key});

  static Future<void> show(BuildContext context) async =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AppSettingsModal(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final asyncSettings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(color: tokens.fgMuted);

    Widget row(String label, Widget trailing) => Padding(
          padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
          child: Row(children: [Expanded(child: Text(label, style: labelStyle)), trailing]),
        );

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(KubbTokens.radiusXl)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KubbTokens.space4, KubbTokens.space2, KubbTokens.space4, KubbTokens.space4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: KubbTokens.space3),
                  decoration: BoxDecoration(
                    color: tokens.line,
                    borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
                  ),
                ),
              ),
              Text(l.settingsTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: KubbTokens.space4),
              _StatsLink(label: l.statsTitle, tokens: tokens),
              const SizedBox(height: KubbTokens.space4),
              asyncSettings.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(KubbTokens.space6),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text(e.toString(), style: TextStyle(color: tokens.danger)),
                data: (settings) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    row(l.settingsLanguage, Text(l.settingsLanguageValue, style: TextStyle(color: tokens.fg))),
                    row(l.settingsTheme, SegmentedButton<ThemeChoice>(
                      segments: [
                        ButtonSegment(value: ThemeChoice.light, label: Text(l.themeLight)),
                        ButtonSegment(value: ThemeChoice.dark, label: Text(l.themeDark)),
                        ButtonSegment(value: ThemeChoice.highContrast, label: Text(l.themeHighContrast)),
                      ],
                      selected: {settings.themeChoice},
                      onSelectionChanged: (s) => notifier.setTheme(s.first),
                    )),
                    row(l.settingsHeli, Switch(
                      value: settings.heliTracking,
                      onChanged: (v) => notifier.setHeliTracking(value: v),
                    )),
                    row(l.settingsVibration, Switch(
                      value: settings.vibration,
                      onChanged: (v) => notifier.setVibration(value: v),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: KubbTokens.space4),
              const _VersionFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsLink extends StatelessWidget {
  const _StatsLink({required this.label, required this.tokens});

  final String label;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Material(
        color: tokens.bg,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          onTap: () {
            Navigator.of(context).pop();
            unawaited(context.push('/stats'));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space3,
              vertical: KubbTokens.space3,
            ),
            child: Row(
              children: [
                Icon(LucideIcons.barChart3, size: 20, color: tokens.fg),
                const SizedBox(width: KubbTokens.space3),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tokens.fg,
                    ),
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 20, color: tokens.fgMuted),
              ],
            ),
          ),
        ),
      );
}

class _VersionFooter extends StatefulWidget {
  const _VersionFooter();

  @override
  State<_VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<_VersionFooter> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _info = info);
    } on Object {
      // Gracefully degrade when the platform channel is unavailable (e.g. tests).
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Center(
      child: Text(
        AppLocalizations.of(context).settingsVersion(info.version, info.buildNumber),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tokens.fgMuted),
      ),
    );
  }
}
