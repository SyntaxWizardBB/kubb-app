import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_live_dashboard_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Live-Dashboard für Veranstalter: Grid aller aktiven Spielfelder eines
/// Turniers. Konsumiert [tournamentLiveDashboardProvider] (M4.2-T4).
/// Pro Pitch-Karte: beide Teams, Status-Border in Farbcode
/// (grau = geplant, gelb = warten, grün = abgeschlossen, rot = strittig).
/// Tap öffnet das Match-Detail.
class TournamentLiveDashboardScreen extends ConsumerWidget {
  const TournamentLiveDashboardScreen({
    required this.tournamentId,
    super.key,
  });

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final id = TournamentId(tournamentId);
    final async = ref.watch(tournamentLiveDashboardProvider(id));
    final cross = MediaQuery.of(context).size.shortestSide >= 600 ? 3 : 2;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        title: const Text('Live-Dashboard'),
        leading: BackButton(
          onPressed: () =>
              context.go('${TournamentRoutes.detail}/$tournamentId'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text('Dashboard konnte nicht geladen werden: $e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: KubbTokens.miss)),
          ),
        ),
        data: (data) {
          if (data.pitches.isEmpty) {
            return Center(
              child: Text('Keine aktiven Spielfelder.',
                  style: TextStyle(color: tokens.fgMuted)),
            );
          }
          return GridView.count(
            crossAxisCount: cross,
            padding: const EdgeInsets.all(KubbTokens.space4),
            mainAxisSpacing: KubbTokens.space3,
            crossAxisSpacing: KubbTokens.space3,
            childAspectRatio: 1.4,
            children: [
              for (final p in data.pitches)
                _PitchCard(
                  cardKey: ValueKey('live-card-${p.matchId.value}'),
                  status: p,
                  onTap: () => context.go(TournamentRoutes.matchDetail(
                      tournamentId, p.matchId.value)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PitchCard extends StatelessWidget {
  const _PitchCard({
    required this.status,
    required this.onTap,
    required this.cardKey,
  });

  final PitchStatus status;
  final VoidCallback onTap;
  final Key cardKey;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final color = _color(status.status);
    final names = status.participantNames;
    final a = names.isNotEmpty ? names[0] : '?';
    final b = names.length > 1 ? names[1] : 'BYE';
    final radius = BorderRadius.circular(KubbTokens.radiusLg);
    final teamStyle = TextStyle(
        fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg);

    return Material(
      color: tokens.bgRaised,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          key: cardKey,
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
              borderRadius: radius, border: Border.all(color: color, width: 2)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('Runde ${status.currentRound}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tokens.fgMuted,
                        letterSpacing: 0.5)),
              ]),
              const SizedBox(height: KubbTokens.space2),
              Text(a,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: teamStyle),
              Text(b,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: teamStyle),
              const Spacer(),
              Row(children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KubbTokens.space2, vertical: 4),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
                      border: Border.all(color: color)),
                  child: Text(_label(status.status),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: tokens.fg)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Color _color(TournamentMatchStatus s) {
    switch (s) {
      case TournamentMatchStatus.scheduled:
      case TournamentMatchStatus.voided:
        return KubbTokens.stone400;
      case TournamentMatchStatus.awaitingResults:
        return KubbTokens.wood400;
      case TournamentMatchStatus.disputed:
        return KubbTokens.miss;
      case TournamentMatchStatus.finalized:
      case TournamentMatchStatus.overridden:
        return KubbTokens.meadow500;
    }
  }

  String _label(TournamentMatchStatus s) {
    switch (s) {
      case TournamentMatchStatus.scheduled:
        return 'Geplant';
      case TournamentMatchStatus.awaitingResults:
        return 'Warten';
      case TournamentMatchStatus.disputed:
        return 'Strittig';
      case TournamentMatchStatus.finalized:
        return 'Abgeschlossen';
      case TournamentMatchStatus.overridden:
        return 'Korrigiert';
      case TournamentMatchStatus.voided:
        return 'Ungültig';
    }
  }
}
