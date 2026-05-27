import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Read-only spectator view of one tournament match (M4.2-T9).
/// Renders team labels, set tally and a status pill — no inputs, no
/// action menus. The realtime stream and detail provider drive the
/// snapshot; polling kicks in automatically when realtime is down.
class PublicMatchScreen extends ConsumerWidget {
  const PublicMatchScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final id = TournamentMatchId(matchId);
    ref.watch(tournamentMatchDetailRealtimeProvider(id));
    final detailAsync = ref.watch(tournamentMatchDetailProvider(id));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        title: Text(l.tournamentMatchDetailTitle),
      ),
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
        data: (match) => match == null
            ? const Center(child: CircularProgressIndicator())
            : _renderMatch(context, ref, match, tokens, l),
      ),
    );
  }

  Widget _renderMatch(BuildContext context, WidgetRef ref,
      TournamentMatchRef match, KubbTokens tokens, AppLocalizations l) {
    final participants = ref
        .watch(tournamentDetailProvider(match.tournamentId))
        .asData
        ?.value
        ?.participants ??
        const <TournamentParticipant>[];
    final nameById = <String, String>{
      for (final p in participants) p.participantId: p.displayLabel,
    };
    String label(TournamentParticipantId? id) =>
        id == null ? '?' : (nameById[id.value] ?? '?');
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                      label(match.participantA), label(match.participantB)),
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: tokens.fg),
            ),
            const SizedBox(height: KubbTokens.space3),
            Row(children: [
              Text(scoreLine,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: tokens.fg,
                      fontFeatures: const [FontFeature.tabularFigures()])),
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
