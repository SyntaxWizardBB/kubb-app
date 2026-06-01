import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_pdf_uploader.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/_wizard_ko_config_step.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/_wizard_league_step.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/_wizard_pool_config_step.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/swiss_config_section.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Logical step identifiers — keeps the dynamic ordering for KO-formats
/// (T13: round_robin_then_ko adds [_StepKind.league] and [_StepKind.koConfig])
/// readable. The visible step index is derived from `_visibleSteps`.
enum _StepKind {
  name,
  participants,
  format,
  league,
  poolConfig,
  koConfig,
  summary,
}

/// Four-step organizer wizard for creating a tournament. Drives the
/// [tournamentConfigControllerProvider] and hands the final draft to
/// [TournamentActions.createTournament] on submit. The detail screen
/// (W3-B) takes over after navigation.
///
/// P7 EDIT mode: when [editId] is non-null the wizard submits through
/// [TournamentActions.updateTournament] instead of `createTournament` and
/// navigates back to the detail screen on success. The prefill is supplied
/// by the caller seeding `tournamentConfigControllerProvider` (the edit
/// route overrides it with a `TournamentConfigController` built from
/// `TournamentConfigDraft.fromDetail`).
class TournamentSetupWizard extends ConsumerStatefulWidget {
  const TournamentSetupWizard({super.key, this.editId});

  /// Non-null when the wizard runs in EDIT mode for an existing
  /// tournament. Drives the submit path (update vs create) and the
  /// primary-button label.
  final TournamentId? editId;

  @override
  ConsumerState<TournamentSetupWizard> createState() =>
      _TournamentSetupWizardState();
}

class _TournamentSetupWizardState extends ConsumerState<TournamentSetupWizard> {
  int _step = 0;
  bool _submitting = false;
  // T9: toggle state for the pool-phase step. Lives in widget state so the
  // organizer can flip it off without losing the previously typed values
  // until they advance the wizard.
  bool _poolPhaseEnabled = false;
  // T10: round-count for the Swiss-System format (default ceil(log2(n)),
  // clamped 3..9). Stored locally — round-count isn't part of the create-
  // RPC contract yet, the pairing engine receives it client-side.
  int? _swissRounds;

  /// Logical step list for the current draft. Hybrid formats unlock
  /// [_StepKind.league] (T12) and [_StepKind.koConfig] (T13); pure
  /// round-robin keeps the original four-step flow.
  List<_StepKind> _visibleSteps(TournamentConfigDraft draft) {
    return <_StepKind>[
      _StepKind.name,
      _StepKind.participants,
      _StepKind.format,
      if (draft.requiresKoConfig) ...[
        _StepKind.league,
        if (draft.supportsPoolPhase) _StepKind.poolConfig,
        _StepKind.koConfig,
      ],
      _StepKind.summary,
    ];
  }

  bool _stepValid(TournamentConfigDraft draft) {
    final kinds = _visibleSteps(draft);
    if (_step >= kinds.length) return false;
    switch (kinds[_step]) {
      case _StepKind.name:
        final n = draft.displayName?.trim() ?? '';
        return n.length >= TournamentConfigDraft.displayNameMinChars &&
            n.length <= TournamentConfigDraft.displayNameMaxChars;
      case _StepKind.participants:
        return draft.minParticipants <= draft.maxParticipants &&
            draft.minParticipants >= TournamentConfigDraft.participantsHardMin;
      case _StepKind.format:
        return draft.setsToWin >= TournamentConfigDraft.setsToWinMin &&
            draft.maxSets >= 2 * draft.setsToWin - 1;
      case _StepKind.league:
        // Boolean switch — always valid.
        return true;
      case _StepKind.poolConfig:
        // Off (toggle stored locally → poolPhaseConfig null) is valid.
        // On with an invalid input also leaves poolPhaseConfig null
        // because the inline widget pushes null until every field is fine.
        // We allow "Weiter" when either:
        //   * the toggle is off (tracked via _poolPhaseEnabled), or
        //   * the toggle is on AND the draft has a valid PoolPhaseConfig.
        return !_poolPhaseEnabled || draft.poolPhaseConfig != null;
      case _StepKind.koConfig:
        final cfg = draft.koConfig;
        return cfg != null &&
            cfg.qualifierCount >= 2 &&
            cfg.qualifierCount <= draft.maxParticipants;
      case _StepKind.summary:
        return draft.validate().isValid;
    }
  }

