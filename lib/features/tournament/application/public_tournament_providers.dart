import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Riverpod-Provider fuer den anon-Spectator-Pfad nach ADR-0026.
///
/// Die Provider sind Pendants zu `tournamentDetailProvider` /
/// `tournamentMatchDetailProvider`, ziehen ihre Daten aber durch die
/// `public_*_get`-RPCs (keine Authentifizierung erforderlich). Public-
/// Screens watchen ausschliesslich diese Provider, nie die
/// authenticated-Varianten.

/// Detail-Snapshot eines public-sichtbaren Turniers fuer anonyme
/// Spectator. Liefert `null`, wenn die RPC kein Turnier zurueckgibt
/// (Turnier existiert nicht / `public = false` / Status draft|aborted).
// ignore: specify_nonobvious_property_types
final publicTournamentDetailProvider =
    FutureProvider.family<PublicTournamentDetail?, TournamentId>(
  (ref, tournamentId) async {
    return ref
        .read(publicTournamentRepositoryProvider)
        .getPublicTournamentDetail(tournamentId);
  },
);

/// Single-Match-Snapshot fuer anonyme Spectator. `null` analog
/// [publicTournamentDetailProvider].
// ignore: specify_nonobvious_property_types
final publicMatchDetailProvider =
    FutureProvider.family<PublicMatchDetail?, TournamentMatchId>(
  (ref, matchId) async {
    return ref
        .read(publicTournamentRepositoryProvider)
        .getPublicMatchDetail(matchId);
  },
);
