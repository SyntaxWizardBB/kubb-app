import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Der kanonische Topic-Builder (`tournamentBroadcastTopic`) lebt jetzt in
// kubb_domain; dieses Modul exponiert den alten Namen weiter via duennem
// Delegator (siehe publicTournamentRealtimeTopic).
import 'package:kubb_domain/kubb_domain.dart';
// `supabase_flutter` exportiert ein eigenes `RealtimeChannel` aus
// `realtime_client`, das mit dem domain-eigenen Port-Typ kollidiert.
// Wir nutzen hier nur das supabase-API (Channel + Config), darum hide
// auf den Domain-Typ.
import 'package:supabase_flutter/supabase_flutter.dart' hide RealtimeChannel;
import 'package:supabase_flutter/supabase_flutter.dart' as sb
    show RealtimeChannel;

/// Realtime-Adapter fuer den anon-Spectator-Pfad (W3-T5 / Sprint-A T6-
/// Followup nach ADR-0026 §Realtime).
///
/// Heute laeuft die `PublicTournamentScreen` rein per Pull: die
/// `public_tournament_get`-RPC wird nur beim ersten Build (und bei
/// manuellem Refresh) aufgerufen. Dieser Adapter abonniert das
/// dedizierte Realtime-Topic `public_tournament_events:<tournament_id>`
/// (Migration 20260601000031), das aus zwei AFTER-Triggern gespeist
/// wird:
///
///   * `tournament_matches` — Status- oder Score-Wechsel, emittiert als
///     `match_status`-Event mit kuratierter Spalten-Whitelist.
///   * `tournament_set_score_proposals` — neuer Vorschlag, emittiert als
///     `proposal_created`-Event (nur match_id + Round + Set-Nr.).
///
/// Beide Events enthalten KEIN `created_by`, KEIN `submitter_user_id`,
/// KEIN `user_id` — die Privacy-Garantie wird serverseitig in der
/// Trigger-Funktion durchgesetzt; der Client whitelisted zusaetzlich
/// beim Decode (`PublicTournamentEvent.fromPayload`).
///
/// Der Topic ist `private: false` deklariert: anon-Clients koennen
/// subscriben, ohne ein JWT zu halten. Damit entfaellt der
/// `signInAnonymously()`-Round-Trip, den ADR-0026 §Decision §1
/// explizit aus dem Public-Pfad entfernt hat.

/// Diskriminator fuer [PublicTournamentEvent]-Subtypen.
enum PublicTournamentEventType {
  matchStatus,
  proposalCreated,
}

/// Event, das ueber den `public_tournament_events`-Topic an den anon-
/// Spectator geliefert wird. Dataclass mit der Whitelist, die der
/// SQL-Trigger projektiert — neue Felder muessen synchron in der
/// Migration und im Decoder ergaenzt werden.
@immutable
class PublicTournamentEvent {
  const PublicTournamentEvent({
    required this.type,
    required this.tournamentId,
    required this.matchId,
    this.previousStatus,
    this.status,
    this.consensusRound,
    this.setNumber,
  });

  final PublicTournamentEventType type;
  final TournamentId tournamentId;
  final TournamentMatchId matchId;
  final String? previousStatus;
  final String? status;
  final int? consensusRound;
  final int? setNumber;

  /// Whitelist: nur diese Keys werden aus dem Realtime-Payload gelesen.
  /// Alles andere (z.B. ein versehentlich durchgeleakter
  /// `submitter_user_id`-Eintrag) wird ignoriert und in
  /// [assertPayloadColumnsWhitelisted] explizit als Privacy-Bruch
  /// markiert. Tests fahren denselben Whitelist-Vergleich.
  static const Set<String> allowedPayloadColumns = <String>{
    'event_type',
    'match_id',
    'tournament_id',
    'round_number',
    'match_number_in_round',
    'status',
    'previous_status',
    'consensus_round',
    'participant_a_id',
    'participant_b_id',
    'winner_participant_id',
    'final_score_a',
    'final_score_b',
    'phase',
    'bracket_position',
    'started_at',
    'completed_at',
    'set_number',
    'emitted_at',
  };

  /// Spalten, die unter KEINEN Umstaenden im Public-Topic auftauchen
  /// duerfen. Tests assert-en explizit auf diese Liste.
  static const Set<String> forbiddenPayloadColumns = <String>{
    'created_by',
    'submitter_user_id',
    'user_id',
    'email',
    'nickname',
  };

