import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Architecture guard for the unified messaging framework (ADR-0029 §(c)
/// FC-10). Three static invariants are enforced against the `lib/` tree:
///
/// 1. No NEW `Timer.periodic` for server-state discovery. The existing
///    pollers/tickers form an explicit allowlist annotated with the phase
///    that removes (or keeps) each one; the check is a SUBSET assertion —
///    a new offender fails, but removing a poller in a later phase does not.
/// 2. No hand-built CDC channel-key literals of the form
///    `<table>:<column>=<value>` — keys MUST come from the `kubb_domain`
///    builders (a typo there yields a silently-dead channel).
/// 3. At most ONE place constructs a Realtime adapter from a Supabase client
///    (`SupabaseRealtimeChannel(...)`), i.e. the bootstrap singleton — a
///    second instantiation would break the single-WebSocket invariant.
///
/// The guard MUST be GREEN on the current tree.
void main() {
  final libDir = Directory(p.join(Directory.current.path, 'lib'));

  /// Allowlist of files that legitimately use `Timer.periodic` today. Each
  /// entry carries the phase that migrates it (P1/P2/P3/P7) or `keep-as-is`
  /// (b.3 — a pure UI ticker / local-drift poll, never a messaging concern).
  const timerPeriodicAllowlist = <String>{
    // UI ticker for the await-others countdown — keep-as-is (b.3).
    'lib/features/match/presentation/match_await_others_screen.dart',
    // Offline-banner label refresh — UI, keep-as-is (b.3).
    'lib/core/ui/widgets/kubb_offline_banner.dart',
    // P7.
    'lib/features/match/application/match_providers.dart',
    // P3.
    'lib/features/social/application/social_providers.dart',
    // P1.
    'lib/features/inbox/application/inbox_controller.dart',
    // P7.
    'lib/features/team/application/team_providers.dart',
    // Auth-cooldown UI ticker — keep-as-is (b.3).
    'lib/features/auth/presentation/restore_flow.dart',
    // P2.
    'lib/features/tournament/application/tournament_bracket_provider.dart',
    // P7.
    'lib/features/tournament/application/tournament_list_provider.dart',
    // P2/P4.
    'lib/features/tournament/application/public_tournament_polling_provider.dart',
    // Local outbox drift — keep-as-is (b.3).
    'lib/features/tournament/application/outbox_pending_provider.dart',
    // P2.
    'lib/features/tournament/application/tournament_match_providers.dart',
    // P2.
    'lib/features/tournament/presentation/tournament_pool_standings_screen.dart',
    // Match-countdown UI ticker — keep-as-is (b.3).
    'lib/features/tournament/presentation/widgets/match_countdown.dart',
  };

  List<File> dartFiles() => libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .toList();

  // Project paths use POSIX separators on the CI / dev targets; normalise
  // through `p.split`/`p.posix.joinAll` so the comparison is separator-safe.
  String rel(File f) => p.posix.joinAll(
        p.split(p.relative(f.path, from: Directory.current.path)),
      );

  /// Lines that are NOT a `//`/`///` comment (leading whitespace stripped).
  /// String-literal mentions are excluded separately by the caller's regex.
  bool isCommentLine(String line) {
    final t = line.trimLeft();
    return t.startsWith('//');
  }

  test('FC-10 (a): Timer.periodic usage is a subset of the allowlist', () {
    // Match real invocations `Timer.periodic(` only; doc-comment mentions
    // (e.g. realtime_fallback_provider.dart) are skipped because they live
    // on a comment line.
    final offenders = <String>{};
    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      final hasRealCall = lines.any(
        (l) => !isCommentLine(l) && l.contains('Timer.periodic('),
      );
      if (hasRealCall) offenders.add(rel(file));
    }

    final outsideAllowlist = offenders.difference(timerPeriodicAllowlist);
    expect(
      outsideAllowlist,
      isEmpty,
      reason: 'New Timer.periodic for server-state outside the FC-10 '
          'allowlist (ADR-0029): $outsideAllowlist. Use a StreamProvider + '
          'realtimePollingFallbackProvider instead, or add a justified '
          'allowlist entry with its target phase.',
    );
  });

  test('FC-10 (b): no hand-built <table>:<column>=<value> channel-key literals',
      () {
    // CDC keys MUST come from the kubb_domain builders. A hand-built literal
    // like 'tournament_matches:tournament_id=...' is the forbidden form.
    final keyLiteral = RegExp("""['"][a-z_]+:[a-z_]+=""");
    final offenders = <String>[];
    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (isCommentLine(line)) continue;
        if (keyLiteral.hasMatch(line)) {
          offenders.add('${rel(file)}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Hand-built CDC channel-key literal(s) found — use the '
          'kubb_domain builders (e.g. tournamentRealtimeChannelKey): '
          '$offenders',
    );
  });

  test('FC-10 (c): at most one SupabaseRealtimeChannel(...) instantiation', () {
    final ctorCall = RegExp(r'\bSupabaseRealtimeChannel\(');
    final sites = <String>[];
    for (final file in dartFiles()) {
      // The adapter's own class declaration is not an instantiation site.
      if (rel(file) == 'lib/core/data/realtime/supabase_realtime_channel.dart') {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (isCommentLine(line)) continue;
        if (ctorCall.hasMatch(line)) {
          sites.add('${rel(file)}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      sites.length,
      lessThanOrEqualTo(1),
      reason: 'More than one SupabaseRealtimeChannel instantiation breaks the '
          'single-WebSocket invariant (ADR-0029). Use the app-wide '
          'realtimeChannelProvider singleton. Sites: $sites',
    );
  });
}
