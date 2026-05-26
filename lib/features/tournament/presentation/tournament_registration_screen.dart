import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Confirm flow for joining a tournament. For `team_size == 1` the M1
/// single-player flow runs in place; for team tournaments the screen
/// hands off to the team-registration route, or prompts the user to
/// create a team first when they have none.
class TournamentRegistrationScreen extends ConsumerStatefulWidget {
  const TournamentRegistrationScreen({required this.tournamentId, super.key});
  final TournamentId tournamentId;

  @override
  ConsumerState<TournamentRegistrationScreen> createState() => _State();
}

class _State extends ConsumerState<TournamentRegistrationScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final detailAsync =
        ref.watch(tournamentDetailProvider(widget.tournamentId));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
          eyebrow: l.tournamentRegistrationEyebrow,
          title: l.tournamentRegistrationTitle),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(e.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: KubbTokens.miss)),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return Center(child: Text(l.tournamentDetailNotFound));
          }
          if (detail.tournament.teamSize > 1) {
            return _TeamBranch(
                tournamentId: widget.tournamentId,
                header: detail.tournament);
          }
          return _soloBody(context, tokens, l, detail);
        },
      ),
    );
  }

  Widget _soloBody(BuildContext context, KubbTokens tokens,
      AppLocalizations l, TournamentDetail detail) {
    final h = detail.tournament;
    return Padding(
      padding: const EdgeInsets.all(KubbTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(KubbTokens.space4),
            decoration: BoxDecoration(
                color: tokens.bgRaised,
                borderRadius: BorderRadius.circular(KubbTokens.radiusLg)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.displayName,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg)),
                const SizedBox(height: KubbTokens.space2),
                Text(
                  '${formatLabel(h.format, l)} · ${l.tournamentListParticipantCount(detail.participants.length)}',
                  style: TextStyle(fontSize: 13, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: KubbTokens.space5),
          Container(
            padding: const EdgeInsets.all(KubbTokens.space3),
            decoration: BoxDecoration(
                color: tokens.bgSunken,
                borderRadius: BorderRadius.circular(KubbTokens.radiusMd)),
            child: Text(l.tournamentRegistrationPendingHint,
                style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
          ),
          const Spacer(),
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy
                  ? l.tournamentRegistrationSubmitting
                  : l.tournamentRegistrationConfirm),
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          TextButton(
              onPressed: _busy ? null : () => context.pop(),
              child: Text(l.tournamentRegistrationCancel)),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(tournamentActionsProvider)
          .registerSingle(widget.tournamentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .tournamentRegistrationSuccess)));
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'), backgroundColor: KubbTokens.miss));
    }
  }
}

/// Team-registration branch. When the user has at least one team we
/// hand off to `/tournament/:id/register/team` (owned by T14); when
/// the user has no teams yet we render an inline CTA that routes to
/// the team-creation screen.
class _TeamBranch extends ConsumerWidget {
  const _TeamBranch({required this.tournamentId, required this.header});

  final TournamentId tournamentId;
  final TournamentDetailHeader header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final teamsAsync = ref.watch(teamListProvider);
    return teamsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(e.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss)),
        ),
      ),
      data: (teams) {
        if (teams.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(header.displayName,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg)),
                const SizedBox(height: KubbTokens.space2),
                Text(
                  'Dieses Turnier verlangt Teams zu ${header.teamSize} Spielern.',
                  style: TextStyle(fontSize: 13, color: tokens.fgMuted),
                ),
                const SizedBox(height: KubbTokens.space5),
                Container(
                  padding: const EdgeInsets.all(KubbTokens.space4),
                  decoration: BoxDecoration(
                      color: tokens.bgSunken,
                      borderRadius:
                          BorderRadius.circular(KubbTokens.radiusMd)),
                  child: Text(
                      'Du bist noch keinem Team beigetreten. Erstelle ein Team, um dich für dieses Turnier anzumelden.',
                      style:
                          TextStyle(fontSize: 13, color: tokens.fgMuted)),
                ),
                const Spacer(),
                SizedBox(
                  height: KubbTokens.touchComfortable,
                  child: FilledButton(
                    onPressed: () => context.go('/teams/new'),
                    child: const Text('Erstelle ein Team'),
                  ),
                ),
                const SizedBox(height: KubbTokens.space2),
                TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                        AppLocalizations.of(context)
                            .tournamentRegistrationCancel)),
              ],
            ),
          );
        }
        // Hand off to the team-registration route (T14 owns it).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          context.pushReplacement(
              '/tournament/${tournamentId.value}/register/team');
        });
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