  Future<void> _onPrimary() async {
    final draft = ref.read(tournamentConfigControllerProvider);
    final totalSteps = _visibleSteps(draft).length;
    if (_step < totalSteps - 1) {
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
    final editId = widget.editId;
    try {
      final TournamentId targetId;
      if (editId != null) {
        await ref
            .read(tournamentActionsProvider)
            .updateTournament(editId, draft);
        targetId = editId;
      } else {
        targetId =
            await ref.read(tournamentActionsProvider).createTournament(draft);
      }
      if (!mounted) return;
      context.go('${TournamentRoutes.detail}/${targetId.value}');
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
    final kinds = _visibleSteps(draft);
    final totalSteps = kinds.length;
    // Clamp step index in case the visible-step list shrank under us
    // (organizer switched back from a KO format after entering KO steps).
    final stepIndex = _step.clamp(0, totalSteps - 1);
    final kind = kinds[stepIndex];
    final stepTitle = _titleForKind(kind, l10n);

    return Scaffold(
      backgroundColor: tokens.bg,
      // Mängel #2.4 / BH-C-03: resizeToAvoidBottomInset + viewInsets-aware
      // bottom-Padding pro Step-Scroller, damit der "Weiter"/"Anlegen"-
      // Button nicht hinter der Software-Tastatur verschwindet (PageView/
      // Stepper-Variante: jeder Step ist sein eigener Scrollable).
      resizeToAvoidBottomInset: true,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: KubbAppBar(
        title: widget.editId != null
            ? l10n.tournamentWizardEditTitle
            : l10n.tournamentWizardTitle,
        eyebrow: stepTitle,
        leading: stepIndex == 0
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
            _ProgressBar(step: stepIndex, total: totalSteps),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  KubbTokens.space4,
                  KubbTokens.space4,
                  KubbTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom +
                      KubbTokens.space8,
                ),
                child: _buildStep(kind, draft, controller),
              ),
            ),
            _BottomBar(
              onPrimary: _stepValid(draft) && !_submitting ? _onPrimary : null,
              onBack: stepIndex == 0 || _submitting
                  ? null
                  : () => setState(() => _step -= 1),
              primaryLabel: stepIndex == totalSteps - 1
                  ? (widget.editId != null
                      ? l10n.tournamentWizardSaveButton
                      : l10n.tournamentWizardCreateButton)
                  : l10n.tournamentWizardNextButton,
              backLabel: l10n.tournamentWizardBackButton,
              submitting: _submitting,
            ),
          ],
        ),
      ),
    );
  }

  String _titleForKind(_StepKind kind, AppLocalizations l10n) {
    switch (kind) {
      case _StepKind.name:
        return l10n.tournamentWizardStep1Title;
      case _StepKind.participants:
        return l10n.tournamentWizardStep2Title;
      case _StepKind.format:
        return l10n.tournamentWizardStep3Title;
      case _StepKind.league:
        return l10n.tournamentWizardStep45Title;
      case _StepKind.poolConfig:
        return 'Pool-Phase';
      case _StepKind.koConfig:
        return l10n.tournamentWizardStep5Title;
      case _StepKind.summary:
        return l10n.tournamentWizardStep4Title;
    }
  }

  /// Dispatches the visible step kind to its widget. Anchor for T12
  /// (`_LeagueStep`) and T13 (`WizardKoConfigStep`) — adding a new step
  /// only touches `_StepKind`, `_visibleSteps` and this switch.
  Widget _buildStep(
    _StepKind kind,
    TournamentConfigDraft draft,
    TournamentConfigController controller,
  ) {
    switch (kind) {
      case _StepKind.name:
        return _StepStammdaten(draft: draft, controller: controller);
      case _StepKind.participants:
        return _StepParticipants(
          draft: draft,
          onMin: controller.setMinParticipants,
          onMax: controller.setMaxParticipants,
          onTeamSize: controller.setTeamSize,
          onMaxTeamSize: controller.setMaxTeamSize,
        );
      case _StepKind.format:
        return _StepFormat(
          draft: draft,
          onVorrundeType: controller.setVorrundeType,
          onKoType: controller.setKoType,
          onSetsToWin: controller.setSetsToWin,
          onMaxSets: controller.setMaxSets,
          swissRounds: _swissRounds ??
              SwissConfigSection.defaultRounds(draft.maxParticipants),
          onSwissRoundsChanged: (v) => setState(() => _swissRounds = v),
          onPitchPlanChanged: controller.setPitchPlan,
          onRoundTime: controller.setRoundTime,
          onPrelimTiebreakAfter: controller.setPrelimTiebreakAfterSeconds,
          onBreakBetween: controller.setBreakBetweenMatchesSeconds,
        );
      case _StepKind.league:
        return WizardLeagueStep(
          value: draft.leagueEligible,
          onChanged: controller.setLeagueEligible,
        );
      case _StepKind.poolConfig:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WizardPoolToggle(
              value: _poolPhaseEnabled,
              onChanged: (next) {
                setState(() => _poolPhaseEnabled = next);
                if (!next) controller.setPoolPhaseConfig(null);
              },
            ),
            if (_poolPhaseEnabled)
              WizardPoolConfigStep(
                key: ValueKey<int>(draft.maxParticipants),
                draft: draft,
                onConfigChanged: controller.setPoolPhaseConfig,
                onPitchPlanChanged: controller.setPitchPlan,
              ),
          ],
        );
      case _StepKind.koConfig:
        return WizardKoConfigStep(
          key: ValueKey<int>(draft.maxParticipants),
          draft: draft,
          controller: controller,
          onConfigChanged: controller.setKoConfig,
          onSeedingModeChanged: controller.setBracketSeedingMode,
        );
      case _StepKind.summary:
        return _StepSummary(draft: draft);
    }
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

