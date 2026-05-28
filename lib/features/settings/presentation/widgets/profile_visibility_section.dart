import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/settings/presentation/widgets/settings_row.dart';
import 'package:kubb_app/features/settings/presentation/widgets/settings_section.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Settings section that exposes the profile visibility picker.
///
/// Renders the current tier as the row subtitle. Tapping the row opens
/// a modal bottom-sheet with the three visibility options; selecting
/// one writes the new value through the cloud profile repository and
/// invalidates [cloudProfileProvider] so dependent surfaces (here:
/// the row's own subtitle) refresh on the next frame.
///
/// Refs: R20-F-02 (FR-AUTH-5, DSGVO Art. 25), R20-F-10 (FR-SOCIAL-4).
class ProfileVisibilitySection extends ConsumerWidget {
  const ProfileVisibilitySection({super.key});

  @visibleForTesting
  static const Key rowKey = Key('settings.visibility.row');

  @visibleForTesting
  static Key optionKey(ProfileVisibility tier) =>
      Key('settings.visibility.option.${tier.wireValue}');

  static String _labelFor(ProfileVisibility tier, AppLocalizations l) {
    return switch (tier) {
      ProfileVisibility.public => l.settingsVisibilityPublic,
      ProfileVisibility.friendsOnly => l.settingsVisibilityFriendsOnly,
      ProfileVisibility.private => l.settingsVisibilityPrivate,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Privacy-by-Default: if the cloud row is not yet loaded (or the
    // user has no profile row), show the friends-only floor so the UI
    // never implies "public" before the real tier is known.
    final tier = ref.watch(cloudProfileProvider).maybeWhen(
          data: (profile) =>
              profile?.visibility ?? ProfileVisibility.defaultTier,
          orElse: () => ProfileVisibility.defaultTier,
        );

    return SettingsSection(
      title: l.settingsVisibilitySection,
      children: [
        SettingsRow(
          key: rowKey,
          icon: LucideIcons.eye,
          label: l.settingsRowVisibility,
          subtitle: _labelFor(tier, l),
          onTap: () => _openPicker(context, ref, current: tier),
        ),
      ],
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    WidgetRef ref, {
    required ProfileVisibility current,
  }) async {
    final selected = await showModalBottomSheet<ProfileVisibility>(
      context: context,
      builder: (sheetCtx) =>
          _PickerSheet(current: current, labelFor: _labelFor),
    );
    if (selected == null || selected == current) return;
    if (!context.mounted) return;
    await _save(context, ref, selected);
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    ProfileVisibility next,
  ) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(cloudProfileRepositoryProvider);
    final profile = await ref.read(cloudProfileProvider.future);
    if (profile == null) {
      // No cloud row yet — treat as a "nothing to update" no-op rather
      // than surfacing a confusing error. This branch only fires when
      // the user has not finished onboarding.
      return;
    }
    try {
      await repo.updateProfile(
        userId: profile.userId,
        visibility: next,
      );
      ref.invalidate(cloudProfileProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l.settingsVisibilitySavedSnack)),
      );
    } on Object catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.settingsVisibilityErrorSnack)),
      );
    }
  }
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.current, required this.labelFor});

  final ProfileVisibility current;
  final String Function(ProfileVisibility tier, AppLocalizations l) labelFor;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: KubbTokens.space3,
          horizontal: KubbTokens.space3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KubbTokens.space2,
                vertical: KubbTokens.space2,
              ),
              child: Text(
                l.settingsVisibilityPickerTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: tokens.fgMuted,
                ),
              ),
            ),
            for (final tier in ProfileVisibility.values)
              ListTile(
                key: ProfileVisibilitySection.optionKey(tier),
                title: Text(labelFor(tier, l)),
                trailing: Icon(
                  tier == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: tier == current
                      ? Theme.of(context).colorScheme.primary
                      : tokens.fgMuted,
                ),
                onTap: () => Navigator.of(context).pop(tier),
              ),
          ],
        ),
      ),
    );
  }
}
