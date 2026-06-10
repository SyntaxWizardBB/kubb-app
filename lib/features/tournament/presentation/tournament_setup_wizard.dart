import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_pdf_uploader.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart'
    show
        StructureLockedException,
        TournamentLockedException,
        tournamentRemoteProvider;
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/_wizard_ko_config_step.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/ko_model_explainer_sheet.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/swiss_config_section.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Logical step identifiers. The visible step index is derived from
/// `_visibleSteps`. K12/K25: the group-phase inputs (group count + grouping
/// strategy + per-group pitch assignment) now live in the Vorrunde step
/// (`_StepFormat`), so there is no separate pool-config step anymore.
enum _StepKind {
  name,
  participants,
  format,
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
  // T10: round-count for the Swiss-System format (default ceil(log2(n)),
  // clamped 3..9). Stored locally — round-count isn't part of the create-
  // RPC contract yet, the pairing engine receives it client-side.
  int? _swissRounds;

  /// Logical step list for the current draft. KO config always appears
  /// (every tournament has a KO stage). K12/K25: the former group-phase step
  /// is gone — group count + grouping strategy are configured inline in the
  /// Vorrunde step (`_StepFormat`) when `vorrundeType == groupPhase`.
  List<_StepKind> _visibleSteps(TournamentConfigDraft draft) {
    return <_StepKind>[
      _StepKind.name,
      _StepKind.participants,
      _StepKind.format,
      _StepKind.koConfig,
      _StepKind.summary,
    ];
  }

  /// Number of KO bracket slots (power of two) implied by the current KO
  /// config — the basis for the derived qualifier-per-group count and the
  /// divisibility check on the group-phase step.
  int _koBracketSize(TournamentConfigDraft draft) {
    final qualifiers = draft.koConfig?.qualifierCount ?? 0;
    if (qualifiers < 2) return 0;
    var size = 1;
    while (size < qualifiers) {
      size <<= 1;
    }
    return size;
  }

