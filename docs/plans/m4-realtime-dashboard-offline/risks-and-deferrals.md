# M4 — Realtime + Live-Dashboard + Offline — Risiken und Deferrals

> Status: Entwurf
> Datum: 2026-05-27

## Risiken pro Sub-Milestone

### M4.1 — Realtime-Layer

**R-M4.1-1: Supabase-Realtime hat unklare SLA beim Free-Tier**

Supabase Free-Tier garantiert keine Verfügbarkeit für Realtime — Status-Seite zeigt periodisch WS-Disconnects, besonders in der EU-Region am Wochenende. Bei Pilot-Demo könnte das peinlich werden.

**Mitigation**: OD-M4-02-Empfehlung A (Polling-Fallback bleibt aktiv) ist die direkte Antwort. Banner zeigt "Polling aktiv, Live nicht verfügbar" wenn Channel-State `errored` länger als 60 s. Smoke-Test vor Demo: Channel manuell killen (Browser-Devtools-Network-Drop), prüfen ob Polling übernimmt.

**R-M4.1-2: Channel-Sharing per Key kann Race-Conditions bei schnellem Subscribe-Unsubscribe-Zyklus haben**

Wenn der User zwischen zwei Match-Detail-Screens hin- und herwechselt, könnte derselbe Channel-Key innerhalb von <100 ms unsubscribed und resubscribed werden. `supabase_flutter` ist in der Channel-Lifecycle-Behandlung nicht immer robust gegen das.

**Mitigation**: `SupabaseRealtimeChannel`-Adapter führt einen Reference-Counter pro Key. `close()` wird erst aufgerufen wenn Counter auf 0 fällt. 500 ms Debouncing vor finalem Close, um schnelle Re-Subscribes nicht zu verlieren. Integrations-Test mit Screen-Wechsel-Loop deckt das ab.

**R-M4.1-3: WebSocket auf Web mit Cookie-Auth funktioniert nicht in Inkognito**

Spectator-Path (M4.2) öffnet Public-URL in Inkognito-Browser. Anon-JWT muss als URL-Query-Parameter oder LocalStorage transportiert werden — `supabase_flutter` Web-Build hat hier in älteren Versionen Bugs.

**Mitigation**: Bei M4.2-T6 Web-Spike — Inkognito-Browser-Smoke-Test als Akzeptanzkriterium. Falls Bug: Anon-JWT explizit beim `supabase.realtime.connect()`-Aufruf mitgeben statt auf Auto-Auth zu vertrauen. Wenn das nicht reicht: Spectator-Path nutzt erstmal nur Polling (Live-Modus-Toggle inaktiv für Anon), Realtime-Public-Channel kommt mit M4.5.

### M4.2 — Live-Dashboard + Spectator-View

**R-M4.2-1: Public-RLS-Policy ist sicherheitskritisch — ein Bug leakt private Turnier-Daten**

Wenn `tournaments_public_read` fälschlich auch `draft`-Rows einschliesst oder die Spalten-Filter falsch sind, sehen anonyme Besucher Daten die sie nicht sehen sollten.

**Mitigation**: pgTAP-Tests in M4.2-T2 sind merge-blocking. Mindestens drei Test-Fälle: (a) anon kann `public=true` lesen, (b) anon kann `public=false` NICHT lesen, (c) anon kann nicht UPDATE / INSERT. Security-Checker-Agent (per Workbench-Rules) ist eingebaut. Falls Owner zusätzliche Tests will: Penetrations-Smoke mit `curl` + anon-JWT.

**R-M4.2-2: Spectator-Spalten-Privacy — Roster-Slots zeigen User-Anzeigenamen**

Ein Spectator sieht "Team Hammer-Crew: Anna M., Beat S., Carlo T.". Das ist von FR-PUB-9 gedeckt aber bei manchen Vereinen heikel (Datenschutz-Awareness).

