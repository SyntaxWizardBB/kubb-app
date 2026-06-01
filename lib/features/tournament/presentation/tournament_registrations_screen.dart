import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// The caller's active tournament registrations (P1 Tournament-Hub).
///
/// Reads [myTournamentRegistrationsProvider]; each row reuses
/// [TournamentCard] (tap → detail) and carries a withdraw action that
/// calls `tournament_withdraw` and invalidates the list to refresh.
class TournamentRegistrationsScreen extends ConsumerWidget {
  const TournamentRegistrationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final async = ref.watch(myTournamentRegistrationsProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentListEyebrow,
        title: l.tournamentRegistrationsTitle,
        actions: const [InboxBellAction()],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              e.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (registrations) {
          if (registrations.isEmpty) {
            return KubbEmptyState(
              title: l.tournamentRegistrationsEmptyTitle,
              body: l.tournamentRegistrationsEmptyBody,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space12,
            ),
            itemCount: registrations.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KubbTokens.space3),
            itemBuilder: (context, i) {
              final reg = registrations[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TournamentCard(
                    summary: reg.tournament,
                    onTap: () => context.push(
                      '${TournamentRoutes.detail}/${reg.tournament.tournamentId.value}',
                    ),
                  ),
                  Row(
                    children: [
                      // Auto-confirmed model: surface the caller's standing
                      // ("Angemeldet" vs "Auf Warteliste") instead of any
                      // pending/awaiting-confirmation framing.
                      Text(
                        reg.status == TournamentParticipantStatus.waitlist
                            ? l.tournamentDetailStatusWaitlist
                            : l.tournamentDetailStatusConfirmed,
                        style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.logout, size: 18),
                        label: Text(l.tournamentRegistrationsWithdraw),
                        style: TextButton.styleFrom(
                            foregroundColor: KubbTokens.miss),
                        onPressed: () =>
                            unawaited(_withdraw(context, ref, reg, l)),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    MyTournamentRegistration reg,
    AppLocalizations l,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tournamentWithdrawConfirmTitle),
        content: Text(l.tournamentWithdrawConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: KubbTokens.miss),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.tournamentRegistrationsWithdraw),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(tournamentRemoteProvider)
        .withdrawRegistration(reg.participantId);
    ref.invalidate(myTournamentRegistrationsProvider);
  }
}
