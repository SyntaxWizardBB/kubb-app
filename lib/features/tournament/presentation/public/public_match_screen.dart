import 'package:flutter/material.dart';

/// Stub for TASK-M4.2-T9. Real implementation owned by the T9 worker.
/// Present here only so T10 (`/public/match/:matchId` route wiring) can
/// reference the symbol without a parallel-merge dependency.
class PublicMatchScreen extends StatelessWidget {
  const PublicMatchScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Public Match')),
      body: Center(child: Text(matchId)),
    );
  }
}