**Mitigation**: View `public_tournament_roster_view` projiziert nur display_name aus `team_memberships.user_id → auth.users` (kein E-Mail, keine User-IDs). Veranstalter kann pro Turnier "Anonyme Roster"-Toggle setzen (Default: aus) — dann zeigen Public-Sichten nur "Team Hammer-Crew (3 Spieler)" ohne Namen. Toggle ist Wizard-Feld. Aufwand: kleine Schema-Erweiterung in M4.2-T1, +0.5 Tag.

**R-M4.2-3: Spectator-Channel-Skalierung im Viral-Fall**

Wenn ein Turnier in Social Media geteilt wird → 200+ concurrent Spectators → Free-Tier-Channel-Limit (200) ist sofort gerissen, eingeloggte Veranstalter werden mit-blockiert.

**Mitigation**: Live-Modus-Toggle ist Default-AUS für Public-Spectator-Sicht (OD-M4-01-Folge). Polling alle 10 s ist Spectator-Default. Live-Modus nur bei explizitem User-Klick — typischerweise nur engagierte Zuschauer aktivieren. Skalierung damit ~linear zu eingeloggten Veranstaltern, nicht zu viralen Spectator-Visits.

### M4.3 — Offline + Sync-Outbox

**R-M4.3-1: drift-Migration für die neue Outbox-Tabelle ist nicht-trivial in einem schon ausgelieferten App-Bestand**

Die App hat schon drift-Schema-Version N. Outbox-Tabelle einfach hinzufügen verlangt `MigrationStrategy.from(N) to (N+1)` — falls falsch implementiert, kollidiert mit bestehenden lokalen Drafts.

**Mitigation**: drift-Migration ist additiv (`CREATE TABLE IF NOT EXISTS`). Migration-Test in `app_database_test.dart` lädt eine alte Datenbank-Datei (Fixture) und prüft Upgrade. Bei Test-Fail: M4.3-T1 wird L statt M.

**R-M4.3-2: Idempotency-Check auf Server greift nur wenn Lamport-Counter und Device-ID übereinstimmen — aber Device-ID kann sich ändern**

Wenn ein User die App neu installiert (oder Datenbank löscht), wechselt seine Device-ID. Re-Submit aus alter Outbox (falls vorhanden) würde dann nicht-idempotent durchgehen.

**Mitigation**: Device-ID wird beim ersten Start in `flutter_secure_storage` persistiert (überlebt App-Reinstallation auf Android wenn Backup aktiviert). Bei Daten-Wipe: Outbox ist auch weg (drift-DB), kein Re-Submit-Risiko. Edge-Case "User installiert neu auf neuem Phone und syncht alte Outbox" gibt es nicht — Outbox ist devicelokal.

**R-M4.3-3: Outbox-Konflikt-UI ("erneut eingeben") ist unangenehm für den User**

Wenn Outbox-Flush einen `STALE_CONSENSUS_ROUND` zurückbekommt (Gegner ist schon in der nächsten Konsens-Runde), muss User den Score erneut eingeben. In der Hitze des Turniers ist das ein UX-Loch.

**Mitigation**: Konflikt-Banner in der Match-Detail-Sicht zeigt klare Erklärung "Dein Vorschlag konnte nicht übertragen werden, weil der Gegner schon korrigiert hat. Bitte erneut eingeben." Plus Link "Letzten Vorschlag anzeigen" — User sieht was er eingegeben hat. Aufwand: +0.5 Tag in M4.3-T8. Nicht-mitigierbares Restrisiko: User muss noch einmal hinschauen — das ist der Preis für Offline-Toleranz mit Drei-Versuche-Konsens.

**R-M4.3-4: Lamport-Hydration aus Server-Stream verlangt aktiven Realtime-Connect**

Wenn die App startet während offline, kann Lamport-Hydration nur aus der lokalen Outbox lesen. Server-Counter ist unbekannt — Outbox-Counter ist dann nicht garantiert höher als Server-State.

