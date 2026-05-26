import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_card.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_status_pill.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Status-aware detail view for one tournament. Renders the header,
/// Stammdaten card, participant list (filtered by caller role), an
/// action area that adapts to lifecycle status, and a collapsible audit
/// tail. Polling via [tournamentDetailPollingProvider].
class TournamentDetailScreen extends ConsumerWidget {
  const TournamentDetailScreen({required this.tournamentId, super.key});
  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    ref.watch(tournamentDetailPollingProvider(tournamentId));
    final detailAsync = ref.watch(tournamentDetailProvider(tournamentId));
    final myUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentDetailEyebrow,
        title: detailAsync.maybeWhen(
            data: (d) => d?.tournament.displayName ?? l.tournamentDetailEyebrow,
            orElse: () => l.tournamentDetailEyebrow),
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
        data: (d) => d == null
            ? Center(child: Text(l.tournamentDetailNotFound))
            : _Body(detail: d, myUserId: myUserId, id: tournamentId),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(
      {required this.detail, required this.myUserId, required this.id});
  final TournamentDetail detail;
  final String? myUserId;
  final TournamentId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final isCreator = detail.isCallerCreator(myUserId);
    TournamentParticipant? me;
    if (myUserId != null) {
      for (final p in detail.participants) {
        if (p.userId == myUserId) {
          me = p;
          break;
        }
      }
    }
    final h = detail.tournament;
    final cfg = h.matchFormatConfig;
    final visibleParts = detail.participants.where((p) {
      if (isCreator) {
        return p.registrationStatus == TournamentParticipantStatus.pending ||
            p.registrationStatus == TournamentParticipantStatus.approved;
      }
      return p.registrationStatus == TournamentParticipantStatus.approved;
    }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(KubbTokens.space4, KubbTokens.space2,
          KubbTokens.space4, KubbTokens.space12),
      children: [
        Row(children: [
          Expanded(
              child: Text(h.displayName,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: tokens.fg))),
          TournamentStatusPill(status: h.status),
        ]),
        const SizedBox(height: KubbTokens.space2),
        Text(
          l.tournamentDetailParticipantSummary(
              detail.participants.length, h.maxParticipants),
          style: TextStyle(fontSize: 13, color: tokens.fgMuted),
        ),
        const SizedBox(height: KubbTokens.space5),
        _card(context, l.tournamentDetailStammdaten, [
          _row(context, l.tournamentDetailFormat, formatLabel(h.format, l)),
          _row(context, l.tournamentDetailTeamSize, '${h.teamSize}'),
          if (cfg['sets_to_win'] != null)
            _row(context, l.tournamentDetailSetsToWin,
                '${cfg['sets_to_win']}'),
          if (cfg['max_sets'] != null)
            _row(context, l.tournamentDetailMaxSets, '${cfg['max_sets']}'),
          if (cfg['round_time_minutes'] != null)
            _row(context, l.tournamentDetailRoundTime,
                '${cfg['round_time_minutes']} min'),
        ]),
        const SizedBox(height: KubbTokens.space5),
        _card(context, l.tournamentDetailParticipants, [
          if (visibleParts.isEmpty)
            Text(l.tournamentDetailParticipantsEmpty,
                style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
          for (final p in visibleParts)
            _participantRow(context, ref, p, isCreator, l, tokens),
        ]),
        const SizedBox(height: KubbTokens.space5),
        _Actions(detail: detail, isCreator: isCreator, me: me, id: id),
        const SizedBox(height: KubbTokens.space5),
        _AuditTail(events: detail.auditTail),
      ],
    );
  }
}

Widget _row(BuildContext context, String label, String value) {
  final tokens = Theme.of(context).extension<KubbTokens>()!;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
    child: Row(children: [
      Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 13, color: tokens.fgMuted))),
      Text(value,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg)),
    ]),
  );
}

Widget _card(BuildContext context, String heading, List<Widget> children) {
  final tokens = Theme.of(context).extension<KubbTokens>()!;
  return Container(
    padding: const EdgeInsets.all(KubbTokens.space4),
    decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(heading.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: tokens.fgMuted)),
      const SizedBox(height: KubbTokens.space2),
      ...children,
    ]),
  );
}

Future<void> _safe(BuildContext context, Future<void> Function() op) async {
  try {
    await op();
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: KubbTokens.miss));
  }
}

Widget _participantRow(
  BuildContext context,
  WidgetRef ref,
  TournamentParticipant p,
  bool isOrganizer,
  AppLocalizations l,
  KubbTokens tokens,
) {
  final pending =
      p.registrationStatus == TournamentParticipantStatus.pending;
  final pid = TournamentParticipantId(p.participantId);
  final actions = ref.read(tournamentActionsProvider);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
    child: Row(children: [
      Expanded(
        child: Text(p.displayLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg)),
      ),
      if (pending)
        Padding(
          padding: const EdgeInsets.only(right: KubbTokens.space2),
          child: Text(l.tournamentDetailPending,
              style: TextStyle(fontSize: 11, color: tokens.fgMuted)),
        ),
      if (isOrganizer && pending) ...[
        TextButton(
            onPressed: () =>
                _safe(context, () => actions.confirmRegistration(pid)),
            child: Text(l.tournamentDetailApprove)),
        TextButton(
            onPressed: () =>
                _safe(context, () => actions.rejectRegistration(pid)),
            child: Text(l.tournamentDetailReject)),
      ],
    ]),
  );
}