/// First wizard step — the tournament Stammdaten (master data). Holds the
/// name plus the P6 meta fields (league categories, location, start
/// date, registration deadline, scoring system). Free-text info blocks,
/// rule-variant toggles and PDF upload land in the next 1b iteration.
class _StepStammdaten extends StatefulWidget {
  const _StepStammdaten({required this.draft, required this.controller});

  final TournamentConfigDraft draft;
  final TournamentConfigController controller;

  @override
  State<_StepStammdaten> createState() => _StepStammdatenState();
}

class _StepStammdatenState extends State<_StepStammdaten> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _contactNameCtrl;
  late final TextEditingController _contactPhoneCtrl;
  late final TextEditingController _foodCtrl;
  late final TextEditingController _travelCtrl;
  late final TextEditingController _accommodationCtrl;
  late final TextEditingController _weatherCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _nameCtrl = TextEditingController(text: d.displayName ?? '');
    _locationCtrl = TextEditingController(text: d.location ?? '');
    _addressCtrl = TextEditingController(text: d.venueAddress ?? '');
    _feeCtrl = TextEditingController(text: _feeText(d.entryFeeCents));
    _contactNameCtrl = TextEditingController(text: d.contactName ?? '');
    _contactPhoneCtrl = TextEditingController(text: d.contactPhone ?? '');
    _foodCtrl = TextEditingController(text: d.infoFood ?? '');
    _travelCtrl = TextEditingController(text: d.infoTravel ?? '');
    _accommodationCtrl =
        TextEditingController(text: d.infoAccommodation ?? '');
    _weatherCtrl = TextEditingController(text: d.weatherNote ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _addressCtrl.dispose();
    _feeCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _foodCtrl.dispose();
    _travelCtrl.dispose();
    _accommodationCtrl.dispose();
    _weatherCtrl.dispose();
    super.dispose();
  }

  /// Cents → editable franc string ('' for null, '10' for whole francs).
  static String _feeText(int? cents) {
    if (cents == null) return '';
    if (cents % 100 == 0) return '${cents ~/ 100}';
    return (cents / 100).toStringAsFixed(2);
  }

  /// Editable franc string → cents (null when blank/invalid).
  static int? _feeCents(String text) {
    final trimmed = text.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    final francs = double.tryParse(trimmed);
    if (francs == null || francs < 0) return null;
    return (francs * 100).round();
  }

  Future<void> _pickDateTime({
    required DateTime? initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final base = initial ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(base);
    onPicked(DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(l10n.tournamentWizardDisplayNameLabel),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          key: const Key('wizardNameField'),
          controller: _nameCtrl,
          maxLength: TournamentConfigDraft.displayNameMaxChars,
          onChanged: controller.setDisplayName,
        ),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardClubLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _ClubPickerField(
          selectedClubId: draft.clubId,
          onChanged: controller.setClubId,
        ),
        const SizedBox(height: KubbTokens.space1half),
        _HelperText(l10n.tournamentWizardClubHint),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(
          l10n.tournamentWizardLeagueCategoriesLabel,
          optional: true,
        ),
        const SizedBox(height: KubbTokens.space2),
        Wrap(
          spacing: KubbTokens.space2,
          runSpacing: KubbTokens.space2,
          children: [
            for (final c in LeagueCategory.values)
              _SelectChip(
                label: l10n.tournamentWizardLeagueCategory(c.wire),
                selected: draft.leagueCategories.contains(c),
                onTap: () => controller.toggleLeagueCategory(c),
              ),
          ],
        ),
        const SizedBox(height: KubbTokens.space1half),
        _HelperText(l10n.tournamentWizardLeagueCategoriesHint),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardLocationLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _locationCtrl,
          hintText: l10n.tournamentWizardLocationHint,
          onChanged: controller.setLocation,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardVenueAddressLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _addressCtrl,
          hintText: l10n.tournamentWizardVenueAddressHint,
          onChanged: controller.setVenueAddress,
        ),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardEventDateLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _DateField(
          value: draft.eventStartsAt,
          onTap: () => _pickDateTime(
            initial: draft.eventStartsAt,
            onPicked: controller.setEventStartsAt,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(
          l10n.tournamentWizardRegistrationDeadlineLabel,
          optional: true,
        ),
        const SizedBox(height: KubbTokens.space2),
        _DateField(
          value: draft.registrationClosesAt,
          onTap: () => _pickDateTime(
            initial: draft.registrationClosesAt,
            onPicked: controller.setRegistrationClosesAt,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(
          l10n.tournamentWizardCheckinUntilLabel,
          optional: true,
        ),
        const SizedBox(height: KubbTokens.space2),
        _DateField(
          value: draft.checkinUntil,
          onTap: () => _pickDateTime(
            initial: draft.checkinUntil,
            onPicked: controller.setCheckinUntil,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardScoringLabel),
        const SizedBox(height: KubbTokens.space2),
        _ScoringOption(
          title: l10n.tournamentWizardScoringEkc,
          subtitle: l10n.tournamentWizardScoringEkcHint,
          selected: draft.scoring == 'ekc',
          onTap: () => controller.setScoring('ekc'),
        ),
        const SizedBox(height: KubbTokens.space2),
        _ScoringOption(
          title: l10n.tournamentWizardScoringClassic,
          subtitle: l10n.tournamentWizardScoringClassicHint,
          selected: draft.scoring == 'classic',
          onTap: () => controller.setScoring('classic'),
        ),

        // ---- Regeln & Dokumente ----
        _SectionHeaderText(l10n.tournamentWizardSectionRules),
        const SizedBox(height: KubbTokens.space3),
        _ToggleRow(
          title: l10n.tournamentWizardRuleSureshot,
          subtitle: l10n.tournamentWizardRuleSureshotHint,
          value: draft.ruleVariants.sureshot,
          onChanged: (v) => controller
              .setRuleVariants(draft.ruleVariants.copyWith(sureshot: v)),
        ),
        _ToggleRow(
          title: l10n.tournamentWizardRuleDiggy,
          subtitle: l10n.tournamentWizardRuleDiggyHint,
          value: draft.ruleVariants.diggy,
          onChanged: (v) => controller
              .setRuleVariants(draft.ruleVariants.copyWith(diggy: v)),
        ),
        _ToggleRow(
          title: l10n.tournamentWizardRuleStrafkubb,
          subtitle: l10n.tournamentWizardRuleStrafkubbHint,
          value: draft.ruleVariants.strafkubbOffBaseline,
          onChanged: (v) => controller.setRuleVariants(
            draft.ruleVariants.copyWith(strafkubbOffBaseline: v),
          ),
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardRulesPdfLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PdfUploadField(
          kind: TournamentPdfKind.rules,
          url: draft.rulesPdfUrl,
          onChanged: controller.setRulesPdfUrl,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardSiteMapPdfLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PdfUploadField(
          kind: TournamentPdfKind.siteMap,
          url: draft.siteMapPdfUrl,
          onChanged: controller.setSiteMapPdfUrl,
        ),

        // ---- Teilnahme ----
        _SectionHeaderText(l10n.tournamentWizardSectionParticipation),
        const SizedBox(height: KubbTokens.space3),
        _FieldLabel(l10n.tournamentWizardEntryFeeLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _feeCtrl,
          hintText: l10n.tournamentWizardEntryFeeHint,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          onChanged: (text) => controller.setEntryFeeCents(_feeCents(text)),
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardPaymentMethodsLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        Wrap(
          spacing: KubbTokens.space2,
          runSpacing: KubbTokens.space2,
          children: [
            for (final m in _paymentMethods(l10n))
              _SelectChip(
                label: m.label,
                selected: draft.paymentMethods.contains(m.wire),
                onTap: () => controller.togglePaymentMethod(m.wire),
              ),
          ],
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardContactNameLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _contactNameCtrl,
          onChanged: controller.setContactName,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardContactPhoneLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _contactPhoneCtrl,
          hintText: l10n.tournamentWizardContactPhoneHint,
          keyboardType: TextInputType.phone,
          onChanged: controller.setContactPhone,
        ),

        // ---- Infos für Teilnehmer ----
        _SectionHeaderText(l10n.tournamentWizardSectionInfo),
        const SizedBox(height: KubbTokens.space3),
        _FieldLabel(l10n.tournamentWizardInfoFoodLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _foodCtrl,
          maxLines: 2,
          onChanged: controller.setInfoFood,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardInfoTravelLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _travelCtrl,
          maxLines: 2,
          onChanged: controller.setInfoTravel,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardInfoAccommodationLabel,
            optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _accommodationCtrl,
          maxLines: 2,
          onChanged: controller.setInfoAccommodation,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardWeatherLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _weatherCtrl,
          maxLines: 2,
          onChanged: controller.setWeatherNote,
        ),
      ],
    );
  }
}

/// (label, wire-value) pair for a payment-method chip.
class _PaymentMethod {
  const _PaymentMethod(this.wire, this.label);
  final String wire;
  final String label;
}

List<_PaymentMethod> _paymentMethods(AppLocalizations l10n) => <_PaymentMethod>[
      _PaymentMethod('cash', l10n.tournamentWizardPaymentCash),
      _PaymentMethod('twint', l10n.tournamentWizardPaymentTwint),
      _PaymentMethod('card', l10n.tournamentWizardPaymentCard),
    ];

/// Section heading with top spacing, used to group the long Stammdaten
/// step into Eckdaten / Regeln / Teilnahme / Infos.
class _SectionHeaderText extends StatelessWidget {
  const _SectionHeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: KubbTokens.space6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: tokens.fg,
        ),
      ),
    );
  }
}

/// Title + subtitle row with a trailing [Switch], used for the rule
/// variants.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: tokens.primary,
          ),
        ],
      ),
    );
  }
}

