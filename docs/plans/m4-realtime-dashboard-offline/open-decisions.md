# M4 — Realtime + Live-Dashboard + Offline — Offene Entscheidungen

> Status: Entwurf, wartet auf Abnahme
> Datum: 2026-05-27

Folgende Punkte sind vor Implementierungsstart zu klären. Jeder blockt mindestens einen Task aus dem Milestone-Plan.

## OD-M4-01: Realtime-Channel-Granularität — per-Tournament oder per-Match?

**Frage**: Wie schneiden wir die Supabase-Realtime-Channels — ein Channel pro Turnier (alle Match-Updates eines Turniers auf einem WS-Channel) oder ein Channel pro Match (jedes Match hat seinen eigenen)?

**Warum blockierend**: Bestimmt die Port-Signatur (`RealtimeChannel.subscribe(table, filter, value)`) und vor allem die Skalierungs-Charakteristik (Tier-1-Hard-Limit ist 500 concurrent Channels — siehe ADR-0004).

**Optionen**:

- **A) Per-Tournament-Channel** — ein Channel pro offenem Turnier, gefiltert auf `tournament_id`. Alle Match-Updates dieses Turniers laufen über denselben WS.
  - Pros: Channels-Anzahl skaliert mit aktiven Turnieren (~10–30), nicht mit aktiven Matches (~hunderte). Bleibt im Free-Tier-Budget bis Tier 1.
  - Cons: jeder Listener bekommt ein Event für JEDE Match-Änderung im Turnier, auch wenn er nur ein Match anschaut → Client-seitig filtern.
- **B) Per-Match-Channel** — ein Channel pro offenem Match-Detail-Screen, gefiltert auf `id=matchId`.
  - Pros: Listener sieht nur die für ihn relevanten Events.
  - Cons: Veranstalter-Dashboard mit 16 Pitches öffnet 16 Channels gleichzeitig. Bei drei Veranstaltern parallel = 48 Channels nur für Dashboards. Free-Tier-Limit (200) ist schnell erreicht.
- **C) Hybrid** — per-Tournament-Channel für Listen / Dashboards / Spectator, per-Match-Channel nur für aktive Score-Eingabe (eine pro aktiver Spieler-Session).
  - Pros: bestes Verhältnis Channel-Anzahl-zu-Granularität.
  - Cons: zwei Channel-Strategien parallel implementieren plus testen.

**Empfehlung**: **A — Per-Tournament-Channel**. Begründung: Tier-Limit (200 / 500) ist die harte Constraint, alles andere ist Komfort. Client-seitige Filterung über `tournament_matches.id`-Vergleich ist trivial (Map-Lookup), die Listener-Overhead-Differenz vernachlässigbar. Hybrid wäre eine Optimierung — die machen wir, wenn Tier-1-Trigger fällt und der Per-Match-Channel-Use-Case sich empirisch zeigt (heute spekulativ).

Implementiert als `subscribe(table='tournament_matches', filterColumn='tournament_id', filterValue=':id')`. Die Match-Detail-Provider filtern dann clientseitig auf die eigene `matchId`.

**Marker**: `[committee]` (Skalierungs-Strategie), `[owner]` (Tier-Roadmap).

## OD-M4-02: Polling-Fallback — als Default behalten oder nur als Notfall?

**Frage**: M1–M3 nutzten 5 s Polling für Match-Liste / Detail / Bracket. M4 ersetzt das durch Realtime. Was passiert mit den Polling-Providern?

**Warum blockierend**: Bestimmt Code-Aufwand in M4.1-T5 (Screen-Umstellung) plus Test-Doppel-Verhalten.

**Optionen**:

- **A) Polling-Provider bleiben, werden aber default-deaktiviert solange Realtime joined ist** — Fallback-Pfad explizit im Code. Polling springt an wenn Channel-State `errored` oder Feature-Flag `realtime_enabled=false`.
  - Pros: nahtlose Degradation. Bei Realtime-Ausfall sieht der User weiter Daten (mit 5 s Verzögerung statt live).
  - Cons: zwei Code-Pfade parallel pflegen.