class _Actions extends ConsumerWidget {
  const _Actions(
      {required this.detail,
      required this.isCreator,
      required this.me,
      required this.id});
  final TournamentDetail detail;
  final bool isCreator;
  final TournamentParticipant? me;
  final TournamentId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final actions = ref.read(tournamentActionsProvider);
    final status = detail.tournament.status;
    final buttons = <Widget>[];
    final pathBase = '${TournamentRoutes.detail}/${id.value}';
    // T15: surface bracket entry once any KO/third_place/final match
    // exists. `tournamentBracketProvider` fetches exactly those rows
    // and throws `ArgumentError` while the tournament is still in the
    // group phase — both `error` and `loading` map to "no bracket yet"
    // via `maybeWhen`.
    final hasBracket = ref.watch(tournamentBracketProvider(id)).maybeWhen(
          data: (b) => switch (b) {
            SingleEliminationBracket(:final rounds) => rounds.isNotEmpty,
          },
          orElse: () => false,
        );

    Widget mk(String label, VoidCallback onTap, {Color? color}) => SizedBox(
          height: KubbTokens.touchComfortable,
          child: FilledButton(
            style: color == null
                ? null
                : FilledButton.styleFrom(backgroundColor: color),
            onPressed: onTap,
            child: Text(label),
          ),
        );
    void op(String label, Future<void> Function() fn, {Color? color}) =>
        buttons.add(mk(label, () => _safe(context, fn), color: color));
    void nav(String label, String path) =>
        buttons.add(mk(label, () => context.push(path)));

    if (status == TournamentStatus.draft && isCreator) {
      op(l.tournamentDetailActionPublish, () => actions.publish(id));
    } else if (status == TournamentStatus.published && isCreator) {
      op(l.tournamentDetailActionOpenReg, () => actions.openRegistration(id));
    } else if (status == TournamentStatus.registrationOpen) {
      if (isCreator) {
        op(l.tournamentDetailActionCloseReg,
            () => actions.closeRegistration(id));
      } else if (me == null) {
        nav(l.tournamentDetailActionRegister, '$pathBase/register');
      } else {
        final m = me!;
        if (m.registrationStatus != TournamentParticipantStatus.withdrawn) {
          op(
              l.tournamentDetailActionWithdraw,
              () => actions.withdrawRegistration(
                  TournamentParticipantId(m.participantId)),
              color: KubbTokens.miss);
        }
      }
    } else if (status == TournamentStatus.registrationClosed && isCreator) {
      op(l.tournamentDetailActionStart, () => actions.startTournament(id));
    } else if (status == TournamentStatus.live) {
      if (isCreator) {
        op(l.tournamentDetailActionFinalize,
            () => actions.finalizeTournament(id));
      }
      if (me != null) {
        nav(l.tournamentDetailActionGotoMatches, '$pathBase/matches');
      }
    } else if (status == TournamentStatus.finalized) {
      nav(l.tournamentDetailActionStandings, '$pathBase/standings');
    } else if (status == TournamentStatus.aborted) {
      return Container(
        padding: const EdgeInsets.all(KubbTokens.space4),
        decoration: BoxDecoration(
            color: KubbTokens.miss.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(KubbTokens.radiusMd)),
        child: Text(l.tournamentDetailAborted,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg)),
      );
    }

    if (hasBracket) {
      nav(l.tournamentDetailActionBracket, '$pathBase/bracket');
    }
    if (isCreator &&
        status != TournamentStatus.finalized &&
        status != TournamentStatus.aborted) {
      op(l.tournamentDetailActionAbort, () => actions.abortTournament(id),
          color: KubbTokens.miss);
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: KubbTokens.space2),
          buttons[i],
        ],
      ],
    );
  }
}

class _AuditTail extends StatelessWidget {
  const _AuditTail({required this.events});
  final List<TournamentAuditEvent> events;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final latest = events.take(5).toList(growable: false);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg)),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
          title: Text(l.tournamentDetailAuditHeader.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.88,
                  color: tokens.fgMuted)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(KubbTokens.space4, 0,
                  KubbTokens.space4, KubbTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (latest.isEmpty)
                    Text(l.tournamentDetailAuditEmpty,
                        style:
                            TextStyle(fontSize: 13, color: tokens.fgMuted)),
                  for (final e in latest)
                    Padding(
                      padding: const EdgeInsets.only(top: KubbTokens.space1),
                      child: Text('${e.at.toIso8601String()} — ${e.kind}',
                          style:
                              TextStyle(fontSize: 12, color: tokens.fgMuted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
