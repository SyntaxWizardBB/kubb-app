import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/supabase/anon_session.dart';

/// Mount-time gate for every `/public/...` route.
///
/// Public spectator screens (M4.2) need a usable Supabase JWT — even an
/// anonymous one — before any provider that hits RLS-gated tables or
/// Realtime can run. Routing the public branch through this shell lets
/// the auth bootstrap happen lazily on the first public hit instead of
/// blocking app cold-start for authenticated users who never visit a
/// `/public` link.
///
/// While [AnonSessionBootstrapper.ensureAnonSession] is in-flight, a
/// neutral spinner is shown. Errors surface inline so a transient
/// network blip on cold-start is visible and recoverable on retry
/// rather than silently feeding "no data" into the child screen.
class PublicRouterShell extends ConsumerStatefulWidget {
  const PublicRouterShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PublicRouterShell> createState() => _PublicRouterShellState();
}

class _PublicRouterShellState extends ConsumerState<PublicRouterShell> {
  late Future<void> _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = ref.read(anonSessionBootstrapperProvider).ensureAnonSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snapshot.error}'),
              ),
            ),
          );
        }
        return widget.child;
      },
    );
  }
}
