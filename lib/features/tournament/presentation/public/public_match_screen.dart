import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/public_link_share_service.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_realtime.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
      appBar: KubbAppBar(
        title: l.tournamentMatchDetailTitle,
        actions: [
          // Per-match share entry: builds the public /public/match/<id>
          // link and shares it (SharePlus) with a clipboard fallback. The
          // matchId comes from the route param, so the action is available
          // independent of the load state.
          PublicMatchShareButton(matchId: matchId),
        ],
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
    // Live-Aktualisierung ueber den BESTEHENDEN anon-Broadcast (ADR-0029):
    // sobald der Match-Status-/Score-Trigger ein Event auf dem
    // `public_tournament_events:<tournament_id>`-Topic emittiert,
    // invalidieren wir den Match- (und Roster-)Provider, der dann den
    // naechsten RPC-Snapshot zieht. Kein Timer.periodic, kein neuer
    // Polling-Provider — gleiches Muster wie PublicTournamentScreen.
    ref.listen<AsyncValue<PublicTournamentEvent>>(
      publicTournamentEventsProvider(match.tournamentId),
      (previous, next) {
        if (next.hasValue) {
          ref
            ..invalidate(publicMatchDetailProvider(match.matchId))
            ..invalidate(publicTournamentDetailProvider(match.tournamentId));
        }
      },
    );
    // Roster-Lookup ueber den Public-Tournament-Provider — die RPC
    // liefert nur display_name (kein user_id / nickname-Profil-Leak).
    final tournamentAsync =
        ref.watch(publicTournamentDetailProvider(match.tournamentId));
    final detail = tournamentAsync.asData?.value;

    // M1: Public-Roster-Lookup ueber `displayNameFor`; fehlt der Name
    // (z.B. im Augenblick zwischen Match-Detail- und Tournament-Detail-
    // Resolve), faellt das Label auf das lokalisierte
    // `tournamentParticipantUnknown` ("Unbekannt") zurueck — niemals auf
    // eine roh-/gekuerzte UUID oder 'A'/'B'.
    String label(TournamentParticipantId? id) {
      if (id == null) return l.tournamentParticipantUnknown;
      final name = detail?.displayNameFor(id)?.trim();
      if (name != null && name.isNotEmpty) return name;
      return l.tournamentParticipantUnknown;
    }

    final isBye = match.participantB == null;
    final scoreLine = _scoreLine(match);
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

  /// Read-only score line. For FINALIZED / overridden matches it shows the
  /// final match score (`final_score_a:final_score_b`). For RUNNING matches
  /// (scheduled / awaiting_results / disputed) it shows the live agreed set
  /// tally (`sets_won_a:sets_won_b`, projected by the public match RPC since
  /// migration 20261241000000) instead of a blanket `–:–`. Falls back to
  /// `–:–` only when no score data is available yet (e.g. a freshly
  /// scheduled match with no agreed set).
  String _scoreLine(PublicMatchDetail match) {
    final isFinal = match.status == TournamentMatchStatus.finalized ||
        match.status == TournamentMatchStatus.overridden;
    if (isFinal && match.finalScoreA != null && match.finalScoreB != null) {
      return '${match.finalScoreA}:${match.finalScoreB}';
    }
    final setsA = match.setsWonA;
    final setsB = match.setsWonB;
    if (setsA != null && setsB != null && (setsA > 0 || setsB > 0)) {
      return '$setsA:$setsB';
    }
    return '–:–';
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

/// Share entry for a single public match: builds the
/// `/public/match/<matchId>` link (same host convention as the public
/// tournament link) and hands it to [PublicLinkShareService] — system
/// share sheet on mobile, clipboard fallback otherwise. Exposed as a
/// public widget so it can be reused as an entry point and tested in
/// isolation with an overridden share service.
class PublicMatchShareButton extends ConsumerWidget {
  const PublicMatchShareButton({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return IconButton(
      icon: const Icon(LucideIcons.share2),
      color: tokens.fg,
      iconSize: 24,
      splashRadius: 24,
      tooltip: l.publicMatchShareAction,
      constraints: const BoxConstraints.tightFor(
        width: KubbTokens.touchMin,
        height: KubbTokens.touchMin,
      ),
      onPressed: () => _share(context, ref, l),
    );
  }

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final service = ref.read(publicLinkShareServiceProvider);
    final result = await service.shareLink(
      publicMatchLink(matchId),
      subject: l.publicMatchShareSubject,
    );
    // Confirm the clipboard fallback so the user knows the link was copied
    // when no system share sheet is available (desktop / web).
    if (result.kind == LinkShareKind.copiedToClipboard) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l.publicMatchLinkCopied)),
      );
    }
  }
}
