import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Placeholder for the live dashboard introduced in M4.2-T5. Wired up
/// here so the router (M4.2-T6) compiles ahead of the screen landing.
/// The body is intentionally minimal — the real grid of
/// `PitchStatusCard`s replaces this widget as part of T5.
class TournamentLiveDashboardScreen extends ConsumerWidget {
  const TournamentLiveDashboardScreen({required this.tournamentId, super.key});

  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        title: const Text('Live-Dashboard'),
      ),
      body: Center(
        child: Text(
          tournamentId.value,
          style: TextStyle(color: tokens.fgMuted),
        ),
      ),
    );
  }
}
