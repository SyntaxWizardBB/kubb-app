import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_binary_choice.dart';
import 'package:kubb_app/core/ui/widgets/kubb_field.dart';
import 'package:kubb_app/core/ui/widgets/kubb_select_chip.dart';
import 'package:kubb_app/core/ui/widgets/wizard_help.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/ko_model_explainer_sheet.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/ko_round_block.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Wizard KO-phase configuration step.
///
/// Power-of-two KO-size selector (no byes), seeding-source choice and the
/// per-KO-round rule blocks. Spiel um Platz 3 is always on. Domain rules
/// pinned by ADR-0017 §3.
class WizardKoConfigStep extends StatefulWidget {
  const WizardKoConfigStep({
    required this.draft,
    required this.controller,
    required this.onConfigChanged,
    required this.onSeedingModeChanged,
    required this.helpShown,
    required this.onHelpChanged,
    super.key,
  });

  final TournamentConfigDraft draft;
  final TournamentConfigController controller;
  final ValueChanged<KoPhaseConfig?> onConfigChanged;
  final ValueChanged<SeedingMode> onSeedingModeChanged;
  final bool helpShown;
  final ValueChanged<bool> onHelpChanged;

  @override
  State<WizardKoConfigStep> createState() => _WizardKoConfigStepState();
}

class _WizardKoConfigStepState extends State<WizardKoConfigStep> {
  late int _qualifierCount;
  late SeedingMode _seedingMode;

  /// Controller for the (now required, K18) consolation/Trostturnier name.
  /// Lives here so its text survives rebuilds while the organiser types.
  late final TextEditingController _consolationNameCtrl;

