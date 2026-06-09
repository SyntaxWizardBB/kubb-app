import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_state_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_status_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_stammdaten_card.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_status_pill.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:url_launcher/url_launcher.dart';

/// CF5/K28: opens an external URL (the public Storage URL of an uploaded
/// tournament PDF). Injectable so widget tests can assert the open callback
/// without reaching the platform `url_launcher`.
typedef TournamentUrlOpener = Future<bool> Function(Uri url);

final tournamentUrlOpenerProvider = Provider<TournamentUrlOpener>((ref) {
  return (url) => launchUrl(url, mode: LaunchMode.externalApplication);
});

/// Status-aware detail view for one tournament. Renders the header,
/// Stammdaten card, participant list (filtered by caller role), an
/// action area that adapts to lifecycle status, and a collapsible audit
/// tail. Live updates via CDC ([tournamentDetailCdcProvider]).
class TournamentDetailScreen extends ConsumerWidget {
  const TournamentDetailScreen({required this.tournamentId, super.key});
  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    // M4.1-T12: subscribe to the bracket realtime stream so winner
    // propagations (`bracket_advance`) re-fetch the bracket without
    // touching the detail poll. The match-list realtime keeps the
    // participant counters and audit tail aligned via its provider
    // invalidation chain (M4.1-T8).
    ref
      ..watch(tournamentMatchListRealtimeProvider(tournamentId))
      ..watch(tournamentBracketRealtimeProvider(tournamentId))
      // C4-T3: tournament_matches CDC keeps the detail fresh (terminal-stop
      // after finalized/aborted, gated 30 s fallback). Replaces the 5 s poll.
      ..watch(tournamentDetailCdcProvider(tournamentId))
      // D4: tournament_participants CDC (D3 provider) pushes check-in flips
      // from other devices and invalidates tournamentDetailProvider — no new
      // polling (ADR-0029). Subscribe on first watch, autoDispose teardown.
      ..watch(tournamentParticipantListRealtimeProvider(tournamentId));
    final detailAsync = ref.watch(tournamentDetailProvider(tournamentId));
    final myUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: KubbAppBar(
        eyebrow: l.tournamentDetailEyebrow,
        title: detailAsync.maybeWhen(
            data: (d) => d?.tournament.displayName ?? l.tournamentDetailEyebrow,
            orElse: () => l.tournamentDetailEyebrow),
      ),
      body: Column(
        children: [
          RealtimeStateBanner(tournamentId: tournamentId),
          RealtimeStatusBanner(tournamentId: tournamentId),
          Expanded(
            child: detailAsync.when(
              // The detail is invalidated by [tournamentDetailCdcProvider]
              // (event-driven CDC, with a gated 30 s fallback); without this
              // the whole body would flash a full-screen spinner on each
              // reload ("spinning" detail screen). Keep the last data during
              // background reloads — only show the spinner on the very first
              // load (no value yet).
              skipLoadingOnReload: true,
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
          ),
        ],
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
    // Lifecycle/edit authority (PER-TOURNAMENT). The creator is always
    // allowed; an active owner/admin/organizer of the tournament's
    // organizing club (detail.tournament.clubId) also gets the lifecycle and
    // edit actions. A tournament with no club is manageable by the creator
    // only. The server re-checks `tournament_caller_can_manage` in every
    // lifecycle/update RPC, so this only governs button visibility.
    final canManage = isCreator ||
        ref.watch(canManageTournamentClubProvider(detail.tournament.clubId));
    // D4: on-site check-in window (OE-D1 + K4). The toggle is offered only
    // while the tournament accepts/runs play; draft/finalized/aborted never
    // show it. The server re-checks the same gate + status window, so this
    // only governs button visibility.
    final checkinWindowOpen =
        detail.tournament.status == TournamentStatus.registrationOpen ||
            detail.tournament.status == TournamentStatus.registrationClosed ||
            detail.tournament.status == TournamentStatus.live;
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
    // New open-registration model: confirmed participants form the pool;
    // waitlisted ones are shown in a separate, ordered section. Legacy
    // `pending` rows (no longer produced) still count as confirmed-pool
    // for display so old data renders sensibly. `withdrawn`/`rejected`
    // never surface.
    final confirmedParts = detail.participants
        .where((p) =>
            p.registrationStatus == TournamentParticipantStatus.approved ||
            p.registrationStatus == TournamentParticipantStatus.pending)
        .toList(growable: false);
    final waitlistParts = detail.participants
        .where((p) =>
            p.registrationStatus == TournamentParticipantStatus.waitlist)
        .toList(growable: false)
      ..sort((a, b) => a.registeredAt.compareTo(b.registeredAt));

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
        // H2: the shared Stammdaten card renders ALL configured master data
        // (B3.1–B3.4) verbatim from the header (matchFormatConfig + setup),
        // omitting unset fields. It replaces the former inline Stammdaten
        // section + `_metaCards` so the detail (and the upcoming-tournaments
        // detail, same route) always shows every configured field.
        TournamentStammdatenCard(header: h),
        const SizedBox(height: KubbTokens.space5),
        _card(context, l.tournamentDetailParticipants, [
          // D4 (optional header counter): while the check-in window is open and
          // the caller can manage, show "X/Y eingecheckt" over the confirmed
          // pool so the organizer sees attendance at a glance.
          if (canManage && checkinWindowOpen && confirmedParts.isNotEmpty) ...[
            Text(
              l.tournamentDetailCheckedInCount(
                confirmedParts.where((p) => p.isCheckedIn).length,
                confirmedParts.length,
              ),
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
            const SizedBox(height: KubbTokens.space1),
          ],
          if (confirmedParts.isEmpty)
            Text(l.tournamentDetailParticipantsEmpty,
                style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
          for (final p in confirmedParts)
            _participantRow(context, ref, p, isCreator, l, tokens,
                tournamentId: id,
                canManage: canManage,
                checkinWindowOpen: checkinWindowOpen),
          // Waitlist overview (in registration order). Visible to everyone
          // so registrants understand the queue; the organizer additionally
          // gets the optional (non-required) moderation remove on each row.
          if (waitlistParts.isNotEmpty) ...[
            const SizedBox(height: KubbTokens.space3),
            Text(l.tournamentDetailWaitlistHeading.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.88,
                    color: tokens.fgMuted)),
            const SizedBox(height: KubbTokens.space1),
            // Waitlisted rows never get a check-in toggle (check-in is for
            // confirmed pool members only — Phase-D spec, check-in ≠ confirm).
            for (final p in waitlistParts)
              _participantRow(context, ref, p, isCreator, l, tokens),
          ],
        ]),
        // T17: Roster tab visibility. The caller's participant carries a
        // team_id exactly when the tournament is configured for teams
        // (team_size > 1) — single-player tournaments don't materialize
        // a roster row. Only render when the caller is part of the pool
        // so non-members never see the section (acceptance criterion 2).
        if (me != null && h.teamSize > 1) ...[
          const SizedBox(height: KubbTokens.space5),
          _RosterCard(
              participantId: TournamentParticipantId(me.participantId)),
        ],
        // T12 (M3.3): pool-phase "Gruppen" tab. The detail screen renders
        // a flat ListView (no TabController), so the tab maps to an
        // inline card — same pattern as `_RosterCard`. Visibility is
        // gated on `match_format.pool_phase=true`; when the flag is
        // absent or false the section vanishes entirely (no provider
        // watch, no RPC).
        if (cfg['pool_phase'] == true) ...[
          const SizedBox(height: KubbTokens.space5),
          _PoolStandingsCard(id: id),
        ],
        const SizedBox(height: KubbTokens.space5),
        _Actions(
            detail: detail,
            isCreator: isCreator,
            canManage: canManage,
            me: me,
            id: id),
        const SizedBox(height: KubbTokens.space5),
        _AuditTail(events: detail.auditTail),
      ],
    );
  }
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

/// CF6 (K19): the configured seeding mode, read from the
/// `ko_config.seeding_mode` discriminator on the projected setup map.
/// Defaults to [SeedingMode.auto] when absent or unrecognised, matching
/// the wizard/server default — so only an explicit `manual` triggers the
/// mandatory seeding step.
SeedingMode _seedingMode(TournamentDetail detail) {
  final ko = detail.tournament.setup['ko_config'];
  if (ko is Map && ko['seeding_mode'] == 'manual') {
    return SeedingMode.manual;
  }
  return SeedingMode.auto;
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
  KubbTokens tokens, {
  // D4: on-site check-in gate. The toggle is rendered ONLY for confirmed rows
  // when [canManage] is true AND the tournament status is inside the check-in
  // window ([checkinWindowOpen], OE-D1 + K4). Both default to off so waitlist
  // rows and non-manager views never see it. The server re-checks the same
  // gate/status/idempotency; this is visibility only.
  TournamentId? tournamentId,
  bool canManage = false,
  bool checkinWindowOpen = false,
}) {
  // New model: registrations are auto-confirmed; the only non-confirmed
  // pool state shown here is `waitlist`. Approve/reject is gone (no row is
  // ever `pending` anymore); the organizer keeps an OPTIONAL moderation
  // remove that maps to the legacy reject RPC — it is not a required step.
  final isWaitlist =
      p.registrationStatus == TournamentParticipantStatus.waitlist;
  final pid = TournamentParticipantId(p.participantId);
  final actions = ref.read(tournamentActionsProvider);
  // Check-in is for confirmed pool members only (check-in ≠ confirm).
  final showCheckin =
      !isWaitlist && canManage && checkinWindowOpen && tournamentId != null;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
    child: Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg)),
            // D4-3: check-in timestamp label on an already-checked-in row.
            if (showCheckin && p.isCheckedIn && p.checkedInAt != null)
              Text(
                l.tournamentDetailCheckedInAt(
                    _formatCheckedInAt(p.checkedInAt!)),
                style: TextStyle(fontSize: 11, color: tokens.fgMuted),
              ),
          ],
        ),
      ),
      if (showCheckin)
        ParticipantCheckinToggle(
          isCheckedIn: p.isCheckedIn,
          onCheckin: () => _safe(
              context,
              () => ref
                  .read(tournamentActionsProvider)
                  .checkin(pid, tournamentId: tournamentId)),
          onUndoCheckin: () => _safe(
              context,
              () => ref
                  .read(tournamentActionsProvider)
                  .undoCheckin(pid, tournamentId: tournamentId)),
        )
      else
        Padding(
          padding: const EdgeInsets.only(right: KubbTokens.space2),
          child: Text(
              isWaitlist
                  ? l.tournamentDetailStatusWaitlist
                  : l.tournamentDetailStatusConfirmed,
              style: TextStyle(fontSize: 11, color: tokens.fgMuted)),
        ),
      if (isOrganizer)
        TextButton(
            onPressed: () =>
                _safe(context, () => actions.rejectRegistration(pid)),
            child: Text(l.tournamentDetailActionRemove)),
    ]),
  );
}

