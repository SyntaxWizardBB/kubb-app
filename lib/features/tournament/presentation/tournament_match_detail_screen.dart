import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/score_consensus_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_set_input.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Critical M1 screen: per-set score entry for one tournament match.
///
/// Layout decision (DSCORE flow + handoff §7.1): every active set is
/// rendered as an always-visible card stacked vertically inside a
/// ListView. Accordions and PageView were rejected because the spec
/// requires one-handed input under 30s and either pattern adds taps
/// or hides the live match score.
class TournamentMatchDetailScreen extends ConsumerStatefulWidget {
  const TournamentMatchDetailScreen({
    required this.tournamentId,
    required this.matchId,
    super.key,
  });

  final String tournamentId;
  final String matchId;

  @override
  ConsumerState<TournamentMatchDetailScreen> createState() =>
      _TournamentMatchDetailScreenState();
}

class _TournamentMatchDetailScreenState
    extends ConsumerState<TournamentMatchDetailScreen> {
  List<_SetDraft> _drafts = const <_SetDraft>[_SetDraft()];
  int? _prefilledForRound;
  bool _submitting = false;

  /// Spec default per DSCORE-15. Wizard-configurable; threaded through
  /// `TournamentMatchRef` once the detail RPC exposes it.
  static const int _maxBasekubbs = 5;

  /// Best-of-3 default; max-set cap from `matchFormatConfig` is wired
  /// through once the wizard surfaces it.
  static const int _maxSets = 3;

  void _ensureDraftForRound(TournamentMatchRef m) {
    if (_prefilledForRound == m.consensusRound) return;
    setState(() {
      _prefilledForRound = m.consensusRound;
      _drafts = const <_SetDraft>[_SetDraft()];
    });
  }

  void _update(int i, TournamentSetInputValue v) => setState(() {
        final next = List<_SetDraft>.of(_drafts);
        next[i] = _SetDraft(
            basekubbsA: v.basekubbsA, basekubbsB: v.basekubbsB, king: v.king);
        _drafts = next;
      });

  void _addSet() {
    if (_drafts.length >= _maxSets) return;
    setState(() => _drafts = <_SetDraft>[..._drafts, const _SetDraft()]);
  }

  void _removeSet() {
    if (_drafts.length <= 1) return;
    setState(() => _drafts = _drafts.sublist(0, _drafts.length - 1));
  }

  String? _validate(AppLocalizations l) {
    for (var i = 0; i < _drafts.length; i++) {
      final d = _drafts[i];
      if (d.king == null && d.basekubbsA == 0 && d.basekubbsB == 0) {
        return l.tournamentMatchValidationEmpty(i + 1);
      }
      if (d.king == SetWinner.teamA && d.basekubbsA != _maxBasekubbs) {
        return l.tournamentMatchValidationKingNeedsMax(i + 1);
      }
      if (d.king == SetWinner.teamB && d.basekubbsB != _maxBasekubbs) {
        return l.tournamentMatchValidationKingNeedsMax(i + 1);
      }
    }
    return null;
  }

  List<SetScore> _setScores() => <SetScore>[
        for (final d in _drafts)
          SetScore(
            basekubbsKnockedByA: d.basekubbsA,
            basekubbsKnockedByB: d.basekubbsB,
            winner: d.king ??
                (d.basekubbsA >= d.basekubbsB
                    ? SetWinner.teamA
                    : SetWinner.teamB),
          ),
      ];

  Future<void> _submit(TournamentMatchRef match) async {
    final l = AppLocalizations.of(context);
    if (_submitting || _validate(l) != null) return;
    setState(() => _submitting = true);
    final prevConsensus = match.consensusRound;
    try {
      await ref.read(tournamentActionsProvider).proposeSetScores(
            matchId: match.matchId,
            consensusRound: prevConsensus,
            setScores: _setScores(),
          );
      if (!mounted) return;
      final next = await ref
          .read(tournamentMatchDetailProvider(match.matchId).future);
      if (!mounted || next == null) return;
      final messenger = ScaffoldMessenger.of(context);
      if (next.status == TournamentMatchStatus.finalized ||
          next.status == TournamentMatchStatus.overridden) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.tournamentMatchFinalizedToast)));
        context.go(TournamentRoutes.standings(widget.tournamentId));
        return;
      }
      if (next.status == TournamentMatchStatus.disputed) {
        messenger.showSnackBar(SnackBar(
            content: Text(l.tournamentMatchDisputedToast),
            backgroundColor: KubbTokens.miss));
        context.go(TournamentRoutes.matchesFor(widget.tournamentId));
        return;
      }
      if (next.consensusRound > prevConsensus) {
        setState(() {
          _prefilledForRound = next.consensusRound;
          _drafts = const <_SetDraft>[_SetDraft()];
        });
        if (mounted) {
          unawaited(context.push<void>(TournamentRoutes.conflict(
              widget.tournamentId, match.matchId.value)));
        } else {
          messenger.showSnackBar(SnackBar(
            content: Text(l.tournamentMatchDisagreementToast(
                next.consensusRound, ScoreConsensusBanner.maxAttempts)),
            backgroundColor: KubbTokens.wood400,
          ));
        }
      }
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${l.tournamentMatchSubmitError}: $e'),
        backgroundColor: KubbTokens.miss,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final id = TournamentMatchId(widget.matchId);
    ref.watch(tournamentMatchPollingProvider(id));
    final detailAsync = ref.watch(tournamentMatchDetailProvider(id));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(
          onPressed: () =>
              context.go(TournamentRoutes.matchesFor(widget.tournamentId)),
        ),
        title: Text(l.tournamentMatchDetailTitle),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(message: '${l.tournamentMatchLoadError}: $e'),
        data: (match) {
          if (match == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _ensureDraftForRound(match);
          return _renderBody(context, match, l, tokens);
        },
      ),
    );
  }

  Widget _renderBody(BuildContext context, TournamentMatchRef match,
      AppLocalizations l, KubbTokens tokens) {
    final readOnly = match.status == TournamentMatchStatus.finalized ||
        match.status == TournamentMatchStatus.overridden ||
        match.status == TournamentMatchStatus.voided;
    final validationMessage = _validate(l);
    final ekc = computeEkc(_setScores());

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        _Header(match: match, tournamentId: TournamentId(widget.tournamentId)),
        const SizedBox(height: KubbTokens.space3),
        ScoreConsensusBanner(attempt: match.consensusRound),
        for (var i = 0; i < _drafts.length; i++) ...[
          TournamentSetInput(
            setNumber: i + 1,
            basekubbsA: _drafts[i].basekubbsA,
            basekubbsB: _drafts[i].basekubbsB,
            king: _drafts[i].king,
            maxBasekubbs: _maxBasekubbs,
            enabled: !readOnly,
            onChanged: (v) => _update(i, v),
          ),
          const SizedBox(height: KubbTokens.space3),
        ],
        if (!readOnly) ...[
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _drafts.length <= 1 ? null : _removeSet,
                icon: const Icon(LucideIcons.minus),
                label: Text(l.tournamentMatchRemoveSet),
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _drafts.length >= _maxSets ? null : _addSet,
                icon: const Icon(LucideIcons.plus),
                label: Text(l.tournamentMatchAddSet),
              ),
            ),
          ]),
          const SizedBox(height: KubbTokens.space4),
        ],
        _LivePreview(ekc: ekc),
        const SizedBox(height: KubbTokens.space4),
        if (validationMessage != null && !readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: KubbTokens.space3),
            child: Text(validationMessage,
                style: const TextStyle(
                    fontSize: 12,
                    color: KubbTokens.miss,
                    fontWeight: FontWeight.w600)),
          ),
        if (!readOnly)
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: FilledButton(
              onPressed: _submitting || validationMessage != null
                  ? null
                  : () => _submit(match),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l.tournamentMatchSubmitButton),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: KubbTokens.space2),
            child: Text(l.tournamentMatchReadOnlyNotice,
                style: TextStyle(color: tokens.fgMuted, fontSize: 13)),
          ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss)),
        ),
      );
}

