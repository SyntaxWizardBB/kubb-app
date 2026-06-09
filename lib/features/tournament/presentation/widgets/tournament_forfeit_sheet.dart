import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Bottom-sheet surface for the organizer-driven forfeit declaration
/// (spec DSCORE-62..-66, FR-MATCH-7, FR-CFG-11, BR-14). One radio group
/// selects the absent side, one multi-line text field captures the
/// mandatory reason (>= 10 chars per DSCORE-65), and the submit button
/// forwards to [TournamentActions.declareForfeit] which calls the
/// `tournament_match_forfeit` RPC.
///
/// The screen-side caller is responsible for the organizer gate — the
/// sheet itself only ensures that the inputs are syntactically valid
/// before enabling submit; the server enforces the authorisation and
/// status rules.
class TournamentForfeitSheet extends ConsumerStatefulWidget {
  const TournamentForfeitSheet({
    required this.matchId,
    super.key,
    this.initialAbsentSide,
    this.initialReason,
  });

  final TournamentMatchId matchId;

  /// D5: optional pre-selected absent side. The No-Show→Forfait shortcut in
  /// the escalation panel passes the side the absent participant sits on so
  /// the organizer doesn't re-pick it. `null` (default) keeps the legacy
  /// behaviour where the radio group starts unselected — existing callers
  /// (match-detail / dashboard-detail) are unaffected.
  final ForfeitAbsentSide? initialAbsentSide;

  /// D5: optional pre-filled reason. The No-Show shortcut seeds
  /// "No-Show - nicht eingecheckt"; `null` (default) keeps the field empty
  /// for the legacy callers.
  final String? initialReason;

  /// Reason minimum per spec DSCORE-65. Mirrored on the server.
  static const int reasonMin = 10;

  /// Reason cap, mirrors the override RPC (500 chars). Keeps the audit
  /// payload bounded.
  static const int reasonMax = 500;

  /// Opens the sheet and returns `true` when the user submitted a
  /// forfeit successfully, `false`/`null` when they cancelled.
  static Future<bool?> show(
    BuildContext context, {
    required TournamentMatchId matchId,
    ForfeitAbsentSide? initialAbsentSide,
    String? initialReason,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: TournamentForfeitSheet(
          matchId: matchId,
          initialAbsentSide: initialAbsentSide,
          initialReason: initialReason,
        ),
      ),
    );
  }

  @override
  ConsumerState<TournamentForfeitSheet> createState() =>
      _TournamentForfeitSheetState();
}

class _TournamentForfeitSheetState
    extends ConsumerState<TournamentForfeitSheet> {
  ForfeitAbsentSide? _absentSide;
  late final TextEditingController _reason;
  bool _submitting = false;
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    // D5: seed the radio group + reason from the optional pre-fill so the
    // No-Show shortcut lands on a ready-to-submit sheet. Both default to the
    // legacy empty state when the caller passes nothing.
    _absentSide = widget.initialAbsentSide;
    _reason = TextEditingController(text: widget.initialReason ?? '')
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String? _reasonError(AppLocalizations l) {
    final trimmed = _reason.text.trim();
    if (trimmed.length < TournamentForfeitSheet.reasonMin) {
      return l.tournamentForfeitReasonTooShort;
    }
    return null;
  }

  String? _sideError(AppLocalizations l) {
    if (_absentSide == null) return l.tournamentForfeitSideRequired;
    return null;
  }

  bool get _isValid =>
      _absentSide != null &&
      _reason.text.trim().length >= TournamentForfeitSheet.reasonMin;

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    if (!_isValid) {
      setState(() => _showValidation = true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(tournamentActionsProvider).declareForfeit(
            matchId: widget.matchId,
            absentSide: _absentSide!,
            reason: _reason.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.tournamentForfeitSuccessToast)),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.tournamentForfeitSubmitError(e.toString())),
          backgroundColor: KubbTokens.miss,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final reasonErr = _showValidation ? _reasonError(l) : null;
    final sideErr = _showValidation ? _sideError(l) : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(KubbTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.tournamentForfeitSheetTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
              ),
            ),
            const SizedBox(height: KubbTokens.space4),
            Text(
              l.tournamentForfeitAbsentSideLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.fgMuted,
              ),
            ),
            const SizedBox(height: KubbTokens.space2),
            RadioGroup<ForfeitAbsentSide>(
              groupValue: _absentSide,
              onChanged: (v) {
                if (_submitting) return;
                setState(() => _absentSide = v);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioListTile<ForfeitAbsentSide>(
                    value: ForfeitAbsentSide.a,
                    title: Text(l.tournamentForfeitSideA),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<ForfeitAbsentSide>(
                    value: ForfeitAbsentSide.b,
                    title: Text(l.tournamentForfeitSideB),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (sideErr != null)
              Padding(
                padding: const EdgeInsets.only(top: KubbTokens.space1),
                child: Text(
                  sideErr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: KubbTokens.miss,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: KubbTokens.space4),
            TextField(
              controller: _reason,
              enabled: !_submitting,
              minLines: 3,
              maxLines: 5,
              maxLength: TournamentForfeitSheet.reasonMax,
              decoration: InputDecoration(
                labelText: l.tournamentForfeitReasonLabel,
                hintText: l.tournamentForfeitReasonHint,
                errorText: reasonErr,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: KubbTokens.space4),
            SizedBox(
              height: KubbTokens.touchComfortable,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l.tournamentForfeitSubmitButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
