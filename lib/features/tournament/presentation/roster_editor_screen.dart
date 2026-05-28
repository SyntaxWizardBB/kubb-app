import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Mid-tournament roster editor (TASK-M3.2-T15). Shows the active roster
/// slots for a registered team-participant, lets organisers/captains
/// substitute one slot via the pool dialog, and surfaces past
/// replacements as a compact audit ExpansionTile.
///
/// Locked-handling: while a match of the team is in progress the
/// `tournament_roster_replace` RPC raises `ROSTER_LOCKED_DURING_MATCH`
/// (OD-M3-07). The screen maps that token to a German-labelled
/// AlertDialog instead of a generic snackbar. Once the tournament is
/// `finalized` every Replace button is greyed out — the audit view stays
/// readable.
class RosterEditorScreen extends ConsumerStatefulWidget {
  const RosterEditorScreen({
    required this.tournamentId,
    required this.participantId,
    required this.teamId,
    super.key,
  });

  final TournamentId tournamentId;
  final TournamentParticipantId participantId;
  final TeamId teamId;

  @override
  ConsumerState<RosterEditorScreen> createState() =>
      _RosterEditorScreenState();
}

/// Per-participant roster fetch. Family-keyed so the editor can refetch
/// after a successful replace without invalidating sibling rosters.
// ignore: specify_nonobvious_property_types
final rosterProvider =
    FutureProvider.family<List<RosterSlot>, TournamentParticipantId>(
  (ref, pid) async => ref.read(tournamentRemoteProvider).getRoster(pid),
);

class _RosterEditorScreenState extends ConsumerState<RosterEditorScreen> {
  bool _submitting = false;

  Future<void> _onReplace(RosterSlot slot) async {
    if (_submitting) return;
    final teamAsync = ref.read(teamDetailProvider(widget.teamId));
    final teamData = teamAsync.asData?.value;
    if (teamData == null) return;
    final result = await showDialog<_ReplacePick>(
      context: context,
      builder: (ctx) => _ReplaceDialog(slot: slot, teamData: teamData),
    );
    if (result == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await ref.read(tournamentRemoteProvider).replaceRosterSlot(
            participantId: widget.participantId,
            slotIndex: slot.slotIndex,
            newOccupant: result.input,
            reason: result.reason.isEmpty ? null : result.reason,
          );
      ref.invalidate(rosterProvider(widget.participantId));
    } on Object catch (e) {
      if (!mounted) return;
      if (e.toString().contains('ROSTER_LOCKED_DURING_MATCH')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Roster gesperrt'),
            content: const Text(
                'Substitution nur zwischen Matches möglich. Bitte warte, bis das laufende Match beendet ist.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK')),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'), backgroundColor: KubbTokens.miss));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final detailAsync =
        ref.watch(tournamentDetailProvider(widget.tournamentId));
    final rosterAsync = ref.watch(rosterProvider(widget.participantId));
    final finalized = detailAsync.asData?.value?.tournament.status ==
        TournamentStatus.finalized;
    // Read viewInsets from the build context (above the Scaffold) so the
    // value survives `MediaQuery.removeViewInsets` applied internally by
    // `resizeToAvoidBottomInset: true` further down the tree.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: tokens.bg,
      // Mängel #2.4 / BH-C-03: resizeToAvoidBottomInset hält die "Ersetzen"
      // Aktion und den Audit-Trail über der Soft-Tastatur, sobald der
      // Substitutionsdialog das Grund-Feld fokussiert.
      resizeToAvoidBottomInset: true,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: const KubbAppBar(eyebrow: 'Team', title: 'Roster bearbeiten'),
      body: rosterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Padding(
                padding: const EdgeInsets.all(KubbTokens.space5),
                child: Text('Fehler: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: KubbTokens.miss)))),
        data: (slots) => _Body(
          slots: slots,
          finalized: finalized,
          submitting: _submitting,
          onReplace: _onReplace,
          bottomInset: bottomInset,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.slots,
    required this.finalized,
    required this.submitting,
    required this.onReplace,
    required this.bottomInset,
  });
  final List<RosterSlot> slots;
  final bool finalized;
  final bool submitting;
  final Future<void> Function(RosterSlot slot) onReplace;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final history = slots.where((s) => s.replacedAt != null).toList()
      ..sort((a, b) => b.replacedAt!.compareTo(a.replacedAt!));
    return ListView(
      padding: EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space4,
        bottomInset + KubbTokens.space4,
      ),
      children: [
        Text('AKTIVE SLOTS',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.88,
                color: tokens.fgMuted)),
        const SizedBox(height: KubbTokens.space2),
        for (final slot in slots)
          Padding(
            padding: const EdgeInsets.only(bottom: KubbTokens.space2),
            child: _SlotRow(
              slot: slot,
              disabled: finalized || submitting,
              onTap: () => onReplace(slot),
            ),
          ),
        if (finalized)
          Padding(
            padding: const EdgeInsets.only(top: KubbTokens.space3),
            child: Text(
              'Turnier abgeschlossen — keine Änderungen mehr möglich.',
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
          ),
        const SizedBox(height: KubbTokens.space4),
        ExpansionTile(
          title: Text('Audit-Trail (${history.length})',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.fg)),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          children: [
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: KubbTokens.space2),
                child: Text('Keine Replacements bisher.',
                    style:
                        TextStyle(fontSize: 12, color: tokens.fgMuted)),
              )
            else
              for (final h in history)
                _AuditRow(slot: h),
          ],
        ),
      ],
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow(
      {required this.slot, required this.disabled, required this.onTap});
  final RosterSlot slot;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final label = slot.memberUserId?.value ??
        slot.guestPlayerId?.value ??
        'leer';
    final kind = slot.guestPlayerId != null ? 'Gast' : 'Mitglied';
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text('#${slot.slotIndex}',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: tokens.fgMuted)),
        ),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg)),
                Text(kind,
                    style: TextStyle(
                        fontSize: 11, color: tokens.fgMuted)),
              ]),
        ),
        TextButton(
          onPressed: disabled ? null : onTap,
          child: const Text('Ersetzen'),
        ),
      ]),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.slot});
  final RosterSlot slot;
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final when = slot.replacedAt!.toLocal().toIso8601String().substring(0, 16);
    final reason = slot.reason ?? '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Slot #${slot.slotIndex} · $when',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.fg)),
        Text('Grund: $reason',
            style: TextStyle(fontSize: 12, color: tokens.fgMuted)),
      ]),
    );
  }
}

