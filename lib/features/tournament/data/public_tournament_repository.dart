import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only Adapter fuer den anon-Spectator-Pfad nach ADR-0026
/// Strategie A. Liest ausschliesslich ueber die `public_*_get`-RPCs,
/// nie direkt von den Tabellen — die Public-RPCs sind die einzige
/// Schnittstelle, die die Privacy-Projektion zentral durchsetzt.
///
/// Die Implementierung benoetigt absichtlich KEINEN authentifizierten
/// Caller; der Standard-Supabase-`SupabaseClient` traegt im Header den
/// anon-`apikey`, und die RPCs sind via `GRANT EXECUTE ... TO anon`
/// fuer diese Rolle freigegeben. Kein `signInAnonymously()` mehr.
abstract class PublicTournamentRepository {
  Future<PublicTournamentDetail?> getPublicTournamentDetail(TournamentId id);

  Future<PublicMatchDetail?> getPublicMatchDetail(TournamentMatchId id);
}

/// Supabase-Impl, die die beiden `public_*_get`-RPCs aufruft.
class SupabasePublicTournamentRepository implements PublicTournamentRepository {
  SupabasePublicTournamentRepository({required SupabaseClient client})
      : _client = client;

  final SupabaseClient _client;

  @override
  Future<PublicTournamentDetail?> getPublicTournamentDetail(
    TournamentId id,
  ) async {
    final response = await _client.rpc<Map<String, dynamic>?>(
      'public_tournament_get',
      params: <String, dynamic>{'p_tournament_id': id.value},
    );
    if (response == null) return null;
    return publicTournamentDetailFromEnvelope(response);
  }

  @override
  Future<PublicMatchDetail?> getPublicMatchDetail(
    TournamentMatchId id,
  ) async {
    final response = await _client.rpc<Map<String, dynamic>?>(
      'public_tournament_match_get',
      params: <String, dynamic>{'p_match_id': id.value},
    );
    if (response == null) return null;
    return publicMatchDetailFromRow(response);
  }
}

final publicTournamentRepositoryProvider =
    Provider<PublicTournamentRepository>((ref) {
  return SupabasePublicTournamentRepository(
    client: Supabase.instance.client,
  );
});
