import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/realtime/supabase_realtime_channel.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider;
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');

  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    throw StateError(
      'SUPABASE_URL and SUPABASE_ANON_KEY must be provided via --dart-define. '
      'Example: flutter run '
      '--dart-define=SUPABASE_URL=http://10.0.2.2:54321 '
      '--dart-define=SUPABASE_ANON_KEY=<anon-key>',
    );
  }

  // gotrue's `autoRefreshToken` defaults to true and stays enabled —
  // OAuth (ADR-0010 §"Path A") needs it to rotate the refresh_token
  // shortly before access-token expiry. The Phase-1 keypair JWT has no
  // refresh_token and is handled separately by `KeypairSessionRefresher`
  // (W2-T1 / R1-F-03), which re-mints by re-signing a fresh challenge
  // well before expiry. When gotrue's auto-refresh fires against a
  // keypair-hydrated session it has no refresh_token to send and the
  // refresher's earlier re-sign has already replaced the session.
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // FC-7 (ADR-0029 §(c)): construct the ONE production CDC adapter here,
  // over the already-initialised `Supabase.instance.client` (no second
  // client), and override the app-wide `realtimeChannelProvider` singleton
  // with it. `overrideWithValue` hands every consumer the same instance so
  // all CDC subscriptions multiplex one WebSocket.
  // TODO(realtime-sync): add the broadcast singleton override (FC-4/P2).
  final realtimeAdapter = SupabaseRealtimeChannel(Supabase.instance.client);

  runApp(
    ProviderScope(
      overrides: [
        cachedAuthSessionDaoProvider.overrideWith(
          (ref) => ref.watch(appDatabaseProvider).cachedAuthSessionDao,
        ),
        realtimeChannelProvider.overrideWithValue(realtimeAdapter),
      ],
      child: const KubbApp(),
    ),
  );
}