  bool _stepValid(TournamentConfigDraft draft) {
    final kinds = _visibleSteps(draft);
    if (_step >= kinds.length) return false;
    switch (kinds[_step]) {
      case _StepKind.name:
        // K01/K03/K29-K33: the Stammdaten step is only valid once the name,
        // the club/Spasstournier choice and every required field are set.
        // Liga is only required when a club is chosen (K29 carve-out).
        final n = draft.displayName?.trim() ?? '';
        final nameOk =
            n.length >= TournamentConfigDraft.displayNameMinChars &&
                n.length <= TournamentConfigDraft.displayNameMaxChars;
        final leagueOk =
            draft.clubId == null || draft.leagueCategories.isNotEmpty;
        return nameOk &&
            draft.clubChoiceMade &&
            leagueOk &&
            (draft.location?.trim().isNotEmpty ?? false) &&
            (draft.venueAddress?.trim().isNotEmpty ?? false) &&
            draft.eventStartsAt != null &&
            draft.registrationClosesAt != null &&
            draft.checkinUntil != null;
      case _StepKind.participants:
        // K09: no minimum-participant rule anymore — only the upper bound
        // (K10) and a non-empty roster gate this step.
        return draft.maxParticipants >= 2 &&
            draft.maxParticipants <= TournamentConfigDraft.participantsHardMax;
      case _StepKind.format:
        // Prelim "Max. Sätze" is decoupled from setsToWin (P6): only a sane
        // absolute range applies.
        final maxSetsOk = draft.maxSets >= TournamentConfigDraft.maxSetsMin &&
            draft.maxSets <= TournamentConfigDraft.maxSetsMax;
        if (!maxSetsOk) return false;
        // K12: in the group phase the inline group-count input must be a valid
        // group count (2..16). The qualifier-per-group divisibility check
        // (koBracketSize % groupCount) needs the KO size, which is only chosen
        // in the NEXT step — so it is gated on the koConfig step instead and
        // not required here.
        if (draft.vorrundeType == VorrundeType.groupPhase) {
          final cfg = draft.poolPhaseConfig;
          if (cfg == null) return false;
          return cfg.groupCount >= _StepFormat.groupCountMin &&
              cfg.groupCount <= _StepFormat.groupCountMax;
        }
        return true;
      case _StepKind.koConfig:
        // K11: KO size is bounded by the fixed bracket cap, decoupled from
        // maxParticipants (which may be up to 1000).
        final cfg = draft.koConfig;
        if (cfg == null ||
            cfg.qualifierCount < 2 ||
            cfg.qualifierCount > TournamentConfigDraft.koBracketSizeCap) {
          return false;
        }
        // K12: the group count chosen in the Vorrunde step must evenly divide
        // the KO bracket size (the qualifier-per-group count is derived as
        // koBracketSize / groupCount). The KO size is final on this step, so
        // the divisibility gate lives here.
        if (draft.vorrundeType == VorrundeType.groupPhase) {
          final pool = draft.poolPhaseConfig;
          final bracketSize = _koBracketSize(draft);
          if (pool == null ||
              pool.groupCount <= 0 ||
              bracketSize <= 0 ||
              bracketSize % pool.groupCount != 0) {
            return false;
          }
        }
        // K18: the consolation/Trostturnier config lives in this step now; its
        // name is required, so "Weiter" stays blocked until it is filled.
        if (draft.koType == KoType.consolation &&
            (draft.consolationName?.trim().isEmpty ?? true)) {
          return false;
        }
        return true;
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
      // Invite-only Spaßturnier: send each picked invitation AFTER the
      // tournament exists / its invite_only flag is persisted. Failures are
      // tolerated per invitee so one bad call doesn't abort the whole flow —
      // we surface a soft hint and still navigate to the detail screen.
      final inviteFailures = await _sendInvites(targetId, draft);
      if (!mounted) return;
      if (inviteFailures > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.tournamentWizardInvitePartialError(
              inviteFailures,
            )),
            backgroundColor: KubbTokens.miss,
          ),
        );
      }
      if (!mounted) return;
      context.go('${TournamentRoutes.detail}/${targetId.value}');
    } on StructureLockedException {
      // V2-B2: live edit rejected because it would alter a running phase.
      // Show the rule-specific German message, not the raw error.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tournamentEditStructureLocked),
          backgroundColor: KubbTokens.miss,
        ),
      );
    } on TournamentLockedException {
      // V2-B2: tournament is finalized/aborted — no longer editable.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tournamentEditTournamentLocked),
          backgroundColor: KubbTokens.miss,
        ),
      );
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

  /// Sends one `tournament_invite_user` call per picked invitee for an
  /// invite-only Spaßturnier. Each call is guarded independently so a single
  /// failure (e.g. a user that vanished) does not abort the rest; returns the
  /// number of invitations that failed so the caller can hint at it. A no-op
  /// (returns 0) when the tournament is not invite-only or has a club.
  Future<int> _sendInvites(
    TournamentId tournamentId,
    TournamentConfigDraft draft,
  ) async {
    if (draft.clubId != null || !draft.inviteOnly) return 0;
    final remote = ref.read(tournamentRemoteProvider);
    var failures = 0;
    for (final invitee in draft.invitedUsers) {
      try {
        await remote.inviteUser(tournamentId, UserId(invitee.userId));
      } on Object {
        // Tolerate per-invitee failures — the tournament itself is already
        // created; the organizer can re-invite from the detail screen later.
        failures++;
      }
    }
    return failures;
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
        // Title hierarchy (P6_SETUP_WIZARD_SPEC.md): the step name is the
        // large/bold title; "Neues Turnier" (resp. the edit variant) is the
        // small eyebrow above it.
        title: stepTitle,
        eyebrow: widget.editId != null
            ? l10n.tournamentWizardEditTitle
            : l10n.tournamentWizardTitle,
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
          onMax: controller.setMaxParticipants,
          onTeamSize: controller.setTeamSize,
          onMaxTeamSize: controller.setMaxTeamSize,
        );
      case _StepKind.format:
        return _StepFormat(
          draft: draft,
          controller: controller,
          koBracketSize: _koBracketSize(draft),
          onVorrundeType: controller.setVorrundeType,
          onKoType: controller.setKoType,
          onSetsToWin: controller.setSetsToWin,
          onMaxSets: controller.setMaxSets,
          onPoolGrouping: controller.setPoolGrouping,
          swissRounds: _swissRounds ??
              SwissConfigSection.defaultRounds(draft.maxParticipants),
          onSwissRoundsChanged: (v) => setState(() => _swissRounds = v),
          onPitchPlanChanged: controller.setPitchPlan,
          onRoundTime: controller.setRoundTime,
          onBreakBetween: controller.setBreakBetweenMatchesSeconds,
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
          // K01: leave room for the auto-appended " 2026" suffix (+5 chars)
          // so it never gets clipped by the input length limit.
          maxLength: TournamentConfigDraft.displayNameMaxChars + 5,
          onChanged: controller.setDisplayName,
        ),
        const SizedBox(height: KubbTokens.space1half),
        _HelperText(l10n.tournamentWizardDisplayNameYearHint),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardClubLabel),
        const SizedBox(height: KubbTokens.space2),
        _ClubPickerField(
          selectedClubId: draft.clubId,
          choiceMade: draft.clubChoiceMade,
          onChanged: controller.setClubId,
        ),
        const SizedBox(height: KubbTokens.space1half),
        _HelperText(l10n.tournamentWizardClubHint),
        // League is global (across clubs). The league chips only appear once a
        // club is chosen as host — a personal tournament (clubId == null) is
        // never league-relevant (P6_SETUP_WIZARD_SPEC.md Screen 1). The
        // organiser actively picks the league via these chips.
        if (draft.clubId != null) ...[
          const SizedBox(height: KubbTokens.space5),
          // K29: league categories are required once a club is chosen.
          _FieldLabel(l10n.tournamentWizardLeagueCategoriesLabel),
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
        ],
        // Spaßturnier "auf Einladung": only a personal tournament (no club)
        // can be invite-only — a club tournament is a rated league event. The
        // toggle + player picker therefore appear solely when clubId == null
        // (P6 invite SPEC §3).
        if (draft.clubId == null) ...[
          const SizedBox(height: KubbTokens.space5),
          _ToggleRow(
            key: const Key('wizardInviteOnlyToggle'),
            title: l10n.tournamentWizardInviteOnlyLabel,
            subtitle: l10n.tournamentWizardInviteOnlyHint,
            value: draft.inviteOnly,
            onChanged: controller.setInviteOnly,
          ),
          if (draft.inviteOnly) ...[
            const SizedBox(height: KubbTokens.space2),
            _InviteOnlySection(
              invitedUsers: draft.invitedUsers,
              onAdd: controller.addInvitee,
              onRemove: controller.removeInvitee,
            ),
          ],
        ],
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardLocationLabel),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _locationCtrl,
          hintText: l10n.tournamentWizardLocationHint,
          onChanged: controller.setLocation,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardVenueAddressLabel),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _addressCtrl,
          hintText: l10n.tournamentWizardVenueAddressHint,
          onChanged: controller.setVenueAddress,
        ),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardEventDateLabel),
        const SizedBox(height: KubbTokens.space2),
        _DateField(
          value: draft.eventStartsAt,
          onTap: () => _pickDateTime(
            initial: draft.eventStartsAt,
            onPicked: controller.setEventStartsAt,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardRegistrationDeadlineLabel),
        const SizedBox(height: KubbTokens.space2),
        _DateField(
          value: draft.registrationClosesAt,
          onTap: () => _pickDateTime(
            initial: draft.registrationClosesAt,
            onPicked: controller.setRegistrationClosesAt,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        _FieldLabel(l10n.tournamentWizardCheckinUntilLabel),
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
        // K06: surface the opening rule (Anspielregel). Default stays
        // '2-4-6'; the segmented control writes the choice via
        // setRuleVariants so the value is no longer invisible in the wizard.
        const SizedBox(height: KubbTokens.space2),
        _FieldLabel(l10n.tournamentWizardRuleOpeningLabel),
        const SizedBox(height: KubbTokens.space2),
        SegmentedButton<String>(
          key: const Key('wizardOpeningRule'),
          showSelectedIcon: false,
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(
              value: '2-4-6',
              label: Text(l10n.tournamentWizardRuleOpening246),
            ),
            ButtonSegment<String>(
              value: 'free',
              label: Text(l10n.tournamentWizardRuleOpeningFree),
            ),
          ],
          selected: <String>{
            if (draft.ruleVariants.openingRule == 'free') 'free' else '2-4-6',
          },
          onSelectionChanged: (sel) => controller.setRuleVariants(
            draft.ruleVariants.copyWith(openingRule: sel.first),
          ),
        ),
        const SizedBox(height: KubbTokens.space1half),
        _HelperText(l10n.tournamentWizardRuleOpeningHint),
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
          // K07: allow up to 5 lines for the participant info free-text.
          minLines: 3,
          maxLines: 5,
          onChanged: controller.setInfoFood,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardInfoTravelLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _travelCtrl,
          // K07: allow up to 5 lines for the participant info free-text.
          minLines: 3,
          maxLines: 5,
          onChanged: controller.setInfoTravel,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardInfoAccommodationLabel,
            optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _accommodationCtrl,
          // K07: allow up to 5 lines for the participant info free-text.
          minLines: 3,
          maxLines: 5,
          onChanged: controller.setInfoAccommodation,
        ),
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardWeatherLabel, optional: true),
        const SizedBox(height: KubbTokens.space2),
        _PlainTextField(
          controller: _weatherCtrl,
          // K07: allow up to 5 lines for the participant info free-text.
          minLines: 3,
          maxLines: 5,
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
    super.key,
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
    this.minLines,
    this.keyboardType,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
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
      minLines: minLines,
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
    required this.choiceMade,
    required this.onChanged,
  });

  final String? selectedClubId;

  /// K03: whether the organizer has actively made the club choice. While
  /// `false` the dropdown shows a "bitte wählen" hint and no value is
  /// pre-selected, so "Spasstournier" is never an implicit default.
  final bool choiceMade;
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
    // K03: until the organizer actively chooses, no value is selected and a
    // "bitte wählen" hint shows — the null `clubId` (Spasstournier) must be
    // an explicit pick, not an implicit default.
    return DropdownButtonFormField<String?>(
      key: const Key('wizardClubPicker'),
      initialValue: choiceMade ? value : null,
      isExpanded: true,
      hint: Text(l10n.tournamentWizardClubChoosePrompt),
      decoration: InputDecoration(
        border: border,
        enabledBorder: border,
      ),
      items: <DropdownMenuItem<String?>>[
        // K02/K03: this item carries the implicit null value = the
        // "Spasstournier – ohne Wertung" choice. It is the only null-valued
        // item (every club below has a non-null id), so the picker maps a null
        // selection unambiguously to Spasstournier.
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

/// Player picker for an invite-only Spaßturnier. Debounced directory search
/// (`friendSearchProvider`, ≥2 chars / 250 ms — mirrors
/// `team_add_player_screen`) feeds a tappable result list; chosen players show
/// as removable chips. Selection state lives in the draft (the parent passes
/// [invitedUsers] + [onAdd]/[onRemove]); this widget only holds the transient
/// query.
class _InviteOnlySection extends ConsumerStatefulWidget {
  const _InviteOnlySection({
    required this.invitedUsers,
    required this.onAdd,
    required this.onRemove,
  });

  final List<InvitedUser> invitedUsers;
  final void Function(InvitedUser) onAdd;
  final void Function(String userId) onRemove;

  @override
  ConsumerState<_InviteOnlySection> createState() => _InviteOnlySectionState();
}

class _InviteOnlySectionState extends ConsumerState<_InviteOnlySection> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final results = ref.watch(friendSearchProvider(_query));
    final invitedIds =
        widget.invitedUsers.map((u) => u.userId).toSet();

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('wizardInviteSearchField'),
          controller: _queryCtrl,
          autocorrect: false,
          onChanged: _onChanged,
          decoration: InputDecoration(
            counterText: '',
            hintText: l10n.tournamentWizardInviteSearchHint,
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            border: border,
            enabledBorder: border,
          ),
        ),
        // Already-invited players as removable chips.
        if (widget.invitedUsers.isNotEmpty) ...[
          const SizedBox(height: KubbTokens.space2),
          Wrap(
            spacing: KubbTokens.space2,
            runSpacing: KubbTokens.space2,
            children: [
              for (final u in widget.invitedUsers)
                InputChip(
                  label: Text(u.nickname),
                  onDeleted: () => widget.onRemove(u.userId),
                  // No oversized deleteIconBoxConstraints here: forcing the
                  // delete-icon box taller than the chip breaks the chip's
                  // internal centerLayout. The chip keeps its default hit area.
                  deleteButtonTooltipMessage:
                      l10n.tournamentWizardInviteRemoveTooltip,
                ),
            ],
          ),
        ],
        // Search results (only once the query is long enough).
        if (_query.length >= 2) ...[
          const SizedBox(height: KubbTokens.space2),
          results.when(
            data: (list) {
              if (list.isEmpty) {
                return _HelperText(
                  l10n.tournamentWizardInviteNoResults(_query),
                );
              }
              return Column(
                children: [
                  for (final c in list)
                    _InviteCandidateRow(
                      nickname: c.nickname,
                      alreadyInvited: invitedIds.contains(c.userId),
                      onAdd: () => widget.onAdd(
                        InvitedUser(userId: c.userId, nickname: c.nickname),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(KubbTokens.space3),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _HelperText(
              l10n.tournamentWizardInviteSearchError(e.toString()),
            ),
          ),
        ],
      ],
    );
  }
}

/// One search-result row in the invite picker. Mirrors the team add-player
/// candidate row: avatar initial + nickname + an "Einladen" action that flips
/// to a done-state once the player is on the invite list.
class _InviteCandidateRow extends StatelessWidget {
  const _InviteCandidateRow({
    required this.nickname,
    required this.alreadyInvited,
    required this.onAdd,
  });

  final String nickname;
  final bool alreadyInvited;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final initial = nickname.isEmpty ? '?' : nickname[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space3,
          vertical: KubbTokens.space2,
        ),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          border: Border.all(color: tokens.line),
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: KubbTokens.meadow600,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Text(
                nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tokens.fg,
                ),
              ),
            ),
            if (alreadyInvited)
              Icon(LucideIcons.check, size: 20, color: tokens.primary)
            else
              FilledButton(
                onPressed: onAdd,
                // Design-System: keep the tap target >= 48dp (touch-min).
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KubbTokens.touchMin),
                ),
                child: Text(l10n.tournamentWizardInviteAddAction),
              ),
          ],
        ),
      ),
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
    required this.onMax,
    required this.onTeamSize,
    required this.onMaxTeamSize,
  });

  final TournamentConfigDraft draft;
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
        // K09: the minimum-participant field was removed. K10: the maximum may
        // be configured up to participantsHardMax (1000).
        WizardNumberField(
          label: l10n.tournamentWizardMaxParticipantsLabel,
          value: draft.maxParticipants,
          min: 2,
          max: TournamentConfigDraft.participantsHardMax,
          onChanged: onMax,
        ),
      ],
    );
  }
}