- **B) Polling-Provider löschen, Realtime ist der einzige Pfad** — bei Disconnect zeigt UI "offline, keine Updates" bis Reconnect.
  - Pros: weniger Code, klarere Semantik.
  - Cons: temporärer Realtime-Ausfall (z.B. WS-Bug bei Supabase, Mobile-Netz-Wechsel) blockiert den User.
- **C) Polling-Provider werden nach Feature-Flag-Stabilisierung gelöscht** — Wochen 1–4 nach M4 läuft beides parallel, danach Polling raus.
  - Pros: nachträgliche Aufräum-Option.
  - Cons: Cleanup-Aufwand wird verschoben statt erledigt — typischerweise wird er nie gemacht.

**Empfehlung**: **A — Polling bleibt als Fallback**. Begründung: ADR-0004 §"Things we explicitly do NOT do" sagt "Custom WebSocket / message queue — Supabase Realtime carries us through Tier 2". Wenn Supabase Realtime aber temporär ausfällt (operative Realität: ~99.9 % SLA → ~8 h pro Jahr Ausfall), ist Polling die saubere Degradation. Code-Duplikation ist klein (Polling-Provider sind je <30 LOC) und die Fallback-Logik (`if channelState == joined → realtime else → polling`) trivial. Cleanup (Option C) ist eine Falle.

**Marker**: `[committee]` (Operative Resilience).

## OD-M4-03: Spectator-Auth — anonym mit Public-Read-RLS oder Light-Auth?

**Frage**: Wer sieht öffentliche Turnier-Sichten — anonyme Browser ohne Login, oder verlangen wir Mindest-Login (z.B. Magic-Link, oder einen pseudonymen Account)?

**Warum blockierend**: Bestimmt RLS-Policy-Form (`TO anon` vs `TO authenticated`), JWT-Strategie, und Spectator-Channel-Subscribe-Pfad.

**Optionen**:

- **A) Anonym mit Public-Read-RLS** — anonymes Supabase-JWT (Build-Time-Public), RLS-Policy `FOR SELECT TO anon USING (tournaments.public = true)`. Keine Auth-Hürde.
  - Pros: Maximale Reichweite — Link teilen → Klick → sehen. Wie Sport-Liveticker.
  - Cons: kein User-Tracking, keine Analytics-Per-User, kein Schutz vor Scraping. Anon-JWT muss korrekt geconfigt sein.
- **B) Light-Auth via Magic-Link** — jeder Spectator braucht E-Mail-Magic-Link (bestehende Auth-Infra).
  - Pros: User-Tracking, später Personalisierung ("deine Lieblings-Teams"), kein Anonymous-Channel-Skalierungs-Problem.
  - Cons: Friktion → 80 % der Spectator klicken den Link nicht. Live-Liveticker-Stimmung weg.
- **C) Pseudonymer Account (Display-Name + Geräte-ID)** — Spectator gibt einen Nicknamen ein, bekommt einen Pseudo-Account ohne E-Mail.
  - Pros: irgendein Identitäts-Anker, weniger Friktion als Magic-Link.
  - Cons: Eigener Account-Typ — Komplexität, Auth-Modell aufweichen, Edge-Cases bei Account-Migration zu echtem Login.

**Empfehlung**: **A — Anonym mit Public-Read-RLS**. Begründung: Pilot-Zielgruppe (Schweizer Kubb-Szene) erwartet von einer Spectator-URL keinen Login — das ist die UX-Norm bei FIVB-Liveticker, kicker.de, etc. Anon-JWT ist Supabase-Standard, RLS gibt uns die Autorität. Personalisierung (Option B-Use-Case) ist M5+-Roadmap, dann mit echtem Account-Pfad. Pseudo-Accounts (C) erfinden ein drittes Auth-Modell — nicht jetzt.

