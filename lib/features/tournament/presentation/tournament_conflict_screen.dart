import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_conflict_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/conflict_comparison_row.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Side-by-side diff view shown between consensus rounds.
///
/// Reads proposals via [tournamentConflictProvider] (empty default in
/// M1, server-backed feed in M2) and lets either team retry or
/// escalate. Final escalation RPC lands in M4 — the button posts a
/// snackbar and returns to detail. See FR-CONF-4.
class TournamentConflictScreen extends ConsumerWidget {
  const TournamentConflictScreen({
    required this.tournamentId,
    required this.matchId,
    super.key,
  });

  final String tournamentId;
  final String matchId;
  static const int maxAttempts = 3;

  void _goDetail(BuildContext context) =>
      context.go(TournamentRoutes.matchDetail(tournamentId, matchId));

  void _escalate(BuildContext context, AppLocalizations l) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.tournamentConflictEscalateToast)),
    );
    _goDetail(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final id = TournamentMatchId(matchId);
    final conflictAsync = ref.watch(tournamentConflictProvider(id));
    final matchAsync = ref.watch(tournamentMatchDetailProvider(id));
    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => _goDetail(context)),
        title: Text(l.tournamentConflictTitle),
      ),
      body: conflictAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text('$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss)),
        ),
        data: (snapshot) => _buildBody(
          context,
          l,
          tokens,
          snapshot,
          matchAsync.asData?.value,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l,
    KubbTokens tokens,
    TournamentConflictSnapshot snapshot,
    TournamentMatchRef? match,
  ) {
    final attempt = match?.consensusRound ?? snapshot.consensusRound;
    final isLast = attempt >= maxAttempts;
    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        if (match != null) _header(match, tokens, l),
        const SizedBox(height: KubbTokens.space3),
        _attemptBanner(attempt, tokens, l),
        const SizedBox(height: KubbTokens.space3),
        _columnHeaders(tokens, l),
        const SizedBox(height: KubbTokens.space2),
        if (snapshot.pairs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KubbTokens.space4),
            child: Text(l.tournamentConflictEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.fgMuted, fontSize: 13)),
          )
        else
          for (final pair in snapshot.pairs)
            ConflictComparisonRow(pair: pair),
        if (isLast) ...[
          const SizedBox(height: KubbTokens.space2),
          _lastAttemptWarning(l),
        ],
        const SizedBox(height: KubbTokens.space4),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: FilledButton.icon(
            onPressed: () => _goDetail(context),
            icon: const Icon(LucideIcons.refreshCw),
            label: Text(l.tournamentConflictRetryButton),
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: OutlinedButton.icon(
            onPressed: () => _escalate(context, l),
            icon: const Icon(LucideIcons.shield),
            label: Text(l.tournamentConflictEscalateButton),
          ),
        ),
      ],
    );
  }

  Widget _header(TournamentMatchRef m, KubbTokens t, AppLocalizations l) {
    String s(String? id) =>
        id == null ? '?' : (id.length <= 6 ? id : id.substring(0, 6));
    final isBye = m.participantB == null;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: t.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          l.tournamentMatchHeaderRound(m.roundNumber, m.matchNumberInRound),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: t.fgMuted,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          isBye
              ? l.tournamentMatchByeHeader
              : l.tournamentMatchVersusHeader(
                  s(m.participantA?.value), s(m.participantB?.value)),
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: t.fg),
        ),
      ]),
    );
  }

  Widget _attemptBanner(int attempt, KubbTokens t, AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: KubbTokens.wood100,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: KubbTokens.wood400, width: 2),
      ),
      child: Row(children: [
        const Icon(LucideIcons.alertTriangle, color: KubbTokens.wood600),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: Text(l.tournamentConflictAttempt(attempt),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: t.fg)),
        ),
      ]),
    );
  }

  Widget _lastAttemptWarning(AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: KubbTokens.miss,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Row(children: [
        const Icon(LucideIcons.alertOctagon, color: Colors.white),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: Text(l.tournamentConflictLastAttemptWarning,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
      ]),
    );
  }

  Widget _columnHeaders(KubbTokens t, AppLocalizations l) {
    final style = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: t.fgMuted,
        letterSpacing: 0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
      child: Row(children: [
        const Expanded(flex: 4, child: SizedBox.shrink()),
        Expanded(
          flex: 3,
          child: Text(l.tournamentConflictColumnA,
              textAlign: TextAlign.center, style: style),
        ),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          flex: 3,
          child: Text(l.tournamentConflictColumnB,
              textAlign: TextAlign.center, style: style),
        ),
      ]),
    );
  }
}
