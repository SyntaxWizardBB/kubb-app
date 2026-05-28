import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/presentation/account_section.dart';
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

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: KubbAppBar(eyebrow: l.settingsScreenEyebrow, title: l.settingsTitle),
      body: ListView(
        padding: const EdgeInsets.only(bottom: KubbTokens.space8),
        children: [
          const AccountSection(),
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
}
