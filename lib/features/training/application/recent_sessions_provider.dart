import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight projection of a completed training session for the home list.
///
/// Stub for M4-T5 — the real implementation lands in M5-T1 with a streaming
/// provider against the Drift session DAO. Type signature is meant to stay
/// compatible.
class RecentSessionView {
  const RecentSessionView({
    required this.modeTag,
    required this.hitRatePercent,
    required this.subtitle,
  });

  final String modeTag;
  final int hitRatePercent;
  final String subtitle;
}

final recentSessionsProvider = Provider<List<RecentSessionView>>(
  (ref) => const [],
);
