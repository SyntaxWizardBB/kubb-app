// Stub for TASK-M2.3-T8 (Wave 9). Concrete impl lands later;
// this stub exists only so the T1 widget tests compile.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Root widget that renders a [Bracket] as interactive canvas.
///
/// The constructor surface matches the contract from T1; the concrete
/// `InteractiveViewer` + connector layer arrives in T8.
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
  Widget build(BuildContext context, WidgetRef ref) =>
      throw UnimplementedError('T8');
}
