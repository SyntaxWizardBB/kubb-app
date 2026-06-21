import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';

/// Labelled numeric input used across the tournament-setup wizard. Replaces
/// the old +/- stepper widgets (`_NumberStepper`, `_MiniStepper`) with a
/// plain number field: a numeric keyboard, digits-only filtering and
/// min/max clamping applied on edit and on focus loss.
///
/// The field shows the current [value] and reports clamped integers back via
/// [onChanged]. While the user is mid-edit (e.g. an empty field or a value
/// below [min]) the raw text is left untouched so deletion stays possible;
/// the value is clamped and the visible text reconciled when editing
/// finishes (focus loss / submit) or when [value] changes from the outside.
class WizardNumberField extends StatefulWidget {
  const WizardNumberField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.compact = false,
    this.info,
    super.key,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// Optional explainer shown as a trailing info-glyph next to the label.
  /// Only surfaced in the roomy (non-compact) layout.
  final InfoIconButton? info;

  /// Compact layout (smaller label, tighter height) for dense per-round
  /// rule blocks. Default is the roomy wizard-step layout.
  final bool compact;

  @override
  State<WizardNumberField> createState() => _WizardNumberFieldState();
}

class _WizardNumberFieldState extends State<WizardNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(WizardNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reconcile the visible text when the value changes from the outside
    // (e.g. a clamp side-effect or another field driving this one), but
    // never while the user is actively editing this field.
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      final text = '${widget.value}';
      if (_controller.text != text) {
        _controller.text = text;
      }
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  /// Clamps the typed text into the min..max range, reports it, and snaps
  /// the visible text back to the clamped value.
  void _commit() {
    final parsed = int.tryParse(_controller.text.trim()) ?? widget.value;
    final clamped = parsed.clamp(widget.min, widget.max);
    final text = '$clamped';
    if (_controller.text != text) _controller.text = text;
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  void _onChanged(String raw) {
    final parsed = int.tryParse(raw.trim());
    // Only forward values that are already in range; mid-edit values (empty,
    // below min) are kept as raw text and reconciled on commit so the user
    // can clear the field and retype.
    if (parsed == null) return;
    if (parsed >= widget.min && parsed <= widget.max) {
      widget.onChanged(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
    );
    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      onChanged: _onChanged,
      onSubmitted: (_) => _commit(),
      style: TextStyle(
        fontSize: widget.compact ? 16 : 20,
        fontWeight: FontWeight.w800,
        color: tokens.fg,
      ),
      decoration: InputDecoration(
        isDense: widget.compact,
        contentPadding: EdgeInsets.symmetric(
          vertical: widget.compact ? KubbTokens.space2 : KubbTokens.space3,
          horizontal: KubbTokens.space3,
        ),
        border: border,
        enabledBorder: border,
      ),
    );

    if (widget.compact) {
      // Dense row: label on the left, narrow field on the right.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1half),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.fg,
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            SizedBox(width: 88, child: field),
          ],
        ),
      );
    }

    final labelText = Text(
      widget.label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: tokens.fgMuted,
        letterSpacing: 0.4,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.info != null)
          Row(
            children: [
              Flexible(child: labelText),
              const Spacer(),
              widget.info!,
            ],
          )
        else
          labelText,
        const SizedBox(height: KubbTokens.space2),
        field,
      ],
    );
  }
}
