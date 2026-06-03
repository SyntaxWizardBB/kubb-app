import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_connector_painter.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/kubb_match_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Root widget that renders a [Bracket] as interactive canvas.
///
/// Layout-Math comes from [BracketLayout.compute]; connector lines are
/// painted by [BracketConnectorPainter] beneath the `Positioned`
/// [KubbMatchCard] widgets. Tap on a card navigates to the match detail
/// route via `context.go`. The widget is wrapped in [InteractiveViewer]
/// so wider brackets stay reachable on a 360 px display.
///
/// For a [ConsolationBracket] (Trostturnier, Modell B — ADR-0028) the canvas
/// shows TWO switchable sections via a [SegmentedButton] (analogous to the
/// WB/LB split of a double-elim): the single-elim main tree (from
/// [ConsolationBracket.mainRounds] carried by the read-path, or the explicit
/// [mainBracket] fallback) and the consolation tree (the [ConsolationBracket]
/// itself). Both sections reuse the exact same render path — each tree is
/// projected to a
/// [SingleEliminationBracket]-shaped structure and fed through
/// [BracketLayout.compute] / [KubbMatchCard] / [BracketConnectorPainter]; no new
/// canvas concept is introduced (ADR-0028 §UI / DoD-08).
class BracketCanvas extends ConsumerStatefulWidget {
  const BracketCanvas({
    required this.bracket,
    super.key,
    this.editable = true,
    this.tournamentId,
    this.mainBracket,
    this.consolationName,
  });

  final Bracket bracket;
  final bool editable;
  final TournamentId? tournamentId;

  /// Optional explicit single-elim main tree FALLBACK for the "Hauptbaum"
  /// section when [bracket] is a [ConsolationBracket]. The read-path now carries
  /// the main tree in [ConsolationBracket.mainRounds] (ADR-0028 §7.3), so this
  /// is only used when those are empty. When neither is available the Hauptbaum
  /// section shows an informational hint.
  final Bracket? mainBracket;

  /// Display name of the consolation side-tournament (`consolation_name`).
  /// When `null` the localized fallback ('Trostturnier') is used (DoD-06).
  final String? consolationName;

  @override
  ConsumerState<BracketCanvas> createState() => _BracketCanvasState();
}

/// Which section of a consolation bracket is currently shown.
enum _BracketSection { main, consolation }

class _BracketCanvasState extends ConsumerState<BracketCanvas> {
  late _BracketSection _section;

  @override
  void initState() {
    super.initState();
    // Default to the section that actually has a tree to show: open on the
    // main tree whenever one is available (the ConsolationBracket now carries
    // its own [mainRounds] from the read-path, ADR-0028 §7.3 / DoD-10), else on
    // the consolation tree so the user sees match cards instead of an empty
    // hint page.
    _section =
        _mainTree() != null ? _BracketSection.main : _BracketSection.consolation;
  }