  /// Decoder: liest aus dem rohen `realtime.send()`-Payload. Verwirft
  /// unbekannte Keys still; eine forbidden-Key-Pruefung muss separat
  /// ueber [assertPayloadColumnsWhitelisted] laufen, damit ein
  /// versehentliches Leak nicht bloss "geschluckt" wird.
  static PublicTournamentEvent? fromPayload(Map<String, dynamic> payload) {
    final eventType = payload['event_type'] as String?;
    final matchIdRaw = payload['match_id'] as String?;
    final tournamentIdRaw = payload['tournament_id'] as String?;
    if (matchIdRaw == null || tournamentIdRaw == null) return null;
    final matchId = TournamentMatchId(matchIdRaw);
    final tournamentId = TournamentId(tournamentIdRaw);
    switch (eventType) {
      case 'match_status':
        return PublicTournamentEvent(
          type: PublicTournamentEventType.matchStatus,
          tournamentId: tournamentId,
          matchId: matchId,
          status: payload['status'] as String?,
          previousStatus: payload['previous_status'] as String?,
          consensusRound: _asIntOrNull(payload['consensus_round']),
        );
      case 'proposal_created':
        return PublicTournamentEvent(
          type: PublicTournamentEventType.proposalCreated,
          tournamentId: tournamentId,
          matchId: matchId,
          consensusRound: _asIntOrNull(payload['consensus_round']),
          setNumber: _asIntOrNull(payload['set_number']),
        );
      default:
        return null;
    }
  }
}

/// Asserts that [payload] only contains allow-listed keys. Used in
/// tests *and* defensively beim Decode (Debug-Mode), damit ein neuer
/// Trigger-Patch nicht versehentlich eine Privacy-Spalte mitliefert.
///
/// Wirft im Treffer-Fall einen [StateError] mit dem Treffer-Set; das
/// gibt deterministische Test-Failure-Messages und macht den
/// Privacy-Bruch im Logging sichtbar.
@visibleForTesting
void assertPayloadColumnsWhitelisted(Map<String, dynamic> payload) {
  final leaks = <String>{};
  for (final key in payload.keys) {
    if (PublicTournamentEvent.forbiddenPayloadColumns.contains(key)) {
      leaks.add(key);
    } else if (!PublicTournamentEvent.allowedPayloadColumns.contains(key)) {
      // Unbekannter Key. In Tests soll das brennen, weil es entweder
      // (a) eine neue legitime Spalte im Trigger ist und der Whitelist-
      // Eintrag fehlt, oder (b) ein versehentliches Leak. Beides muss
      // den Schreiber zwingen, in beiden Stellen synchron zu pflegen.
      leaks.add(key);
    }
  }
  if (leaks.isNotEmpty) {
    throw StateError(
      'Public tournament realtime payload carries unexpected columns: '
      '${leaks.toList()..sort()}. Whitelist-Pflege in Migration '
      '20260601000031 und PublicTournamentEvent synchron pflegen.',
    );
  }
}

/// Topic-Name pro Turnier-ID. Spiegel der SQL-Funktion
/// `public.public_tournament_realtime_topic(uuid)` — Drift wuerde von
/// den Adapter-Tests sofort gemeldet.
///
/// Thin delegator: the canonical builder now lives in `kubb_domain`
/// (`tournamentBroadcastTopic`). Kept here under the old name so existing
/// call-sites keep compiling; P0b migrates them to the new name.
String publicTournamentRealtimeTopic(TournamentId id) =>
    tournamentBroadcastTopic(id);

/// Adapter fuer das public Realtime-Topic. Die abstrakte Klasse erlaubt
/// es Tests, einen Fake einzusetzen, ohne den `SupabaseClient` zu
/// mocken.
// ignore: one_member_abstracts
abstract class PublicTournamentRealtime {
  /// Subscribed das Topic fuer [tournamentId] und gibt einen Broadcast-
  /// Stream zurueck, der pro Trigger-Event genau einen
  /// [PublicTournamentEvent] emittiert. Mehrere Listener teilen sich den
  /// physischen Channel; der Adapter zaehlt Referenzen und schliesst
  /// den Channel beim letzten Detach.
  Stream<PublicTournamentEvent> watch(TournamentId tournamentId);
}

/// Supabase-Impl: oeffnet pro Turnier einen Channel mit
/// `private: false`, bindet `match_status`- und `proposal_created`-
/// Broadcast-Events und mappt die Payloads ueber
/// [PublicTournamentEvent.fromPayload]. Eine Wrapper-Schicht
/// (`_ChannelEntry`) refcount't Subscriber, damit das
/// `publicTournamentRealtimeProvider`-`autoDispose` pro letztem
/// Listener den Channel sauber teardown.
class SupabasePublicTournamentRealtime implements PublicTournamentRealtime {
  SupabasePublicTournamentRealtime({required SupabaseClient client})
      : _client = client;