class _StepFormat extends StatefulWidget {
  const _StepFormat({
    required this.draft,
    required this.controller,
    required this.koBracketSize,
    required this.onVorrundeType,
    required this.onKoType,
    required this.onSetsToWin,
    required this.onMaxSets,
    required this.onPoolGrouping,
    required this.swissRounds,
    required this.onSwissRoundsChanged,
    required this.onPitchPlanChanged,
    required this.onRoundTime,
    required this.onBreakBetween,
  });

  /// K12: group-count bounds for the inline group-phase config.
  static const int groupCountMin = 2;
  static const int groupCountMax = 16;

  final TournamentConfigDraft draft;
  final TournamentConfigController controller;

  /// KO bracket size (power of two) implied by the current KO config. Basis
  /// for the read-only "Qualifier pro Gruppe" value derived inline (K12).
  /// 0 until a valid KO size is chosen (the KO step follows this one).
  final int koBracketSize;
  // Two-axis format selection: Vorrunde (group phase vs Schoch) and KO
  // system (single-out / double-elimination / consolation). The controller
  // derives the legacy `TournamentFormat` + `BracketType` from these axes.
  final ValueChanged<VorrundeType> onVorrundeType;
  final ValueChanged<KoType> onKoType;
  // V2: prelim "sets to win". Maps onto the existing controller.setSetsToWin
  // (no duplicated clamp logic in the widget).
  final ValueChanged<int> onSetsToWin;
  final ValueChanged<int> onMaxSets;

