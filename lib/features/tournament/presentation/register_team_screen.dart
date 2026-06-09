import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/roster_composition_widget.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wave-7 team-registration screen (TASK-M3.2-T14). Composes the team
/// picker (`teamListProvider`, M3.1) with the `RosterCompositionWidget`
/// (T13) and submits the roster via `TournamentRemote.registerTeam`
/// (T9). On server validation failures (`BR_5_VIOLATION` /
/// `MIN_ONE_REGISTERED`) the screen surfaces a German snackbar and
/// highlights the offending slot. AppLocalizations migration lands in
/// T18 — strings stay inline German for now.
class RegisterTeamScreen extends ConsumerStatefulWidget {
  const RegisterTeamScreen({required this.tournamentId, super.key});

  final TournamentId tournamentId;

  @override
  ConsumerState<RegisterTeamScreen> createState() => _State();
}

class _State extends ConsumerState<RegisterTeamScreen> {
  TeamWire? _selectedTeam;
  List<RosterSlotInput> _roster = const <RosterSlotInput>[];
  int? _highlightSlot;
  bool _busy = false;

  /// Once the server accepts the registration we flip into a confirmation
  /// view that reflects the now-"angemeldet" roster (P6 stage-3). The push
  /// notification to the members themselves is server-side.
  List<String>? _registeredLabels;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final detailAsync = ref.watch(tournamentDetailProvider(widget.tournamentId));
    final teamsAsync = ref.watch(teamListProvider);
    return Scaffold(
      backgroundColor: t.bg,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: const KubbAppBar(eyebrow: 'Turnier', title: 'Team registrieren'),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _error('$e'),
        data: (detail) => detail == null
            ? _error('Turnier nicht gefunden.')
            : _registeredLabels != null
                ? _confirmation(t, l, detail)
                : teamsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _error('$e'),
                    data: (teams) => _form(t, l, detail, teams),
                  ),
      ),
    );
  }

  Widget _form(KubbTokens t, AppLocalizations l, TournamentDetail detail,
      List<TeamWire> teams) {
    final minSize = detail.tournament.teamSize;
    final maxSize = detail.tournament.maxTeamSize;
    final count = _roster.length;
    final withinRange = count >= minSize && count <= maxSize;
    return Padding(
      padding: const EdgeInsets.all(KubbTokens.space4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(detail.tournament.displayName,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: t.fg)),
        const SizedBox(height: KubbTokens.space2),
        // P6 stage-2: surface the allowed roster range up-front so the
        // user knows the target before composing the roster.
        Text(
          minSize == maxSize
              ? l.tournamentTeamRosterRangeFixed(minSize)
              : l.tournamentTeamRosterRange(minSize, maxSize),
          style: TextStyle(fontSize: 13, color: t.fgMuted),
        ),
        const SizedBox(height: KubbTokens.space4),
        DropdownButtonFormField<TeamWire>(
          initialValue: _selectedTeam,
          decoration: const InputDecoration(labelText: 'Team'),
          items: [
            for (final team in teams)
              DropdownMenuItem(value: team, child: Text(team.displayName)),
          ],
          onChanged: _busy ? null : _onTeamChanged,
        ),
        const SizedBox(height: KubbTokens.space4),
        if (_selectedTeam != null)
          Expanded(child: _rosterSection(_selectedTeam!, maxSize))
        else
          const Spacer(),
        if (_selectedTeam != null) ...[
          const SizedBox(height: KubbTokens.space2),
          Text(
            l.tournamentTeamRosterSelected(count),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: withinRange ? t.fgMuted : t.danger,
            ),
          ),
        ],
        const SizedBox(height: KubbTokens.space2),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: FilledButton(
            onPressed:
                (!_busy && _selectedTeam != null && withinRange) ? _submit : null,
            child: Text(_busy ? 'Wird gesendet…' : 'Team registrieren'),
          ),
        ),
      ]),
    );
  }

  /// P6 stage-3 confirmation: after the server accepts the roster the
  /// selected members are reflected as "angemeldet". The actual
  /// inbox/push notification to those members is server-side (next stage);
  /// here the client just states the registered roster.
  Widget _confirmation(
      KubbTokens t, AppLocalizations l, TournamentDetail detail) {
    final labels = _registeredLabels ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.all(KubbTokens.space4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(detail.tournament.displayName,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: t.fg)),
        const SizedBox(height: KubbTokens.space4),
        Container(
          padding: const EdgeInsets.all(KubbTokens.space4),
          decoration: BoxDecoration(
            color: KubbTokens.hit.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            border: Border.all(color: KubbTokens.hit),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.check_circle, color: KubbTokens.hit, size: 20),
              const SizedBox(width: KubbTokens.space2),
              Expanded(
                child: Text(l.tournamentTeamRegistered,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: t.fg)),
              ),
            ]),
            const SizedBox(height: KubbTokens.space3),
            Text(l.tournamentTeamRegisteredMembers,
                style: TextStyle(fontSize: 13, color: t.fgMuted)),
            const SizedBox(height: KubbTokens.space2),
            for (final name in labels)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
                child: Row(children: [
                  Icon(Icons.person, size: 16, color: t.fgMuted),
                  const SizedBox(width: KubbTokens.space2),
                  Expanded(
                    child: Text(name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.fg)),
                  ),
                  Text(l.tournamentTeamMemberRegistered,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: KubbTokens.hit)),
                ]),
              ),
          ]),
        ),
        const Spacer(),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: FilledButton(
            onPressed: () => context.pop(),
            child: Text(l.tournamentTeamRegisterDone),
          ),
        ),
      ]),
    );
  }

  Widget _rosterSection(TeamWire team, int availableSlots) {
    final detailAsync = ref.watch(teamDetailProvider(TeamId(team.id)));
    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _error('$e'),
      data: (data) {
        final pool = _poolFrom(data);
        final guests = _guestsFrom(data);
        // The roster widget grows with `availableSlots` (up to
        // max_team_size = 6) and the pool size, so keep it scrollable
        // inside the fixed-height `Expanded` slot to avoid overflow.
        return SingleChildScrollView(
          child: RosterCompositionWidget(
            key: ValueKey<String>('roster-${team.id}'),
            pool: pool,
            guests: guests,
            availableSlots: availableSlots,
            onChanged: (slots) => setState(() {
              _roster = slots;
              _highlightSlot = null;
            }),
          ),
        );
      },
    );
  }

  /// Maps the `pool` array of the `team_get` jsonb envelope onto the
  /// widget's [RosterPoolMember] shape. The RPC payload carries `user_id`
  /// + `membership_id` per row; `display_name` is not yet projected
  /// there, so we fall back to the user-id token (parity with
  /// `team_detail_screen.dart`). Conflict detection happens server-side
  /// at `registerTeam` time — surface `conflicted: false` until the
  /// dedicated `team_pool_with_tournament_conflicts` RPC is wired.
  List<RosterPoolMember> _poolFrom(Map<String, dynamic> data) {
    final raw = (data['pool'] as List? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    return [
      for (final m in raw)
        RosterPoolMember(
          userId: UserId(m['user_id'] as String),
          displayName:
              (m['display_name'] as String?) ?? (m['user_id'] as String),
          conflicted: false,
        ),
    ];
  }

  List<RosterPoolGuest> _guestsFrom(Map<String, dynamic> data) {
    final raw = (data['guests'] as List? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    return [
      for (final g in raw)
        RosterPoolGuest(
          guestId: TeamGuestPlayerId(g['guest_id'] as String),
          displayName: (g['display_name'] as String?) ?? '?',
        ),
    ];
  }

  /// Resolves the picked roster slots to display names using the already
  /// loaded team-detail payload (pool + guests). Falls back to the raw
  /// id token when a name is not projected.
  List<String> _rosterLabels(TeamWire team) {
    final data = ref.read(teamDetailProvider(TeamId(team.id))).maybeWhen(
          data: (d) => d,
          orElse: () => const <String, dynamic>{},
        );
    final pool = {for (final m in _poolFrom(data)) m.userId: m.displayName};
    final guests = {
      for (final g in _guestsFrom(data)) g.guestId: g.displayName,
    };
    final sorted = [..._roster]
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    return [
      for (final s in sorted)
        if (s.memberUserId != null)
          pool[s.memberUserId] ?? s.memberUserId!.value
        else if (s.guestPlayerId != null)
          guests[s.guestPlayerId] ?? s.guestPlayerId!.value
        else
          '?',
    ];
  }

  void _onTeamChanged(TeamWire? team) => setState(() {
        _selectedTeam = team;
        _roster = const <RosterSlotInput>[];
        _highlightSlot = null;
      });

  Widget _error(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss)),
        ),
      );

  Future<void> _submit() async {
    final team = _selectedTeam;
    if (team == null) return;
    setState(() {
      _busy = true;
      _highlightSlot = null;
    });
    // Resolve human-readable labels for the picked roster *before* the
    // await so the confirmation can reflect exactly who got registered,
    // even if the team detail provider is later invalidated.
    final labels = _rosterLabels(team);
    try {
      await ref.read(tournamentRemoteProvider).registerTeam(
            tournamentId: widget.tournamentId,
            teamId: TeamId(team.id),
            roster: _roster,
          );
      if (!mounted) return;
      // BUG3/Task3: this screen calls `registerTeam` directly on the remote
      // (not via TournamentActions), so unlike the single-registration path it
      // never refreshed the detail. Invalidate the tournament detail so its
      // participant list shows the new team immediately, instead of waiting for
      // the gated 30 s realtime fallback poll.
      ref
        ..invalidate(tournamentDetailProvider(widget.tournamentId))
        ..invalidate(myTournamentRegistrationsProvider);
      // P6 stage-3: flip into the confirmation view that reflects the
      // now-"angemeldet" roster instead of popping straight away.
      setState(() {
        _busy = false;
        _registeredLabels = labels;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // BR-5 violations come without a slot index from the server —
        // focus slot 1 as a default cue; T13 highlights it in `miss`.
        if (e.hint == 'BR_5_VIOLATION') _highlightSlot = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_messageFor(e.hint, e.message)),
          backgroundColor: KubbTokens.miss));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: KubbTokens.miss));
    }
  }

  String _messageFor(String? hint, String fallback) => switch (hint) {
        'BR_5_VIOLATION' =>
          'Ein Spieler ist bereits in einem anderen Team-Roster desselben Turniers eingetragen.',
        'MIN_ONE_REGISTERED' =>
          'Mindestens ein registriertes Mitglied muss im Roster stehen.',
        _ => fallback,
      };
}