Folgemassnahme: `tournaments.public bool DEFAULT true`. Veranstalter kann pro Turnier auf `false` umschalten, wenn er ein internes Turnier ohne öffentliche Sicht will (Edge-Case, Wizard-Flag).

**Marker**: `[owner]` (Policy: was darf öffentlich sichtbar sein), `[committee]` (UX-Tradeoff).

## OD-M4-04: Push-Notifications — eigener Folge-Milestone oder in M4 mit drin?

**Frage**: Spec verlangt Push-Notifications (FCM Android, APNs iOS) für Match-Start, Konflikt, Score-Erinnerung. Headline-M4-Outline aus Tournament-Foundation-Plan listet das auf. Schaffen wir das in 8–10 Tagen?

**Warum blockierend**: Bestimmt M4-Scope. Wenn drin → eigene Sub-Milestone M4.4, Aufwand +4–6 Tage. Wenn raus → klare Aussage im Plan, eigener Folge-Milestone.

**Optionen**:

- **A) Push komplett in M4 (M4.4 als vierte Sub-Milestone)** — FCM + APNs Setup, In-App-Notification-Konfiguration, Server-Trigger-RPCs für die drei Notification-Typen. +4–6 Tage Aufwand.
  - Pros: Live-Erleben "endlich-fertig" Gefühl nach M4.
  - Cons: 8–10 Tage werden 12–16. M4-Risiko steigt deutlich. APNs verlangt Apple Developer Account (ADR-0015: iOS ist nach M5). FCM allein ist Android-only — entspricht der Plattform-Sequenzierung aus ADR-0015.
- **B) Push als eigener Folge-Milestone "M4.5 Push"** — kommt nach M4.3, eigene 4–6 Tage. Inbox-Items decken In-App-Notifications ab; ohne Push gibt es keine OS-Banner.
  - Pros: M4-Budget bleibt realistisch. Push-Architektur kann sauber als eigener ADR entstehen (Trigger-Strategie, Quiet-Hours, Subscription-Management, Topic-Aufteilung).
  - Cons: User muss App offen lassen, um Updates zu sehen — Inbox-Pull ist nicht aktiv.
- **C) Push wird auf M5 zusammen mit Liga-System verschoben** — Liga-System bringt Saison-Tabellen, Match-Reminders für nächste Liga-Runde, etc. Push-Strategie ist da reicher motiviert.
  - Pros: konsolidierte Push-Implementierung mit mehr Use-Cases gleichzeitig.
  - Cons: M4-Demobar-Story ohne Push wirkt schwächer (Spectator muss aktiv refreshen, kein "ping aufs Phone").

**Empfehlung**: **B — Eigener Folge-Milestone M4.5**. Begründung: M4-Sub-Milestones 4.1–4.3 sind bereits am oberen Ende des 8–10-Tage-Budgets. Push-Notifications brauchen ein eigenes Stack-Stück (FCM-SDK, Topic-Subscription-Management, Server-Side-RPC-Trigger) plus eigenen ADR (Quiet-Hours, Opt-In-Mechanik, Topic-Hierarchie). Das verdient eigenen Plan-Zyklus statt am Rand von M4 mitgeschleppt zu werden. Inbox-Items aus M3.1 decken die In-App-Sicht ab — User sieht alles, wenn die App offen ist. OS-Banner kommt mit M4.5.

iOS-Push-Pfad bleibt ohnehin gesperrt bis Apple Developer Account vorliegt (ADR-0015 §"iOS verlangt Pipeline-Investition"). FCM-Android-only in M4.5 ist konsistent mit ADR-0015.

**Marker**: `[owner]` (Roadmap-Priorisierung), `[committee]` (Scope-Realismus).

## OD-M4-05: Lamport-Clock-Aktivierung im Event-Log — jetzt in M4 oder später?

