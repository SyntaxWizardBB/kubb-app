import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Token-styled accordion for the optional blocks of the setup wizard. A
/// header row with the section title and a chevron; tapping it reveals or
/// hides [children]. Starts collapsed by default so the long Stammdaten step
/// shows only its core fields until the organizer opens an optional block.
///
/// Deliberately not a Material `ExpansionTile` — that brings its own divider
/// and tile padding that fight the wizard's token spacing. This keeps the
/// `line` border, `radiusMd` corners and `sectionHeaderStyle` the rest of the
/// step uses.
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
                    size: 18,
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