  /// K12: pushes the group-phase grouping inputs (group count + strategy +
  /// optional random seed) gathered inline in this step.
  final void Function({
    required int groupCount,
    required PoolGroupingStrategy strategy,
    int? randomSeed,
  }) onPoolGrouping;
  // T10: Swiss-System round count — surfaced inline when the Vorrunde is
  // Schoch. State lives in the wizard.
  final int swissRounds;
  final ValueChanged<int> onSwissRoundsChanged;
  final ValueChanged<PitchPlan?> onPitchPlanChanged;
  final ValueChanged<int> onRoundTime;
  final ValueChanged<int> onBreakBetween;

  @override
  State<_StepFormat> createState() => _StepFormatState();
}

class _StepFormatState extends State<_StepFormat> {
  late final TextEditingController _groupCountCtrl;
  late final TextEditingController _seedCtrl;

  @override
  void initState() {
    super.initState();
    final pool = widget.draft.poolPhaseConfig;
    _groupCountCtrl = TextEditingController(
      text: '${pool?.groupCount ?? 4}',
    );
    _seedCtrl = TextEditingController(text: pool?.randomSeed?.toString() ?? '');
  }

  @override
  void dispose() {
    _groupCountCtrl.dispose();
    _seedCtrl.dispose();
    super.dispose();
  }

  /// Current grouping strategy (defaults to snake before the organiser picks).
  PoolGroupingStrategy get _strategy =>
      widget.draft.poolPhaseConfig?.strategy ?? PoolGroupingStrategy.snake;

  int get _groupCount => widget.draft.poolPhaseConfig?.groupCount ?? 0;

  bool get _groupCountValid =>
      _groupCount >= _StepFormat.groupCountMin &&
      _groupCount <= _StepFormat.groupCountMax;

  /// Whether the chosen group count evenly divides the KO bracket size. When
  /// the KO size is not yet known (0) the check is deferred to the KO step.
  bool get _divisible =>
      widget.koBracketSize <= 0 ||
      widget.koBracketSize % _groupCount == 0;

  /// Qualifier-per-group derived read-only as koBracketSize / groupCount.
  int get _derivedQualifiersPerGroup {
    if (!_groupCountValid ||
        widget.koBracketSize <= 0 ||
        widget.koBracketSize % _groupCount != 0) {
      return 0;
    }
    return widget.koBracketSize ~/ _groupCount;
  }

  void _onGroupsTyped(String raw) {
    final value = int.tryParse(raw.trim()) ?? 0;
    widget.onPoolGrouping(
      groupCount: value,
      strategy: _strategy,
      randomSeed: _randomSeed(),
    );
  }

  void _onStrategyChanged(PoolGroupingStrategy? next) {
    if (next == null) return;
    widget.onPoolGrouping(
      groupCount: _groupCount,
      strategy: next,
      randomSeed: _randomSeed(),
    );
  }

  void _onSeedTyped(String raw) {
    final trimmed = raw.trim();
    widget.onPoolGrouping(
      groupCount: _groupCount,
      strategy: _strategy,
      randomSeed: trimmed.isEmpty ? null : int.tryParse(trimmed),
    );
  }

