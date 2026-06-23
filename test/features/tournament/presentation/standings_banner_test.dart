// W1-T13 (Spec §3.2, acceptance 5.7) — degraded-banner on the standings view.
//
// A critical screen must not age silently when the realtime channel falls
// over. The standings view subscribes to the per-tournament channel (anchor)
// and shows the "Live unterbrochen / lade nach" strip once the fallback gate
// flips to polling (errored ≥60 s); it disappears again on reconnect.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_standings_screen.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_status_banner.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _tid = TournamentId('t-banner');

void main() {
  late FakeRealtimeChannel channel;
  late FakeTournamentRemote remote;

  setUp(() {
    channel = FakeRealtimeChannel();
    remote = FakeTournamentRemote(
      initialUser: const UserId('u'),
      realtime: channel,
    );
  });

  Widget shell() => ProviderScope(
        overrides: [
          tournamentRemoteProvider.overrideWithValue(remote),
          realtimeChannelProvider.overrideWithValue(channel),
          realtimeEnabledFlagProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TournamentStandingsView(tournamentId: _tid.value),
          ),
        ),
      );

  testWidgets('no degraded banner while the channel is joined', (tester) async {
    final key = tournamentRealtimeChannelKey(_tid);
    await tester.pumpWidget(shell());
    channel.setState(key, RealtimeChannelState.joined);
    await tester.pump();
    await tester.pump(const Duration(seconds: 90));

    expect(find.byType(RealtimeStatusBanner), findsOneWidget);
    expect(
      find.text(
        AppLocalizations.of(tester.element(find.byType(RealtimeStatusBanner)))
            .realtimeStatusPolling,
      ),
      findsNothing,
    );
  });

  testWidgets('shows the degraded strip after the channel errors for 60 s',
      (tester) async {
    final key = tournamentRealtimeChannelKey(_tid);
    await tester.pumpWidget(shell());
    channel.setState(key, RealtimeChannelState.errored);
    await tester.pump();
    // Grace window not elapsed yet -> still no strip.
    await tester.pump(const Duration(seconds: 30));
    final l10n =
        AppLocalizations.of(tester.element(find.byType(RealtimeStatusBanner)));
    expect(find.text(l10n.realtimeStatusPolling), findsNothing);

    // Cross the 60 s grace -> the strip appears.
    await tester.pump(const Duration(seconds: 40));
    expect(find.text(l10n.realtimeStatusPolling), findsOneWidget);

    // Reconnect -> the strip disappears again. The fallback gate mirrors
    // through one extra async hop, so settle two frames.
    channel.setState(key, RealtimeChannelState.joined);
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.realtimeStatusPolling), findsNothing);
  });
}
