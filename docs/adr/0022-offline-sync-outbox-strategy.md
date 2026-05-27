# ADR-0022: Offline-Sync-Strategie — Outbox + Lamport-Idempotency

- **Status**: Proposed
- **Date**: 2026-05-27
- **Depends on**: ADR-0001 (Sync-Model — append-only event log, Lamport ordering), ADR-0004 (Pre-work — Realtime-Abstraktion), ADR-0006 (Lamport-Clock-Invariants), ADR-0014 (Tournament-Match-Coexistence)
- **Bezug**: `docs/plans/m4-realtime-dashboard-offline/architecture.md` §3.4, `open-decisions.md` OD-M4-05, OD-M4-06, `docs/specs/score-input-conflict-spec.md` DSCORE-94..-104

## Kontext

Die Score-Eingabe muss offline tolerant sein: ein Captain trägt mehrere Set-Scores ein während die Halle schlechtes Netz hat, später flusht alles automatisch. M1 hat das vorbereitet (Score-Draft-Cache in drift, DSCORE-19..-22) — aber Drafts sind UI-State, kein Sync-State. Wenn der User auf "Senden" tippt und das Netz weg ist, hat M1 nichts.

M4 schliesst die Lücke. Drei Architektur-Entscheidungen sind nötig:

1. **Wo persistieren wir ausstehende Submissions** — eigene Outbox-Tabelle oder Update-Flag auf Drafts?
2. **Wie macht der Server unsere Re-Submits idempotent** — damit derselbe Submit nach Retry nicht zweimal als getrennte Score-Proposals landet?
3. **Wann aktivieren wir die Lamport-Clock produktiv** — ADR-0006 verlangt das, M0–M3 haben es nicht eingelöst.

ADR-0006 §"Followups" listet beide Lamport-Folgemassnahmen explizit als M3/M4-Boundary. M3 hat sie nicht eingelöst — M4 ist die letzte Gelegenheit vor M5 (Liga / Schweizer System, ungünstiger Zeitpunkt für Infrastruktur-Refactor).

## Entscheidung

### 1. Eigene drift-Tabelle `score_submission_outbox`

Pro ausstehender Score-Submission ein Row mit Payload-JSON, Lamport-Marker, Retry-Counter, Acknowledgement-Status:

```dart
@DataClassName('ScoreSubmissionOutboxRow')
class ScoreSubmissionOutbox extends Table {
  TextColumn get id => text()(); // UUIDv7
  TextColumn get matchId => text()();
  IntColumn get consensusRound => integer()();
  IntColumn get setIndex => integer()();
  TextColumn get submitterUserId => text()();
  TextColumn get payloadJson => text()();
  IntColumn get lamportCounter => integer()();
  TextColumn get lamportDeviceId => text()();
  DateTimeColumn get queuedAt => dateTime()();
  DateTimeColumn get firstAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastErrorCode => text().nullable()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

UNIQUE-Index auf `(matchId, consensusRound, setIndex, submitterUserId, lamportCounter, lamportDeviceId)` verhindert lokale Duplikate beim Reflush.

`OutboxFlusher`-Komponente in `lib/core/application/`:
- Singleton-Provider, Lifecycle App-Start bis App-Stop.
- Reagiert auf `connectivity_plus`-State (online ↔ offline).
- Bei `online`: alle Rows mit `acknowledgedAt IS NULL`, sortiert nach `queuedAt ASC`, einzeln seriell an `TournamentRemote.proposeSetScoreWithLamport`.
- Bei Erfolg: `acknowledgedAt = now()`.
- Bei Konflikt (`STALE_CONSENSUS_ROUND`): Row mit `lastErrorCode` markieren, UI zeigt Konflikt, User muss manuell auflösen.
- GC: Rows mit `acknowledgedAt < now() - 30 days` beim App-Start purgen.

Drafts (M1) bleiben unverändert: sie sind UI-Zwischenstand vor Submit. Beim Submit verschiebt sich der Datensatz aus dem Draft in die Outbox.

### 2. Server-Idempotenz über (match, consensus_round, set, submitter, lamport, device)

Migration `20260701000001_score_rpc_idempotency.sql`:

```sql
ALTER FUNCTION tournament_propose_set_score(
  p_match_id uuid,
  p_consensus_round int,
  p_set_index int,
  p_set_score jsonb,
  p_lamport_counter int DEFAULT NULL,
  p_device_id text DEFAULT NULL
) ...