/// Upload control for a tournament PDF. Picks a PDF via [openFile],
/// uploads it through [tournamentPdfUploaderProvider], and reports the
/// resulting public URL via [onChanged]. Shows uploaded / uploading
/// states and an error snackbar on failure.
class _PdfUploadField extends ConsumerStatefulWidget {
  const _PdfUploadField({
    required this.kind,
    required this.url,
    required this.onChanged,
  });

  final TournamentPdfKind kind;
  final String? url;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<_PdfUploadField> createState() => _PdfUploadFieldState();
}

class _PdfUploadFieldState extends ConsumerState<_PdfUploadField> {
  bool _uploading = false;

  Future<void> _pick() async {
    const group = XTypeGroup(
      label: 'PDF',
      extensions: <String>['pdf'],
      mimeTypes: <String>['application/pdf'],
    );
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _uploading = true);
    final l10n = AppLocalizations.of(context);
    try {
      final url = await ref
          .read(tournamentPdfUploaderProvider)
          .uploadPdf(kind: widget.kind, bytes: bytes);
      widget.onChanged(url);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.tournamentWizardPdfUploadError),
            backgroundColor: KubbTokens.miss,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);

    if (_uploading) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: KubbTokens.space3),
          Text(
            l10n.tournamentWizardPdfUploading,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted),
          ),
        ],
      );
    }

    if (widget.url != null) {
      return Container(
        padding: const EdgeInsets.all(KubbTokens.space3),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
          border: Border.all(color: tokens.line, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 20, color: tokens.primary),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Text(
                l10n.tournamentWizardPdfUploaded,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.fg,
                ),
              ),
            ),
            TextButton(
              onPressed: () => widget.onChanged(null),
              child: Text(l10n.tournamentWizardPdfRemove),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: KubbTokens.touchMin,
      child: OutlinedButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.upload_file, size: 20),
        label: Text(l10n.tournamentWizardPdfUpload),
      ),
    );
  }
}

