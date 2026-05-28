import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Read-only spectator view of one tournament match nach ADR-0026
/// Strategie A.
///
/// Liest ueber `publicMatchDetailProvider` (RPC
/// `public_tournament_match_get`) und loest Teilnehmernamen ueber das
/// Roster des Eltern-Turniers (RPC `public_tournament_get`) auf —
/// keine authentifizierten Tournament-RPCs mehr. Liefert eine der RPCs
/// `null` (Match nicht public, Turnier draft/aborted), zeigt der
/// Screen einen neutralen Platzhalter.
class PublicMatchScreen extends ConsumerWidget {
  const PublicMatchScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final id = TournamentMatchId(matchId);
    final detailAsync = ref.watch(publicMatchDetailProvider(id));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(title: l.tournamentMatchDetailTitle),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text('${l.tournamentMatchLoadError}: $e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: KubbTokens.miss)),
          ),
        ),
        data: (match) {
          if (match == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(KubbTokens.space5),
                child: Text(l.tournamentMatchLoadError,
                    style: TextStyle(color: tokens.fgMuted)),
              ),
            );
          }
          return _Body(match: match);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.match});

  final PublicMatchDetail match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    // Roster-Lookup ueber den Public-Tournament-Provider — die RPC
    // liefert nur display_name (kein user_id / nickname-Profil-Leak).
    final tournamentAsync =
        ref.watch(publicTournamentDetailProvider(match.tournamentId));
    final detail = tournamentAsync.asData?.value;

    String label(TournamentParticipantId? id) {
      if (id == null) return '?';
      final name = detail?.displayNameFor(id);
      if (name != null) return name;
      // Fallback fuer den Augenblick zwischen Match-Detail-Resolve und
      // Tournament-Detail-Resolve: zeige eine gekuerzte ID.
      final v = id.value;
      return v.length <= 6 ? v : v.substring(0, 6);
    }

    final isBye = match.participantB == null;
    final isFinal = match.status == TournamentMatchStatus.finalized ||
        match.status == TournamentMatchStatus.overridden;
    final scoreLine =
        isFinal && match.finalScoreA != null && match.finalScoreB != null
            ? '${match.finalScoreA}:${match.finalScoreB}'
            : '–:–';
    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        Container(
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
            color: tokens.bgSunken,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tournamentMatchHeaderRound(
                      match.roundNumber, match.matchNumberInRound),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: tokens.fgMuted,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: KubbTokens.space2),
                Text(
                  isBye
                      ? l.tournamentMatchByeHeader
                      : l.tournamentMatchVersusHeader(
                          label(match.participantA),
                          label(match.participantB)),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: tokens.fg),
                ),
                const SizedBox(height: KubbTokens.space3),
                Row(children: [
                  Text(scoreLine,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: tokens.fg,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ])),
                  const SizedBox(width: KubbTokens.space3),
                  _StatusPill(status: match.status),
                ]),
              ]),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final TournamentMatchStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final label = switch (status) {
      TournamentMatchStatus.scheduled => l.tournamentMatchStatusScheduled,
      TournamentMatchStatus.awaitingResults => l.tournamentMatchStatusAwaiting,
      TournamentMatchStatus.disputed => l.tournamentMatchStatusDisputed,
      TournamentMatchStatus.finalized => l.tournamentMatchStatusFinalized,
      TournamentMatchStatus.overridden => l.tournamentMatchStatusOverridden,
      TournamentMatchStatus.voided => l.tournamentMatchStatusVoided,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space2, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        border: Border.all(color: tokens.line),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: tokens.fg)),
    );
  }
}
