import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Match-Box widget rendered inside the bracket canvas.
///
/// Shows both participants of [pairing], the seed prefix, and an
/// optional winner highlight. BYE-slots render the localized "Freilos"
/// label with an icon (FR-FMT-11 / U5).
///
/// [winnerId] is optional — the underlying [BracketPairing] does not
/// carry the winner, so callers (e.g. `bracketFromMatches` + canvas)
/// pass the `winnerParticipantId` separately. When `null`, no slot is
/// highlighted.
///
/// When [editable] is `false`, the card renders without an [InkWell]
/// ripple but still calls [onTap] if provided (read-only navigation).
class KubbMatchCard extends StatelessWidget {
  const KubbMatchCard({
    required this.matchId,
    required this.pairing,
    super.key,
    this.onTap,
    this.editable = true,
    this.winnerId,
  });

  final String matchId;
  final BracketPairing pairing;
  final VoidCallback? onTap;
  final bool editable;
  final String? winnerId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final (a, b) = pairing;
    final nameA = a.isBye ? l.tournamentBracketByeLabel : (a.participantId ?? '—');
    final nameB = b.isBye ? l.tournamentBracketByeLabel : (b.participantId ?? '—');
    final semanticsLabel =
        'Match $matchId: ${l.tournamentMatchVersusHeader(nameA, nameB)}';

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space3,
          vertical: KubbTokens.space2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Slot(
              entry: a,
              label: nameA,
              isWinner: winnerId != null && a.participantId == winnerId,
              tokens: tokens,
              seedPrefix: l.tournamentBracketSeedPrefix,
            ),
            Divider(height: KubbTokens.space2, color: tokens.line),
            _Slot(
              entry: b,
              label: nameB,
              isWinner: winnerId != null && b.participantId == winnerId,
              tokens: tokens,
              seedPrefix: l.tournamentBracketSeedPrefix,
            ),
          ],
        ),
      ),
    );

    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
      child: editable
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
              child: InkWell(
                borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                onTap: onTap,
                child: card,
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: card,
            ),
    );

    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticsLabel,
      child: body,
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.entry,
    required this.label,
    required this.isWinner,
    required this.tokens,
    required this.seedPrefix,
  });

  final BracketEntry entry;
  final String label;
  final bool isWinner;
  final KubbTokens tokens;
  final String Function(int) seedPrefix;

  @override
  Widget build(BuildContext context) {
    final fg = isWinner ? tokens.primary : tokens.fg;
    final weight = isWinner ? FontWeight.w700 : FontWeight.w500;
    return Row(
      children: [
        if (entry.isBye)
          Icon(LucideIcons.skipForward, size: 14, color: tokens.fgMuted)
        else if (entry.seed > 0)
          Padding(
            padding: const EdgeInsets.only(right: KubbTokens.space2),
            child: Text(
              seedPrefix(entry.seed),
              style: TextStyle(
                fontSize: 11,
                color: tokens.fgMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (entry.isBye) const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: fg,
              fontWeight: weight,
              fontStyle: entry.isBye ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
        if (isWinner)
          Icon(LucideIcons.trophy, size: 14, color: tokens.primary),
      ],
    );
  }
}