  int? _randomSeed() {
    final t = _seedCtrl.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  /// Group label for index 0..n: 'A', 'B', 'C', …
  static String _groupLabel(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);

  /// K23/K24: toggles [pitch] in the assignment list of group [label] and
  /// pushes the updated pitch plan. A pitch may serve several groups, so this
  /// only flips the one group.
  void _togglePitchForGroup(PitchPlan plan, String label, int pitch) {
    final next = <String, List<int>>{
      for (final entry in plan.groupAssignment.entries)
        entry.key: List<int>.of(entry.value),
    };
    final current = next.putIfAbsent(label, () => <int>[]);
    if (current.contains(pitch)) {
      current.remove(pitch);
    } else {
      current
        ..add(pitch)
        ..sort();
    }
    if (current.isEmpty) next.remove(label);
    widget.onPitchPlanChanged(plan.copyWith(groupAssignment: next));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final draft = widget.draft;
    final onVorrundeType = widget.onVorrundeType;
    final onKoType = widget.onKoType;
    final onSetsToWin = widget.onSetsToWin;
    final onMaxSets = widget.onMaxSets;
    final onRoundTime = widget.onRoundTime;
    final onBreakBetween = widget.onBreakBetween;
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
            rounds: widget.swissRounds,
            onRoundsChanged: widget.onSwissRoundsChanged,
          ),
        // K12: group-phase config (group count + grouping strategy) lives
        // inline here, only when the group phase is the selected Vorrunde.
        if (draft.vorrundeType == VorrundeType.groupPhase)
          ..._groupPhaseSection(tokens, l10n),
        const SizedBox(height: KubbTokens.space5),
        // ---- KO axis (Single-Out | Double-Elimination | Trostturnier) ----
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tournamentWizardKoSystemLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: tokens.fgMuted,
                ),
              ),
            ),
            // Info icon opens the KO-model explainer sheet. >=48dp touch
            // target per --bk-touch-min (Design-System).
            IconButton(
              icon: Icon(
                LucideIcons.info,
                size: 18,
                color: tokens.fgMuted,
              ),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: EdgeInsets.zero,
              tooltip: l10n.tournamentKoModelExplainerOpen,
              onPressed: () => KoModelExplainerSheet.show(context),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space2),
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
        _OptionRow(
          selected: draft.koType == KoType.consolation,
          label: l10n.tournamentWizardKoSystemConsolation,
          description: l10n.tournamentWizardKoSystemConsolationHint,
          onTap: () => onKoType(KoType.consolation),
        ),
        // K15: the Model-B (Trostturnier) config — main-bracket size, direct
        // starters and the (required) name — lives ENTIRELY in the KO step now
        // (_wizard_ko_config_step.dart, _ConsolationKoSection). It is no longer
        // rendered here, so the main-bracket size is chosen exactly once.
        const SizedBox(height: KubbTokens.space5),
        // ---- Vorrunde scoring: "Sätze zum Sieg" + "Max. Sätze" (V2 spec) ----
        // The prelim sets-to-win field. onChanged maps onto the existing
        // controller.setSetsToWin, which auto-clamps maxSets to >= 2*n-1, so
        // sets_to_win <= max_sets stays consistent without extra widget logic.
        WizardNumberField(
          label: l10n.tournamentWizardSetsToWinPrelimLabel,
          value: draft.setsToWin,
          min: TournamentConfigDraft.setsToWinMin,
          max: TournamentConfigDraft.setsToWinMax,
          onChanged: onSetsToWin,
        ),
        const SizedBox(height: KubbTokens.space4),
        WizardNumberField(
          label: l10n.tournamentWizardMaxSetsLabel,
          value: draft.maxSets,
          min: TournamentConfigDraft.maxSetsMin,
          max: TournamentConfigDraft.maxSetsMax,
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
          onChanged: widget.onPitchPlanChanged,
        ),
        // K23/K24: per-group pitch assignment lives in the pitch context, gated
        // on group phase + a pitch plan with available pitches.
        if (draft.vorrundeType == VorrundeType.groupPhase)
          ..._pitchAssignmentSection(tokens, l10n),
      ],
    );
  }

  /// K12: inline group-phase config — group count + grouping strategy +
  /// optional random seed + read-only derived "Qualifier pro Gruppe".
  List<Widget> _groupPhaseSection(KubbTokens tokens, AppLocalizations l10n) {
    final divisibilityError = (!_divisible && widget.koBracketSize > 0)
        ? l10n.tournamentWizardPoolDivisibilityError(widget.koBracketSize)
        : null;
    return <Widget>[
      const SizedBox(height: KubbTokens.space4),
      _FieldLabel(l10n.tournamentWizardPoolGroupCountLabel),
      const SizedBox(height: KubbTokens.space2),
      TextField(
        key: const Key('wizardGroupCountField'),
        controller: _groupCountCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: _onGroupsTyped,
        decoration: _outlineDecoration(tokens).copyWith(
          counterText: '',
          errorText: !_groupCountValid
              ? l10n.tournamentWizardPoolGroupCountRangeError(
                  _StepFormat.groupCountMin,
                  _StepFormat.groupCountMax,
                )
              : divisibilityError,
        ),
      ),
      const SizedBox(height: KubbTokens.space4),
      // Qualifier-per-group is derived read-only from koBracketSize / groupCount
      // (K12 — not an input). The KO step follows this one, so it shows "—"
      // until the KO size is chosen.
      _FieldLabel(l10n.tournamentWizardPoolQualifiersPerGroupLabel),
      const SizedBox(height: KubbTokens.space2),
      _DerivedValueBox(
        tokens: tokens,
        value: _derivedQualifiersPerGroup > 0
            ? '$_derivedQualifiersPerGroup'
            : '—',
      ),
      const SizedBox(height: KubbTokens.space4),
      _FieldLabel(l10n.tournamentWizardPoolStrategyLabel),
      const SizedBox(height: KubbTokens.space2),
      DropdownButtonFormField<PoolGroupingStrategy>(
        key: const Key('wizardGroupStrategyField'),
        initialValue: _strategy,
        onChanged: _onStrategyChanged,
        decoration: _outlineDecoration(tokens),
        items: [
          DropdownMenuItem(
            value: PoolGroupingStrategy.snake,
            child: Text(l10n.tournamentWizardPoolStrategySnake),
          ),
          DropdownMenuItem(
            value: PoolGroupingStrategy.seeded,
            child: Text(l10n.tournamentWizardPoolStrategySeeded),
          ),
          DropdownMenuItem(
            value: PoolGroupingStrategy.random,
            child: Text(l10n.tournamentWizardPoolStrategyRandom),
          ),
        ],
      ),
      if (_strategy == PoolGroupingStrategy.random) ...[
        const SizedBox(height: KubbTokens.space4),
        _FieldLabel(l10n.tournamentWizardPoolRandomSeedLabel),
        const SizedBox(height: KubbTokens.space2),
        TextField(
          key: const Key('wizardGroupRandomSeedField'),
          controller: _seedCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: _onSeedTyped,
          decoration: _outlineDecoration(tokens).copyWith(counterText: ''),
        ),
      ],
    ];
  }

  /// K23/K24: "Pitch-Zuteilung pro Gruppe" — rendered in the pitch context
  /// only when a pitch plan with available pitches exists and the group count
  /// is valid. For each group label (A, B, …) the organiser multi-selects
  /// which pitch numbers serve that group.
  List<Widget> _pitchAssignmentSection(
    KubbTokens tokens,
    AppLocalizations l10n,
  ) {
    final plan = widget.draft.pitchPlan;
    if (plan == null || !_groupCountValid) return const <Widget>[];
    final pitches = plan.availablePitches();
    if (pitches.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: KubbTokens.space6),
      _FieldLabel(l10n.tournamentWizardPoolPitchAssignmentLabel),
      const SizedBox(height: KubbTokens.space2),
      _HelperText(l10n.tournamentWizardPoolPitchAssignmentHint),
      const SizedBox(height: KubbTokens.space3),
      for (var g = 0; g < _groupCount; g++) ...[
        if (g > 0) const SizedBox(height: KubbTokens.space4),
        Builder(
          builder: (context) {
            final label = _groupLabel(g);
            final assigned = plan.groupAssignment[label] ?? const <int>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tournamentWizardPoolGroupLabel(label),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: KubbTokens.space2),
                Wrap(
                  spacing: KubbTokens.space2,
                  runSpacing: KubbTokens.space2,
                  children: [
                    for (final pitch in pitches)
                      _SelectChip(
                        label: '$pitch',
                        selected: assigned.contains(pitch),
                        onTap: () => _togglePitchForGroup(plan, label, pitch),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    ];
  }

  InputDecoration _outlineDecoration(KubbTokens tokens) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
    );
    return InputDecoration(border: border, enabledBorder: border);
  }
}

/// Read-only display box for a derived value (e.g. qualifier-per-group),
/// styled like a disabled outline field so it reads as non-editable (K12).
class _DerivedValueBox extends StatelessWidget {
  const _DerivedValueBox({required this.tokens, required this.value});

  final KubbTokens tokens;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: tokens.fg,
        ),
      ),
    );
  }
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

