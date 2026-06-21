import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Token-styled accordion for the optional blocks of the setup wizard. Starts
/// collapsed. Not a Material `ExpansionTile` — its divider and tile padding
/// fight the wizard's token spacing.
class KubbCollapsibleSection extends StatefulWidget {
  const KubbCollapsibleSection({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<KubbCollapsibleSection> createState() => _KubbCollapsibleSectionState();
}

class _KubbCollapsibleSectionState extends State<KubbCollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      margin: const EdgeInsets.only(top: KubbTokens.space5),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KubbTokens.space4,
                vertical: KubbTokens.space3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: tokens.sectionHeaderStyle,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: KubbTokens.iconSm,
                    color: tokens.fgMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KubbTokens.space4,
                0,
                KubbTokens.space4,
                KubbTokens.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}