class _ReplacePick {
  const _ReplacePick(this.input, this.reason);
  final RosterSlotInput input;
  final String reason;
}

class _ReplaceDialog extends StatefulWidget {
  const _ReplaceDialog({required this.slot, required this.teamData});
  final RosterSlot slot;
  final Map<String, dynamic> teamData;
  @override
  State<_ReplaceDialog> createState() => _ReplaceDialogState();
}

class _ReplaceDialogState extends State<_ReplaceDialog> {
  /// Encoded as `m:<userId>` or `g:<guestId>` so members and guests can
  /// share one [RadioGroup] without breaking mutual exclusivity.
  String? _pick;
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  RosterSlotInput? _buildInput() {
    final pick = _pick;
    if (pick == null) return null;
    if (pick.startsWith('m:')) {
      return RosterSlotInput.member(
          widget.slot.slotIndex, UserId(pick.substring(2)));
    }
    if (pick.startsWith('g:')) {
      return RosterSlotInput.guest(
          widget.slot.slotIndex, TeamGuestPlayerId(pick.substring(2)));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pool = (widget.teamData['pool'] as List? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final guests = (widget.teamData['guests'] as List? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final input = _buildInput();
    return AlertDialog(
      title: Text('Slot #${widget.slot.slotIndex} ersetzen'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: RadioGroup<String>(
            groupValue: _pick,
            onChanged: (v) => setState(() => _pick = v),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Mitglieder',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final m in pool)
                    RadioListTile<String>(
                      value: 'm:${m['user_id']}',
                      title: Text((m['user_id'] as String?) ?? '?',
                          overflow: TextOverflow.ellipsis),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  if (guests.isNotEmpty) ...[
                    const SizedBox(height: KubbTokens.space2),
                    const Text('Gäste',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final g in guests)
                      RadioListTile<String>(
                        value: 'g:${g['guest_id']}',
                        title: Text((g['display_name'] as String?) ?? '?',
                            overflow: TextOverflow.ellipsis),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                  const SizedBox(height: KubbTokens.space2),
                  TextField(
                    controller: _reason,
                    decoration: const InputDecoration(
                        labelText: 'Grund (optional)'),
                    maxLength: 200,
                  ),
                ]),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
          onPressed: input == null
              ? null
              : () => Navigator.of(context)
                  .pop(_ReplacePick(input, _reason.text.trim())),
          child: const Text('Ersetzen'),
        ),
      ],
    );
  }
}
