import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';

/// Pool entry tile used by `TeamDetailScreen` for both regular members
/// and guest players. Caller picks the [roleLabel] ("Mitglied"/"Gast").
///
/// Contract: M3.2-T13 (`RosterCompositionWidget`) reuses this card and
/// flips [isConflicted] to surface roster-eligibility conflicts via a
/// danger-tinted outline.
class TeamMemberCard extends StatelessWidget {
  const TeamMemberCard({
    required this.displayName,
    required this.roleLabel,
    super.key,
    this.onTap,
    this.isConflicted = false,
  });

  final String displayName;
  final String roleLabel;
  final VoidCallback? onTap;
  final bool isConflicted;

  String get _initials {
    final parts =
        displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final f = parts.first.characters.first;
    if (parts.length == 1) return f.toUpperCase();
    return (f + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(KubbTokens.space3),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          border: Border.all(
              color: isConflicted ? tokens.danger : tokens.line,
              width: isConflicted ? 2 : 1),
        ),
        child: Row(children: [
          AvatarCircle(initials: _initials, color: tokens.primary, size: 40),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
              child: Text(displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tokens.fg))),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: KubbTokens.space2, vertical: KubbTokens.space1),
            decoration: BoxDecoration(
                color: tokens.bgSunken,
                borderRadius: BorderRadius.circular(KubbTokens.radiusPill)),
            child: Text(roleLabel,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tokens.fgMuted)),
          ),
        ]),
      ),
    );
  }
}
