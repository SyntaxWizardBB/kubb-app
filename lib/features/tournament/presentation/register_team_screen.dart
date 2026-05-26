import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/roster_composition_widget.dart';
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<KubbTokens>()!;
    final detailAsync = ref.watch(tournamentDetailProvider(widget.tournamentId));
    final teamsAsync = ref.watch(teamListProvider);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: const KubbAppBar(eyebrow: 'Turnier', title: 'Team registrieren'),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _error('$e'),
        data: (detail) => detail == null
            ? _error('Turnier nicht gefunden.')
            : teamsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _error('$e'),
                data: (teams) => _form(t, detail, teams),
              ),
      ),
    );
  }

  Widget _form(KubbTokens t, TournamentDetail detail, List<TeamWire> teams) {
    final teamSize = detail.tournament.teamSize;
    return Padding(
      padding: const EdgeInsets.all(KubbTokens.space4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(detail.tournament.displayName,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: t.fg)),
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
          Expanded(
            child: RosterCompositionWidget(
              teamId: TeamId(_selectedTeam!.id),
              tournamentId: widget.tournamentId,
              availableSlots: teamSize,
              highlightedSlotIndex: _highlightSlot,
              onChanged: (slots) => setState(() {
                _roster = slots;
                _highlightSlot = null;
              }),
            ),
          )
        else
          const Spacer(),
        const SizedBox(height: KubbTokens.space2),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: FilledButton(
            onPressed: (!_busy && _selectedTeam != null && _roster.length == teamSize)
                ? _submit
                : null,
            child: Text(_busy ? 'Wird gesendet…' : 'Team registrieren'),
          ),
        ),
      ]),
    );
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
    try {
      await ref.read(tournamentRemoteProvider).registerTeam(
            tournamentId: widget.tournamentId,
            teamId: TeamId(team.id),
            roster: _roster,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Team registriert.')));
      context.pop();
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
