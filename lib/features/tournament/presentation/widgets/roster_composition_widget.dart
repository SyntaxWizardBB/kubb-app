import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/team/presentation/widgets/team_member_card.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Pool-Member-Eintrag wie von `team_pool_with_tournament_conflicts` (T12)
/// zurückgegeben.
@immutable
class RosterPoolMember {
  const RosterPoolMember({
    required this.userId,
    required this.displayName,
    required this.conflicted,
  });

  final UserId userId;
  final String displayName;
  final bool conflicted;
}

/// Gast-Pool-Eintrag — Gäste haben kein User-Konto, daher keinen Conflict-Check.
@immutable
class RosterPoolGuest {
  const RosterPoolGuest({required this.guestId, required this.displayName});

  final TeamGuestPlayerId guestId;
  final String displayName;
}

/// Tap-Select-Roster-Composition (TASK-M3.2-T13).
///
/// Pool links, [availableSlots] Slots rechts. Tap auf Pool-Eintrag öffnet
/// Slot-Picker; Tap auf Slot öffnet Pool-Picker. Conflicted Pool-Entries
/// sind disabled. Parent erhält `onChanged` mit dem aktuellen
/// `List<RosterSlotInput>` (FR-REG-12: min. 1 Member-Slot, sonst Warnung).
class RosterCompositionWidget extends StatefulWidget {
  const RosterCompositionWidget({
    required this.pool,
    required this.guests,
    required this.availableSlots,
    required this.onChanged,
    super.key,
  });

  final List<RosterPoolMember> pool;
  final List<RosterPoolGuest> guests;
  final int availableSlots;
  final ValueChanged<List<RosterSlotInput>> onChanged;

  @override
  State<RosterCompositionWidget> createState() =>
      _RosterCompositionWidgetState();
}

class _RosterCompositionWidgetState extends State<RosterCompositionWidget> {
  /// slotIndex (1..N) → Assignment, oder fehlend für leere Slots.
  final Map<int, RosterSlotInput> _assignments = <int, RosterSlotInput>{};

  void _emit() {
    final list = _assignments.values.toList()
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    widget.onChanged(list);
  }

  bool _isAssigned(RosterPoolMember m) => _assignments.values
      .any((s) => s.memberUserId != null && s.memberUserId == m.userId);

  bool _isGuestAssigned(RosterPoolGuest g) => _assignments.values
      .any((s) => s.guestPlayerId != null && s.guestPlayerId == g.guestId);

  void _assign(int slotIndex, RosterSlotInput input) {
    setState(() {
      // Falls Pool-Entry bereits in einem anderen Slot ist: dort entfernen.
      _assignments.removeWhere((_, v) =>
          (v.memberUserId != null && v.memberUserId == input.memberUserId) ||
          (v.guestPlayerId != null && v.guestPlayerId == input.guestPlayerId));
      _assignments[slotIndex] = input;
    });
    _emit();
  }

  void _clearSlot(int slotIndex) {
    setState(() => _assignments.remove(slotIndex));
    _emit();
  }

