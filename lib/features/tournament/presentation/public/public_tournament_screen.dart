import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_match_card.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_status_pill.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Public, read-only tournament view for anon spectators (M4.2-T8).
///
/// Three-tab layout: Spielplan (matches grouped by round), Rangliste
/// (standings table), Bracket (KO visualizer). When the backend marks
/// the tournament as non-public — surfaced via `matchFormatConfig['public']
/// == false`, since M4.2-T1 ships the column but M4.2-T8's dependency
/// chain does not extend the dart entity — the screen collapses to a
/// "nicht öffentlich" placeholder. Realtime streams from M4.1-T8 keep
/// the match list and bracket fresh while the screen is mounted.
class PublicTournamentScreen extends ConsumerStatefulWidget {
  const PublicTournamentScreen({required this.tournamentId, super.key});

  final TournamentId tournamentId;

  @override
  ConsumerState<PublicTournamentScreen> createState() =>
      _PublicTournamentScreenState();
}

class _PublicTournamentScreenState extends ConsumerState<PublicTournamentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    // Subscribe to realtime so list/bracket re-fetch on backend events
    // (M4.1-T8 invalidates the polling providers automatically).
    ref
      ..watch(tournamentMatchListRealtimeProvider(widget.tournamentId))
      ..watch(tournamentBracketRealtimeProvider(widget.tournamentId));
    final detailAsync = ref.watch(tournamentDetailProvider(widget.tournamentId));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        title: Text(detailAsync.maybeWhen(
            data: (d) => d?.tournament.displayName ?? 'Turnier',
            orElse: () => 'Turnier')),
      ),
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
        data: (d) {
          if (d == null) return _notPublic(context, tokens);
          final isPublic = d.tournament.matchFormatConfig['public'] != false;
          if (!isPublic) return _notPublic(context, tokens);
          return _body(context, tokens, d);
        },
      ),
    );
  }

  Widget _body(BuildContext context, KubbTokens tokens, TournamentDetail d) {
    final approved = d.participants
        .where((p) =>
            p.registrationStatus == TournamentParticipantStatus.approved)
        .length;
    final rounds = _roundsCounter(d.matches);
    final h = d.tournament;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(KubbTokens.space4,
              KubbTokens.space3, KubbTokens.space4, KubbTokens.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(h.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: tokens.fg)),
                ),
                TournamentStatusPill(status: h.status),
              ]),
              const SizedBox(height: KubbTokens.space2),
              Text(
                'Runde ${rounds.$1} von ${rounds.$2}  ·  $approved Teilnehmer',
                style: TextStyle(fontSize: 13, color: tokens.fgMuted),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: tokens.fg,
          unselectedLabelColor: tokens.fgMuted,
          indicatorColor: tokens.fg,
          tabs: const [
            Tab(text: 'Spielplan'),
            Tab(text: 'Rangliste'),
            Tab(text: 'Bracket'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ScheduleTab(matches: d.matches),
              _StandingsTab(tournamentId: widget.tournamentId),
              _BracketTab(tournamentId: widget.tournamentId),
            ],
          ),
        ),
      ],
    );
  }

  /// Returns `(current, total)` rounds. `current` is the highest round
  /// with at least one non-`scheduled` match (i.e. play has started in
  /// that round); falls back to `1` when nothing is in flight yet.
  (int, int) _roundsCounter(List<TournamentMatchRef> matches) {
    if (matches.isEmpty) return (1, 1);
    var total = 1;
    var current = 1;
    for (final m in matches) {
      if (m.roundNumber > total) total = m.roundNumber;
      if (m.status != TournamentMatchStatus.scheduled &&
          m.roundNumber > current) {
        current = m.roundNumber;
      }
    }
    return (current, total);
  }

  Widget _notPublic(BuildContext context, KubbTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KubbTokens.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: tokens.fgMuted),
            const SizedBox(height: KubbTokens.space3),
            Text(
              'Dieses Turnier ist nicht öffentlich',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({required this.matches});

  final List<TournamentMatchRef> matches;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text('Noch keine Spiele geplant',
              style: TextStyle(color: tokens.fgMuted)),
        ),
      );
    }
    final byRound = <int, List<TournamentMatchRef>>{};
    for (final m in matches) {
      byRound.putIfAbsent(m.roundNumber, () => <TournamentMatchRef>[]).add(m);
    }
    final ordered = byRound.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        for (final r in ordered) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
            child: Text(
              'Runde $r',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                  letterSpacing: 0.5),
            ),
          ),
          for (final m in byRound[r]!) ...[
            TournamentMatchCard(
              match: m,
              nameFor: (id) => id.value.length <= 6
                  ? id.value
                  : id.value.substring(0, 6),
              onTap: () {},
            ),
            const SizedBox(height: KubbTokens.space2),
          ],
        ],
      ],
    );
  }
}

class _StandingsTab extends ConsumerWidget {
  const _StandingsTab({required this.tournamentId});

  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(tournamentStandingsProvider(tournamentId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text('Rangliste noch nicht verfügbar',
              style: TextStyle(color: tokens.fgMuted)),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(KubbTokens.space5),
              child: Text('Rangliste noch nicht verfügbar',
                  style: TextStyle(color: tokens.fgMuted)),
            ),
          );
        }
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final s = rows[i];
            final diff = s.kubbsScored - s.kubbsConceded;
            final name = s.participantId.length <= 8
                ? s.participantId
                : s.participantId.substring(0, 8);
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space4,
                  vertical: KubbTokens.space3),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: tokens.line, width: 0.5)),
              ),
              child: Row(children: [
                SizedBox(
                  width: 32,
                  child: Text('${i + 1}.',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: tokens.fgMuted)),
                ),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tokens.fg)),
                ),
                Text('${s.totalPoints}  ·  ${s.wins}W  ·  $diff',
                    style: TextStyle(
                        fontSize: 13,
                        color: tokens.fg,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            );
          },
        );
      },
    );
  }
}

class _BracketTab extends ConsumerWidget {
  const _BracketTab({required this.tournamentId});

  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(tournamentBracketProvider(tournamentId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // Group phase returns no KO rows — collapse error to empty state.
      error: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text('Bracket noch nicht verfügbar',
              style: TextStyle(color: tokens.fgMuted)),
        ),
      ),
      data: (bracket) {
        if (bracket is SingleEliminationBracket &&
            (bracket.rounds.isEmpty ||
                bracket.rounds.every((r) => r.pairings.isEmpty))) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(KubbTokens.space5),
              child: Text('Bracket noch nicht verfügbar',
                  style: TextStyle(color: tokens.fgMuted)),
            ),
          );
        }
        // `tournamentId: null` tells BracketCanvas to swallow taps —
        // the public view stays purely read-only, no match-detail jumps.
        return BracketCanvas(bracket: bracket, editable: false);
      },
    );
  }
}
