import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/presentation/avatar_color.dart';
import 'package:kubb_app/features/settings/application/danger_actions_notifier.dart';
import 'package:kubb_app/features/settings/presentation/confirm_dialog.dart';
import 'package:kubb_app/features/settings/presentation/csv_export_modal.dart';
import 'package:kubb_app/features/settings/presentation/widgets/app_section.dart';
import 'package:kubb_app/features/settings/presentation/widgets/settings_row.dart';
import 'package:kubb_app/features/settings/presentation/widgets/settings_section.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(eyebrow: l.settingsScreenEyebrow, title: l.settingsTitle),
      body: ListView(
        padding: const EdgeInsets.only(bottom: KubbTokens.space8),
        children: [
          profileAsync.when(
            loading: () => const SizedBox(height: 80),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(KubbTokens.space4),
              child: Text(e.toString(), style: TextStyle(color: tokens.danger)),
            ),
            data: (player) => player == null
                ? const SizedBox.shrink()
                : _ProfileHeader(name: player.name, deviceId: player.deviceId,
                    avatarColor: AvatarColorHelper.resolve(
                      player.avatarColor,
                      seed: player.id,
                    )),
          ),
          SettingsSection(
            title: l.settingsAccountSection,
            children: [
              SettingsRow(
                icon: LucideIcons.user,
                label: l.settingsRowProfile,
                subtitle: l.settingsRowProfileSub,
                onTap: () => context.push('/profile'),
              ),
              SettingsRow(
                icon: LucideIcons.trash2,
                label: l.settingsRowDeleteProfile,
                subtitle: l.settingsRowDeleteProfileSub,
                danger: true,
                onTap: () => _confirmDeleteProfile(context, ref),
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsDataSection,
            children: [
              SettingsRow(
                icon: LucideIcons.barChart3,
                label: l.settingsRowStats,
                subtitle: l.settingsRowStatsSub,
                onTap: () => context.push('/stats'),
              ),
              SettingsRow(
                icon: LucideIcons.download,
                label: l.settingsRowExport,
                subtitle: l.settingsRowExportSub,
                onTap: () => CsvExportModal.show(context),
              ),
              SettingsRow(
                icon: LucideIcons.eraser,
                label: l.settingsRowResetSessions,
                subtitle: l.settingsRowResetSessionsSub,
                danger: true,
                onTap: () => _confirmResetSessions(context, ref),
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsAppSection,
            children: const [SettingsAppBlock()],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space4,
              KubbTokens.space5,
              KubbTokens.space4,
              0,
            ),
            child: Center(
              child: Text(
                l.settingsFooterTagline,
                style: TextStyle(color: tokens.fgMuted, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetSessions(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDangerConfirm(
      context: context,
      title: l.confirmResetSessionsTitle,
      body: l.confirmResetSessionsBody,
    );
    if (!confirmed) return;
    await ref.read(dangerActionsProvider).resetSessions();
    messenger.showSnackBar(SnackBar(content: Text(l.settingsResetDoneSnack)));
  }

  Future<void> _confirmDeleteProfile(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDangerConfirm(
      context: context,
      title: l.confirmDeleteProfileTitle,
      body: l.confirmDeleteProfileBody,
    );
    if (!confirmed) return;
    await ref.read(dangerActionsProvider).deleteProfile();
    // Router redirect handles navigation back to /onboarding.
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.deviceId,
    required this.avatarColor,
  });

  final String name;
  final String deviceId;
  final Color avatarColor;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final initials = name.isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space3,
        KubbTokens.space4,
        KubbTokens.space3,
      ),
      child: Row(
        children: [
          AvatarCircle(initials: initials, color: avatarColor, size: 56),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${l.settingsRowDeviceLabel}: $deviceId',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: tokens.fgMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
