// Stub for TASK-M2.3-T6 (Wave 9). Concrete impl lands later;
// this stub exists only so the T1 widget tests compile.
import 'package:flutter/material.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Match-Box widget rendered inside the bracket canvas.
///
/// The constructor surface matches the contract referenced by T1 tests
/// (matchId, pairing, optional onTap). The concrete render lands in T6.
class KubbMatchCard extends StatelessWidget {
  const KubbMatchCard({
    required this.matchId,
    required this.pairing,
    super.key,
    this.onTap,
    this.editable = true,
  });

  final String matchId;
  final BracketPairing pairing;
  final VoidCallback? onTap;
  final bool editable;

  @override
  Widget build(BuildContext context) => throw UnimplementedError('T6');
}