class _Header extends ConsumerWidget {
  const _Header({required this.match, required this.tournamentId});
  final TournamentMatchRef match;
  final TournamentId tournamentId;

  static String _shortId(String? id) => id == null
      ? '?'
      : (id.length <= 6 ? id : id.substring(0, 6));

  /// T17 — render a roster summary for a team participant. Falls back
  /// to the short participant id while the roster is loading or when
  /// the RPC fails (the header itself stays useful either way).
  String _teamLabel(
    WidgetRef ref,
    AppLocalizations l,
    TournamentParticipantId? pid,
  ) {
    if (pid == null) return '?';
    final roster = ref.watch(tournamentRosterProvider(pid));
    final members = roster.maybeWhen<List<String>?>(
      data: (slots) => <String>[
        for (final s in slots)
          if (s.memberUserId != null)
            _shortId(s.memberUserId!.value)
          else if (s.guestPlayerId != null)
            _shortId(s.guestPlayerId!.value),
      ],
      orElse: () => null,
    );
    if (members == null || members.isEmpty) return _shortId(pid.value);
    return l.tournamentMatchHammerCrew(members.join(', '));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final isBye = match.participantB == null;
    // T17 — opt into the team-match header only when the tournament is
    // configured for teams (team_size > 1). Single-player tournaments
    // keep the M1 short-id header verbatim per acceptance criterion 4.
    final teamSize = ref.watch(tournamentDetailProvider(tournamentId)).maybeWhen(
          data: (d) => d?.tournament.teamSize ?? 1,
          orElse: () => 1,
        );
    final isTeam = teamSize > 1;
    final aLabel = isTeam
        ? _teamLabel(ref, l, match.participantA)
        : _shortId(match.participantA?.value);
    final bLabel = isTeam
        ? _teamLabel(ref, l, match.participantB)
        : _shortId(match.participantB?.value);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              : l.tournamentMatchVersusHeader(aLabel, bLabel),
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: tokens.fg),
        ),
      ]),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.ekc});
  final MatchEkcScore ekc;
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final w = ekc.matchWinner;
    final score = l.tournamentMatchLivePreviewScore(ekc.setsWonA, ekc.setsWonB);
    final line = w == null
        ? '$score — ${l.tournamentMatchLivePreviewUndecided}'
        : '$score — ${w == SetWinner.teamA ? l.tournamentMatchKingByA : l.tournamentMatchKingByB}';
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.tournamentMatchLivePreviewLabel,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.fgMuted)),
        const SizedBox(height: KubbTokens.space2),
        Text(line,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: tokens.fg)),
      ]),
    );
  }
}

@immutable
class _SetDraft {
  const _SetDraft({this.basekubbsA = 0, this.basekubbsB = 0, this.king});
  final int basekubbsA;
  final int basekubbsB;
  final SetWinner? king;
}