/// Final wizard step (K26): a full read-only review of EVERYTHING the
/// organizer configured, grouped by the wizard steps (Stammdaten /
/// Teilnehmer / Vorrunde / K.-o.). Optional/empty fields render a clear
/// "—" placeholder rather than blank or `null`. When the draft does not
/// validate, the concrete validation issues are surfaced PROMINENTLY in
/// `tokens.miss` (ERR-1) so the organizer sees WHY the "Anlegen" button is
/// blocked; the gate itself stays in `_stepValid` / `_BottomBar` (ERR-3).
class _StepSummary extends ConsumerWidget {
  const _StepSummary({required this.draft});

  final TournamentConfigDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final validation = draft.validate();
    final placeholder = l10n.tournamentWizardSummaryPlaceholder;
    // Resolve the chosen club's display name from the same provider the
    // picker uses, so the summary shows WHICH club was selected (not the
    // field label). While the list loads/errors we fall back to the id.
    final clubs = ref.watch(manageableClubsProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <ManageableClub>[],
        );

    // -- text helpers (placeholder mapping for null/empty/optional) --------
    String text(String? value) {
      final v = value?.trim() ?? '';
      return v.isEmpty ? placeholder : v;
    }

    String dateText(DateTime? value) {
      if (value == null) return placeholder;
      return '${materialL10n.formatMediumDate(value)} · '
          '${TimeOfDay.fromDateTime(value).format(context)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ERR-1: the issue list is rendered first (prominently) whenever the
        // draft is invalid, so the organizer immediately sees the blockers.
        if (!validation.isValid) ...[
          _SummaryErrorBox(issues: validation.issues),
          const SizedBox(height: KubbTokens.space4),
        ],
        _SummarySection(
          title: l10n.tournamentWizardSummarySectionStammdaten,
          rows: <_SummaryRowData>[
            // K26-1: name with the auto-appended year (resolvedDisplayName).
            _SummaryRowData(
              l10n.tournamentWizardDisplayNameLabel,
              text(draft.resolvedDisplayName),
            ),
            // Verein OR Spasstournier (clubId == null && choice made).
            _SummaryRowData(
              l10n.tournamentWizardClubLabel,
              _clubText(l10n, placeholder, clubs),
            ),
            // Liga-Kategorien only when a club is chosen.
            if (draft.clubId != null)
              _SummaryRowData(
                l10n.tournamentWizardLeagueCategoriesLabel,
                draft.leagueCategories.isEmpty
                    ? placeholder
                    : draft.leagueCategories.map((c) => c.wire).join(', '),
              ),
            _SummaryRowData(
              l10n.tournamentWizardLocationLabel,
              text(draft.location),
            ),
            _SummaryRowData(
              l10n.tournamentWizardVenueAddressLabel,
              text(draft.venueAddress),
            ),
            _SummaryRowData(
              l10n.tournamentWizardEventDateLabel,
              dateText(draft.eventStartsAt),
            ),
            _SummaryRowData(
              l10n.tournamentWizardRegistrationDeadlineLabel,
              dateText(draft.registrationClosesAt),
            ),
            _SummaryRowData(
              l10n.tournamentWizardCheckinUntilLabel,
              dateText(draft.checkinUntil),
            ),
            _SummaryRowData(
              l10n.tournamentWizardEntryFeeLabel,
              _feeText(l10n),
            ),
            _SummaryRowData(
              l10n.tournamentWizardPaymentMethodsLabel,
              draft.paymentMethods.isEmpty
                  ? placeholder
                  : draft.paymentMethods.join(', '),
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryContactLabel,
              _contactText(placeholder),
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryInfoLabel,
              _infoText(l10n, placeholder),
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryPdfRulesLabel,
              draft.rulesPdfUrl != null
                  ? l10n.tournamentWizardSummaryYes
                  : l10n.tournamentWizardSummaryNo,
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryPdfSiteMapLabel,
              draft.siteMapPdfUrl != null
                  ? l10n.tournamentWizardSummaryYes
                  : l10n.tournamentWizardSummaryNo,
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryRulesLabel,
              _rulesText(l10n),
            ),
            _SummaryRowData(
              l10n.tournamentWizardScoringLabel,
              draft.scoring == 'classic'
                  ? l10n.tournamentWizardSummaryScoringClassic
                  : l10n.tournamentWizardSummaryScoringEkc,
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space4),
        // K26-2: participants step.
        _SummarySection(
          title: l10n.tournamentWizardSummarySectionParticipants,
          rows: <_SummaryRowData>[
            _SummaryRowData(
              l10n.tournamentWizardMaxParticipantsLabel,
              '${draft.maxParticipants}',
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryTeamSizeLabel,
              draft.teamSize == draft.maxTeamSize
                  ? l10n.tournamentWizardSummaryTeamSizeFixed(draft.teamSize)
                  : l10n.tournamentWizardSummaryTeamSizeRange(
                      draft.maxTeamSize,
                      draft.teamSize,
                    ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space4),
        // K26-3: prelim (Vorrunde) step.
        _SummarySection(
          title: l10n.tournamentWizardSummarySectionVorrunde,
          rows: <_SummaryRowData>[
            _SummaryRowData(
              l10n.tournamentWizardSummaryFormatLabel,
              draft.vorrundeType == VorrundeType.schoch
                  ? l10n.tournamentWizardVorrundeSchoch
                  : l10n.tournamentWizardVorrundeGroupPhase,
            ),
            // Group count + grouping strategy only for the group phase.
            if (draft.vorrundeType == VorrundeType.groupPhase) ...[
              _SummaryRowData(
                l10n.tournamentWizardPoolGroupCountLabel,
                draft.poolPhaseConfig == null
                    ? placeholder
                    : '${draft.poolPhaseConfig!.groupCount}',
              ),
              _SummaryRowData(
                l10n.tournamentWizardPoolStrategyLabel,
                _strategyText(l10n, placeholder),
              ),
            ],
            _SummaryRowData(
              l10n.tournamentWizardMaxSetsLabel,
              '${draft.maxSets}',
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryMatchTimeLabel,
              '${(draft.roundTimeSeconds / 60).round()}',
            ),
            _SummaryRowData(
              l10n.tournamentWizardBreakBetweenLabel,
              '${(draft.breakBetweenMatchesSeconds / 60).round()}',
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryPitchesLabel,
              _pitchText(placeholder),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space4),
        // K26-4: KO step.
        _SummarySection(
          title: l10n.tournamentWizardSummarySectionKo,
          rows: <_SummaryRowData>[
            _SummaryRowData(
              l10n.tournamentWizardSummaryKoTypeLabel,
              _koTypeText(l10n),
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryKoSizeLabel,
              (draft.koConfig?.qualifierCount ?? 0) >= 2
                  ? '${draft.koConfig!.qualifierCount}'
                  : placeholder,
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummaryKoRoundsLabel,
              _koRoundsText(l10n, placeholder),
            ),
            _SummaryRowData(
              l10n.tournamentWizardSummarySeedingLabel,
              (draft.bracketSeedingMode ?? SeedingMode.auto) ==
                      SeedingMode.manual
                  ? l10n.tournamentWizardSummarySeedingManual
                  : l10n.tournamentWizardSummarySeedingAuto,
            ),
            _SummaryRowData(
              l10n.tournamentWizardKoMatchupLabel,
              draft.koMatchup == KoMatchup.oneVsTwo
                  ? l10n.tournamentWizardKoMatchupOneTwo
                  : l10n.tournamentWizardKoMatchupHighLow,
            ),
            _SummaryRowData(
              l10n.tournamentWizardKoTiebreakMethodLabel,
              draft.koTiebreakMethod ==
                      KoTiebreakMethod.mightyFinisherShootout
                  ? l10n.tournamentWizardKoTiebreakMighty
                  : l10n.tournamentWizardKoTiebreakClassic,
            ),
            // Consolation-only: name + direct-starter count.
            if (draft.koType == KoType.consolation) ...[
              _SummaryRowData(
                l10n.tournamentWizardConsolationNameLabel,
                text(draft.consolationName),
              ),
              _SummaryRowData(
                l10n.tournamentWizardSummaryConsolationDirectLabel,
                draft.consolationDirectCount <= 0
                    ? l10n.tournamentWizardConsolationDirectCountNone
                    : '${draft.consolationDirectCount}',
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Verein name when a club is chosen, otherwise the "Spasstournier – ohne
  /// Wertung" label (clubId == null after an explicit choice). Falls back to
  /// the placeholder while no choice was made yet.
  String _clubText(
    AppLocalizations l10n,
    String placeholder,
    List<ManageableClub> clubs,
  ) {
    if (draft.clubId == null) {
      return draft.clubChoiceMade
          ? l10n.tournamentWizardClubNone
          : placeholder;
    }
    // Resolve the chosen club's display name from the manageable-clubs list
    // (the draft only holds the opaque club_id). Fall back to the raw id if
    // the list has not resolved the club, so the value is never the field
    // label and always tells the organizer WHICH club was picked.
    for (final c in clubs) {
      if (c.id == draft.clubId) return c.name;
    }
    return draft.clubId!;
  }

  /// Entry fee as `amount currency`, "Gratis" for a free tournament.
  String _feeText(AppLocalizations l10n) {
    final cents = draft.entryFeeCents;
    if (cents == null || cents == 0) {
      return l10n.tournamentWizardSummaryFeeFree;
    }
    final amount =
        cents % 100 == 0 ? '${cents ~/ 100}' : (cents / 100).toStringAsFixed(2);
    return l10n.tournamentWizardSummaryFee(amount, draft.currency);
  }

  /// Contact `name · phone`; placeholder when both are empty.
  String _contactText(String placeholder) {
    final name = draft.contactName?.trim() ?? '';
    final phone = draft.contactPhone?.trim() ?? '';
    final parts = <String>[
      if (name.isNotEmpty) name,
      if (phone.isNotEmpty) phone,
    ];
    return parts.isEmpty ? placeholder : parts.join(' · ');
  }

  /// Count of the four info free-text blocks that carry content.
  String _infoText(AppLocalizations l10n, String placeholder) {
    final filled = <String?>[
      draft.weatherNote,
      draft.infoFood,
      draft.infoTravel,
      draft.infoAccommodation,
    ].where((s) => s?.trim().isNotEmpty ?? false).length;
    return filled == 0
        ? placeholder
        : l10n.tournamentWizardSummaryInfoCount(filled);
  }

  /// Active rule variants as a short comma list (Diggy/Sureshot/Strafkubb +
  /// the opening rule); "Keine Sonderregeln" when nothing is on.
  String _rulesText(AppLocalizations l10n) {
    final rv = draft.ruleVariants;
    // Opening rule is always shown (it always has a value, default 2-4-6).
    final opening = rv.openingRule == 'free'
        ? l10n.tournamentWizardRuleOpeningFree
        : l10n.tournamentWizardRuleOpening246;
    final parts = <String>[
      if (rv.diggy) l10n.tournamentWizardRuleDiggy,
      if (rv.sureshot) l10n.tournamentWizardRuleSureshot,
      if (rv.strafkubbOffBaseline) l10n.tournamentWizardRuleStrafkubb,
      opening,
    ];
    return parts.isEmpty
        ? l10n.tournamentWizardSummaryRulesNone
        : parts.join(', ');
  }

  String _strategyText(AppLocalizations l10n, String placeholder) {
    final strategy = draft.poolPhaseConfig?.strategy;
    return switch (strategy) {
      PoolGroupingStrategy.snake => l10n.tournamentWizardPoolStrategySnake,
      PoolGroupingStrategy.seeded => l10n.tournamentWizardPoolStrategySeeded,
      PoolGroupingStrategy.random => l10n.tournamentWizardPoolStrategyRandom,
      null => placeholder,
    };
  }

  String _pitchText(String placeholder) {
    final plan = draft.pitchPlan;
    if (plan == null) return placeholder;
    final count = plan.availablePitches().length;
    return count == 0 ? placeholder : '$count';
  }

  /// K26-4: a real short form of the per-round KO rules — one "best-of"
  /// chip per round (e.g. "R1: Bo3 · R2: Bo5"), where the best-of count is
  /// the round's max sets. Empty list → placeholder.
  String _koRoundsText(AppLocalizations l10n, String placeholder) {
    final rounds = draft.koRoundFormats;
    if (rounds.isEmpty) return placeholder;
    final parts = <String>[
      for (var i = 0; i < rounds.length; i++)
        l10n.tournamentWizardSummaryKoRoundEntry(i + 1, rounds[i].maxSets),
    ];
    return parts.join(' · ');
  }

  String _koTypeText(AppLocalizations l10n) {
    return switch (draft.koType) {
      KoType.singleOut => l10n.tournamentWizardSummaryKoTypeSingle,
      KoType.doubleOut => l10n.tournamentWizardSummaryKoTypeDouble,
      KoType.consolation => l10n.tournamentWizardSummaryKoTypeConsolation,
    };
  }
}

/// Immutable (label, value) pair for one summary row.
class _SummaryRowData {
  const _SummaryRowData(this.label, this.value);
  final String label;
  final String value;
}

/// A titled card grouping one wizard step's review rows. Uses only
/// [KubbTokens] for colours / spacing / radii (K26-6).
class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.rows});

  final String title;
  final List<_SummaryRowData> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: KubbTokens.space1,
            bottom: KubbTokens.space2,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: tokens.fg,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(KubbTokens.space4),
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            border: Border.all(color: tokens.line, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++)
                _summaryRow(
                  tokens,
                  rows[i].label,
                  rows[i].value,
                  isLast: i == rows.length - 1,
                ),
            ],
          ),
        ),
      ],
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
          const SizedBox(width: KubbTokens.space3),
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

/// ERR-1: prominent validation-issue box shown in the summary step when the
/// draft does not validate. Rendered in `tokens.miss` so the organizer sees
/// exactly which fields block the "Anlegen" button.
class _SummaryErrorBox extends StatelessWidget {
  const _SummaryErrorBox({required this.issues});

  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // ERR-1: the spec requires tokens.miss for the issue list. `KubbTokens.miss`
    // is the shared danger accent (== tokens.danger); a low-opacity tint backs
    // the box so the red text stays legible on the wizard background.
    const miss = KubbTokens.miss;
    return Container(
      key: const Key('wizardSummaryErrorBox'),
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: miss.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: miss, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.alertTriangle, size: 18, color: miss),
              const SizedBox(width: KubbTokens.space2),
              Expanded(
                child: Text(
                  l10n.tournamentWizardSummaryErrorTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: miss,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: KubbTokens.space1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: miss,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      issue,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: miss,
                      ),
                    ),
                  ),
                ],
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

  /// Organiser-defined pitch order. Only written/emitted while
  /// [PitchSortStrategy.manual] is active; reset on switch to top-seeds.
  List<int> _order = const <int>[];

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _mode = p?.mode ?? PitchMode.range;
    _sort = p?.sortStrategy ?? PitchSortStrategy.topSeedsLowNumbers;
    _order = List<int>.of(p?.order ?? const <int>[]);
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

  /// Raw available pitch numbers for the current inputs, WITHOUT applying
  /// any manual `order` (used to seed/sync the reorder editor).
  List<int> _availablePitches() {
    if (_mode == PitchMode.range) {
      final from = _parseInt(_fromCtrl.text);
      final to = _parseInt(_toCtrl.text);
      if (from == null || to == null || from < 1 || to < from) {
        return const <int>[];
      }
      return <int>[for (var n = from; n <= to; n++) n];
    }
    return _parseNumbers(_numbersCtrl.text);
  }

  /// Effective manual order: keep stored entries that are still available
  /// (no stale numbers), then append any new available pitches. Returns an
  /// empty list when there is nothing to order yet.
  List<int> _effectiveOrder() {
    final available = _availablePitches();
    if (available.isEmpty) return const <int>[];
    final inOrder = _order.where(available.contains).toList();
    final rest = available.where((n) => !inOrder.contains(n));
    return <int>[...inOrder, ...rest];
  }

  /// Builds the plan from the current inputs (null when effectively empty).
  /// `order` is only carried while `PitchSortStrategy.manual` is active.
  PitchPlan? _currentPlan() {
    final manualOrder = _sort == PitchSortStrategy.manual
        ? _effectiveOrder()
        : const <int>[];
    if (_mode == PitchMode.range) {
      final from = _parseInt(_fromCtrl.text);
      final to = _parseInt(_toCtrl.text);
      if (from == null && to == null) return null;
      return PitchPlan(
        mode: PitchMode.range,
        rangeFrom: from,
        rangeTo: to,
        order: manualOrder,
        sortStrategy: _sort,
      );
    }
    final nums = _parseNumbers(_numbersCtrl.text);
    if (nums.isEmpty) return null;
    return PitchPlan(
      mode: PitchMode.manual,
      numbers: nums,
      order: manualOrder,
      sortStrategy: _sort,
    );
  }

  void _emit() => widget.onChanged(_currentPlan());

  void _onReorder(int oldIndex, int newIndex) {
    final items = _effectiveOrder();
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(target, moved);
    setState(() => _order = items);
    _emit();
  }

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
                setState(() {
                  _sort = PitchSortStrategy.topSeedsLowNumbers;
                  // Drop any stale manual order when leaving manual mode.
                  _order = const <int>[];
                });
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
        if (_sort == PitchSortStrategy.manual) ...[
          const SizedBox(height: KubbTokens.space4),
          _PitchOrderEditor(
            pitches: _effectiveOrder(),
            onReorder: _onReorder,
          ),
        ],
        if (count > 0) ...[
          const SizedBox(height: KubbTokens.space2),
          _HelperText(l10n.tournamentWizardPitchSummary(count)),
        ],
      ],
    );
  }
}

/// Drag-to-reorder editor for the manual pitch order. Renders the
/// available pitch numbers as a [ReorderableListView]; each row is a
/// >= 48 dp touch target with an explicit drag handle.
class _PitchOrderEditor extends StatelessWidget {
  const _PitchOrderEditor({required this.pitches, required this.onReorder});