  /// The single-elim main tree to render in the "Hauptbaum" section, or `null`
  /// when none is available. Prefers the [ConsolationBracket.mainRounds] carried
  /// by the read-path; falls back to an explicit [BracketCanvas.mainBracket].
  SingleEliminationBracket? _mainTree() {
    final bracket = widget.bracket;
    if (bracket is ConsolationBracket && bracket.mainRounds.isNotEmpty) {
      return SingleEliminationBracket(rounds: bracket.mainRounds);
    }
    if (widget.mainBracket is SingleEliminationBracket) {
      return widget.mainBracket! as SingleEliminationBracket;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bracket = widget.bracket;
    // Plain single-elim: render unchanged (golden parity, DoD-08).
    if (bracket is SingleEliminationBracket) {
      return _BracketTreeView(
        bracket: bracket,
        editable: widget.editable,
        tournamentId: widget.tournamentId,
      );
    }
    // Consolation (Trostturnier, Modell B): two switchable sections.
    if (bracket is ConsolationBracket) {
      return _buildConsolation(context, bracket);
    }
    // Other bracket types are not rendered by this canvas yet.
    return const SizedBox.shrink();
  }

  Widget _buildConsolation(BuildContext context, ConsolationBracket bracket) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final consolationLabel =
        widget.consolationName ?? l.tournamentBracketConsolationLabel;

    // Project each tree into a single-elim-shaped structure so the existing
    // layout/painter/card path renders it verbatim (DoD-08). The main tree now
    // comes from [ConsolationBracket.mainRounds] (read-path, ADR-0028 §7.3).
    final mainTree = _mainTree();
    final consolationTree = _consolationToSingleElim(bracket);

    final body = switch (_section) {
      _BracketSection.main => mainTree != null
          ? _BracketTreeView(
              // Distinct key so InteractiveViewer state resets between sections.
              key: const ValueKey('main-tree'),
              bracket: mainTree,
              editable: widget.editable,
              tournamentId: widget.tournamentId,
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(KubbTokens.space5),
                child: Text(
                  l.tournamentBracketMainTreeUnavailable,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.fgMuted),
                ),
              ),
            ),
      _BracketSection.consolation => _BracketTreeView(
          // Distinct key so InteractiveViewer state resets between sections.
          key: const ValueKey('consolation-tree'),
          bracket: consolationTree,
          editable: widget.editable,
          tournamentId: widget.tournamentId,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KubbTokens.space4,
            KubbTokens.space3,
            KubbTokens.space4,
            KubbTokens.space2,
          ),
          child: SizedBox(
            // Touch-target >= 48 dp on the switch control (DoD-09).
            height: KubbTokens.touchMin,
            child: SegmentedButton<_BracketSection>(
              segments: <ButtonSegment<_BracketSection>>[
                ButtonSegment<_BracketSection>(
                  value: _BracketSection.main,
                  label: Text(l.tournamentBracketSectionMain),
                ),
                ButtonSegment<_BracketSection>(
                  value: _BracketSection.consolation,
                  label: Text(consolationLabel),
                ),
              ],
              selected: <_BracketSection>{_section},
              showSelectedIcon: false,
              onSelectionChanged: (sel) =>
                  setState(() => _section = sel.first),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  /// Project a [ConsolationBracket] onto a [SingleEliminationBracket]-shaped
  /// structure so the existing canvas/layout renders it (DoD-08). The
  /// consolation rounds become the winners rounds (the last one = the
  /// consolation final / places 5/6 via the [BracketPhase.finals] role inferred
  /// by [BracketLayout.compute]); the consolation third-place playoff (places
  /// 7/8) becomes the standard [BracketPhase.thirdPlace] round so the existing
  /// "third-place" box (key `third-place`) is reused (DoD-07). The connector
  /// painter key conventions (`r<round>-m<index>`, `third-place`) stay intact.
  static SingleEliminationBracket _consolationToSingleElim(
    ConsolationBracket bracket,
  ) {
    // Sort by round number and re-index to a gapless 1..N sequence before
    // handing the rounds to BracketLayout.compute. That layout treats round
    // numbers as power-of-two positions (pitch1 * (1 << (r-1))), so any gap or
    // offset in the source round_numbers would distort the geometry. Re-indexing
    // makes the projection robust against non-continuous round_number rows
    // (reviewer finding).
    final sorted = [...bracket.rounds]
      ..sort((a, b) => a.number.compareTo(b.number));
    final rounds = <BracketRound>[
      for (var i = 0; i < sorted.length; i++)
        BracketRound(number: i + 1, pairings: sorted[i].pairings),
      // The consolation third-place playoff reuses the standard thirdPlace box
      // (key 'third-place'); its round number mirrors the consolation final's
      // re-indexed round so it sits at the same column (DoD-07).
      if (bracket.thirdPlace != null)
        BracketRound(
          number: sorted.isEmpty ? 1 : sorted.length,
          phase: BracketPhase.thirdPlace,
          pairings: bracket.thirdPlace!.pairings,
        ),
    ];
    return SingleEliminationBracket(rounds: rounds);
  }
}

/// Renders one [SingleEliminationBracket]-shaped tree as the interactive
/// canvas (the original [BracketCanvas] body, extracted for reuse across the
/// consolation sections). Keeps the connector-painter key conventions.
class _BracketTreeView extends StatelessWidget {
  const _BracketTreeView({
    required this.bracket,
    required this.editable,
    this.tournamentId,
    super.key,
  });

  final SingleEliminationBracket bracket;
  final bool editable;
  final TournamentId? tournamentId;

  @override
  Widget build(BuildContext context) {
    final layout = BracketLayout.compute(bracket);
    final rects = layout.rects;
    final cards = <Widget>[];

    for (final round in bracket.rounds) {
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
                painter: BracketConnectorPainter(
                  layout: layout,
                  color: defaultConnectorColor(context),
                ),
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