/// Formats a check-in timestamp for the inline row label (D4-3). The stored
/// [checkedInAt] is already an absolute server instant (timestamptz projected
/// by `tournament_get`), so it needs no Phase-A skew correction — the offset
/// only matters for live countdowns against the local wall clock, not for
/// rendering a fixed past instant. It is simply shown in the device's local
/// time, which also degrades gracefully when Phase A is absent.
String _formatCheckedInAt(DateTime checkedInAt) {
  final dt = checkedInAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// Reusable on-site check-in toggle for a confirmed participant row (ADR-0031
/// Phase D, Block D4 / OE-D5). Deliberately decoupled from the detail-screen
/// internals so the upcoming B-dashboard shell can embed it 1:1: it takes only
/// the derived [isCheckedIn] state (from the D3 domain `checkedInAt`, never
/// client-tracked) and the two callbacks. Two states:
///   • not checked in → tappable "Einchecken" action.
///   • checked in     → green "Anwesend" state; tapping reverts the check-in.
/// The server owns gate/status/idempotency; this widget never re-implements
/// those checks. Touch target ≥ 48 dp; colours come from KubbTokens only.
class ParticipantCheckinToggle extends StatelessWidget {
  const ParticipantCheckinToggle({
    required this.isCheckedIn,
    required this.onCheckin,
    required this.onUndoCheckin,
    super.key,
  });

  final bool isCheckedIn;
  final VoidCallback onCheckin;
  final VoidCallback onUndoCheckin;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    if (isCheckedIn) {
      // Checked-in state: green "Anwesend"; tap reverts. KubbTokens.hit is the
      // design-system green (= meadow600), not a raw Color literal.
      return InkWell(
        onTap: onUndoCheckin,
        borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: KubbTokens.space2, vertical: KubbTokens.space2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 18, color: KubbTokens.hit),
                const SizedBox(width: KubbTokens.space1),
                Text(
                  l.tournamentDetailCheckedInState,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KubbTokens.hit),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Not checked in: "Einchecken" action.
    return InkWell(
      onTap: onCheckin,
      borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space2, vertical: KubbTokens.space2),
          child: Center(
            widthFactor: 1,
            child: Text(
              l.tournamentDetailCheckinAction,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.primary),
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions(
      {required this.detail,
      required this.isCreator,
      required this.canManage,
      required this.me,
      required this.id});
  final TournamentDetail detail;
  final bool isCreator;

  /// Creator OR a role holder (profile organizer / club admin). Gates the
  /// lifecycle + edit actions and the lifecycle hint; participant moderation
  /// stays creator-only via [isCreator].
  final bool canManage;
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
            DoubleEliminationBracket(:final wbRounds) => wbRounds.isNotEmpty,
            // ADR-0028: a consolation tree (Model B) counts as a bracket once
            // either its main tree or any consolation round is materialised.
            ConsolationBracket(:final mainRounds, :final rounds) =>
              mainRounds.isNotEmpty || rounds.isNotEmpty,
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

    // V2-B2 edit-after-publish (incl. live): the organizer (creator/admin)
    // may edit the details across the pre-start statuses AND while the
    // tournament is `live`. The server (migration 20261243000000) re-checks
    // the manage gate and applies the field-safety classes / safe recompute;
    // a structural change against an already-played phase is rejected with
    // HINT STRUCTURE_LOCKED. Only `finalized` and `aborted` are frozen — for
    // those two the edit entry-point is not rendered at all.
    final canEdit = canManage &&
        (status == TournamentStatus.draft ||
            status == TournamentStatus.published ||
            status == TournamentStatus.registrationOpen ||
            status == TournamentStatus.registrationClosed ||
            status == TournamentStatus.live);
    if (canEdit) {
      nav(l.tournamentDetailActionEdit, TournamentRoutes.edit(id.value));
    }

    // New open-registration model: publishing goes straight to
    // `registration_open` (no separate "Anmeldung öffnen" step). The
    // organizer can start directly from `registration_open` (the start
    // implicitly closes registration); an explicit "Anmeldung schliessen"
    // remains available but optional. `published` is no longer reachable
    // from publish, but is handled defensively for any legacy row.
    if (status == TournamentStatus.draft && canManage) {
      op(l.tournamentDetailActionPublish, () => actions.publish(id));
    } else if (status == TournamentStatus.registrationOpen ||
        status == TournamentStatus.published) {
      // Organizer lifecycle controls.
      if (canManage) {
        op(l.tournamentDetailActionStart, () => actions.startTournament(id));
        op(l.tournamentDetailActionCloseReg,
            () => actions.closeRegistration(id));
      }
      // Personal registration — available to EVERYONE while registration is
      // open, INCLUDING the organizer/creator (they may play in their own
      // tournament). Shown alongside the manage controls above, so an admin
      // is no longer stuck with only Start/Close and can register + withdraw.
      final m = me;
      if (m == null ||
          m.registrationStatus == TournamentParticipantStatus.withdrawn ||
          m.registrationStatus == TournamentParticipantStatus.rejected) {
        nav(l.tournamentDetailActionRegister, '$pathBase/register');
      } else {
        // Confirmed or waitlisted: show the standing, then offer withdraw.
        buttons.add(_RegistrationStatusBadge(status: m.registrationStatus));
        op(
            l.tournamentDetailActionWithdraw,
            () => actions.withdrawRegistration(
                TournamentParticipantId(m.participantId),
                tournamentId: id),
            color: KubbTokens.miss);
      }
    } else if (status == TournamentStatus.registrationClosed && canManage) {
      op(l.tournamentDetailActionStart, () => actions.startTournament(id));
    } else if (status == TournamentStatus.live) {
      if (canManage) {
        // CF6 (K19): manual-seeding is a mandatory step on the Vorrunde->KO
        // transition. When seeding_mode == manual and the KO bracket has not
        // been built yet, the organizer must commit a seed list FIRST — the
        // CTA routes to the seeding screen instead of starting the KO blind.
        // Auto seeding keeps the existing flow (no extra step). The server
        // re-enforces the gate (seeding_required) regardless.
        if (!hasBracket && _seedingMode(detail) == SeedingMode.manual) {
          nav(l.tournamentDetailActionSetSeeding,
              TournamentRoutes.seeding(id.value));
        }
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
    if (canManage &&
        status != TournamentStatus.finalized &&
        status != TournamentStatus.aborted) {
      op(l.tournamentDetailActionAbort, () => actions.abortTournament(id),
          color: KubbTokens.miss);
    }
    // Lifecycle hint: only a manager (creator or organizer/club admin) sees
    // it, and only while the tournament is pre-start. It spells out the
    // publish→open→close→start sequence so the registration flow stops being
    // invisible (USER SPEC).
    final hint = canManage ? _lifecycleHint(status, l) : null;

    if (buttons.isEmpty && hint == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hint != null) ...[
          _LifecycleHint(text: hint),
          const SizedBox(height: KubbTokens.space3),
        ],
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: KubbTokens.space2),
          buttons[i],
        ],
      ],
    );
  }

  /// Organizer-facing copy for the current lifecycle stage; null when the
  /// stage carries no guidance (live / finalized / aborted).
  String? _lifecycleHint(TournamentStatus status, AppLocalizations l) {
    return switch (status) {
      TournamentStatus.draft => l.tournamentDetailHintDraft,
      TournamentStatus.published => l.tournamentDetailHintPublished,
      TournamentStatus.registrationOpen =>
        l.tournamentDetailHintRegistrationOpen,
      TournamentStatus.registrationClosed =>
        l.tournamentDetailHintRegistrationClosed,
      TournamentStatus.live ||
      TournamentStatus.finalized ||
      TournamentStatus.aborted =>
        null,
    };
  }
}

