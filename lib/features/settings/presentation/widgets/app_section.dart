import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/features/settings/presentation/widgets/settings_control_row.dart';
import 'package:kubb_app/features/settings/presentation/widgets/settings_row.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// General app preferences: language, theme, vibration and the global heli
/// tracking toggle. Finisseur-specific tracking lives in [FinisseurOptionsBlock]
/// and legal links in [LegalBlock] — split out so each settings section owns a
/// single, scannable group (the old monolithic block crammed all of them plus
/// version into one container).
class AppOptionsBlock extends ConsumerWidget {
  const AppOptionsBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final asyncSettings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

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
          SettingsControlRow(
            label: l.settingsLanguage,
            trailing: Text(
              l.settingsLanguageValue,
              style: TextStyle(color: tokens.fgMuted),
            ),
          ),
          SettingsControlRow(
            label: l.settingsTheme,
            // "Sonnenlicht" (high-contrast) was retired from the picker. Any
            // legacy highContrast selection shows as Hell here.
            trailing: SegmentedButton<ThemeChoice>(
              segments: [
                ButtonSegment(
                    value: ThemeChoice.light, label: Text(l.themeLight)),
                ButtonSegment(
                    value: ThemeChoice.dark, label: Text(l.themeDark)),
              ],
              selected: {
                if (settings.themeChoice == ThemeChoice.dark)
                  ThemeChoice.dark
                else
                  ThemeChoice.light,
              },
              onSelectionChanged: (s) => notifier.setTheme(s.first),
            ),
          ),
          SettingsControlRow(
            label: l.settingsVibration,
            trailing: Switch(
              value: settings.vibration,
              onChanged: (v) => notifier.setVibration(value: v),
            ),
          ),
          SettingsControlRow(
            label: l.settingsHeli,
            trailing: Switch(
              value: settings.heliTracking,
              onChanged: (v) => notifier.setHeliTracking(value: v),
            ),
          ),
        ],
      ),
    );
  }
}

/// Finisseur-specific tracking toggles. Disabling one of these drops the
/// matching metric from the finisseur stats and quota (see stats repository),
/// so the group is kept separate from the global app preferences.
class FinisseurOptionsBlock extends ConsumerWidget {
  const FinisseurOptionsBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final asyncSettings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

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
          SettingsControlRow(
            label: l.settingsLongDubbie,
            trailing: Switch(
              value: settings.longDubbieTracking,
              onChanged: (v) => notifier.setLongDubbieTracking(value: v),
            ),
          ),
          SettingsControlRow(
            label: l.settingsPenaltyKubb,
            trailing: Switch(
              value: settings.penaltyKubbTracking,
              onChanged: (v) => notifier.setPenaltyKubbTracking(value: v),
            ),
          ),
          SettingsControlRow(
            label: l.settingsKingThrow,
            trailing: Switch(
              value: settings.kingThrowTracking,
              onChanged: (v) => notifier.setKingThrowTracking(value: v),
            ),
          ),
          SettingsControlRow(
            label: l.settingsAllowContinue,
            subtitle: l.settingsAllowContinueSub,
            trailing: Switch(
              value: settings.allowContinueBeyondSticks,
              onChanged: (v) =>
                  notifier.setAllowContinueBeyondSticks(value: v),
            ),
          ),
        ],
      ),
    );
  }
}

/// Privacy explanation + the two legal destinations (privacy policy, imprint).
class LegalBlock extends StatelessWidget {
  const LegalBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KubbTokens.space4,
            KubbTokens.space3,
            KubbTokens.space4,
            KubbTokens.space2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.settingsPrivacyHeader,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: tokens.fg,
                ),
              ),
              const SizedBox(height: KubbTokens.space1),
              Text(
                l.settingsPrivacyBody,
                style: TextStyle(color: tokens.fgMuted, fontSize: 12),
              ),
              const SizedBox(height: KubbTokens.space1),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: AlignmentDirectional.centerStart,
                  ),
                  onPressed: () => context.push('/legal/privacy'),
                  child: Text(l.settingsPrivacyLinkLabel),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.line),
        SettingsRow(
          icon: LucideIcons.shieldCheck,
          label: l.settingsRowPrivacyPolicy,
          onTap: () => context.push('/legal/privacy'),
        ),
        SettingsRow(
          icon: LucideIcons.fileText,
          label: l.settingsRowImprint,
          onTap: () => context.push('/legal/imprint'),
        ),
      ],
    );
  }
}

/// App version line, rendered in the settings footer. Best-effort: shows a
/// dash until [PackageInfo] resolves (and silently stays dashed in tests where
/// the platform channel is unavailable).
class SettingsVersionRow extends StatefulWidget {
  const SettingsVersionRow({super.key});

  @override
  State<SettingsVersionRow> createState() => _SettingsVersionRowState();
}

class _SettingsVersionRowState extends State<SettingsVersionRow> {
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
    final text =
        info == null ? '—' : l.settingsVersion(info.version, info.buildNumber);
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: tokens.fgMuted, fontSize: 12),
    );
  }
}
