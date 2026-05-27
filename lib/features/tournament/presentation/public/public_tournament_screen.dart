import 'package:flutter/material.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Stub for TASK-M4.2-T8. Real implementation owned by the T8 worker.
/// Present here only so T10 (`/public/tournament/:id` route wiring) can
/// reference the symbol without a parallel-merge dependency.
class PublicTournamentScreen extends StatelessWidget {
  const PublicTournamentScreen({required this.tournamentId, super.key});

  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Public Tournament')),
      body: Center(child: Text(tournamentId.value)),
    );
  }
}
