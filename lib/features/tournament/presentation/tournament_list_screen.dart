import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart'
    show tournamentActionsProvider;
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Discovery list reached from the hub's "Aktuelle Turniere" tile.
///
/// Shows every published (non-draft, not-yet-finished) tournament as a
/// flat list — the per-caller "mine" view now lives behind the hub's
/// "Angemeldete Turniere" tile, and creating is the organizer-gated hub
/// tile, so this screen no longer needs tabs or a FAB.
class TournamentListScreen extends ConsumerWidget {
  const TournamentListScreen({super.key});

  /// Lifecycle states that count as "published / currently listed".
  static const _published = <TournamentStatus>{
    TournamentStatus.published,
    TournamentStatus.registrationOpen,
    TournamentStatus.registrationClosed,
    TournamentStatus.live,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    ref.watch(tournamentListPollingProvider(null));
    final async = ref.watch(tournamentListProvider(null));
    // P6 L123: each registration-open tile carries a self-register /
    // self-withdraw toggle. Map the caller's registrations by tournament
    // id so the tile knows its current state and the participant id to
    // withdraw without a second round-trip.
    final myRegs = ref.watch(myTournamentRegistrationsProvider).maybeWhen(
          data: (rows) => <String, MyTournamentRegistration>{
            for (final r in rows) r.tournament.tournamentId.value: r,
          },
          orElse: () => const <String, MyTournamentRegistration>{},
        );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentListEyebrow,
        title: l.tournamentListTabPublic,
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
        data: (rows) {
          final published = rows
              .where((t) => _published.contains(t.status))
              .toList(growable: false);
          if (published.isEmpty) {
            return KubbEmptyState(
              title: l.emptyTournamentsTitle,
              body: l.tournamentBrowseEmptyBody,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space12,
            ),
            itemCount: published.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KubbTokens.space3),
            itemBuilder: (context, i) {
              final t = published[i];
              final detailPath =
                  '${TournamentRoutes.detail}/${t.tournamentId.value}';
              final reg = myRegs[t.tournamentId.value];
              final registered = reg != null &&
                  reg.status != TournamentParticipantStatus.withdrawn;
              // Register/withdraw only makes sense while registration is
              // open; for every other published state the tile still
              // offers the explicit "Details" button.
              final canToggle =
                  t.status == TournamentStatus.registrationOpen;
              return TournamentCard(
                summary: t,
                onTap: () => context.push(detailPath),
                onDetails: () => context.push(detailPath),
                isRegistered: registered,
                onRegister: canToggle && !registered
                    ? () => context.push('$detailPath/register')
                    : null,
                onWithdraw: canToggle && registered
                    ? () =>
                        unawaited(_withdraw(context, ref, reg.participantId, l))
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  /// Self-withdraw from a registration-open tournament straight off the
  /// tile. Mirrors the confirm dialog used on the "Angemeldete Turniere"
  /// list; on success it invalidates the registrations provider so the
  /// tile flips back to "Anmelden".
  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    TournamentParticipantId participantId,
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
            child:
                Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
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
        .read(tournamentActionsProvider)
        .withdrawRegistration(participantId);
    ref.invalidate(myTournamentRegistrationsProvider);
  }
}