/// Small all-caps field label used across the Stammdaten step, with an
/// optional "optional" badge.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.optional = false});

  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: tokens.fgMuted,
            ),
          ),
        ),
        if (optional) ...[
          const SizedBox(width: KubbTokens.space2),
          Text(
            l10n.tournamentWizardOptional,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: tokens.fgSubtle,
            ),
          ),
        ],
      ],
    );
  }
}

class _HelperText extends StatelessWidget {
  const _HelperText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        height: 1.35,
        color: tokens.fgSubtle,
      ),
    );
  }
}

/// Outline-bordered text field matching the wizard's design tokens.
class _PlainTextField extends StatelessWidget {
  const _PlainTextField({
    required this.controller,
    required this.onChanged,
    this.hintText,
    this.maxLength,
    this.maxLines = 1,
    this.keyboardType,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
    );
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        counterText: '',
        hintText: hintText,
        border: border,
        enabledBorder: border,
      ),
    );
  }
}

/// Optional organizing-club picker (Stammdaten step). Lists only the clubs
/// the caller may run a tournament under — owner/admin/organizer of the
/// club — from [manageableClubsProvider]; the first entry clears the club
/// (personal tournament). The selection persists to the draft's `club_id`
/// and, together with the per-tournament server gate, decides who may later
/// manage the tournament. While the club list loads or errors the picker is
/// disabled so the wizard never offers an unverified club.
class _ClubPickerField extends ConsumerWidget {
  const _ClubPickerField({
    required this.selectedClubId,
    required this.onChanged,
  });

