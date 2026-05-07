import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
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

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
    // Phase-1 keypair tokens have no refresh_token (the keypair-verify
    // edge function only mints access_token). Auto-refresh would fire
    // ~5 min before expiry, fail, and trigger an immediate signOut.
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
  );

  runApp(
    ProviderScope(
      overrides: [
        cachedAuthSessionDaoProvider.overrideWith(
          (ref) => ref.watch(appDatabaseProvider).cachedAuthSessionDao,
        ),
      ],
      child: const KubbApp(),
    ),
  );
}
