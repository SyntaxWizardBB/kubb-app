import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_live_dashboard_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Live-Dashboard für Veranstalter: Grid aller aktiven Spielfelder eines
/// Turniers. Konsumiert [tournamentLiveDashboardProvider] (M4.2-T4).
/// Pro Pitch-Karte: Match-Nummer, beide Teams, aktueller Satzstand und
/// ein Status-Border in Farbcode (grau = geplant, gelb = warten,
/// grün = abgeschlossen, rot = strittig). Tap öffnet das Match-Detail.
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
        data: (pitches) {
          if (pitches.isEmpty) {
            return Center(
              child: Text('Keine aktiven Spielfelder.',
                  style: TextStyle(color: tokens.fgMuted)),
            );
          }
          final keys = pitches.keys.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          return GridView.count(
            crossAxisCount: cross,
            padding: const EdgeInsets.all(KubbTokens.space4),
            mainAxisSpacing: KubbTokens.space3,
            crossAxisSpacing: KubbTokens.space3,
            childAspectRatio: 1.4,
            children: [
              for (final k in keys)
                _PitchCard(
                  status: pitches[k]!,
                  onTap: () => context.go(TournamentRoutes.matchDetail(
                      tournamentId, pitches[k]!.match.matchId.value)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PitchCard extends StatelessWidget {
  const _PitchCard({required this.status, required this.onTap});

  final PitchStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final m = status.match;
    final color = _color(m.status);
    final a = _shortId(m.participantA?.value);
    final b = m.participantB == null ? 'BYE' : _shortId(m.participantB?.value);
    final score = (status.currentSetA != null && status.currentSetB != null)
        ? '${status.currentSetA}:${status.currentSetB}'
        : '–:–';
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
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
              borderRadius: radius, border: Border.all(color: color, width: 2)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('Feld ${status.pitchNumber.value}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tokens.fgMuted,
                        letterSpacing: 0.5)),
                const Spacer(),
                Text('#${m.matchNumberInRound}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.fgSubtle)),
              ]),
              const SizedBox(height: KubbTokens.space2),
              Text(a,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: teamStyle),
              Text(b,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: teamStyle),
              const Spacer(),
              Row(children: [
                Text(score,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KubbTokens.space2, vertical: 4),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
                      border: Border.all(color: color)),
                  child: Text(_label(m.status),
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

  String _shortId(String? raw) =>
      raw == null ? '?' : (raw.length < 6 ? raw : raw.substring(0, 6));

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
