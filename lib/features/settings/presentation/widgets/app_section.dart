import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsAppBlock extends ConsumerWidget {
  const SettingsAppBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final asyncSettings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    Widget row(String label, Widget trailing, {String? subtitle}) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space4,
            vertical: KubbTokens.space2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: TextStyle(color: tokens.fgMuted)),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.fgSubtle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        );

    return asyncSettings.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(KubbTokens.space4),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(KubbTokens.space4),
        child: Text(e.toString(), style: TextStyle(color: tokens.danger)),
      ),
      data: (settings) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(l.settingsLanguage, Text(l.settingsLanguageValue)),
          row(
            l.settingsTheme,
            SegmentedButton<ThemeChoice>(
              segments: [
                ButtonSegment(
                    value: ThemeChoice.light, label: Text(l.themeLight)),
                ButtonSegment(
                    value: ThemeChoice.dark, label: Text(l.themeDark)),
                ButtonSegment(
                    value: ThemeChoice.highContrast,
                    label: Text(l.themeHighContrast)),
              ],
              selected: {settings.themeChoice},
              onSelectionChanged: (s) => notifier.setTheme(s.first),
            ),
          ),
          row(
            l.settingsHeli,
            Switch(
              value: settings.heliTracking,
              onChanged: (v) => notifier.setHeliTracking(value: v),
            ),
          ),
          row(
            l.settingsVibration,
            Switch(
              value: settings.vibration,
              onChanged: (v) => notifier.setVibration(value: v),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space4,
              KubbTokens.space3,
              KubbTokens.space4,
              0,
            ),
            child: Text(
              l.settingsFinisseurSection.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted,
              ),
            ),
          ),
          row(
            l.settingsLongDubbie,
            Switch(
              value: settings.longDubbieTracking,
              onChanged: (v) => notifier.setLongDubbieTracking(value: v),
            ),
          ),
          row(
            l.settingsPenaltyKubb,
            Switch(
              value: settings.penaltyKubbTracking,
              onChanged: (v) => notifier.setPenaltyKubbTracking(value: v),
            ),
          ),
          row(
            l.settingsKingThrow,
            Switch(
              value: settings.kingThrowTracking,
              onChanged: (v) => notifier.setKingThrowTracking(value: v),
            ),
          ),
          row(
            l.settingsAllowContinue,
            Switch(
              value: settings.allowContinueBeyondSticks,
              onChanged: (v) =>
                  notifier.setAllowContinueBeyondSticks(value: v),
            ),
            subtitle: l.settingsAllowContinueSub,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space4,
              KubbTokens.space3,
              KubbTokens.space4,
              KubbTokens.space3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.settingsPrivacyHeader,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: tokens.fg,
                    )),
                const SizedBox(height: KubbTokens.space1),
                Text(l.settingsPrivacyBody,
                    style: TextStyle(color: tokens.fgMuted, fontSize: 12)),
              ],
            ),
          ),
          const _VersionRow(),
        ],
      ),
    );
  }
}

class _VersionRow extends StatefulWidget {
  const _VersionRow();

  @override
  State<_VersionRow> createState() => _VersionRowState();
}

class _VersionRowState extends State<_VersionRow> {
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
      // Channel unavailable in tests — silently skip.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final info = _info;
    final l = AppLocalizations.of(context);
    final text = info == null
        ? '—'
        : l.settingsVersion(info.version, info.buildNumber);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space2,
        KubbTokens.space4,
        KubbTokens.space3,
      ),
      child: Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(color: tokens.fgMuted))),
        ],
      ),
    );
  }
}
