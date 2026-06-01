import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Wizard step 5 (T13): KO-phase configuration.
///
/// Hosts the free-integer qualifier-count input (U1/U2), the preview panel
/// (U3), the bronze-match switch (pre-filled from
/// [TournamentConfigDraft.suggestedWithThirdPlacePlayoff]) and the seeding
/// mode radio. Domain rules pinned by `docs/domain-knowledge/qualifier-count.md`
/// U1–U4 and ADR-0017 §3.
class WizardKoConfigStep extends StatefulWidget {
  const WizardKoConfigStep({
    required this.draft,
    required this.controller,
    required this.onConfigChanged,
    required this.onSeedingModeChanged,
    super.key,
  });

  final TournamentConfigDraft draft;
  final TournamentConfigController controller;
  final ValueChanged<KoPhaseConfig?> onConfigChanged;
  final ValueChanged<SeedingMode> onSeedingModeChanged;

  @override
  State<WizardKoConfigStep> createState() => _WizardKoConfigStepState();
}

class _WizardKoConfigStepState extends State<WizardKoConfigStep> {
  late TextEditingController _qualifierCtrl;
  late int _qualifierCount;
  late bool _withBronze;
  late SeedingMode _seedingMode;

  @override
  void initState() {
    super.initState();
    final participants = widget.draft.maxParticipants;
    final existing = widget.draft.koConfig;
    _qualifierCount = existing?.qualifierCount ?? _smartDefault(participants);
    _withBronze = existing?.withThirdPlacePlayoff ??
        widget.draft.suggestedWithThirdPlacePlayoff;
    _seedingMode = widget.draft.bracketSeedingMode ??
        existing?.seedingMode ??
        SeedingMode.auto;
    _qualifierCtrl = TextEditingController(text: '$_qualifierCount');
    // Commit the smart default upfront so the wizard's `_stepValid` can
    // verify the KO config without waiting for user input, then seed the
    // per-round §A default profiles for rounds still at the bare default.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushIfValid();
      _seedRoundDefaults();
    });
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

  @override
  void dispose() {
    _qualifierCtrl.dispose();
    super.dispose();
  }

  /// U4 — `participantCount` is a power of two → `participantCount / 2`,
  /// otherwise the largest 2^n strictly below `participantCount`. Clamped
  /// to the U2 minimum of 2.
  static int _smartDefault(int participants) {
    if (participants < 2) return 2;
    if (_isPow2(participants)) return participants ~/ 2;
    return _prevPow2(participants).clamp(2, participants);
  }

  static bool _isPow2(int n) => n > 0 && (n & (n - 1)) == 0;

  static int _nextPow2(int n) {
    if (n < 2) return 2;
    var v = 1;
    while (v < n) {
      v <<= 1;
    }
    return v;
  }

  static int _prevPow2(int n) {
    var v = 1;
    while (v * 2 < n) {
      v <<= 1;
    }
    return v;
  }

  bool get _isValid =>
      _qualifierCount >= 2 && _qualifierCount <= widget.draft.maxParticipants;

  void _pushIfValid() {
    if (!_isValid) {
      widget.onConfigChanged(null);
      return;
    }
    widget.onConfigChanged(
      KoPhaseConfig(
        qualifierCount: _qualifierCount,
        participantCount: widget.draft.maxParticipants,
        withThirdPlacePlayoff: _withBronze,
        seedingMode: _seedingMode,
      ),
    );
  }

  void _onQualifierTyped(String raw) {
    final parsed = int.tryParse(raw.trim());
    setState(() {
      _qualifierCount = parsed ?? 0;
    });
    _pushIfValid();
  }

  void _onBronzeChanged(bool value) {
    setState(() => _withBronze = value);
    _pushIfValid();
  }

  void _onSeedingChanged(SeedingMode? mode) {
    if (mode == null) return;
    setState(() => _seedingMode = mode);
    widget.onSeedingModeChanged(mode);
    _pushIfValid();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final participants = widget.draft.maxParticipants;
    final outOfRange = !_isValid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.tournamentWizardQualifierCountLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        TextField(
          controller: _qualifierCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: _onQualifierTyped,
          decoration: InputDecoration(
            errorText: outOfRange
                ? 'Wert zwischen 2 und $participants erforderlich.'
                : null,
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
        const SizedBox(height: KubbTokens.space2),
        Text(
          l10n.tournamentWizardQualifierCountHelper,
          style: TextStyle(
            fontSize: 12,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space4),
        if (_isValid) _PreviewPanel(qualifierCount: _qualifierCount),
        const SizedBox(height: KubbTokens.space5),
        _BronzeSwitch(
          value: _withBronze,
          onChanged: _onBronzeChanged,
        ),
        const SizedBox(height: KubbTokens.space5),
        _SeedingModeRadios(
          value: _seedingMode,
          onChanged: _onSeedingChanged,
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
  /// koRoundFormats]. Seeds any round still at the bare default with the
  /// deterministic §A profile (postframe, so it doesn't mutate during build).
  List<Widget> _koRoundSections(
    BuildContext context,
    Widget Function(String) label,
  ) {
    final l10n = AppLocalizations.of(context);
    final d = widget.draft;
    final c = widget.controller;
    final rounds = d.koRoundFormats;
    if (rounds.isEmpty) return const <Widget>[];
    final total = rounds.length;
    return <Widget>[
      label(l10n.tournamentWizardKoRoundRulesLabel),
      Padding(
        padding: const EdgeInsets.only(bottom: KubbTokens.space3),
        child: Text(
          l10n.tournamentWizardKoRoundRulesHint,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).extension<KubbTokens>()!.fgMuted,
          ),
        ),
      ),
      for (var i = 0; i < total; i++)
        _KoRoundBlock(
          key: ValueKey<int>(i),
          title: _koRoundLabel(l10n, i, total),
          spec: rounds[i],
          onChanged: (spec) => c.setKoRoundFormat(i, spec),
        ),
    ];
  }

  List<Widget> _phase3Sections(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final d = widget.draft;
    final c = widget.controller;
    final quali = d.mightyFinisherQuali;
    final consol = d.consolationBracket;

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: KubbTokens.space2),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: tokens.fgMuted,
            ),
          ),
        );

    return [
      // The single/double-out distinction is chosen on the format step via
      // the KO-system axis (KoType) — `bracketType` derives from it, so we
      // do NOT ask it again here to avoid a conflicting second source.
      label(l10n.tournamentWizardKoMatchupLabel),
      SegmentedButton<KoMatchup>(
        segments: [
          ButtonSegment(
            value: KoMatchup.seedHighVsLow,
            label: Text(l10n.tournamentWizardKoMatchupHighLow),
          ),
          ButtonSegment(
            value: KoMatchup.oneVsTwo,
            label: Text(l10n.tournamentWizardKoMatchupOneTwo),
          ),
        ],
        selected: {d.koMatchup},
        onSelectionChanged: (s) => c.setKoMatchup(s.first),
        showSelectedIcon: false,
      ),
      const SizedBox(height: KubbTokens.space5),
      label(l10n.tournamentWizardKoTiebreakMethodLabel),
      SegmentedButton<KoTiebreakMethod>(
        segments: [
          ButtonSegment(
            value: KoTiebreakMethod.classicKingtossRemoval,
            label: Text(l10n.tournamentWizardKoTiebreakClassic),
          ),
          ButtonSegment(
            value: KoTiebreakMethod.mightyFinisherShootout,
            label: Text(l10n.tournamentWizardKoTiebreakMighty),
          ),
        ],
        selected: {d.koTiebreakMethod},
        onSelectionChanged: (s) => c.setKoTiebreakMethod(s.first),
        showSelectedIcon: false,
      ),
      const SizedBox(height: KubbTokens.space5),
      // Per-KO-round rule blocks. The list length is derived from the
      // qualifier count (bracket size) and kept in sync by the controller;
      // each block edits one round's MatchFormatSpec via setKoRoundFormat.
      ..._koRoundSections(context, label),
      const SizedBox(height: KubbTokens.space5),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.tournamentWizardMightyQualiLabel),
        subtitle: Text(l10n.tournamentWizardMightyQualiHint),
        value: quali?.enabled ?? false,
        onChanged: (v) => c.setMightyFinisherQuali(
          MightyFinisherQuali(enabled: v, slots: quali?.slots ?? 6),
        ),
      ),
      if (quali?.enabled ?? false)
        WizardNumberField(
          label: l10n.tournamentWizardMightyQualiSlots,
          value: quali?.slots ?? 6,
          min: 1,
          max: 32,
          compact: true,
          onChanged: (v) => c.setMightyFinisherQuali(
            MightyFinisherQuali(enabled: true, slots: v),
          ),
        ),
      const SizedBox(height: KubbTokens.space5),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.tournamentWizardConsolationLabel),
        subtitle: Text(l10n.tournamentWizardConsolationHint),
        value: consol?.enabled ?? false,
        onChanged: (v) => c.setConsolationBracket(
          ConsolationConfig(
            enabled: v,
            sourceRounds: v ? const <int>[1, 2] : const <int>[],
          ),
        ),
      ),
    ];
  }
}

