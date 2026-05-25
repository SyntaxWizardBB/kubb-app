# Tournament foundation — Risiken und Deferrals

> Status: Entwurf
> Datum: 2026-05-25

## Hoch-Risiko-Items

### R-1: Score-Eingabe-UI in 30 Sekunden am Pitch

Die NFR-UX-1-Anforderung "Score-Eingabe in unter 30 Sekunden, robust gegen nasse Finger" ist die Kernanforderung. Pro Satz drei Eingaben (Basekubbs A, Basekubbs B, König) × 1–5 Sätze × Bestätigungs-Dialog × Konflikt-Anzeige × Outbox-Status. Wenn das UI nicht extrem schnell ist, fühlt sich die App schlechter an als der existierende WordPress-Tournament-Manager — den die App ja ablösen soll.

**Mitigation**: Frühe Usability-Tests am Pitch (M1-Demo direkt im echten Setting), Stepper statt Tastatur als Default, grosse Touch-Ziele (NFR-UX-1 nennt 60×60 px). Bei OD-05 wurde empfohlen, im MVP mit Match-Total statt EKC-per-Satz zu starten — das halbiert den Eingabe-Aufwand und ist konsistent mit der existierenden Solo-Match-UI.

### R-2: Bracket-Generation und Schweizer System

Round-Robin ist trivial. Schweizer System hat scharfe Kanten: Wiederholungs-Vermeidung, BYE-Verteilung, Floater-Logik, Sortierung nach Tiebreaker vor der Paarung. Die typische Falle: Implementierung sieht in Tests gut aus, fällt in der Praxis bei ungeradem Teilnehmerfeld + Wiederholungs-Sperre in eine unauflösbare Konstellation.

**Mitigation**: Schweizer System ist explizit in M5 und nicht im MVP. M1 nutzt Round-Robin oder simples Single-Elimination. Wenn M5 kommt, gibt es einen separaten Spike-Tag für die Schweizer-System-Implementierung mit Stresstests gegen pathologische Eingabedaten.

### R-3: Realtime-Skalierung

Supabase Realtime hat 200 gleichzeitige Verbindungen auf Free Tier, 500 auf Pro. Ein Turnier mit 50 Spielern + 100 Zuschauern × mehrere offene Tabs erreicht das schnell. Tier 1 erreichen wir spätestens beim zweiten parallelen Turnier.

**Mitigation**: Hybride Strategie aus OD-01 (nur Match-Detail per Realtime, Listen per Polling). Skalierungs-Trigger aus ADR-0004 sind aktiv ab M4 (Realtime-Einführung).

### R-4: Cross-Platform-Build (Web/Linux kaputt)

Web-Build ist nicht getestet (drift dart:ffi, ADR-0005 WASM-Spike noch nicht durchgeführt). Linux-Build auf der Dev-Maschine scheitert an pkg-config. Android funktioniert. Owner will alle fünf Plattformen.

**Mitigation**: M1 ist Android-only (OD-02). Web wird vor M2 mit 2-Tage-Spike geklärt — entweder Drift-on-Web zum Laufen bringen oder per ADR-0005 die Web-Variante auf `SupabaseTournamentRemote`-only ohne lokales Drift. Linux-Build-Problem ist Owner-eigener Komfort als Entwickler, kein User-Issue.

### R-5: Vermischung Solo-Match und Turnier-Match

Wenn die `public.matches`-Tabelle für beide Welten verwendet wird (per OD-06 Empfehlung B), wachsen die Code-Pfade `match_propose_result` (Solo) und `tournament_propose_set_score` (Turnier) auseinander. RLS-Policies werden komplexer (zwei Berechtigungspfade auf derselben Zeile). Bugs in einer Welt können die andere betreffen.

**Mitigation**: klarer Trennstrich bei der RPC-Ebene — beide RPCs schreiben in dieselbe Match-Identität, aber die Reconciliation-Logik ist je RPC separat. Audit-Events zeigen klar an, welcher Pfad sie geschrieben hat. Integrationstests decken beide Pfade ab.

### R-6: Liga-Punkte-Berechnung rückwirkend

FR-POINTS-13: "Wenn ein Custom-Punkte-Turnier nachträglich freigegeben wird, werden die Punkte rückwirkend in die laufende Saison eingebucht." Das verlangt eine Re-Berechnungs-Funktion, die mit eingefrorenen Saisontabellen klarkommt.

**Mitigation**: Out of scope bis M5. Wenn M5 kommt, separater Spike für die Re-Berechnungs-Logik.

### R-7: Audit-Trail-Konsistenz

Drei Tabellen führen Audit-Logs: `match_audit_events` (existiert für Solo), `tournament_audit_events` (neu), und eine spätere `liga_audit_events` (für Liga-Wechsel). Wenn sie auseinanderlaufen, wird das Plattform-Admin-Dashboard zur Diskontinuität.

**Mitigation**: Einheitliche Event-Schema-Struktur (`kind`, `actor_user_id`, `payload`, `at`) über alle Audit-Tabellen. Spätere Vereinheitlichung in eine einzige `audit_events`-Tabelle mit `domain`-Diskriminator ist möglich, aber kein MVP-Thema.