**Frage**: ADR-0006 verlangt Lamport-Hydration und produktive Nutzung beim App-Start. Bisher (M0–M3) ist `LamportClock` implementiert aber nirgends im Schreib-Pfad genutzt. Schalten wir Lamport jetzt scharf, oder erst wenn Solo-Match-Live-Multi-Device kommt?

**Warum blockierend**: Bestimmt ob die Idempotency-Spalte im Outbox-Pfad echte semantische Funktion hat oder nur als Schlüssel dient. Bestimmt Hydration-Code-Aufwand (M4.3-T7).

**Optionen**:

- **A) Lamport jetzt aktivieren** — Outbox-Rows tragen Lamport-Counter und Device-ID, Server schreibt sie in `tournament_set_scores`-Tabelle, Idempotency-Check nutzt das Tupel. Hydration beim App-Start aus Outbox-Max + Server-Stream-Max.
  - Pros: ADR-0006-Folgemassnahmen werden produktiv. Multi-Device-Score-Eingabe auf demselben Match (zwei Captains aus demselben Team gleichzeitig) wird konsistent geordnet. Idempotency-Schutz greift.
  - Cons: Komplexität für einen Use-Case (Multi-Device-für-eine-Identität), den die Score-Eingabe heute nicht wirklich hat (Score wird typisch von einem Phone pro Team eingetragen).
- **B) Lamport erst aktivieren, wenn Solo-Match-Multi-Device aktiv wird (M5+)** — M4 nutzt für Idempotenz nur `(match_id, consensus_round, set_index, submitter, queued_at)` als Tupel, Lamport bleibt in `LamportClock` ungenutzt.
  - Pros: weniger Code in M4.3.
  - Cons: ADR-0006-Folgemassnahmen bleiben uneingelöst. `queued_at` ist Wall-Clock — bei Phone mit verstellter Uhr wird die Outbox-Order falsch. Lamport ist genau dafür da.
- **C) Hybrid — Lamport-Counter wird in der Outbox geführt, aber Server-seitig nur als opaker Idempotency-Marker behandelt (keine Stream-Replay-Semantik)** — Minimum-Aktivierung.
  - Pros: löst das `queued_at`-Wall-Clock-Problem, ohne den vollen Hydration-Pfad zu bauen.
  - Cons: Mittelweg ohne klaren Use-Case. Wenn wir Lamport schon haben, sollten wir ihn richtig nutzen.

**Empfehlung**: **A — Lamport jetzt aktivieren**. Begründung: ADR-0006 §"Followups" listet "Implementation task (M3 boundary): hydrate LamportClock at app boot from persisted events" und "(M3/M4 boundary): server-side validation rejecting events for matches with existing MatchFinished". M3 hat das nicht eingelöst, M4 ist die letzte saubere Gelegenheit vor M5 (Schweizer / Liga-Punkte — kein guter Zeitpunkt für Infrastruktur-Schichten). Outbox-Idempotency und Lamport-Hydration sind ein Implementierungsblock — wir machen beides gleichzeitig oder gar nicht. Multi-Device-Use-Case ist heute selten, wird aber mit Team-Captain-Score-Eingabe (BR-9, M3.2-Implementierung) realistischer (zwei Captains desselben Teams).

**Marker**: `[committee]` (technische Schuld).

## OD-M4-06: Sync-Outbox in drift — eigene Tabelle oder Update-Flag pro Match?

**Frage**: Wo persistieren wir ausstehende Score-Submissions — eigene drift-Tabelle `score_submission_outbox` oder ein Update-Flag (`pending_sync bool`) auf der bestehenden `tournament_score_drafts`-Tabelle?

**Warum blockierend**: Bestimmt das drift-Schema, die DAO-Form, und den Flusher-Code-Pfad.

**Optionen**:

- **A) Eigene Tabelle `score_submission_outbox`** — pro ausstehendem Submit ein Row mit Payload-JSON, Lamport-Marker, Retry-Counter, Acknowledgement-Status.
  - Pros: klare Trennung Draft (UI-State) vs Outbox (Sync-State). Multiple Submits pro Match (Konsens-Runden) sauber abbildbar. Unabhängige Retention-Policy.
  - Cons: zweite Tabelle, separate DAO.
- **B) Update-Flag auf `tournament_score_drafts`** — Bestehende `TournamentScoreDrafts`-Tabelle bekommt `pending_sync bool`, `last_attempt_at`, `last_error`. Flusher iteriert über `WHERE pending_sync = true`.
  - Pros: weniger Schema, weniger Code.
  - Cons: Draft hat aktuell PK `(matchId, consensusRound)` — wenn ein Match mehrere Sets mit unabhängigem Sync-Status hat, müssen wir den Draft pro Set splitten. Verändert Draft-Semantik invasiv. Draft ist "noch nicht abgeschickt", Outbox ist "abgeschickt aber unack" — semantisch unterschiedlich.
- **C) Append-only Event-Log in eigener Tabelle** — analog `match_events` aus M0, für jede Score-Submission ein Event. Server-Sync ist Event-Replay.
  - Pros: konsequenter Event-Sourcing-Pfad, passt zu ADR-0006-Geist.
  - Cons: deutlich mehr Aufwand. Server-Pfad ist heute kein Event-Log, sondern RPC-basiert — würde Server-Schema-Refactor erzwingen.

**Empfehlung**: **A — Eigene Tabelle `score_submission_outbox`**. Begründung: Draft (UI-Zwischenstand vor Submit) und Outbox (gequeut, wartet auf Server-Ack) sind semantisch unterschiedlich — beim Submit wechselt der Status von Draft zu Outbox. Eine geteilte Tabelle vermischt das. Eigene Tabelle ist je <60 LOC drift-Code plus DAO. Event-Log (C) wäre Re-Refactoring der Server-Strategie — out of scope für M4.

Außerdem: Outbox-GC (Retention 30 Tage nach Ack) ist sauberer auf eigener Tabelle. Draft hat keine Retention — er wird bei Submit gelöscht.

**Marker**: `[committee]` (Schema-Design).

## OD-M4-07: Realtime-Channel-Auth — RLS-basiert oder ChannelAuthToken?

**Frage**: Supabase Realtime kennt zwei Auth-Modelle für Channels: RLS-basiert (jeder mit gültigem JWT subscribt, RLS filtert die Rows) oder ChannelAuthToken (per-Channel-Permission-Token, das der Server vor Subscribe ausgibt).

**Warum blockierend**: Bestimmt den Channel-Adapter-Code-Pfad, die RLS-Policies, und das Spectator-Channel-Setup.

**Optionen**:

- **A) RLS-basiert** — anonymes / user-JWT, Postgres RLS-Policies filtern automatisch. Channel-Subscribe braucht keinen Extra-Server-Call.
  - Pros: weniger Round-Trip, weniger Code, RLS ist ohnehin die Wahrheit. Konsistent mit allen anderen Supabase-Pfaden.
  - Cons: Wenn RLS-Policy versehentlich zu offen ist → Channel-Subscriber sieht zu viel.
- **B) ChannelAuthToken** — Backend gibt pro Channel-Subscribe ein signiertes Token aus, das Channel-spezifische Permissions enthält.
  - Pros: feinere Steuerung. Veranstalter kriegt Token mit "alle Pitches dieses Turniers", Spectator nur "public Match Liste".
  - Cons: Extra-Server-Call vor Subscribe (Latenz). Eigene Token-Lifecycle-Verwaltung (Refresh, Revoke). Komplexität.