/// Small info banner that guides the organizer through the lifecycle
/// (publish → open registration → close → start). Uses the raised-surface
/// chrome so it reads as helper copy, not an error.
class _LifecycleHint extends StatelessWidget {
  const _LifecycleHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: tokens.fgMuted),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: tokens.fgMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standing badge shown to a registered caller while registration is open:
/// "Angemeldet" for a confirmed (auto-confirmed) registration, "Auf
/// Warteliste" once capacity is reached. Replaces the old
/// "Bestätigung ausstehend" framing — registrations are no longer pending.
class _RegistrationStatusBadge extends StatelessWidget {
  const _RegistrationStatusBadge({required this.status});

  final TournamentParticipantStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final isWaitlist = status == TournamentParticipantStatus.waitlist;
    final label = isWaitlist
        ? l.tournamentDetailStatusWaitlist
        : l.tournamentDetailStatusConfirmed;
    final icon = isWaitlist ? Icons.hourglass_empty : Icons.check_circle;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tokens.fgMuted),
          const SizedBox(width: KubbTokens.space2),
          Text(
            label,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg),
          ),
        ],
      ),
    );
  }
}

/// T17 — caller-side roster section. Renders the open slots returned by
/// `tournament_roster_list` for the caller's own team participant. The
/// section is wrapped in the same card chrome as Stammdaten /
/// participants so the screen remains a single scroll surface (the
/// "tab" framing in the spec maps to a section because the rest of
/// the screen is also a flat ListView, not a TabController).
class _RosterCard extends ConsumerWidget {
  const _RosterCard({required this.participantId});
  final TournamentParticipantId participantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final rosterAsync = ref.watch(tournamentRosterProvider(participantId));
    return _card(context, l.tournamentDetailRoster, [
      rosterAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: KubbTokens.space2),
          child: SizedBox(
              height: 18, width: 18, child: CircularProgressIndicator()),
        ),
        error: (_, _) => Text(l.tournamentDetailRosterEmpty,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
        data: (slots) {
          if (slots.isEmpty) {
            return Text(l.tournamentDetailRosterEmpty,
                style: TextStyle(fontSize: 13, color: tokens.fgMuted));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in slots) _rosterRow(context, l, tokens, s),
            ],
          );
        },
      ),
    ]);
  }
}

