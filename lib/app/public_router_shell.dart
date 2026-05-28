import 'package:flutter/material.dart';

/// Mount-time gate fuer jede `/public/...`-Route.
///
/// Seit ADR-0026 Strategie A laufen Public-Spectator-Reads ueber
/// dedizierte `public_*_get`-RPCs mit `GRANT EXECUTE ... TO anon`. Ein
/// `signInAnonymously()`-Bootstrap ist nicht mehr noetig: der Standard-
/// SupabaseClient traegt im Header den anon-`apikey`, und das reicht
/// PostgREST + den public-RPCs fuer den Read-Pfad.
///
/// Diese Shell bleibt erhalten, weil der Router ein gemeinsames
/// Eltern-Widget fuer den `/public`-Branch erwartet (Riverpod-Scope-
/// Setup, kuenftiger Realtime-Wireup in Wave 4). Sie rendert das Child
/// jetzt synchron — keine Loading-Round-Trip beim Cold-Start einer
/// Spectator-URL.
class PublicRouterShell extends StatelessWidget {
  const PublicRouterShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
