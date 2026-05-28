import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_status_pill.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Public, read-only tournament view for anon spectators.
///
/// Drei-Tab-Layout: Spielplan (Matches gruppiert nach Runde), Rangliste
/// (clientseitig aus den gelieferten Matches berechnet), Bracket (KO-
/// Visualizer aus `phase`-getaggten Matches). Liest ausschliesslich
/// ueber `publicTournamentDetailProvider`, der die `public_tournament_get`-
/// RPC nach ADR-0026 Strategie A aufruft — kein authentifizierter
/// Caller, keine `signInAnonymously()`-Round-Trip. Liefert die RPC
/// `null` (Turnier non-public / draft / aborted), zeigt der Screen den
/// `_notPublic`-Placeholder.
///
/// Realtime-Streams sind in diesem Pfad bewusst NICHT mehr verdrahtet:
/// die Authenticated-Realtime-Channels brauchen ein JWT, das der anon-
/// Pfad nicht besitzt. Folge-Task in Wave 4 (anon-rls-plan.md T6).
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
    final detailAsync =
        ref.watch(publicTournamentDetailProvider(widget.tournamentId));

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
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
          // Die RPC liefert NULL fuer non-public oder draft/aborted —
          // der Fallback auf `matchFormatConfig['public']` aus dem
          // Vorgaenger ist nicht mehr noetig.
          if (d == null) return _notPublic(context, tokens);
          return _body(context, tokens, d);
        },
      ),
    );
  }

  Widget _body(
      BuildContext context, KubbTokens tokens, PublicTournamentDetail d) {
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
                'Runde ${rounds.$1} von ${rounds.$2}  ·  '
                '${d.participantCount} Teilnehmer',
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
              _ScheduleTab(detail: d),
              _StandingsTab(detail: d),
              _BracketTab(detail: d),
            ],
          ),
        ),
      ],
    );
  }

  /// Returns `(current, total)` rounds. `current` is the highest round
  /// with at least one non-`scheduled` match (i.e. play has started in
  /// that round); falls back to `1` when nothing is in flight yet.
  (int, int) _roundsCounter(List<PublicMatchDetail> matches) {
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
  const _ScheduleTab({required this.detail});

  final PublicTournamentDetail detail;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final matches = detail.matches;
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text('Noch keine Spiele geplant',
              style: TextStyle(color: tokens.fgMuted)),
        ),
      );
    }
    final byRound = <int, List<PublicMatchDetail>>{};
    for (final m in matches) {
      byRound.putIfAbsent(m.roundNumber, () => <PublicMatchDetail>[]).add(m);
    }
    final ordered = byRound.keys.toList()..sort();
    // W3-T5: Public-Roster zeigt Namen oder `tournamentParticipantUnknown`
    // ("Unbekannt"). BYE bleibt eigener Marker fuer leere Slots.
    String label(TournamentParticipantId? id) {
      if (id == null) return 'BYE';
      return detail.displayNameFor(id) ?? l.tournamentParticipantUnknown;
    }
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
            _PublicMatchTile(match: m, labelFor: label),
            const SizedBox(height: KubbTokens.space2),
          ],
        ],
      ],
    );
  }
}

class _PublicMatchTile extends StatelessWidget {
  const _PublicMatchTile({required this.match, required this.labelFor});

  final PublicMatchDetail match;
  final String Function(TournamentParticipantId?) labelFor;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final isBye = match.participantB == null;
    final isFinal = match.status == TournamentMatchStatus.finalized ||
        match.status == TournamentMatchStatus.overridden;
    final score =
        isFinal && match.finalScoreA != null && match.finalScoreB != null
            ? '${match.finalScoreA}:${match.finalScoreB}'
            : '–:–';
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            isBye
                ? '${labelFor(match.participantA)}  ·  BYE'
                : '${labelFor(match.participantA)}  vs  '
                    '${labelFor(match.participantB)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg),
          ),
        ),
        const SizedBox(width: KubbTokens.space3),
        Text(score,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class _StandingsTab extends StatelessWidget {
  const _StandingsTab({required this.detail});

  final PublicTournamentDetail detail;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final finished = detail.matches.where(_isStandingsCounted).toList();
    if (finished.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text('Rangliste noch nicht verfügbar',
              style: TextStyle(color: tokens.fgMuted)),
        ),
      );
    }
    final participantIds = <String>{
      for (final m in detail.matches) ...[
        if (m.participantA != null) m.participantA!.value,
        if (m.participantB != null) m.participantB!.value,
      ],
    }.toList(growable: false);
    final results = <TournamentMatchResult>[
      for (final m in finished) _resultFromMatch(m),
    ];
    final rows = computeStandings(
      participantIds: participantIds,
      results: results,
      tiebreaker: const TiebreakerChain(<TiebreakerCriterion>[
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
        TiebreakerCriterion.buchholzMinusH2H,
        TiebreakerCriterion.kubbDifference,
      ]),
    );
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final s = rows[i];
        final diff = s.kubbsScored - s.kubbsConceded;
        // W3-T5: Standings nutzen denselben Roster-Lookup wie der
        // Spielplan-Tab; ohne Treffer faellt der Eintrag auf das
        // lokalisierte `tournamentParticipantUnknown` zurueck statt auf
        // den UUID-Substring-Hack (R13-F-02).
        final name = detail.displayNameFor(
                TournamentParticipantId(s.participantId)) ??
            l.tournamentParticipantUnknown;
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space4,
              vertical: KubbTokens.space3),
          decoration: BoxDecoration(
            border:
                Border(bottom: BorderSide(color: tokens.line, width: 0.5)),
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
  }

  bool _isStandingsCounted(PublicMatchDetail m) {
    return m.status == TournamentMatchStatus.finalized ||
        m.status == TournamentMatchStatus.overridden;
  }

  TournamentMatchResult _resultFromMatch(PublicMatchDetail m) {
    final a = m.participantA!.value;
    final b = m.participantB?.value;
    final sA = m.finalScoreA ?? 0;
    final sB = m.finalScoreB ?? 0;
    final winner = sA >= sB ? SetWinner.teamA : SetWinner.teamB;
    return TournamentMatchResult(
      participantA: a,
      participantB: b,
      score: MatchEkcScore(<SetScore>[
        SetScore(
          basekubbsKnockedByA: sA,
          basekubbsKnockedByB: sB,
          winner: winner,
        ),
      ]),
    );
  }
}

class _BracketTab extends StatelessWidget {
  const _BracketTab({required this.detail});

  final PublicTournamentDetail detail;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final koRows = <KoMatchRow>[
      for (final m in detail.matches)
        if (_phaseFromWire(m.phase) != null && m.bracketPosition != null)
          (
            roundNumber: m.roundNumber,
            bracketPosition: m.bracketPosition!,
            phase: _phaseFromWire(m.phase)!,
            participantA: m.participantA?.value,
            participantB: m.participantB?.value,
            winnerParticipantId: m.winnerParticipant?.value,
            isBye: m.participantA == null || m.participantB == null,
          ),
    ];
    if (koRows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text('Bracket noch nicht verfügbar',
              style: TextStyle(color: tokens.fgMuted)),
        ),
      );
    }
    final bracket = bracketFromMatches(koRows);
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
    return BracketCanvas(bracket: bracket, editable: false);
  }

  BracketPhase? _phaseFromWire(String? raw) {
    if (raw == null || raw == 'group') return null;
    switch (raw) {
      case 'ko':
        return BracketPhase.winners;
      case 'third_place':
        return BracketPhase.thirdPlace;
      case 'final':
        return BracketPhase.finals;
    }
    return null;
  }
}
