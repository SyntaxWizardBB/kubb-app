import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Passphrase entry per design brief #4. Show/hide toggle, optional
/// strength meter, 12-char minimum validation.
class PassphraseInput extends StatefulWidget {
  const PassphraseInput({
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.helper,
    this.error,
    this.showStrength = false,
    this.autofocus = false,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? placeholder;
  final String? helper;
  final String? error;
  final bool showStrength;
  final bool autofocus;

  @override
  State<PassphraseInput> createState() => _PassphraseInputState();
}

class _PassphraseInputState extends State<PassphraseInput> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    const min = 12;
    final lengthErr = widget.value.isNotEmpty && widget.value.length < min;
    final errorText = widget.error ??
        (lengthErr ? l10n.authPassphraseMinError : null);
    final hasError = errorText != null;
    final strength =
        widget.showStrength ? _estimateStrength(widget.value) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label ?? l10n.authPassphraseLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: tokens.fgMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: hasError ? KubbTokens.miss : tokens.lineStrong,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController.fromValue(
                    TextEditingValue(
                      text: widget.value,
                      selection: TextSelection.collapsed(
                        offset: widget.value.length,
                      ),
                    ),
                  ),
                  obscureText: !_shown,
                  autofocus: widget.autofocus,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: widget.onChanged,
                  decoration: InputDecoration(
                    hintText: widget.placeholder ??
                        l10n.authPassphrasePlaceholder,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: KubbTokens.space3,
                      vertical: KubbTokens.space3,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: tokens.fg,
                    letterSpacing: _shown ? 0 : 1.2,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _shown = !_shown),
                icon: Icon(
                  _shown ? Icons.visibility_off : Icons.visibility,
                  color: tokens.fgMuted,
                ),
                tooltip:
                    _shown ? l10n.authPassphraseHide : l10n.authPassphraseShow,
              ),
            ],
          ),
        ),
        if (widget.showStrength && widget.value.isNotEmpty) ...[
          const SizedBox(height: KubbTokens.space2),
          _StrengthMeter(strength: strength!),
        ],
        if (hasError) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 14,
                color: KubbTokens.miss,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  errorText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: KubbTokens.miss,
                  ),
                ),
              ),
            ],
          ),
        ] else if (widget.helper != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.helper!,
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          ),
        ],
      ],
    );
  }

  PassphraseStrength _estimateStrength(String value) {
    if (value.length < 12) return PassphraseStrength.weak;
    var classes = 0;
    if (RegExp('[a-z]').hasMatch(value)) classes++;
    if (RegExp('[A-Z]').hasMatch(value)) classes++;
    if (RegExp('[0-9]').hasMatch(value)) classes++;
    if (RegExp('[^A-Za-z0-9]').hasMatch(value)) classes++;
    if (value.length >= 16 && classes >= 3) return PassphraseStrength.strong;
    if (value.length >= 12 && classes >= 2) return PassphraseStrength.medium;
    return PassphraseStrength.weak;
  }
}

enum PassphraseStrength { weak, medium, strong }

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final PassphraseStrength strength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (filledBars, color, label, symbol) = switch (strength) {
      PassphraseStrength.weak => (
          1,
          KubbTokens.miss,
          l10n.authPassphraseStrengthWeak,
          '!',
        ),
      PassphraseStrength.medium => (
          2,
          KubbTokens.wood400,
          l10n.authPassphraseStrengthMedium,
          '~',
        ),
      PassphraseStrength.strong => (
          3,
          KubbTokens.meadow600,
          l10n.authPassphraseStrengthStrong,
          '✓',
        ),
    };
    return Semantics(
      label: 'Passphrase-Stärke: $label',
      child: Row(
        children: [
          for (var n = 1; n <= 3; n++) ...[
            Container(
              width: 24,
              height: 4,
              decoration: BoxDecoration(
                color: n <= filledBars ? color : KubbTokens.stone200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
          ],
          const SizedBox(width: KubbTokens.space2),
          Text(
            '$symbol $label',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