  final SupabaseClient _client;
  final Map<String, _ChannelEntry> _entries = <String, _ChannelEntry>{};

  @override
  Stream<PublicTournamentEvent> watch(TournamentId tournamentId) {
    final topic = publicTournamentRealtimeTopic(tournamentId);
    // _open can throw (subscribe handshake fails). When it does the entry
    // must not linger half-built in the map with a bumped refCount, or the
    // onCancel teardown never runs and the channel zombies (Spec Bug 4.5).
    final isNew = !_entries.containsKey(topic);
    final _ChannelEntry entry;
    try {
      entry = _entries.putIfAbsent(topic, () => _open(topic))..refCount += 1;
    } on Object {
      if (isNew) _entries.remove(topic);
      rethrow;
    }

    late StreamSubscription<PublicTournamentEvent> sub;
    final controller = StreamController<PublicTournamentEvent>.broadcast(
      onCancel: () async {
        await sub.cancel();
        entry.refCount -= 1;
        if (entry.refCount <= 0) {
          _entries.remove(topic);
          final channel = entry.channel;
          if (channel != null) {
            try {
              await _client.removeChannel(channel);
            } on Object {
              // Best-effort teardown — channel may already be gone.
            }
          }
          await entry.controller.close();
        }
      },
    );
    sub = entry.controller.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    return controller.stream;
  }

  _ChannelEntry _open(String topic) {
    final entry = _ChannelEntry();
    // Channel-Default ist `RealtimeChannelConfig(private: false)` —
    // anon-Subscribe-Bedingung aus ADR-0026 §Alternatives B. Sobald
    // jemand das Topic auf private zieht (oder Supabase den Default
    // dreht), muss der signInAnonymously()-Trip wieder rein. Tests
    // pinnen das Verhalten ueber `assertPayloadColumnsWhitelisted` —
    // ein privates Topic wuerde ohne JWT gar keine Events liefern.
    final channel = _client.channel(topic);
    void handlePayload(Map<String, dynamic> payload) {
      // Supabase liefert den Trigger-Payload unter `payload`. Wir
      // greifen defensiv beide Formen ab: das aeussere Envelope (Top-
      // Level Keys) und das innere `payload`-Objekt.
      final inner = payload['payload'];
      final eventPayload = inner is Map<String, dynamic>
          ? Map<String, dynamic>.from(inner)
          : Map<String, dynamic>.from(payload);
      // Defensive Whitelist-Pruefung nur im Debug-Mode; im Release-
      // Mode wuerde ein nicht-fataler Trigger-Diff die UI unnoetig
      // killen. Tests laufen im Debug-Mode und sehen den Throw.
      assert(
        () {
          assertPayloadColumnsWhitelisted(eventPayload);
          return true;
        }(),
        'public tournament realtime payload must stay column-whitelisted',
      );
      final event = PublicTournamentEvent.fromPayload(eventPayload);
      if (event != null) {
        entry.controller.add(event);
      }
    }

    channel
      ..onBroadcast(event: 'match_status', callback: handlePayload)
      ..onBroadcast(event: 'proposal_created', callback: handlePayload)
      ..subscribe();
    entry.channel = channel;
    return entry;
  }
}

class _ChannelEntry {
  final StreamController<PublicTournamentEvent> controller =
      StreamController<PublicTournamentEvent>.broadcast();
  sb.RealtimeChannel? channel;
  int refCount = 0;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Provider fuer den Realtime-Adapter. Singleton pro `ProviderContainer`,
/// damit alle `watch()`-Aufrufe denselben Channel-Cache teilen.
final publicTournamentRealtimeProvider =
    Provider<PublicTournamentRealtime>((ref) {
  return SupabasePublicTournamentRealtime(
    client: Supabase.instance.client,
  );
});

/// Stream-Provider, der den anon-Realtime-Pfad fuer ein konkretes
/// Turnier exponiert. Konsumenten (z.B. `PublicTournamentScreen`)
/// `listen`-en darauf, um beim Eintreffen eines Events den
/// `publicTournamentDetailProvider` zu invalidieren — das ist der
/// Hebel, der die heutige Pull-only-Sicht auf live-update umstellt.
///
/// `autoDispose` per Konvention der bestehenden
/// `tournamentMatchListRealtimeProvider`-Familie: ohne aktiven Listener
/// wird die Subscription geschlossen und der Channel teardown.
// ignore: specify_nonobvious_property_types
final publicTournamentEventsProvider = StreamProvider.autoDispose
    .family<PublicTournamentEvent, TournamentId>((ref, tournamentId) {
  final adapter = ref.watch(publicTournamentRealtimeProvider);
  return adapter.watch(tournamentId);
});