  final String? selectedClubId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final clubs = ref.watch(manageableClubsProvider);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
    );
    final items = clubs.maybeWhen(
      data: (list) => list,
      orElse: () => const <ManageableClub>[],
    );
    // Drop a stale selection (e.g. a club the caller no longer manages) so
    // the dropdown never holds a value absent from its item list.
    final value =
        items.any((c) => c.id == selectedClubId) ? selectedClubId : null;
    return DropdownButtonFormField<String?>(
      key: const Key('wizardClubPicker'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        border: border,
        enabledBorder: border,
      ),
      items: <DropdownMenuItem<String?>>[
        DropdownMenuItem<String?>(
          child: Text(l10n.tournamentWizardClubNone),
        ),
        for (final c in items)
          DropdownMenuItem<String?>(
            value: c.id,
            child: Text(c.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: clubs.isLoading ? null : onChanged,
    );
  }
}

/// Tappable date(+time) field; shows the selected value or a placeholder.
class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap});

  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final v = value;
    final label = v == null
        ? l10n.tournamentWizardDateNotSet
        : '${materialL10n.formatMediumDate(v)} · '
            '${TimeOfDay.fromDateTime(v).format(context)}';
    return InkWell(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          border: Border.all(color: tokens.lineStrong, width: 1.5),
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        ),
        child: Row(
          children: [
            Icon(Icons.event, size: 20, color: tokens.fgMuted),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: v == null ? FontWeight.w500 : FontWeight.w700,
                  color: v == null ? tokens.fgSubtle : tokens.fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
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
    return InkWell(
      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space4,
          vertical: KubbTokens.space2,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          border: Border.all(
            color: selected ? tokens.primary : tokens.line,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: selected ? Colors.white : tokens.fgMuted,
            ),
            const SizedBox(width: KubbTokens.space2),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : tokens.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoringOption extends StatelessWidget {
  const _ScoringOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      onTap: onTap,
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
              color: tokens.fg,
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tokens.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: tokens.fgMuted),
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

class _StepParticipants extends StatelessWidget {
  const _StepParticipants({
    required this.draft,
    required this.onMin,
    required this.onMax,
    required this.onTeamSize,
    required this.onMaxTeamSize,
  });

  final TournamentConfigDraft draft;
  final ValueChanged<int> onMin;
  final ValueChanged<int> onMax;
  final ValueChanged<int> onTeamSize;
  final ValueChanged<int> onMaxTeamSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WizardNumberField(
          label: l10n.tournamentWizardMinTeamSizeLabel,
          value: draft.teamSize,
          min: 1,
          max: 6,
          onChanged: onTeamSize,
        ),
        const SizedBox(height: KubbTokens.space4),
        WizardNumberField(
          label: l10n.tournamentWizardMaxTeamSizeLabel,
          value: draft.maxTeamSize,
          min: draft.teamSize,
          max: 6,
          onChanged: onMaxTeamSize,
        ),
        const SizedBox(height: KubbTokens.space1half),
        _HelperText(l10n.tournamentWizardTeamSizeHint),
        const SizedBox(height: KubbTokens.space5),
        WizardNumberField(
          label: l10n.tournamentWizardMinParticipantsLabel,
          value: draft.minParticipants,
          min: TournamentConfigDraft.participantsHardMin,
          max: draft.maxParticipants,
          onChanged: onMin,
        ),
        const SizedBox(height: KubbTokens.space4),
        WizardNumberField(
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
    required this.onVorrundeType,
    required this.onKoType,
    required this.onSetsToWin,
    required this.onMaxSets,
    required this.swissRounds,
    required this.onSwissRoundsChanged,
    required this.onPitchPlanChanged,
    required this.onRoundTime,
    required this.onPrelimTiebreakAfter,
    required this.onBreakBetween,
  });

  final TournamentConfigDraft draft;
  // Two-axis format selection: Vorrunde (group phase vs Schoch) and KO
  // system (none / single-out / double-out). The controller derives the
  // legacy `TournamentFormat` + `BracketType` from these axes.
  final ValueChanged<VorrundeType> onVorrundeType;
  final ValueChanged<KoType> onKoType;
  final ValueChanged<int> onSetsToWin;
  final ValueChanged<int> onMaxSets;
  // T10: Swiss-System round count — surfaced inline when the Vorrunde is
  // Schoch. State lives in the wizard.
  final int swissRounds;
  final ValueChanged<int> onSwissRoundsChanged;
  final ValueChanged<PitchPlan?> onPitchPlanChanged;
  final ValueChanged<int> onRoundTime;
  final ValueChanged<int?> onPrelimTiebreakAfter;
  final ValueChanged<int> onBreakBetween;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Vorrunde axis (Gruppenphase | Schoch) ----
        Text(
          l10n.tournamentWizardVorrundeLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        _OptionRow(
          selected: draft.vorrundeType == VorrundeType.groupPhase,
          label: l10n.tournamentWizardVorrundeGroupPhase,
          description: l10n.tournamentWizardVorrundeGroupPhaseHint,
          onTap: () => onVorrundeType(VorrundeType.groupPhase),
        ),
        _OptionRow(
          selected: draft.vorrundeType == VorrundeType.schoch,
          label: l10n.tournamentWizardVorrundeSchoch,
          description: l10n.tournamentWizardVorrundeSchochHint,
          onTap: () => onVorrundeType(VorrundeType.schoch),
        ),
        // T10: the Schoch-rounds slider surfaces when the Vorrunde is Schoch
        // (the pairing engine shares the round count with the Swiss system).
        if (draft.vorrundeType == VorrundeType.schoch)
          SwissConfigSection(
            participantCount: draft.maxParticipants,
            rounds: swissRounds,
            onRoundsChanged: onSwissRoundsChanged,
          ),
        const SizedBox(height: KubbTokens.space5),
        // ---- KO axis (Kein KO | Single-Out | Double-Out) ----
        Text(
          l10n.tournamentWizardKoSystemLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        _OptionRow(
          selected: draft.koType == KoType.none,
          label: l10n.tournamentWizardKoSystemNone,
          description: l10n.tournamentWizardKoSystemNoneHint,
          onTap: () => onKoType(KoType.none),
        ),
        _OptionRow(
          selected: draft.koType == KoType.singleOut,
          label: l10n.tournamentWizardKoSystemSingle,
          description: l10n.tournamentWizardKoSystemSingleHint,
          onTap: () => onKoType(KoType.singleOut),
        ),
        _OptionRow(
          selected: draft.koType == KoType.doubleOut,
          label: l10n.tournamentWizardKoSystemDouble,
          description: l10n.tournamentWizardKoSystemDoubleHint,
          onTap: () => onKoType(KoType.doubleOut),
        ),
        const SizedBox(height: KubbTokens.space5),
        WizardNumberField(
          label: l10n.tournamentWizardSetsToWinLabel,
          value: draft.setsToWin,
          min: TournamentConfigDraft.setsToWinMin,
          max: TournamentConfigDraft.setsToWinMax,
          onChanged: onSetsToWin,
        ),
        const SizedBox(height: KubbTokens.space4),
        WizardNumberField(
          label: l10n.tournamentWizardMaxSetsLabel,
          value: draft.maxSets,
          min: 2 * draft.setsToWin - 1,
          max: 9,
          onChanged: onMaxSets,
        ),
        const SizedBox(height: KubbTokens.space4),
        WizardNumberField(
          label: l10n.tournamentWizardMatchTimeLabel,
          value: (draft.roundTimeSeconds / 60).round(),
          min: 5,
          max: 120,
          onChanged: (minutes) => onRoundTime(minutes * 60),
        ),
        const SizedBox(height: KubbTokens.space4),
        _ToggleRow(
          title: l10n.tournamentWizardTiebreakLabel,
          subtitle: l10n.tournamentWizardTiebreakHint,
          value: draft.prelimTiebreakAfterSeconds != null,
          onChanged: (on) => onPrelimTiebreakAfter(
            on
                ? (draft.roundTimeSeconds - 300)
                    .clamp(60, draft.roundTimeSeconds)
                : null,
          ),
        ),
        if (draft.prelimTiebreakAfterSeconds != null) ...[
          const SizedBox(height: KubbTokens.space2),
          WizardNumberField(
            label: l10n.tournamentWizardTiebreakAfterLabel,
            value: (draft.prelimTiebreakAfterSeconds! / 60).round(),
            min: 1,
            max: (draft.roundTimeSeconds / 60).round(),
            onChanged: (minutes) => onPrelimTiebreakAfter(minutes * 60),
          ),
        ],
        const SizedBox(height: KubbTokens.space4),
        WizardNumberField(
          label: l10n.tournamentWizardBreakBetweenLabel,
          value: (draft.breakBetweenMatchesSeconds / 60).round(),
          min: 0,
          max: 60,
          onChanged: (minutes) => onBreakBetween(minutes * 60),
        ),
        _SectionHeaderText(l10n.tournamentWizardSectionPitches),
        const SizedBox(height: KubbTokens.space2),
        _HelperText(l10n.tournamentWizardPitchHint),
        const SizedBox(height: KubbTokens.space3),
        _PitchPlanSection(
          plan: draft.pitchPlan,
          onChanged: onPitchPlanChanged,
        ),
      ],
    );
  }

}

/// Human-friendly German label for the selected format, derived from the
/// two-axis (Vorrunde × KO) selection rather than the legacy enum. Used by
/// the summary step.
String _humanFormatLabel(VorrundeType vorrunde, KoType ko) {
  final base = switch (vorrunde) {
    VorrundeType.groupPhase => 'Gruppenphase',
    VorrundeType.schoch => 'Schoch',
  };
  return switch (ko) {
    KoType.none => base,
    KoType.singleOut => '$base + Single-Out-K.-o.',
    KoType.doubleOut => '$base + Double-Out-K.-o.',
  };
}

/// Radio-style selectable card with a label + one-line description. Used by
/// the two-axis format selector (Vorrunde / KO system).
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.selected,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: InkWell(
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        onTap: onTap,
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
                color: tokens.fg,
              ),
              const SizedBox(width: KubbTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.fgMuted,
                      ),
                    ),
                  ],
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
            _humanFormatLabel(draft.vorrundeType, draft.koType),
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