  @override
  void initState() {
    super.initState();
    final participants = widget.draft.maxParticipants;
    final existing = widget.draft.koConfig;
    _qualifierCount = existing?.qualifierCount ?? _smartDefault(participants);
    _seedingMode = widget.draft.bracketSeedingMode ??
        existing?.seedingMode ??
        SeedingMode.auto;
    _consolationNameCtrl =
        TextEditingController(text: widget.draft.consolationName ?? '');
    // Commit the smart default upfront so the wizard's `_stepValid` can verify
    // the KO config without waiting for user input, then seed the per-round §A
    // default profiles for rounds still at the bare default.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushIfValid();
      _seedRoundDefaults();
    });
  }

  @override
  void dispose() {
    _consolationNameCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WizardKoConfigStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the qualifier count changes the per-round list is resized by the
    // controller; reseed the §A profiles for the freshly-added bare-default
    // rounds (existing organiser edits are left untouched).
    if (widget.draft.koRoundFormats.length !=
        oldWidget.draft.koRoundFormats.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seedRoundDefaults();
      });
    }
  }

  /// Replaces any per-round entry still equal to the bare fallback default
  /// with its deterministic P6_RULES_DECISIONS §A profile (Bo3 early,
  /// Bo5 from quarter, no tiebreak from the semifinal). Organiser edits are
  /// preserved because only untouched (bare-default) rounds are reseeded.
  void _seedRoundDefaults() {
    final rounds = widget.draft.koRoundFormats;
    final total = rounds.length;
    for (var i = 0; i < total; i++) {
      if (rounds[i] == TournamentConfigDraft.defaultKoRoundFormat) {
        widget.controller.setKoRoundFormat(
          i,
          TournamentConfigDraft.defaultKoRoundFormatFor(i, total),
        );
      }
    }
  }

  /// K11 — selectable KO sizes are decoupled from the participant count: the
  /// bracket is a power of two from 2 up to [TournamentConfigDraft.koBracketSizeCap]
  /// (64), independent of `maxParticipants` (which may be up to 1000). This
  /// keeps the live KO bracket sane no matter how many players register.
  static List<int> _bracketSizes() {
    final out = <int>[];
    var size = 2;
    while (size <= TournamentConfigDraft.koBracketSizeCap) {
      out.add(size);
      size <<= 1;
    }
    if (out.isEmpty) out.add(2);
    return out;
  }

  /// U4 — `participants` is a power of two → `participants / 2`, otherwise the
  /// largest 2^n strictly below `participants`. Clamped to [2, koBracketSizeCap]
  /// so the default never exceeds the KO cap even for very large rosters (K11).
  static int _smartDefault(int participants) {
    if (participants < 2) return 2;
    final raw = _isPow2(participants)
        ? participants ~/ 2
        : _prevPow2(participants);
    return raw.clamp(2, TournamentConfigDraft.koBracketSizeCap);
  }

  static bool _isPow2(int n) => n > 0 && (n & (n - 1)) == 0;

  static int _prevPow2(int n) {
    var v = 1;
    while (v * 2 < n) {
      v <<= 1;
    }
    return v;
  }

  // K11 — KO size is bounded by the fixed bracket cap, NOT by maxParticipants.
  bool get _isValid =>
      _qualifierCount >= 2 &&
      _qualifierCount <= TournamentConfigDraft.koBracketSizeCap &&
      _isPow2(_qualifierCount);

  void _pushIfValid() {
    if (!_isValid) {
      widget.onConfigChanged(null);
      return;
    }
    widget.onConfigChanged(
      KoPhaseConfig(
        qualifierCount: _qualifierCount,
        // K11: KO size is decoupled from maxParticipants. The domain invariant
        // requires qualifierCount <= participantCount, so the bracket capacity
        // must be at least the chosen KO size (e.g. a 16-bracket on a 8-player
        // cap is allowed now). Take the max so the invariant always holds.
        participantCount: widget.draft.maxParticipants > _qualifierCount
            ? widget.draft.maxParticipants
            : _qualifierCount,
        // Spiel um Platz 3 is always on now (P6_SETUP_WIZARD_SPEC.md Screen 6).
        withThirdPlacePlayoff: true,
        seedingMode: _seedingMode,
      ),
    );
  }

  void _onSizePicked(int size) {
    setState(() => _qualifierCount = size);
    _pushIfValid();
  }

  void _onSeedingChanged(SeedingMode mode) {
    setState(() => _seedingMode = mode);
    widget.onSeedingModeChanged(mode);
    _pushIfValid();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sizes = _bracketSizes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: WizardHelpToggle(
            value: widget.helpShown,
            onChanged: widget.onHelpChanged,
            label: l10n.tournamentWizardHelpToggle,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        // ---- KO axis (Single-Out | Double-Elimination | Trostturnier) ----
        // The KO system is chosen here, at the top of the KO config (it used to
        // sit on the format step, but the KO type belongs with the rest of the
        // KO setup). One info glyph via KubbField; the detailed three-model
        // sheet hangs off a discreet text link below so there is no second
        // identical "i"-glyph competing with it.
        KubbField(
          label: l10n.tournamentWizardKoSystemLabel,
          info: InfoIconButton(
            title: l10n.tournamentSetupInfoKoTypeTitle,
            message: l10n.tournamentSetupInfoKoTypeBody,
          ),
          child: KubbBinaryChoice<KoType>(
            selected: widget.draft.koType,
            onChanged: widget.controller.setKoType,
            options: <KubbChoiceOption<KoType>>[
              KubbChoiceOption<KoType>(
                value: KoType.singleOut,
                title: l10n.tournamentWizardKoSystemSingle,
                subtitle: l10n.tournamentWizardKoSystemSingleHint,
              ),
              KubbChoiceOption<KoType>(
                value: KoType.doubleOut,
                title: l10n.tournamentWizardKoSystemDouble,
                subtitle: l10n.tournamentWizardKoSystemDoubleHint,
              ),
              KubbChoiceOption<KoType>(
                value: KoType.consolation,
                title: l10n.tournamentWizardKoSystemConsolation,
                subtitle: l10n.tournamentWizardKoSystemConsolationHint,
              ),
            ],
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => KoModelExplainerSheet.show(context),
            child: Text(
              l10n.tournamentKoModelExplainerLink,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                color: Theme.of(context).extension<KubbTokens>()!.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        // KO size is restricted to powers of two — no byes in the main
        // bracket (P6_SETUP_WIZARD_SPEC.md Screen 6).
        KubbField(
          label: l10n.tournamentWizardQualifierCountLabel,
          helper: l10n.tournamentWizardQualifierCountHelper,
          info: InfoIconButton(
            title: l10n.tournamentSetupInfoKoBracketSizeTitle,
            message: l10n.tournamentSetupInfoKoBracketSizeBody,
          ),
          child: Wrap(
            spacing: KubbTokens.space2,
            runSpacing: KubbTokens.space2,
            children: [
              for (final s in sizes)
                KubbSelectChip(
                  label: '$s',
                  selected: _qualifierCount == s,
                  onTap: () => _onSizePicked(s),
                ),
            ],
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        KubbField(
          label: l10n.tournamentWizardSeedingSourceLabel,
          info: InfoIconButton(
            title: l10n.tournamentSetupInfoKoSeedingSourceTitle,
            message: l10n.tournamentSetupInfoKoSeedingSourceBody,
          ),
          child: KubbBinaryChoice<SeedingMode>(
            selected: _seedingMode,
            onChanged: _onSeedingChanged,
            options: <KubbChoiceOption<SeedingMode>>[
              KubbChoiceOption<SeedingMode>(
                value: SeedingMode.auto,
                // "aus Vorrunde" (not "Gruppenphase") — Schoch is also a valid
                // Vorrunde (P6_SETUP_WIZARD_SPEC.md Screen 6).
                title: l10n.tournamentWizardSeedingSourceAuto,
              ),
              KubbChoiceOption<SeedingMode>(
                value: SeedingMode.manual,
                title: l10n.tournamentWizardSeedingSourceManual,
              ),
            ],
          ),
        ),
        const SizedBox(height: KubbTokens.space6),
        ..._phase3Sections(context),
      ],
    );
  }

  /// Human label for KO round [index] (0-based, 0 = first round) of
  /// [totalRounds] total, counted from the back: last = Final, then
  /// Halbfinale / Viertelfinale / Achtelfinale, and `1/{n}-Final` beyond.
  String _koRoundLabel(AppLocalizations l10n, int index, int totalRounds) {
    final fromBack = totalRounds - index; // 1 = final, 2 = semi, …
    final remaining = 1 << fromBack; // teams entering this round
    return switch (remaining) {
      2 => l10n.tournamentWizardKoRoundFinal,
      4 => l10n.tournamentWizardKoRoundSemi,
      8 => l10n.tournamentWizardKoRoundQuarter,
      16 => l10n.tournamentWizardKoRoundEighth,
      _ => l10n.tournamentWizardKoRoundOf(remaining ~/ 2),
    };
  }

  /// Per-KO-round rule blocks, one per entry in [TournamentConfigDraft.
  /// koRoundFormats]. The block carries no per-field glyphs — a single short
  /// "Regeln pro KO-Runde" intro helper above the cards covers them. Seeds any
  /// round still at the bare default with the deterministic §A profile
  /// (postframe, so it doesn't mutate during build).
  List<Widget> _koRoundSections(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final d = widget.draft;
    final c = widget.controller;
    final rounds = d.koRoundFormats;
    if (rounds.isEmpty) return const <Widget>[];
    final total = rounds.length;
    return <Widget>[
      Text(
        l10n.tournamentWizardKoRoundRulesLabel,
        style: tokens.labelStyle,
      ),
      Padding(
        padding: const EdgeInsets.only(
          top: KubbTokens.space1half,
          bottom: KubbTokens.space3,
        ),
        child: Text(
          l10n.tournamentWizardKoRoundRulesHint,
          style: tokens.helperStyle,
        ),
      ),
      for (var i = 0; i < total; i++)
        KoRoundBlock(
          key: ValueKey<int>(i),
          title: _koRoundLabel(l10n, i, total),
          spec: rounds[i],
          onChanged: (spec) => c.setKoRoundFormat(i, spec),
        ),
    ];
  }

  List<Widget> _phase3Sections(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final d = widget.draft;
    final c = widget.controller;

    return [
      // K15/K16/K18: the whole Model-B (Trostturnier) config lives here in the
      // KO step (no longer on the format step), only when the consolation KO
      // type is chosen. The main-bracket size is NOT asked again — it equals
      // the KO bracket size picked above (single source, K15).
      if (d.koType == KoType.consolation) ...[
        _ConsolationKoSection(
          draft: d,
          controller: c,
          nameController: _consolationNameCtrl,
          bracketSize: _qualifierCount,
        ),
        const SizedBox(height: KubbTokens.space6),
      ],
      // The single/double-out distinction is the KO-system axis (KoType)
      // picked at the top of this step — `bracketType` derives from it, so we
      // do NOT ask it again here to avoid a conflicting second source.
      // K21: KO-matchup as a shared binary-choice card (ADR-0033 P1.2).
      KubbField(
        label: l10n.tournamentWizardKoMatchupLabel,
        info: InfoIconButton(
          title: l10n.tournamentSetupInfoKoMatchupTitle,
          message: l10n.tournamentSetupInfoKoMatchupBody,
        ),
        child: KubbBinaryChoice<KoMatchup>(
          selected: d.koMatchup,
          onChanged: c.setKoMatchup,
          options: <KubbChoiceOption<KoMatchup>>[
            KubbChoiceOption<KoMatchup>(
              value: KoMatchup.seedHighVsLow,
              title: l10n.tournamentWizardKoMatchupHighLow,
            ),
            KubbChoiceOption<KoMatchup>(
              value: KoMatchup.oneVsTwo,
              title: l10n.tournamentWizardKoMatchupOneTwo,
            ),
          ],
        ),
      ),
      const SizedBox(height: KubbTokens.space5),
      // K22: KO-tiebreak method as a shared binary-choice card (ADR-0033 P1.2).
      KubbField(
        label: l10n.tournamentWizardKoTiebreakMethodLabel,
        info: InfoIconButton(
          title: l10n.tournamentSetupInfoKoTiebreakTitle,
          message: l10n.tournamentSetupInfoKoTiebreakBody,
        ),
        child: KubbBinaryChoice<KoTiebreakMethod>(
          selected: d.koTiebreakMethod,
          onChanged: c.setKoTiebreakMethod,
          options: <KubbChoiceOption<KoTiebreakMethod>>[
            KubbChoiceOption<KoTiebreakMethod>(
              value: KoTiebreakMethod.classicKingtossRemoval,
              title: l10n.tournamentWizardKoTiebreakClassic,
            ),
            KubbChoiceOption<KoTiebreakMethod>(
              value: KoTiebreakMethod.mightyFinisherShootout,
              title: l10n.tournamentWizardKoTiebreakMighty,
            ),
          ],
        ),
      ),
      const SizedBox(height: KubbTokens.space5),
      // Per-KO-round rule blocks. The list length is derived from the
      // qualifier count (bracket size) and kept in sync by the controller;
      // each block edits one round's MatchFormatSpec via setKoRoundFormat.
      ..._koRoundSections(context),
    ];
  }
}

/// K15/K16/K18 — Model-B (consolation / Trostturnier) config, rendered only
/// in the KO step when [KoType.consolation] is chosen. The main-bracket size
/// is NOT asked here: it equals the KO bracket size picked above (single
/// source, K15). Offers the direct-starter count as chips (K16) and the
/// required consolation name (K18). Neither field carries an explainer glyph —
/// the direct-starter helper and the self-explanatory name suffice.
class _ConsolationKoSection extends StatelessWidget {
  const _ConsolationKoSection({
    required this.draft,
    required this.controller,
    required this.nameController,
    required this.bracketSize,
  });

  final TournamentConfigDraft draft;
  final TournamentConfigController controller;
  final TextEditingController nameController;

  /// The KO bracket size chosen above (= consolation main-bracket size). The
  /// direct-starter chip options are derived from it.
  final int bracketSize;

  /// K16 — sensible direct-starter chip options derived from the bracket size:
  /// 0 ("Keine") plus the powers of two strictly below the bracket size
  /// (e.g. size 16 → 0/4/8; size 8 → 0/4; size 4 → 0). No option is >= the
  /// bracket size.
  static List<int> directCountOptions(int bracketSize) {
    final out = <int>[0];
    for (final v in <int>[4, 8, 16, 32]) {
      if (v < bracketSize) out.add(v);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final options = directCountOptions(bracketSize);
    final selectedDirect = draft.consolationDirectCount;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
    );
    return Container(
      // Section now holds only direct-starter chips + the required name field
      // (the main bracket size lives in the KO size chips), hence the KO-scoped
      // key rather than the legacy Model-B name.
      key: const Key('wizardConsolationKoSection'),
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.tournamentWizardConsolationSectionLabel,
            style: tokens.labelStyle,
          ),
          const SizedBox(height: KubbTokens.space4),
          // K16 — direct starters as chips (no free number field anymore).
          // The helper carries the explanation; no glyph.
          KubbField(
            label: l10n.tournamentWizardConsolationDirectCountLabel,
            helper: l10n.tournamentWizardConsolationDirectCountHint,
            child: Wrap(
              key: const Key('wizardConsolationDirectCountChips'),
              spacing: KubbTokens.space2,
              runSpacing: KubbTokens.space2,
              children: [
                for (final v in options)
                  KubbSelectChip(
                    label: v == 0
                        ? l10n.tournamentWizardConsolationDirectCountNone
                        : '$v',
                    selected: selectedDirect == v,
                    onTap: () => controller.setConsolationDirectCount(v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: KubbTokens.space4),
          // K18 — consolation name is required (no "optional" badge) and
          // self-explanatory, so no glyph.
          KubbField(
            label: l10n.tournamentWizardConsolationNameLabel,
            child: TextField(
              key: const Key('wizardConsolationNameField'),
              controller: nameController,
              onChanged: controller.setConsolationName,
              decoration: InputDecoration(
                counterText: '',
                hintText: l10n.tournamentWizardConsolationNameHint,
                border: border,
                enabledBorder: border,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