/// One per-KO-round rules card: numeric Sätze-zum-Sieg, Match-Zeit and
/// Pause inputs plus a Tiebreak on/off switch with its own after-time. Edits
/// emit a new [MatchFormatSpec] via [onChanged]; `max_sets` is auto-clamped
/// to `2*setsToWin - 1` so a series can always be decided.
class _KoRoundBlock extends StatelessWidget {
  const _KoRoundBlock({
    required this.title,
    required this.spec,
    required this.onChanged,
    super.key,
  });

  final String title;
  final MatchFormatSpec spec;
  final ValueChanged<MatchFormatSpec> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final timeMin = (spec.timeLimitSeconds / 60).round();
    return Container(
      margin: const EdgeInsets.only(bottom: KubbTokens.space3),
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space1half),
          WizardNumberField(
            label: l10n.tournamentWizardSetsToWinLabel,
            value: spec.setsToWin,
            min: 1,
            max: 4,
            compact: true,
            onChanged: (v) {
              final floor = 2 * v - 1;
              onChanged(
                spec.copyWith(
                  setsToWin: v,
                  maxSets: spec.maxSets < floor ? floor : spec.maxSets,
                ),
              );
            },
          ),
          WizardNumberField(
            label: l10n.tournamentWizardMatchTimeLabel,
            value: timeMin,
            min: 5,
            max: 120,
            compact: true,
            onChanged: (v) => onChanged(spec.copyWith(timeLimitSeconds: v * 60)),
          ),
          WizardNumberField(
            label: l10n.tournamentWizardKoRoundPauseLabel,
            value: (spec.breakBetweenMatchesSeconds / 60).round(),
            min: 0,
            max: 60,
            compact: true,
            onChanged: (v) =>
                onChanged(spec.copyWith(breakBetweenMatchesSeconds: v * 60)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.tournamentWizardKoRoundTiebreakLabel),
            value: spec.tiebreakEnabled,
            onChanged: (on) => onChanged(
              spec.copyWith(
                tiebreakEnabled: on,
                // Seed a sane after-time when enabling without one set.
                tiebreakAfterSeconds: on
                    ? (spec.tiebreakAfterSeconds ??
                        (spec.timeLimitSeconds - 600)
                            .clamp(60, spec.timeLimitSeconds))
                    : spec.tiebreakAfterSeconds,
              ),
            ),
          ),
          if (spec.tiebreakEnabled)
            WizardNumberField(
              label: l10n.tournamentWizardKoRoundTiebreakAfterLabel,
              value: ((spec.tiebreakAfterSeconds ?? spec.timeLimitSeconds) / 60)
                  .round(),
              min: 1,
              max: timeMin,
              compact: true,
              onChanged: (v) =>
                  onChanged(spec.copyWith(tiebreakAfterSeconds: v * 60)),
            ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.qualifierCount});

  final int qualifierCount;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final size = _WizardKoConfigStepState._nextPow2(qualifierCount);
    final byes = size - qualifierCount;
    final realMatches = qualifierCount - byes;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _previewLine(
            tokens,
            l10n.tournamentWizardQualifierPreviewBracketSize(size),
          ),
          const SizedBox(height: KubbTokens.space2),
          _previewLine(
            tokens,
            l10n.tournamentWizardQualifierPreviewByes(byes),
          ),
          const SizedBox(height: KubbTokens.space2),
          _previewLine(
            tokens,
            l10n.tournamentWizardQualifierPreviewRealMatches(realMatches),
          ),
        ],
      ),
    );
  }

  Widget _previewLine(KubbTokens tokens, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: tokens.fg,
      ),
    );
  }
}

class _BronzeSwitch extends StatelessWidget {
  const _BronzeSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tournamentWizardBronzeMatchLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.fg,
                ),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
        Text(
          l10n.tournamentWizardBronzeMatchHelper,
          style: TextStyle(fontSize: 12, color: tokens.fgMuted),
        ),
      ],
    );
  }
}

class _SeedingModeRadios extends StatelessWidget {
  const _SeedingModeRadios({required this.value, required this.onChanged});

  final SeedingMode value;
  final ValueChanged<SeedingMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Seeding-Quelle',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        RadioGroup<SeedingMode>(
          groupValue: value,
          onChanged: onChanged,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioListTile<SeedingMode>(
                value: SeedingMode.auto,
                contentPadding: EdgeInsets.zero,
                title: Text('Automatisch aus Gruppenphase'),
              ),
              RadioListTile<SeedingMode>(
                value: SeedingMode.manual,
                contentPadding: EdgeInsets.zero,
                title: Text('Manuell festlegen'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