## Explizit deferred aus dem MVP

Diese Punkte sind Teil der Spec, aber bewusst nicht im ersten Slice. Begründung jeweils kurz.

| Bereich | FR | Verschoben auf | Grund |
|---|---|---|---|
| KO-Bracket | FR-FMT-1, FR-FMT-5, FR-FMT-10, FR-FMT-11 | M2 | MVP-Slice nutzt nur Round-Robin |
| Bracket-Visualisierung | FR-PUB-6 | M2 | Hängt an KO |
| Teams, Pool, Roster | FR-TEAM-1..-20, FR-REG-2/-11/-12 | M3 | Owner Roadmap: Solo zuerst |
| Schweizer System, Schoch | FR-FMT-3, FR-FMT-4, FR-FMT-6, FR-FMT-7 | M5 | Komplexe Paarungs-Logik |
| Liga-Punkte | FR-POINTS-1..-18 | M5 | Hängt an Saison-Modell |
| Globales Ranking, Liga-System | FR-GLB-1..-22 | M5 | Hängt an Liga-Punkte |
| Liga-Administrator-Rolle, mid-season-Wechsel | FR-ADM-14..-17 | M5 | Hängt an Liga-System |
| Vereine, Vereins-Admin | FR-CLUB-1..-8 | nach M5 | Eigene Domain, hängt an Rollen-Modell |
| Veranstalter-Bewertung | FR-FEEDBACK-1..-7 | nach M5 | Optional für Tournament-Funktion |
| Lageplan | FR-MAP-1..-5 | nach M5 | Nice-to-have, keine Blocker |
| Vollbild-Streaming-Sicht | FR-PUB-10 | nach M5 (KANN) | Spec sagt KANN |
| Shared Tournament Liga-Split | FR-FMT-8, FR-POINTS-14/-15 | nach M5 | Hängt an Liga-System |
| Double Elimination | FR-FMT-9 | nach M5 (KANN) | Spec sagt KANN |
| Privacy-Granularität pro Datenkategorie | FR-AUTH-5 | nach M5 | OD-03 deckt die wichtigste Trennung |
| Datenexport | FR-AUTH-6 (KANN) | nach M5 | Spec sagt KANN |
| Self-Check-In per QR | FR-REG-9 (SOLL) | M4+ | Hängt an Check-In-Flow |
| Französisch + Englisch | NFR-I18N-2 | nach M5 | Deutsch zuerst pro NFR-I18N-1 |
| In-App-Postfach für Turnier | FR-NOT-7 | M4 | Inbox-System existiert (per ADR-0011) — anschliessen statt neu bauen |
| Auto-Auf-/Abstiegsregeln Liga | (Open Point 3 der Spec) | nach M5 | Owner-Entscheidung steht aus |
| Anti-Cheat, Sanktionen | (Open Point 4 der Spec) | nach M5 | Owner-Entscheidung steht aus |
| Achievements, Badges | (Open Point 5 der Spec) | nach M5 | Owner sagt explizit später |

## Bekannte Einschränkungen der Dev-Umgebung

Diese Punkte sind keine Architektur-Risiken, sondern Reibungspunkte beim Entwickeln.

- **Linux-Build (Dev-Maschine)**: scheitert an pkg-config-Kette. Ist nicht Teil des MVP-Targets (siehe OD-02), aber Owner kann lokal nichts auf Linux ausprobieren. Workaround: alles auf Android-Device demoen.
- **Web-Build**: ADR-0005-WASM-Spike pending. Vor M2 entweder Spike durchziehen oder per ADR-0005 die Web-Variante ohne lokales Drift bauen (`SupabaseTournamentRemote`-only auf Web). Beide Pfade sind machbar.
- **iOS-Build**: braucht Apple Developer Account + macOS-Build-Maschine. Owner hat aktuell keinen davon. Verschoben auf M3 oder später.
- **Supabase-Quota**: Free Tier ausreichend für Tier-0 (siehe ADR-0004). Bei mehreren parallelen Test-Turnieren während der Entwicklung kann die Tabellengrösse-Grenze interessant werden — quartal-pg_dump als Backup ist sowieso vorgesehen.
- **Push-Notifications**: noch nicht implementiert. Spec verlangt FCM (Android), APNs (iOS), Web Push. M4 schliesst das ab. M1 kommt ohne Push aus — Eingabe-Erinnerungen aus DSCORE-105 fallen entsprechend weg im MVP.

## Nicht-Risiken (zur Klärung)

Diese Punkte werden gelegentlich als Risiko diskutiert, sind aber adressiert:

- **Supabase-Migration**: ADR-0004 beschreibt einen 5-Wochen-Migrationspfad nach Self-Hosted-Supabase. Kein Lock-In-Risiko.
- **Per-Throw vs. Per-Match-Event**: Per-Match per ADR-0013 + feature-note bestätigt. Diskussion abgeschlossen.
- **Drift-on-Web Spike**: ADR-0005 hat den Weg vorgesehen, Web-Client braucht nur `SupabaseTournamentRemote` + IndexedDB-Draft-Cache.
- **Solo-Match-Pfad und Turnier-Pfad-Koexistenz**: technisch sauber zu trennen (OD-06), kein Risiko.
