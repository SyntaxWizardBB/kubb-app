import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_drawer.dart';
import 'package:kubb_app/core/ui/widgets/kubb_mode_card.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/social/presentation/social_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Landing screen for the Training tab (BottomNav branch 0).
///
/// A home-style overview that surfaces the solo/multiplayer modes as
/// [KubbModeCard] tiles — Sniper, Finisseur, Match — plus a tile that opens
/// the stats screen. These are the same destinations the home `TrainingSheet`
/// offers; the hub presents them as a full tab so the modes have a permanent
/// home in the nav. All targets live in this branch, so a `context.push` keeps
/// them on the Training stack (back returns here, the BottomNav stays put).
class TrainingHubScreen extends ConsumerWidget {
  const TrainingHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: tokens.bg,
      drawer: const KubbDrawer(),
      appBar: KubbAppBar.slots(
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            icon: const KubbIcon(LucideIcons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        eyebrow: Text(
          l.homeFabLabel.toUpperCase(),
          style: t.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: tokens.fgMuted,
          ),
        ),
        title: Text(
          l.trainingSheetTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.36,
            color: tokens.fg,
          ),
        ),
        trailing: const InboxBellAction(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space5,
          KubbTokens.space4,
          KubbTokens.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KubbModeCard(
              title: l.modeSniperTitle,
              subtitle: l.modeSniperSubtitle,
              icon: KubbIcons.target,
              accentTone: KubbChipTone.sniperMeadow,
              onTap: () => unawaited(context.push('/training/sniper/config')),
            ),
            const SizedBox(height: KubbTokens.space3),
            KubbModeCard(
              title: l.modeFinisseurTitle,
              subtitle: l.modeFinisseurSubtitle,
              icon: KubbIcons.king,
              accentTone: KubbChipTone.finisseurInk,
              onTap: () =>
                  unawaited(context.push('/training/finisseur/config')),
            ),
            const SizedBox(height: KubbTokens.space3),
            KubbModeCard(
              title: l.trainingHubMatchTitle,
              subtitle: l.trainingHubMatchSubtitle,
              icon: KubbIcons.players,
              accentTone: KubbChipTone.matchWood,
              onTap: () => unawaited(context.push(MatchRoutes.newMatch)),
            ),
            const SizedBox(height: KubbTokens.space3),
            // Freunde wurde aus dem HomeScreen-Spieler-Icon hierher als Kachel
            // verschoben (P7). userPlus = „Mitspieler hinzufügen" (Multiplayer-
            // Glyph mit Plus). Tippt man eine Person in der Liste an, öffnet
            // sich deren Profil + Statistik.
            KubbModeCard(
              title: 'Freunde',
              subtitle: 'Mitspieler finden · Profil & Statistik ansehen',
              icon: LucideIcons.userPlus,
              accentTone: KubbChipTone.line4mMeadowSoft,
              onTap: () => unawaited(context.push(SocialRoutes.friends)),
            ),
            const SizedBox(height: KubbTokens.space3),
            KubbModeCard(
              title: l.statsTitle,
              subtitle: l.trainingHubStatsSubtitle,
              icon: KubbIcons.stat,
              accentTone: KubbChipTone.tournamentWood,
              onTap: () => unawaited(context.push('/stats')),
            ),
          ],
        ),
      ),
    );
  }
}
