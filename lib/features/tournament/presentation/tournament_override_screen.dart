import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_override_controller.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_set_input.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Organizer-only entry point for disputed matches (spec DSCORE-52..-58).
/// Three stacked sections — proposals review (collapsible), final score
/// (reusing [TournamentSetInput]) and the mandatory reason — feed a
/// single submit that calls `tournament_organizer_override`.
class TournamentOverrideScreen extends ConsumerStatefulWidget {
  const TournamentOverrideScreen({
    required this.tournamentId,
    required this.matchId,
    super.key,
  });

  final String tournamentId;
  final String matchId;

  @override
  ConsumerState<TournamentOverrideScreen> createState() =>
      _OverrideState();
}

class _OverrideState extends ConsumerState<TournamentOverrideScreen> {
  late final TextEditingController _reason;
  bool _proposalsExpanded = false;
  static const int _defaultMaxBasekubbs = 5;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController()..addListener(_syncReason);
  }

  @override
  void dispose() {
    _reason
      ..removeListener(_syncReason)
      ..dispose();
    super.dispose();
  }

  void _syncReason() {
    final n = ref.read(tournamentOverrideControllerProvider.notifier);
    if (_reason.text == ref.read(tournamentOverrideControllerProvider).reason) {
      return;
    }
    n.setReason(_reason.text);
    final clamped = ref.read(tournamentOverrideControllerProvider).reason;
    if (clamped != _reason.text) {
      _reason.value = TextEditingValue(
        text: clamped,
        selection: TextSelection.collapsed(offset: clamped.length),
      );
    }
  }

  ({int setsToWin, int maxSets, int maxBasekubbs}) _config(
      TournamentDetail? d) {
    final cfg = d?.tournament.matchFormatConfig ?? const <String, Object?>{};
    final s = (cfg['sets_to_win'] as num?)?.toInt() ?? 2;
    return (
      setsToWin: s,
      maxSets: (cfg['max_sets'] as num?)?.toInt() ?? (2 * s - 1),
      maxBasekubbs:
          (cfg['basekubbs_per_side'] as num?)?.toInt() ?? _defaultMaxBasekubbs,
    );
  }

  Future<void> _submit({
    required TournamentMatchId matchId,
    required int setsToWin,
    required AppLocalizations l,
  }) async {
    final n = ref.read(tournamentOverrideControllerProvider.notifier);
    try {
      await n.submit(matchId, setsToWin: setsToWin);
      if (!mounted) return;
      context.go(TournamentRoutes.matchDetail(widget.tournamentId, widget.matchId));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.tournamentOverrideSubmitError(e.toString())),
        backgroundColor: KubbTokens.miss,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final matchIdObj = TournamentMatchId(widget.matchId);
    final tournamentIdObj = TournamentId(widget.tournamentId);
    final myUserId = ref.watch(currentUserIdProvider);
    final detailAsync = ref.watch(tournamentDetailProvider(tournamentIdObj));
    final matchAsync = ref.watch(tournamentMatchDetailProvider(matchIdObj));

    Widget gate(String message) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: KubbTokens.miss,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
        );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(
          onPressed: () => context.go(
              TournamentRoutes.matchDetail(widget.tournamentId, widget.matchId)),
        ),
        title: Text(l.tournamentOverrideTitle),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => gate(e.toString()),
        data: (detail) => matchAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => gate(e.toString()),
          data: (match) {
            if (match == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final isCreator = detail?.isCallerCreator(myUserId) ?? false;
            if (!isCreator) return gate(l.tournamentOverrideNotAuthorized);
            if (match.status != TournamentMatchStatus.disputed) {
              return gate(l.tournamentOverrideStatusGate);
            }
            return _body(match: match, detail: detail, l: l, tokens: tokens);
          },
        ),
      ),
    );
  }

  Widget _body({
    required TournamentMatchRef match,
    required TournamentDetail? detail,
    required AppLocalizations l,
    required KubbTokens tokens,
  }) {
    final cfg = _config(detail);
    final draft = ref.watch(tournamentOverrideControllerProvider);
    final n = ref.read(tournamentOverrideControllerProvider.notifier);
    final scores = n.toSetScores();
    final ekc = computeEkc(scores);
    final decisive = n.isScoreDecisive(cfg.setsToWin);
    final reasonValid = n.isReasonValid();
    final canSubmit = decisive && reasonValid && !draft.submitting;

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        _eyebrow(l, tokens, match),
        const SizedBox(height: KubbTokens.space3),
        _proposalsCard(l, tokens, match.consensusRound),
        const SizedBox(height: KubbTokens.space4),
        _sectionHeader(tokens, l.tournamentOverrideFinalHeader),
        const SizedBox(height: KubbTokens.space3),
        for (var i = 0; i < draft.sets.length; i++) ...[
          TournamentSetInput(
            setNumber: i + 1,
            basekubbsA: draft.sets[i].basekubbsA,
            basekubbsB: draft.sets[i].basekubbsB,
            king: draft.sets[i].king,
            maxBasekubbs: cfg.maxBasekubbs,
            onChanged: (v) => n.updateSet(
              i,
              TournamentOverrideSetDraft(
                basekubbsA: v.basekubbsA,
                basekubbsB: v.basekubbsB,
                king: v.king,
              ),
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
        ],
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: draft.sets.length <= 1 ? null : n.removeSet,
              icon: const Icon(LucideIcons.minus),
              label: Text(l.tournamentMatchRemoveSet),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: draft.sets.length >= cfg.maxSets
                  ? null
                  : () => n.addSet(maxSets: cfg.maxSets),
              icon: const Icon(LucideIcons.plus),
              label: Text(l.tournamentMatchAddSet),
            ),
          ),
        ]),
        const SizedBox(height: KubbTokens.space4),
        _livePreview(l, tokens, ekc, decisive),
        const SizedBox(height: KubbTokens.space4),
        _sectionHeader(tokens, l.tournamentOverrideReasonHeader),
        const SizedBox(height: KubbTokens.space2),
        TextField(
          controller: _reason,
          maxLines: 4,
          maxLength: TournamentOverrideController.reasonMax,
          decoration: InputDecoration(
            hintText: l.tournamentOverrideReasonHint,
            filled: true,
            fillColor: tokens.bgSunken,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
              borderSide: BorderSide(color: tokens.line),
            ),
            counterText: '',
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            l.tournamentOverrideReasonCounter(
                draft.reason.trim().length,
                TournamentOverrideController.reasonMax),
            style: TextStyle(
                fontSize: 12,
                color: reasonValid ? tokens.fgMuted : KubbTokens.miss,
                fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        if (!decisive) _validationLine(l.tournamentOverrideValidationScoreNotDecisive),
        if (!reasonValid) _validationLine(l.tournamentOverrideValidationReasonEmpty),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: FilledButton(
            onPressed: canSubmit
                ? () => _submit(matchId: match.matchId, setsToWin: cfg.setsToWin, l: l)
                : null,
            child: draft.submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(l.tournamentOverrideSubmitButton),
          ),
        ),
      ],
    );
  }

  Widget _eyebrow(AppLocalizations l, KubbTokens tokens, TournamentMatchRef m) {
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.tournamentOverrideEyebrow.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: KubbTokens.miss,
                letterSpacing: 0.6)),
        const SizedBox(height: KubbTokens.space2),
        Text(
          l.tournamentMatchHeaderRound(m.roundNumber, m.matchNumberInRound),
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: tokens.fg),
        ),
      ]),
    );
  }

  Widget _sectionHeader(KubbTokens tokens, String label) => Text(label,
      style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800, color: tokens.fg));

  Widget _validationLine(String message) => Padding(
        padding: const EdgeInsets.only(bottom: KubbTokens.space2),
        child: Text(message,
            style: const TextStyle(
                color: KubbTokens.miss,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  /// Header strip + collapsible empty body. No per-team set-proposal
  /// listing API exists yet; the section ships now so the audit trail
  /// surface is on the screen the moment the RPC lands.
  Widget _proposalsCard(AppLocalizations l, KubbTokens tokens, int round) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _proposalsExpanded = !_proposalsExpanded),
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space3),
            child: Row(children: [
              Expanded(
                child: Text(l.tournamentOverrideProposalsHeader,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg)),
              ),
              Text(l.tournamentMatchConsensusAttempt(round, 3),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.fgMuted)),
              const SizedBox(width: KubbTokens.space2),
              Icon(
                _proposalsExpanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                size: 18,
                color: tokens.fgMuted,
              ),
            ]),
          ),
        ),
        if (_proposalsExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(KubbTokens.space3, 0,
                KubbTokens.space3, KubbTokens.space3),
            child: Text(l.tournamentOverrideProposalsEmpty,
                style: TextStyle(
                    fontSize: 12,
                    color: tokens.fgMuted,
                    fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  Widget _livePreview(
      AppLocalizations l, KubbTokens tokens, MatchEkcScore ekc, bool decisive) {
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
        border: Border.all(
            color: decisive ? KubbTokens.meadow600 : tokens.line,
            width: decisive ? 2 : 1),
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