/// Pitch configuration: a number range (von–bis) or a manual list, plus
/// a sort strategy. Emits a [PitchPlan] (or null when empty) via
/// [onChanged]. Group→pitch assignment is a later slice.
class _PitchPlanSection extends StatefulWidget {
  const _PitchPlanSection({required this.plan, required this.onChanged});

  final PitchPlan? plan;
  final ValueChanged<PitchPlan?> onChanged;

  @override
  State<_PitchPlanSection> createState() => _PitchPlanSectionState();
}

class _PitchPlanSectionState extends State<_PitchPlanSection> {
  late PitchMode _mode;
  late PitchSortStrategy _sort;
  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;
  late final TextEditingController _numbersCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _mode = p?.mode ?? PitchMode.range;
    _sort = p?.sortStrategy ?? PitchSortStrategy.topSeedsLowNumbers;
    _fromCtrl = TextEditingController(text: p?.rangeFrom?.toString() ?? '');
    _toCtrl = TextEditingController(text: p?.rangeTo?.toString() ?? '');
    _numbersCtrl = TextEditingController(
      text: (p?.numbers ?? const <int>[]).join(', '),
    );
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _numbersCtrl.dispose();
    super.dispose();
  }

  static int? _parseInt(String s) {
    final t = s.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  static List<int> _parseNumbers(String s) => s
      .split(RegExp(r'[,\s]+'))
      .where((x) => x.isNotEmpty)
      .map(int.tryParse)
      .whereType<int>()
      .where((n) => n > 0)
      .toList();

  /// Builds the plan from the current inputs (null when effectively empty).
  PitchPlan? _currentPlan() {
    if (_mode == PitchMode.range) {
      final from = _parseInt(_fromCtrl.text);
      final to = _parseInt(_toCtrl.text);
      if (from == null && to == null) return null;
      return PitchPlan(
        mode: PitchMode.range,
        rangeFrom: from,
        rangeTo: to,
        sortStrategy: _sort,
      );
    }
    final nums = _parseNumbers(_numbersCtrl.text);
    if (nums.isEmpty) return null;
    return PitchPlan(
      mode: PitchMode.manual,
      numbers: nums,
      sortStrategy: _sort,
    );
  }

  void _emit() => widget.onChanged(_currentPlan());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plan = _currentPlan();
    final count = plan?.availablePitches().length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: KubbTokens.space2,
          runSpacing: KubbTokens.space2,
          children: [
            _SelectChip(
              label: l10n.tournamentWizardPitchModeRange,
              selected: _mode == PitchMode.range,
              onTap: () {
                setState(() => _mode = PitchMode.range);
                _emit();
              },
            ),
            _SelectChip(
              label: l10n.tournamentWizardPitchModeManual,
              selected: _mode == PitchMode.manual,
              onTap: () {
                setState(() => _mode = PitchMode.manual);
                _emit();
              },
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space4),
        if (_mode == PitchMode.range)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FieldLabel(l10n.tournamentWizardPitchRangeFrom),
                    const SizedBox(height: KubbTokens.space2),
                    _PlainTextField(
                      key: const Key('wizardPitchRangeFromField'),
                      controller: _fromCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _emit(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KubbTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FieldLabel(l10n.tournamentWizardPitchRangeTo),
                    const SizedBox(height: KubbTokens.space2),
                    _PlainTextField(
                      key: const Key('wizardPitchRangeToField'),
                      controller: _toCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _emit(),
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...[
          _FieldLabel(l10n.tournamentWizardPitchNumbersLabel),
          const SizedBox(height: KubbTokens.space2),
          _PlainTextField(
            controller: _numbersCtrl,
            hintText: l10n.tournamentWizardPitchNumbersHint,
            keyboardType: TextInputType.number,
            onChanged: (_) => _emit(),
          ),
        ],
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardPitchSortLabel),
        const SizedBox(height: KubbTokens.space2),
        Wrap(
          spacing: KubbTokens.space2,
          runSpacing: KubbTokens.space2,
          children: [
            _SelectChip(
              label: l10n.tournamentWizardPitchSortTopSeeds,
              selected: _sort == PitchSortStrategy.topSeedsLowNumbers,
              onTap: () {
                setState(
                    () => _sort = PitchSortStrategy.topSeedsLowNumbers);
                _emit();
              },
            ),
            _SelectChip(
              label: l10n.tournamentWizardPitchSortManual,
              selected: _sort == PitchSortStrategy.manual,
              onTap: () {
                setState(() => _sort = PitchSortStrategy.manual);
                _emit();
              },
            ),
          ],
        ),
        if (count > 0) ...[
          const SizedBox(height: KubbTokens.space2),
          _HelperText(l10n.tournamentWizardPitchSummary(count)),
        ],
      ],
    );
  }
}
