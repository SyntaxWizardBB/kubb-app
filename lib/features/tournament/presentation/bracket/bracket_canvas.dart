import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_connector_painter.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/kubb_match_card.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Root widget that renders a [Bracket] as interactive canvas.
///
/// Layout-Math comes from [BracketLayout.compute]; connector lines are
/// painted by [BracketConnectorPainter] beneath the `Positioned`
/// [KubbMatchCard] widgets. Tap on a card navigates to the match detail
/// route via `context.go`. The widget is wrapped in [InteractiveViewer]
/// so wider brackets stay reachable on a 360 px display.
class BracketCanvas extends ConsumerWidget {
  const BracketCanvas({
    required this.bracket,
    super.key,
    this.editable = true,
    this.tournamentId,
  });

  final Bracket bracket;
  final bool editable;
  final TournamentId? tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = BracketLayout.compute(bracket);
    final rects = layout.rects;
    final cards = <Widget>[];

    if (bracket is SingleEliminationBracket) {
      final rounds = (bracket as SingleEliminationBracket).rounds;
      for (final round in rounds) {
        final r = round.number;
        final isThird = round.phase == BracketPhase.thirdPlace;
        for (var i = 0; i < round.pairings.length; i++) {
          final pairing = round.pairings[i];
          final matchId = isThird ? 'third-place' : 'r$r-m$i';
          final rect = rects[matchId];
          if (rect == null) continue;
          cards.add(Positioned(
            left: rect.x,
            top: rect.y,
            width: rect.width,
            height: rect.height,
            child: KubbMatchCard(
              matchId: matchId,
              pairing: pairing,
              editable: editable,
              onTap: () => _onTap(context, matchId),
            ),
          ));
        }
      }
    }

    var maxRight = 0.0;
    var maxBottom = 0.0;
    for (final rect in rects.values) {
      if (rect.right > maxRight) maxRight = rect.right;
      if (rect.bottom > maxBottom) maxBottom = rect.bottom;
    }

    return InteractiveViewer(
      constrained: false,
      minScale: 0.5,
      boundaryMargin: const EdgeInsets.all(64),
      child: SizedBox(
        width: maxRight,
        height: maxBottom,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: BracketConnectorPainter(layout: layout),
              ),
            ),
            ...cards,
          ],
        ),
      ),
    );
  }

  void _onTap(BuildContext context, String matchId) {
    final t = tournamentId;
    if (t == null) return;
    context.go('/tournament/${t.value}/match/$matchId');
  }
}