/// T12 (M3.3) — inline pool-standings section. Renders one sub-block
/// per `group_label` returned by `tournament_pool_standings`. The
/// surrounding `_Body` guards visibility on
/// `matchFormatConfig['pool_phase']`; once a tournament with the flag
/// is mounted, [tournamentPoolStandingsPollingProvider] keeps the
/// snapshot fresh at the same 5s cadence as the bracket polling.
///
/// Stats are server-sorted by the tournament's tiebreaker chain
/// (ADR-0019 §3.5), so the widget renders them in arrival order
/// without re-sorting.
class _PoolStandingsCard extends ConsumerWidget {
  const _PoolStandingsCard({required this.id});
  final TournamentId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    ref.watch(tournamentPoolStandingsPollingProvider(id));
    final async = ref.watch(tournamentPoolStandingsProvider(id));
    return _card(context, l.tournamentDetailPools, [
      async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: KubbTokens.space2),
          child: SizedBox(
              height: 18, width: 18, child: CircularProgressIndicator()),
        ),
        // Error path collapses to the empty-state copy: the pool RPC
        // throws ahead of phase-start, which is indistinguishable from
        // "no data yet" for the caller.
        error: (_, _) => Text(l.tournamentDetailPoolsEmpty,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
        data: (groups) {
          if (groups.isEmpty) {
            return Text(l.tournamentDetailPoolsEmpty,
                style: TextStyle(fontSize: 13, color: tokens.fgMuted));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(height: KubbTokens.space3),
                _poolGroup(context, l, tokens, groups[i]),
              ],
            ],
          );
        },
      ),
    ]);
  }
}