**Mitigation**: Sobald Realtime-Channel `joined` ist, observed der `LamportClock` den höchsten Counter aus dem ersten Stream-Batch und springt damit auf den korrekten Wert. Bis dahin können neue Ticks aufeinander aufbauen — der Konsequenz: zwei Devices, die beide offline starten, könnten kurzzeitig dieselben Counter-Werte erzeugen. Im Score-Pfad ist das durch `(consensus_round, submitter)` als Sekundär-Diskriminator abgefangen. Echte Race-Bedingung nur bei zwei Captains, die innerhalb derselben Sekunde dasselbe Set eintragen — extrem selten, durch Konsens-Konflikt auflösbar.

### Übergreifend

**R-M4-G1: Web-Build-Status unklar**

ADR-0015 verlangte einen Web-Spike vor M2. Status ist nicht klar dokumentiert (Spike könnte stattgefunden oder verschoben sein). M4.2 hat öffentliche Spectator-URL — Web-First-Use-Case. Wenn der Web-Build heute scheitert, blockiert das M4.2.

**Mitigation**: Vor M4.2-Start: Web-Build-Status verifizieren. Falls Spike noch nicht erledigt → M4.2-T0 (Web-Spike, 1–2 Tage) wird vorgelagert. Falls Web grundsätzlich nicht funktioniert → Spectator-View bleibt Mobile-Web (Browser auf Phone öffnet die Public-URL als progressive Web App), Desktop-Web kommt nach M4 / M5. Eskaliert an Owner vor M4.2-Start.

**R-M4-G2: Drei Owner-Reviews zwischen Sub-Milestones — Pause-Risiko**

Wie bei M2 / M3: drei Sub-Milestones, drei potenzielle Pause-Punkte. Wenn Owner zwei Wochen Pause macht, läuft Cadence aus.

**Mitigation**: M4.1 ist isoliert demobar (Realtime ersetzt Polling, sichtbar in bestehenden Screens — keine neue UI nötig). Owner kann nach M4.1 abnehmen ohne weiteren Featuredurchbruch. M4.2 ist eigenständig demobar (Dashboard + Public-View). M4.3 schliesst ab. Owner-Abnahme-Frequenz lässt sich mit den Sub-Milestone-Demo-Skripten gut takten.

**R-M4-G3: Realtime macht Test-Setup deutlich schwerer**

Integrations-Tests, die Realtime testen, brauchen entweder einen echten Supabase-Mock-Server oder eine Fake-Channel-Implementation. Beide sind aufwändig.

**Mitigation**: `FakeRealtimeChannel` als `package:kubb_domain/test_support/`-Stelle, die `RealtimeChannel`-Port mit In-Memory-StreamController implementiert. Tests injizieren Fake statt Supabase. Echter End-to-End-Test gegen lebendes Supabase nur für M4.1-T8 — gegen Pilot-Projekt-Instanz, einmal manuell pro Wave.

**R-M4-G4: ADR-0015 sagt iOS nach M5, aber Spectator-Pfad ist Cross-Platform**

iOS-User können die Public-Spectator-URL im Safari öffnen — das funktioniert ohne native App. M4.2 ist also iOS-tauglich, ohne den iOS-Build zu zwingen.

**Mitigation**: Keine — das ist eher eine Klarstellung. Public-Spectator-URL ist Web-First, native iOS-App folgt mit M5+.

## Was bewusst auf M4+ verschoben wird