CREATE UNIQUE INDEX tournament_set_scores_idempotency
  ON tournament_set_scores (match_id, consensus_round, set_index, submitter_user_id, lamport_counter, device_id)
  WHERE lamport_counter IS NOT NULL AND device_id IS NOT NULL;
```

Implementation in der RPC:

- Wenn `p_lamport_counter IS NULL OR p_device_id IS NULL` → Legacy-Pfad (M1-Verhalten ohne Idempotency).
- Wenn beide gesetzt → INSERT mit ON CONFLICT auf den Idempotency-Index → DO NOTHING. Anschliessend lädt die RPC den vorhandenen Match-Zustand und gibt ihn zurück. Re-Submit erkennt das und meldet "bereits angekommen".

### 3. Lamport-Clock wird in M4 produktiv aktiviert

`LamportClock`-Hydration beim App-Start (`lib/features/match/application/lamport_clock_provider.dart`):

1. Pro `(match_id, device_id)`-Paar in der Outbox → MAX(`lamport_counter`) lesen.
2. Pro aktivem `tournament_set_scores`-Stream (Realtime joined) → höchster gesehener Counter beobachten.
3. Provider hält eine `LamportClock`-Instanz pro Match, hydrated mit `max(outbox_max, server_max)`.
4. Jede Score-Submission ruft `clock.tick()` und schreibt Counter + Device-ID in die Outbox.

Wall-Clock-Timestamp (`queuedAt`) bleibt für UI-Anzeige und GC. Ordering passiert nur über Lamport.

## Alternativen

### A — Update-Flag auf bestehender `TournamentScoreDrafts`-Tabelle

**Verworfen**: Draft hat PK `(matchId, consensusRound)`. Outbox-Items müssen pro Set-Index getrennt sein (mehrere Sets in einem Match werden unabhängig ackd). Splitting der Draft-Tabelle vermischt UI-State und Sync-State semantisch — Draft ist "vor Submit", Outbox ist "nach Submit, vor Ack". Saubere Trennung ist eigene Tabelle.

### B — Append-only Event-Log analog `match_events`

**Verworfen**: würde Server-Schema-Refactor erzwingen (`tournament_set_scores` wäre Event-Log statt RPC-State). Out of Scope für M4. Konzeptuell richtig im DDD-Sinn — wird mit M5+ neu bewertet, wenn Liga-Punkte ihr eigenes Event-Log brauchen.

### C — Lamport-Aktivierung erst mit Solo-Match-Multi-Device (M5+)

**Verworfen**: ADR-0006 verlangt Hydration explizit als M3/M4-Boundary. M4-Outbox-Idempotenz braucht eine eindeutige Identität pro Submit-Attempt — `(submitter, queued_at)` ist Wall-Clock-abhängig und damit unzuverlässig (User mit verstellter Phone-Uhr kann Duplikate erzeugen). Lamport-Counter ist genau der richtige Schlüssel. Wenn wir Lamport schon haben, nutzen wir ihn jetzt.

### D — Server vergibt Idempotency-Key statt Client

**Verworfen**: würde extra Server-Roundtrip vor jedem Submit verlangen ("gib mir einen Idempotency-Key"). Bricht Offline-First — wenn Netz weg ist, kann der User keinen neuen Submit starten. Client-Side Lamport-Counter funktioniert offline.

## Konsequenzen

### Positiv

- Offline-Score-Eingabe funktioniert: Captain trägt drei Set-Scores ein während die Halle kein Netz hat, alles flusht sauber.
- Idempotenz-Schutz greift bei Netzwerk-Flaps: doppelter Submit derselben Identität erzeugt keine Doppel-Scores.
- ADR-0006-Folgemassnahmen werden eingelöst — Lamport-Clock-Hydration produktiv, Server-side rejection bei `MatchFinished` kann in M4.3-T2 als kleine Erweiterung mitgenommen werden.
- Drei-Versuche-Konsens aus M1 bleibt intakt — Outbox respektiert `consensus_round`, Stale-Round-Submission wird sauber zurückgewiesen.
- Test-Doppel-Setup ist überschaubar: `FakeOutboxFlusher` + `InMemoryConnectivity` reichen für Widget-/Provider-Tests.

### Negativ

- Outbox ist zweite drift-Tabelle neben Drafts — doppelter Lese-Pfad in der UI für "wo ist mein Score gerade?".
- Konflikt-UI ("erneut eingeben") ist nicht schön für den User. Mitigation in Risk R-M4.3-3 dokumentiert.
- drift-Schema-Version steigt — Migration in bestehenden App-Installationen muss sauber sein. Test-Fixture-basierter Upgrade-Test ist Pflicht (M4.3-T1).
- Lamport-Counter ohne Server-Stream-Sync (Cold-Start ohne Netz) ist nicht garantiert eindeutig zwischen Devices. Risiko-Notiz in R-M4.3-4: durch `(consensus_round, submitter)` als Sekundär-Diskriminator abgefangen.

### Neutral

- drift-Tabelle ist klein (<60 LOC). DAO ist generiert.
- Idempotency-Index ist partial (`WHERE lamport_counter IS NOT NULL`) — Legacy-Submits ohne Lamport landen weiterhin ohne Idempotency-Schutz, was rückwärtskompatibel ist.
- Outbox-Retention 30 Tage ist Daumenwert — Schweizer Turnier-Pilot dauert max ein Wochenende, alles ältere ist Forensik.

## Test-Strategie

- **Property-Test** in `kubb_domain`: `LamportClock` nach Hydration aus N Mock-Events liefert für N+1-ten Tick einen Counter > MAX. (M4.3-T11)
- **pgTAP**: Idempotenter Re-Submit mit identischem Tupel gibt identischen Match-State zurück, keine neue `tournament_set_scores`-Row entsteht. Legacy-Submit (ohne Lamport) funktioniert wie M1. (M4.3-T3)
- **Integrations-Test**: Flugmodus an, 3 Set-Scores, Flugmodus aus, assert Outbox leer und Server hat 3 Scores. Zweimaliger Flush ohne Datenänderung dazwischen ist No-Op. (M4.3-T10)
- **Widget-Test**: Konflikt-UI rendert "erneut eingeben"-CTA wenn Outbox-Row mit `lastErrorCode='STALE_CONSENSUS_ROUND'` existiert.

## Folgepunkte

- **M4.3-T1..T11** implementieren die Outbox + Flusher + Lamport-Hydration.
- **M4.3-T2** erweitert die Score-RPC um Idempotency-Parameter. Die ADR-0006-Folgemassnahme "Server-side validation rejecting events for matches with existing MatchFinished" wird hier mitgenommen — selbe Migration, +5 LOC plpgsql.
- **In M5+ (Liga)** wird der Append-only-Event-Log-Pfad (Alt. B) neu bewertet, wenn Liga-Punkte ihr eigenes Event-Schema brauchen.
- **Konflikt-Auto-Merge** ist explizit ausgeschlossen (würde dem Drei-Versuche-Konsens widersprechen). Bei wachsendem Pilot-Feedback kann das in einem späteren ADR neu diskutiert werden.

## Status-Notiz

Sobald M4-Auftrag erteilt ist und OD-M4-05 / OD-M4-06 vom Committee bestätigt sind, wird dieser ADR auf "Accepted" gehoben.
