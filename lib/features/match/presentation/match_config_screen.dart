import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/application/match_config_controller.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_config_draft.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/match/presentation/widgets/participant_picker_sheet.dart';
import 'package:kubb_app/features/match/presentation/widgets/team_slot_chip.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Single-screen wizard for configuring a brand-new match. Drives
/// [matchConfigControllerProvider] for state and finally hands the
/// draft to `MatchActions.createMatch` on submit.
class MatchConfigScreen extends ConsumerStatefulWidget {
  const MatchConfigScreen({super.key});

  @override
  ConsumerState<MatchConfigScreen> createState() => _MatchConfigScreenState();
}

class _MatchConfigScreenState extends ConsumerState<MatchConfigScreen> {
  bool _submitting = false;

  Future<void> _addToTeam(MatchTeamTag team) async {
    final picked = await ParticipantPickerSheet.show(context);
    if (picked == null || !mounted) return;
    ref.read(matchConfigControllerProvider.notifier).addToTeam(picked, team);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final controller = ref.read(matchConfigControllerProvider.notifier);
    final validation = controller.validate();
    if (!validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            validation.issues.isEmpty
                ? 'Konfiguration unvollständig'
                : validation.issues.first,
          ),
          backgroundColor: KubbTokens.miss,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final draft = ref.read(matchConfigControllerProvider);
      final matchId =
          await ref.read(matchActionsProvider).createMatch(draft);
      if (!mounted) return;
      context.go('${MatchRoutes.lobby}/$matchId');
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Match konnte nicht gestartet werden: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final draft = ref.watch(matchConfigControllerProvider);
    final controller = ref.read(matchConfigControllerProvider.notifier);
    final validation = controller.validate();

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => context.go('/')),
        title: const Text('Neues Match'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space2,
          KubbTokens.space4,
          KubbTokens.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionLabel(text: 'Best of:'),
            const SizedBox(height: KubbTokens.space2),
            _FormatStepper(
              selected: draft.format,
              onChanged: controller.setFormat,
            ),
            const SizedBox(height: KubbTokens.space5),
            const _SectionLabel(text: 'Wertung'),
            const SizedBox(height: KubbTokens.space2),
            _ScoringChips(
              selected: draft.scoring,
              onSelected: controller.setScoring,
            ),
            const SizedBox(height: KubbTokens.space5),
            _TeamColumn(
              title: 'Team A',
              accent: KubbTokens.meadow600,
              slots: draft.teamA,
              onAdd: () => _addToTeam(MatchTeamTag.a),
              onRemove: controller.removeFromTeam,
            ),
            const SizedBox(height: KubbTokens.space4),
            _TeamColumn(
              title: 'Team B',
              accent: KubbTokens.wood400,
              slots: draft.teamB,
              onAdd: () => _addToTeam(MatchTeamTag.b),
              onRemove: controller.removeFromTeam,
            ),
            const SizedBox(height: KubbTokens.space6),
            if (!validation.isValid && validation.issues.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: KubbTokens.space3),
                child: Text(
                  validation.issues.first,
                  style: const TextStyle(
                    fontSize: 12,
                    color: KubbTokens.miss,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SizedBox(
              height: KubbTokens.touchComfortable,
              child: FilledButton(
                onPressed:
                    _submitting || !validation.isValid ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Match starten'),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.88,
        color: tokens.fgMuted,
      ),
    );
  }
}

/// "Best of" stepper. Free integer in `MatchFormat.minN..maxN`
/// (currently 1..99). +/- buttons step by 1; long-press accelerates so
/// the user can dial up large values quickly without 50 taps.
class _FormatStepper extends StatelessWidget {
  const _FormatStepper({required this.selected, required this.onChanged});

  final MatchFormat selected;
  final ValueChanged<MatchFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final n = selected.n;
    final canDec = n > MatchFormat.minN;
    final canInc = n < MatchFormat.maxN;

    return Row(
      children: [
        _StepBtn(
          icon: LucideIcons.minus,
          onPressed: canDec ? () => onChanged(MatchFormat(n - 1)) : null,
        ),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: tokens.bgRaised,
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              border: Border.all(color: tokens.lineStrong, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(width: KubbTokens.space2),
        _StepBtn(
          icon: LucideIcons.plus,
          onPressed: canInc ? () => onChanged(MatchFormat(n + 1)) : null,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              border: Border.all(color: tokens.line, width: 1.5),
            ),
            child: Icon(
              icon,
              color: onPressed == null ? tokens.fgSubtle : tokens.fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoringChips extends StatelessWidget {
  const _ScoringChips({required this.selected, required this.onSelected});

  final MatchScoring selected;
  final ValueChanged<MatchScoring> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: KubbTokens.space2,
      children: [
        _Chip(
          label: 'Sätze',
          selected: selected == MatchScoring.wins,
          onTap: () => onSelected(MatchScoring.wins),
        ),
        _Chip(
          label: 'Punkte',
          selected: selected == MatchScoring.points,
          onTap: () => onSelected(MatchScoring.points),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Material(
      color: selected ? tokens.primary : tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space4,
            vertical: KubbTokens.space2,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? tokens.primary : tokens.line,
            ),
            borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? tokens.onPrimary : tokens.fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.title,
    required this.accent,
    required this.slots,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final Color accent;
  final List<TeamSlot> slots;
  final VoidCallback onAdd;
  final ValueChanged<TeamSlot> onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                ),
              ),
              const Spacer(),
              Text(
                '${slots.length} Spieler',
                style: TextStyle(fontSize: 11, color: tokens.fgMuted),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          for (final slot in slots) ...[
            TeamSlotChip(
              label: _labelOf(slot),
              subtitle: _subtitleOf(slot),
              isSelf: slot is SelfSlot,
              onRemove: slot is SelfSlot ? null : () => onRemove(slot),
            ),
            const SizedBox(height: KubbTokens.space2),
          ],
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Spieler hinzufügen'),
          ),
        ],
      ),
    );
  }

  String _labelOf(TeamSlot slot) => switch (slot) {
        SelfSlot() => 'Du',
        FriendSlot(:final nickname) => nickname,
      };

  String _subtitleOf(TeamSlot slot) => switch (slot) {
        SelfSlot() => 'Eigener Account',
        FriendSlot() => 'Freund',
      };
}