| Bereich | FR | Verschoben auf | Grund |
|---|---|---|---|
| Push-Notifications (FCM Android) | FR-NOT-1..-7 | M4.5 (eigener Folge-Milestone) | OD-M4-04, Scope-Realismus |
| Push-Notifications (APNs iOS) | FR-NOT-1..-7 | M5+ | iOS-Build-Pfad noch nicht offen (ADR-0015) |
| Runden-Clock mit Pause / Verlängerung / vorzeitigem Ende | FR-LIVE-5..-8 | M4.4 oder M5 | Eigener Algorithmus, orthogonal zu Realtime |
| Vollbild-Streaming-Sicht | FR-PUB-10 (KANN) | nicht priorisiert | KANN, nicht MUST |
| Cross-Tournament-Spectator-Übersicht | — | nicht priorisiert | Use-Case spekulativ |
| Realtime für Roster-Änderungen | FR-TEAM-14 (live-roster) | nicht priorisiert | Roster ändert sich langsam, Polling reicht |
| Konflikt-Auto-Merge für Outbox-Konflikte | — | nicht priorisiert | Widerspricht Drei-Versuche-Konsens (M1) |
| Pro-Set-Substitution mid-Match | FR-TEAM-13 Erweiterung | M5 | Set-State-Tracking auf Match-Ebene fehlt (Carry-over aus M3 OD-M3-07) |
| Multi-Region-Deploy für Realtime | — | nach Tier 2 | ADR-0004: Single-Region bis Latency-Complaints |

## Bekannte Einschränkungen — bleiben aus M1–M3 erhalten

- **iOS, Linux, Windows-Build**: M4 bleibt Android-only auf Mobile. Web-Build wird mit M4.2 Pflicht (Spectator-Path). iOS / Linux / Windows nach M5 (ADR-0015).
- **Score-Eingabe-Granularität**: per-Match-Result mit per-Set-EKC, keine per-Wurf-Events (ADR-0014, OD-08 Tournament-Foundation).
- **Solo-Match-Pfad bleibt unverändert**: `MatchEventRepository.watchEvents` wird in M4.1 als Port erweitert, aber UI-seitig nicht produktiv. Solo-Match-Multi-Device-Live-View kommt frühestens M5.
- **Free-Tier-Skalierungs-Grenzen**: Realtime 200 concurrent, Postgres ~50 req/s. Tier 1-Upgrade ($25/mo) bei MAU > 400 (ADR-0004).

## Nicht-Risiken (zur Klärung)

- **Anonyme Public-Spectator-Sicht ist DSGVO-konform**: kein Tracking, keine personenbezogenen Daten (User-Anzeigenamen sind FR-PUB-9-gedeckt). Sentry-Integration braucht eigene Disclosure, aber das ist M4-überschritten (separater Task).
- **Polling-Fallback bleibt im Code**: bewusst. Operative Resilience > Code-Cleanup. OD-M4-02 dokumentiert die Entscheidung.
- **Outbox-Tabelle als zweite Persistenz neben Drafts**: bewusst. OD-M4-06-Empfehlung — Draft (UI-State) und Outbox (Sync-State) sind semantisch unterschiedlich.
- **Lamport-Counter wird beim ersten App-Start in M4 produktiv**: bewusst — ADR-0006 hat das als Folgemassnahme markiert. M4 ist die saubere Gelegenheit (vor M5 Liga / Schweizer).
- **Spectator nutzt anonymes JWT (Build-Time-Public)**: bewusst. Supabase-Standard-Modell, Risiko durch RLS gedeckt.

## Demobarkeits-Risiko-Bewertung

Damit der M4-Demo am Tablet / Phone funktioniert, müssen drei Dinge bei der Demo stabil sein:

1. **Realtime-Connect**: WS-Connection zu Supabase steht. Falls Free-Tier flaky: Pre-Demo-Connection-Test, ggf. auf Pro-Tier upgraden für Demo-Tag ($25 / Monat — vernachlässigbar).
2. **Spectator-URL**: Public-URL muss von einem zweiten Gerät (Inkognito-Browser) erreichbar sein. Verlangt Web-Build und DNS-Setup. Pre-Demo-Smoke.
3. **Outbox-Flush**: Flugmodus-Toggle muss zuverlässig sein — auf manchen Android-Versionen ist der Toggle träge. Falls Bug: manueller WLAN-Disconnect via Settings.

Pre-Demo-Checklist gehört in `demo-script.md` (folgt aus dem Sprint-Plan).