- **C) Hybrid — RLS für Lese-Streams, Token nur für Schreib-Channels (Heartbeat-Channels für aktive Veranstalter)** — bei Use-Cases mit Schreib-Komponente.
  - Pros: kontrollierter Schreib-Pfad.
  - Cons: M4 hat keine Channel-Schreib-Komponente. Schreiben läuft weiter über RPCs.

**Empfehlung**: **A — RLS-basiert**. Begründung: M4 hat keine Channel-Schreib-Komponente (alles Schreiben geht über RPCs, die ihrerseits Realtime-Events triggern). RLS-Policies sind die Wahrheit für die Schreib-Pfade — die gleiche Policy nochmal als Channel-Token zu codieren wäre Redundanz. Risiko "RLS zu offen" mitigieren wir durch pgTAP-Tests (M4.2-T2) die explizit anonymen Schreib- und Lese-Zugriff prüfen. ChannelAuthToken (B) ist überengineering für unser Datenmodell.

**Marker**: `[committee]` (Security-Modell).

---

## Übersicht der ODs nach Marker

| ID | `[committee]` | `[owner]` | `[domain]` | Blockt |
|---|---|---|---|---|
| OD-M4-01 | ja | ja | — | M4.1-T1 |
| OD-M4-02 | ja | — | — | M4.1-T5 |
| OD-M4-03 | ja | ja | — | M4.2-T1 |
| OD-M4-04 | ja | ja | — | M4-Scope |
| OD-M4-05 | ja | — | — | M4.3-T2, M4.3-T7 |
| OD-M4-06 | ja | — | — | M4.3-T1 |
| OD-M4-07 | ja | — | — | M4.1-T2, M4.2-T1 |

Zählung: 7 ODs gesamt. Marker-Verteilung:
- `[committee]`: 7 (alle — Technik / Skalierung / UX)
- `[owner]`: 3 (OD-M4-01 Roadmap-Berührung, OD-M4-03 Privacy-Policy, OD-M4-04 Roadmap-Priorität)
- `[domain]`: 0 (keine Kubb-Regel-Frage)

## Entscheidungs-Reihenfolge

Sequenz vor Implementations-Start:

1. **OD-M4-01** entscheiden — Channel-Granularität ist die Architektur-Grundsatzentscheidung.
2. **OD-M4-04** entscheiden — bestimmt M4-Scope (Push drin oder nicht).
3. **OD-M4-03** entscheiden — Spectator-Auth bestimmt RLS-Policy-Form.
4. **OD-M4-07** entscheiden — Channel-Auth-Modell (folgt aus OD-M4-03).
5. **OD-M4-05** und **OD-M4-06** parallel — beide M4.3-spezifisch.
6. **OD-M4-02** kann zuletzt — Polling-Fallback ist taktische Frage.

Bei Architect-Empfehlung-Übernahme: alle 7 ODs in einem Aufwasch resolvable (analog M2/M3-Verfahren).

## Was die ODs explizit NICHT entscheiden

- **Sentry-Integration** — ADR-0004 listet das für M4. Wird ohne OD als Architect-Default mitgenommen: Sentry-SDK in `lib/main.dart` initialisieren, Errors automatisch melden, Performance-Tracing für Realtime-Subscribe und Outbox-Flush. Separater Task in M4.3 (oder M4.1), kein eigenes OD.
- **Web-Build-Status** — siehe `risks-and-deferrals.md`. ADR-0015 sagt Web-Spike vor M2. Falls Web-Spike noch nicht erledigt, eskaliert M4.2-T6 (Public-Screen ist Web-First).
- **Wahl von `connectivity_plus` vs Alternative** — Standard-Flutter-Community-Plugin, MIT, aktive Pflege. Kein eigener ADR nötig.
- **Schweizer DSGVO / DSG für anonyme Spectator** — Public-RLS speichert keine personenbezogenen Daten (kein User-Tracking auf Spectator-Seite). Sentry braucht eigene Disclosure → wird Teil der Sentry-Integration-Task.