  final List<int> pitches;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(l10n.tournamentWizardPitchOrderLabel),
        const SizedBox(height: KubbTokens.space2),
        _HelperText(l10n.tournamentWizardPitchOrderHint),
        if (pitches.isNotEmpty) ...[
          const SizedBox(height: KubbTokens.space3),
          ReorderableListView.builder(
            key: const Key('wizardPitchOrderEditor'),
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pitches.length,
            onReorder: onReorder,
            itemBuilder: (context, index) {
              final pitch = pitches[index];
              return Padding(
                key: ValueKey<int>(pitch),
                padding: const EdgeInsets.only(bottom: KubbTokens.space2),
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: KubbTokens.touchMin),
                  padding: const EdgeInsets.symmetric(
                    horizontal: KubbTokens.space3,
                    vertical: KubbTokens.space2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.bgRaised,
                    borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                    border: Border.all(color: tokens.line, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: KubbTokens.space6,
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: tokens.fgMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: KubbTokens.space2),
                      Expanded(
                        child: Text(
                          l10n.tournamentWizardPitchOrderItem(pitch),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: tokens.fg,
                          ),
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Container(
                          width: KubbTokens.touchMin,
                          height: KubbTokens.touchMin,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.drag_handle,
                            size: 20,
                            color: tokens.fgMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
