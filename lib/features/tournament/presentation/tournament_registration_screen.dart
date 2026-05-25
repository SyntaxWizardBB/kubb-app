import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Single-step confirm flow for joining a tournament. M1 only supports
/// single-player registration; team registration lands in wave 2.
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
                      borderRadius:
                          BorderRadius.circular(KubbTokens.radiusLg)),
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
                        style:
                            TextStyle(fontSize: 13, color: tokens.fgMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: KubbTokens.space5),
                Container(
                  padding: const EdgeInsets.all(KubbTokens.space3),
                  decoration: BoxDecoration(
                      color: tokens.bgSunken,
                      borderRadius:
                          BorderRadius.circular(KubbTokens.radiusMd)),
                  child: Text(l.tournamentRegistrationPendingHint,
                      style:
                          TextStyle(fontSize: 13, color: tokens.fgMuted)),
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
        },
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