Widget _poolGroup(BuildContext context, AppLocalizations l, KubbTokens tokens,
    PoolGroupStandings g) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(l.tournamentDetailPoolGroup(g.groupLabel),
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: tokens.fg)),
      const SizedBox(height: KubbTokens.space1),
      for (var i = 0; i < g.stats.length; i++)
        _poolRow(context, tokens, i + 1, g.stats[i]),
    ],
  );
}

Widget _poolRow(BuildContext context, KubbTokens tokens, int rank,
    ParticipantStats s) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
    child: Row(children: [
      SizedBox(
        width: 28,
        child: Text('$rank.',
            style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
      ),
      Expanded(
        child: Text(s.participantId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg)),
      ),
      Text('${s.totalPoints}',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg)),
    ]),
  );
}

Widget _rosterRow(BuildContext context, AppLocalizations l, KubbTokens tokens,
    RosterSlot s) {
  final label = s.memberUserId?.value ?? s.guestPlayerId?.value ?? '?';
  final marker = s.memberUserId != null ? '' : ' · ${l.tournamentDetailRosterGuest}';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
    child: Row(children: [
      SizedBox(
        width: 64,
        child: Text(l.tournamentDetailRosterSlot(s.slotIndex),
            style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
      ),
      Expanded(
        child: Text('$label$marker',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: tokens.fg)),
      ),
    ]),
  );
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