  Future<void> _pickSlotForPool(RosterSlotInput Function(int) build) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Slot wählen'),
        children: [
          for (var i = 1; i <= widget.availableSlots; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: Text(
                _assignments.containsKey(i) ? 'Slot $i (ersetzen)' : 'Slot $i',
              ),
            ),
        ],
      ),
    );
    if (picked != null) _assign(picked, build(picked));
  }

  Future<void> _pickPoolForSlot(int slotIndex) async {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final picked = await showDialog<RosterSlotInput>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Pool-Eintrag für Slot $slotIndex'),
        children: [
          for (final m in widget.pool)
            SimpleDialogOption(
              onPressed: m.conflicted
                  ? null
                  : () => Navigator.pop(
                      ctx, RosterSlotInput.member(slotIndex, m.userId)),
              child: Text(
                '${m.displayName} (Mitglied)',
                style: TextStyle(
                    color: m.conflicted ? tokens.fgSubtle : tokens.fg),
              ),
            ),
          for (final g in widget.guests)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                  ctx, RosterSlotInput.guest(slotIndex, g.guestId)),
              child: Text('${g.displayName} (Gast)'),
            ),
        ],
      ),
    );
    if (picked != null) _assign(slotIndex, picked);
  }

  Widget _slotTile(int slotIndex) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final assigned = _assignments[slotIndex];
    final label = assigned == null
        ? 'Leer'
        : assigned.memberUserId != null
            ? widget.pool
                .firstWhere((m) => m.userId == assigned.memberUserId,
                    orElse: () => RosterPoolMember(
                          userId: assigned.memberUserId!,
                          displayName: '?',
                          conflicted: false,
                        ))
                .displayName
            : widget.guests
                .firstWhere((g) => g.guestId == assigned.guestPlayerId,
                    orElse: () => RosterPoolGuest(
                          guestId: assigned.guestPlayerId!,
                          displayName: '?',
                        ))
                .displayName;
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: InkWell(
        onTap: () => _pickPoolForSlot(slotIndex),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
            color: assigned == null ? tokens.bgSunken : tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            border: Border.all(color: tokens.line),
          ),
          child: Row(children: [
            CircleAvatar(
                radius: 14,
                backgroundColor: tokens.primary,
                child: Text('$slotIndex',
                    style: TextStyle(
                        color: tokens.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            assigned == null ? tokens.fgMuted : tokens.fg))),
            if (assigned != null)
              IconButton(
                tooltip: 'Slot leeren',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _clearSlot(slotIndex),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _poolEntry({
    required String name,
    required String role,
    required bool conflicted,
    required bool alreadyAssigned,
    required VoidCallback? onTap,
  }) {
    final disabled = conflicted || alreadyAssigned;
    final card = Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: IgnorePointer(
          ignoring: disabled,
          child: TeamMemberCard(
            displayName: name,
            roleLabel: role,
            isConflicted: conflicted,
            onTap: onTap,
          ),
        ),
      ),
    );
    if (conflicted) {
      return Tooltip(message: 'Bereits in anderem Roster', child: card);
    }
    return card;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final hasMember = requireAtLeastOneMember(_assignments.values.toList());
    final anyAssigned = _assignments.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: KubbTokens.space2),
              child: Text('Pool',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.fgMuted,
                      letterSpacing: 0.5)),
            ),
            for (final m in widget.pool)
              _poolEntry(
                name: m.displayName,
                role: 'Mitglied',
                conflicted: m.conflicted,
                alreadyAssigned: _isAssigned(m),
                onTap: () => _pickSlotForPool(
                    (slot) => RosterSlotInput.member(slot, m.userId)),
              ),
            for (final g in widget.guests)
              _poolEntry(
                name: g.displayName,
                role: 'Gast',
                conflicted: false,
                alreadyAssigned: _isGuestAssigned(g),
                onTap: () => _pickSlotForPool(
                    (slot) => RosterSlotInput.guest(slot, g.guestId)),
              ),
          ]),
        ),
        const SizedBox(width: KubbTokens.space3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: KubbTokens.space2),
              child: Text('Slots',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.fgMuted,
                      letterSpacing: 0.5)),
            ),
            for (var i = 1; i <= widget.availableSlots; i++) _slotTile(i),
          ]),
        ),
      ]),
      if (anyAssigned && !hasMember)
        Padding(
          padding: const EdgeInsets.only(top: KubbTokens.space2),
          child: Container(
            padding: const EdgeInsets.all(KubbTokens.space3),
            decoration: BoxDecoration(
              color: tokens.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              border: Border.all(color: tokens.danger),
            ),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, color: tokens.danger, size: 18),
              const SizedBox(width: KubbTokens.space2),
              Expanded(
                child: Text('Mind. 1 registriertes Mitglied',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.danger)),
              ),
            ]),
          ),
        ),
    ]);
  }
}
