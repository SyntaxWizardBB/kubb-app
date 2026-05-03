import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        foregroundColor: tokens.fg,
        elevation: 0,
        title: Text(l.profileTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SafeArea(
        child: profile.when(
          data: (player) =>
              player == null ? const Center(child: Text('Kein Profil')) : _body(context, player, tokens, l),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(e.toString())),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Player player, KubbTokens tokens, AppLocalizations l) {
    final textTheme = Theme.of(context).textTheme;
    final since = DateFormat.yMMMMd('de').format(player.createdAt.toLocal());
    final labelStyle = textTheme.labelSmall?.copyWith(color: tokens.fgMuted);
    final valueStyle = textTheme.bodyLarge?.copyWith(color: tokens.fg);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space6,
        vertical: KubbTokens.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(player.name, style: textTheme.displaySmall?.copyWith(color: tokens.fg)),
          const SizedBox(height: KubbTokens.space6),
          Text(l.profileSinceLabel, style: labelStyle),
          const SizedBox(height: KubbTokens.space1),
          Text(since, style: valueStyle),
          const SizedBox(height: KubbTokens.space4),
          Text(l.profileDeviceLabel, style: labelStyle),
          const SizedBox(height: KubbTokens.space1),
          Text(
            player.deviceId,
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: tokens.fgMuted),
          ),
        ],
      ),
    );
  }
}
