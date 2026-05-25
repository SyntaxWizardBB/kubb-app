import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const int _kTotalSteps = 4;

/// Four-step organizer wizard for creating a tournament. Drives the
/// [tournamentConfigControllerProvider] and hands the final draft to
/// [TournamentActions.createTournament] on submit. The detail screen
/// (W3-B) takes over after navigation.
class TournamentSetupWizard extends ConsumerStatefulWidget {
  const TournamentSetupWizard({super.key});

  @override
  ConsumerState<TournamentSetupWizard> createState() =>
      _TournamentSetupWizardState();
}

class _TournamentSetupWizardState extends ConsumerState<TournamentSetupWizard> {
  int _step = 0;
  bool _submitting = false;

  bool _stepValid(TournamentConfigDraft draft) {
    switch (_step) {
      case 0:
        final n = draft.displayName?.trim() ?? '';
        return n.length >= TournamentConfigDraft.displayNameMinChars &&
            n.length <= TournamentConfigDraft.displayNameMaxChars;
      case 1:
        return draft.minParticipants <= draft.maxParticipants &&
            draft.minParticipants >= TournamentConfigDraft.participantsHardMin;
      case 2:
        return draft.setsToWin >= TournamentConfigDraft.setsToWinMin &&
            draft.maxSets >= 2 * draft.setsToWin - 1;
      case 3:
        return draft.validate().isValid;
      default:
        return false;
    }
  }

