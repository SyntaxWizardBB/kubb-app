import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
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
    required this.onConfigChanged,
    required this.onSeedingModeChanged,
    super.key,
  });

  final TournamentConfigDraft draft;
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
    // verify the KO config without waiting for user input.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushIfValid());
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
      ],
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
