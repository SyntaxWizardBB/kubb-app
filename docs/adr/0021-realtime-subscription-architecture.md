# ADR-0021: Realtime-Subscription-Architektur

- **Status**: Proposed
- **Date**: 2026-05-27
- **Depends on**: ADR-0001 (Tech-Stack — Supabase Realtime ist im SDK), ADR-0002 (Bounded Contexts — Realtime ist Cross-Cut, kein neuer Kontext), ADR-0004 (Scaling-Strategie — Tier-Limits 200 / 500 concurrent), ADR-0014 (Tournament-Match-Coexistence), ADR-0015 (Cross-Platform-Sequencing)
- **Bezug**: `docs/plans/m4-realtime-dashboard-offline/architecture.md` §3.1, `open-decisions.md` OD-M4-01, OD-M4-02, OD-M4-07

## Kontext

M1–M3 laufen mit 5 s Polling für Match-Liste, Match-Detail, Bracket-Advance. Bei M3 mit Pool-Phase und ~16 Pitches parallel ist das im Veranstalter-Dashboard sichtbar träge — Status-Wechsel kommen erst nach bis zu 5 s an, was die Veranstalter-Erlebnis schwächt. M4 ersetzt das durch Supabase Realtime (Postgres-CDC über WebSocket).

Drei Entscheidungen müssen vor Implementierung fest sein, weil sie die Port-Form, die Skalierungs-Charakteristik und das Re-Connect-Verhalten bestimmen:

1. **Channel-Granularität**: per-Tournament oder per-Match?
2. **Re-Connect-Strategie**: was tut die App wenn der WS abreisst?
3. **Channel-Auth**: RLS-basiert oder ChannelAuthToken?

## Entscheidung

### 1. Channel-Strategy: Per-Tournament-Channel mit clientseitiger Filterung

Ein Supabase-Realtime-Channel pro geöffnetem Turnier-Detail / Live-Dashboard / Public-Spectator-View. Filter auf `tournament_matches.tournament_id = :id`. Listener filtern clientseitig auf die Matches die sie interessieren.

**Begründung**: Tier-1-Hard-Limit (500 concurrent Channels, Pro-Tier) ist die kritische Constraint per ADR-0004 §"Capacity assumptions". Channels-Anzahl skaliert mit aktiven Turnieren (~10–30 in Tier-1-Phase), nicht mit aktiven Matches (~hunderte). Per-Match-Channels würden 16 Channels pro Veranstalter-Dashboard öffnen — bei drei Veranstaltern 48 Channels nur fürs Dashboard, Free-Tier (200) ist damit für Spectator und Score-Eingabe-Devices schnell ausgereizt.

Clientseitige Filterung ist trivial (Map-Lookup auf `match.id`), Listener-Overhead-Differenz vernachlässigbar.

### 2. Re-Connect: Exp-Backoff + Polling-Fallback

`SupabaseRealtimeChannel`-Adapter implementiert exponentielles Backoff für Re-Subscribe nach Disconnect: 1 s, 2 s, 4 s, 8 s, dann 30 s konstant. Channel-State wird über `stateStream` exponiert.

Sobald Channel-State `errored` länger als 60 s ist, schaltet die App auf den bestehenden Polling-Provider (5 s Polling, M1-Implementation). Beim Re-Subscribe-Erfolg wird Polling deaktiviert.

Polling-Provider werden **nicht gelöscht**. Sie sind Fallback für:
- temporäre Supabase-Realtime-Ausfälle (~99.9 % SLA → ~8 h pro Jahr),
- Mobile-Netz-Wechsel (WLAN ↔ LTE),
- Feature-Flag-Abschaltung von Realtime im Notfall.

UI zeigt einen Banner: "Live" / "Verbinde…" / "Offline, Polling aktiv".

### 3. Channel-Auth: RLS-basiert (kein ChannelAuthToken)

Realtime-Subscribes laufen mit dem User-JWT (authentifiziert) oder dem anonymen JWT (für Public-Spectator-View). Supabase Postgres-RLS-Policies sind die Wahrheit über sichtbare Rows. Kein per-Channel-Token, keine Permission-Tokens auf Channel-Ebene.

**Begründung**: M4 hat keine Channel-Schreib-Komponente — Schreiben läuft über RPCs, die ihrerseits Realtime-Events auslösen. RLS-Policies sind ohnehin nötig für die Schreib-Pfade. Sie nochmal als Channel-Token zu codieren wäre Redundanz. Komplexitäts-Gewinn von ChannelAuthToken (feinere Channel-Permissions) lohnt sich nicht für unser Datenmodell.

Risiko "RLS zu offen" wird durch pgTAP-Tests in M4.2-T2 abgesichert (anon kann SELECT auf `public=true`, anon kann nicht SELECT auf `public=false`, anon kann nichts schreiben).

## Port-Definition

`RealtimeChannel` als neuer Port in `packages/kubb_domain/lib/src/ports/realtime_channel.dart`:

