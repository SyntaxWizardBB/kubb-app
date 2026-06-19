import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// One selectable option in a [KubbBinaryChoice].
@immutable
class KubbChoiceOption<T> {
  const KubbChoiceOption({
    required this.value,
    required this.title,
    this.subtitle,
  });

  /// The value reported to `onChanged` when this card is tapped.
  final T value;

  /// Bold primary label.
  final String title;

  /// Optional muted explanation under the title.
  final String? subtitle;
}

/// Shared radio-card selector for the setup wizard's two- (or N-) option
/// decisions — scoring (EKC/Klassisch), Vorrunde-Typ, KO-Typ, Seeding-Quelle,
/// KO-Matchup, KO-Tiebreak, …
///
/// ADR-0033 P1: replaces the previously fragmented `_ScoringOption` /
/// `_OptionRow` / `RadioListTile` one-off designs with a single token-driven
/// component, so every binary decision in the wizard *and* the stage-graph
/// editor looks identical. Generic so the three-way KO-Typ choice reuses it.
class KubbBinaryChoice<T> extends StatelessWidget {
  const KubbBinaryChoice({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<KubbChoiceOption<T>> options;

  /// The currently selected value (compared by `==`).
  final T selected;

  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < options.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: KubbTokens.space2),
          _OptionCard<T>(
            option: options[i],
            selected: options[i].value == selected,
            onTap: () => onChanged(options[i].value),
            tokens: tokens,
          ),
        ],
      ],
    );
  }
}

class _OptionCard<T> extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final KubbChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: option.title,
        child: Container(
          constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
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
            children: <Widget>[
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      option.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                    if (option.subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        option.subtitle!,
                        style: TextStyle(fontSize: 11, color: tokens.fgMuted),
                      ),
                    ],
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