  Future<void> _onPrimary() async {
    if (_step < _kTotalSteps - 1) {
      setState(() => _step += 1);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final draft = ref.read(tournamentConfigControllerProvider);
    final l10n = AppLocalizations.of(context);
    try {
      final id =
          await ref.read(tournamentActionsProvider).createTournament(draft);
      if (!mounted) return;
      context.go('${TournamentRoutes.list}/${id.value}');
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tournamentWizardSubmitError(e.toString())),
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
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(tournamentConfigControllerProvider);
    final controller = ref.read(tournamentConfigControllerProvider.notifier);
    final stepTitle = switch (_step) {
      0 => l10n.tournamentWizardStep1Title,
      1 => l10n.tournamentWizardStep2Title,
      2 => l10n.tournamentWizardStep3Title,
      _ => l10n.tournamentWizardStep4Title,
    };

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        title: l10n.tournamentWizardTitle,
        eyebrow: stepTitle,
        leading: _step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                color: tokens.fg,
                onPressed: _submitting ? null : () => setState(() => _step -= 1),
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ProgressBar(step: _step, total: _kTotalSteps),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  KubbTokens.space4,
                  KubbTokens.space4,
                  KubbTokens.space4,
                  KubbTokens.space8,
                ),
                child: switch (_step) {
                  0 => _StepName(
                      draft: draft,
                      onChanged: controller.setDisplayName,
                    ),
                  1 => _StepParticipants(
                      draft: draft,
                      onMin: controller.setMinParticipants,
                      onMax: controller.setMaxParticipants,
                    ),
                  2 => _StepFormat(
                      draft: draft,
                      onFormat: controller.setFormat,
                      onSetsToWin: controller.setSetsToWin,
                      onMaxSets: controller.setMaxSets,
                    ),
                  _ => _StepSummary(draft: draft),
                },
              ),
            ),
            _BottomBar(
              onPrimary: _stepValid(draft) && !_submitting ? _onPrimary : null,
              onBack: _step == 0 || _submitting
                  ? null
                  : () => setState(() => _step -= 1),
              primaryLabel: _step == _kTotalSteps - 1
                  ? l10n.tournamentWizardCreateButton
                  : l10n.tournamentWizardNextButton,
              backLabel: l10n.tournamentWizardBackButton,
              submitting: _submitting,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        0,
        KubbTokens.space4,
        KubbTokens.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.tournamentWizardStepLabel(step + 1, total),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.88,
              color: tokens.fgMuted,
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          ClipRRect(
            borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
            child: LinearProgressIndicator(
              value: (step + 1) / total,
              minHeight: 6,
              backgroundColor: tokens.line,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.onPrimary,
    required this.onBack,
    required this.primaryLabel,
    required this.backLabel,
    required this.submitting,
  });

  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final String primaryLabel;
  final String backLabel;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space3,
        KubbTokens.space4,
        KubbTokens.space4,
      ),
      decoration: BoxDecoration(
        color: tokens.bg,
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            Expanded(
              child: SizedBox(
                height: KubbTokens.touchMin,
                child: OutlinedButton(
                  onPressed: onBack,
                  child: Text(backLabel),
                ),
              ),
            ),
          if (onBack != null) const SizedBox(width: KubbTokens.space3),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: KubbTokens.touchMin,
              child: FilledButton(
                onPressed: onPrimary,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(primaryLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepName extends StatefulWidget {
  const _StepName({required this.draft, required this.onChanged});

  final TournamentConfigDraft draft;
  final ValueChanged<String> onChanged;

  @override
  State<_StepName> createState() => _StepNameState();
}

class _StepNameState extends State<_StepName> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.draft.displayName ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.tournamentWizardDisplayNameLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        TextField(
          controller: _ctrl,
          maxLength: TournamentConfigDraft.displayNameMaxChars,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepParticipants extends StatelessWidget {
  const _StepParticipants({
    required this.draft,
    required this.onMin,
    required this.onMax,
  });

  final TournamentConfigDraft draft;
  final ValueChanged<int> onMin;
  final ValueChanged<int> onMax;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NumberStepper(
          label: l10n.tournamentWizardMinParticipantsLabel,
          value: draft.minParticipants,
          min: TournamentConfigDraft.participantsHardMin,
          max: draft.maxParticipants,
          onChanged: onMin,
        ),
        const SizedBox(height: KubbTokens.space4),
        _NumberStepper(
          label: l10n.tournamentWizardMaxParticipantsLabel,
          value: draft.maxParticipants,
          min: draft.minParticipants,
          max: TournamentConfigDraft.participantsHardMax,
          onChanged: onMax,
        ),
      ],
    );
  }
}

class _StepFormat extends StatelessWidget {
  const _StepFormat({
    required this.draft,
    required this.onFormat,
    required this.onSetsToWin,
    required this.onMaxSets,
  });

  final TournamentConfigDraft draft;
  final ValueChanged<TournamentFormat> onFormat;
  final ValueChanged<int> onSetsToWin;
  final ValueChanged<int> onMaxSets;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.tournamentWizardFormatLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        for (final f in TournamentFormat.values)
          _FormatRow(
            format: f,
            selected: draft.format == f,
            enabled: f == TournamentFormat.roundRobin,
            label: f == TournamentFormat.roundRobin
                ? l10n.tournamentWizardFormatRoundRobin
                : _humanFormatLabel(f),
            comingSoonLabel: l10n.tournamentWizardFormatComingSoon,
            onTap: () => onFormat(f),
          ),
        const SizedBox(height: KubbTokens.space5),
        _NumberStepper(
          label: l10n.tournamentWizardSetsToWinLabel,
          value: draft.setsToWin,
          min: TournamentConfigDraft.setsToWinMin,
          max: TournamentConfigDraft.setsToWinMax,
          onChanged: onSetsToWin,
        ),
        const SizedBox(height: KubbTokens.space4),
        _NumberStepper(
          label: l10n.tournamentWizardMaxSetsLabel,
          value: draft.maxSets,
          min: 2 * draft.setsToWin - 1,
          max: 9,
          onChanged: onMaxSets,
        ),
      ],
    );
  }

  String _humanFormatLabel(TournamentFormat f) {
    switch (f) {
      case TournamentFormat.roundRobin:
        return 'Round Robin';
      case TournamentFormat.singleElimination:
        return 'Single Elimination';
      case TournamentFormat.schoch:
        return 'Schoch';
      case TournamentFormat.swiss:
        return 'Schweizer System';
      case TournamentFormat.roundRobinThenKo:
        return 'Round Robin + KO';
      case TournamentFormat.schochThenKo:
        return 'Schoch + KO';
      case TournamentFormat.swissThenKo:
        return 'Schweizer + KO';
    }
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({
    required this.format,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.comingSoonLabel,
    required this.onTap,
  });

  final TournamentFormat format;
  final bool selected;
  final bool enabled;
  final String label;
  final String comingSoonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: InkWell(
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
            color: selected ? tokens.bgSunken : tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            border: Border.all(
              color: selected ? tokens.primary : tokens.line,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: enabled ? tokens.fg : tokens.fgSubtle,
              ),
              const SizedBox(width: KubbTokens.space3),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: enabled ? tokens.fg : tokens.fgSubtle,
                  ),
                ),
              ),
              if (!enabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KubbTokens.space2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.line,
                    borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
                  ),
                  child: Text(
                    comingSoonLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: tokens.fgMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepSummary extends StatelessWidget {
  const _StepSummary({required this.draft});

  final TournamentConfigDraft draft;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryRow(
            tokens,
            l10n.tournamentWizardDisplayNameLabel,
            (draft.displayName ?? '').trim(),
          ),
          _summaryRow(
            tokens,
            l10n.tournamentWizardMinParticipantsLabel,
            '${draft.minParticipants}',
          ),
          _summaryRow(
            tokens,
            l10n.tournamentWizardMaxParticipantsLabel,
            '${draft.maxParticipants}',
          ),
          _summaryRow(
            tokens,
            l10n.tournamentWizardFormatLabel,
            l10n.tournamentWizardFormatRoundRobin,
          ),
          _summaryRow(
            tokens,
            l10n.tournamentWizardSetsToWinLabel,
            '${draft.setsToWin}',
          ),
          _summaryRow(
            tokens,
            l10n.tournamentWizardMaxSetsLabel,
            '${draft.maxSets}',
          ),
          _summaryRow(
            tokens,
            l10n.tournamentWizardRoundTimeLabel,
            '${(draft.roundTimeSeconds / 60).round()}',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    KubbTokens tokens,
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : KubbTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.fgMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final canDec = value > min;
    final canInc = value < max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tokens.fgMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove,
              onPressed: canDec ? () => onChanged(value - 1) : null,
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.bgRaised,
                  border: Border.all(color: tokens.lineStrong, width: 1.5),
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                ),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg,
                  ),
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            _StepButton(
              icon: Icons.add,
              onPressed: canInc ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

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