```dart
abstract interface class RealtimeChannel {
  Stream<RealtimeChange> subscribe({
    required String table,
    required String filterColumn,
    required String filterValue,
  });

  Future<void> close(String channelKey);

  Stream<RealtimeChannelState> stateStream(String channelKey);
}
```

`TournamentRemote` bekommt drei produktive Streams (Replacement für M1-Placeholder `watchMatch`):

- `Stream<TournamentMatchRef> watchMatch(TournamentMatchId id)`
- `Stream<TournamentMatchRef> watchTournamentMatches(TournamentId tournamentId)`
- `Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId tournamentId)`

`MatchEventRepository` (Solo-Match-Port) bekommt analog `Stream<MatchEvent> watchEvents(MatchId id)`. In M4 nur Port + Adapter, kein UI-Konsument.

## Alternativen

### A — Per-Match-Channel statt per-Tournament

**Verworfen** wegen Tier-1-Limit. 16-Pitch-Dashboard × 3 Veranstalter = 48 Channels, plus Score-Eingabe (~32 Devices) = 80 Channels. Plus Spectator: viral leicht >120. Reicht im Free-Tier (200) bei einer einzigen Veranstaltung nicht.

### B — Custom WebSocket / NATS / Pulsar

**Verworfen** per ADR-0004 §"Things we explicitly do NOT do" Punkt 4: "Custom WebSocket / message queue — Supabase Realtime carries us through Tier 2". Eigenes WS-System ist Tier-3-Problem.

### C — Polling-only weiter (kein Realtime in M4)

**Verworfen**: Polling-Latenz im Dashboard ist die UX-Lücke, die M4 schliessen soll. FR-LIVE-2 verlangt Live-Bracket-Updates. Polling-Only wäre Feature-Regression gegenüber dem M4-Auftrag.

### D — ChannelAuthToken statt RLS

**Verworfen**: zusätzlicher Round-Trip vor jedem Subscribe, eigene Token-Lifecycle-Verwaltung. Kein klarer Use-Case in M4. ChannelAuthToken wäre erst sinnvoll wenn Schreib-Channels (Heartbeat, Presence) dazukommen — M5+.

## Konsequenzen

### Positiv

- Pilot-Veranstalter-Demo sieht Live-Updates statt 5 s Polling-Latenz. Klare UX-Verbesserung im sichtbarsten Touchpoint.
- ADR-0004 §"Pre-work" Punkt 5 (`RealtimeChannel`-Abstraktion) wird produktiv. Migration weg von Supabase bleibt billig (Adapter-Swap).
- Polling-Fallback macht die App operativ resilient — kein Single-Point-of-Failure auf Supabase-Realtime.
- Tier-1-Skalierungs-Limit ist abgedeckt: per-Tournament-Channels skalieren langsam.
- RLS-basierte Auth bleibt konsistent zu allen anderen Supabase-Pfaden.

### Negativ

- Zwei Code-Pfade (Realtime + Polling) bleiben dauerhaft im Code. Cleanup-Versuchung — bewusst nicht nachgegeben (siehe OD-M4-02).
- Anonyme Spectator brauchen anonymes JWT auf dem Client — funktioniert in Inkognito-Browsern, aber `supabase_flutter` Web-Build hat hier historische Bugs. Eigene Risk-Notiz in `risks-and-deferrals.md` R-M4.1-3.
- Spectator-Channel-Skalierung bei viralen Turnieren ist eng (Tier-1-Limit). Mitigation: Live-Modus-Toggle für Spectator Default-AUS, Polling als Default für anonyme Spectator.

### Neutral

- Re-Connect-Backoff ist konservativ (1/2/4/8/30 s) — könnte aggressiver sein, aber Supabase-Backend mag hammering nicht. 60 s `errored` als Fallback-Trigger ist Erfahrungswert aus anderen Supabase-Projekten.
- `MatchEventRepository.watchEvents` ist Port-Erweiterung ohne UI-Konsument in M4. Bewusst — wir gleichen den `match/`-Kontext zur gleichen Discipline auf, damit M5+ Solo-Match-Live-View nicht aus der Reihe fällt.

## Folgepunkte

- **M4.1-T1..T3** implementieren die Port-Erweiterung und den Supabase-Adapter.
- **M4.1-T8** Integrations-Test mit zwei Test-Phones gegen lebendes Supabase (Pilot-Projekt).
- **M4.2-T2** pgTAP-Tests für RLS sind merge-blocking.
- **Mit M4.5 (Push-Notifications)** oder **M5 (Liga)** wird ChannelAuthToken neu bewertet — wenn Heartbeat-Channels oder Presence-Channels dazukommen, ist Token-Modell evtl. besser.
- **Bei Tier-1-Trigger (MAU > 400)** wird Pro-Tier-Upgrade ($25 / Monat) durchgeführt — verdoppelt Realtime-Concurrency von 200 auf 500.

## Status-Notiz

Sobald M4-Auftrag erteilt ist und OD-M4-01 / OD-M4-02 / OD-M4-07 vom Owner / Committee bestätigt sind, wird dieser ADR auf "Accepted" gehoben.
