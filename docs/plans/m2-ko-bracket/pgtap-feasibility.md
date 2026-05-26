# pgTAP Feasibility für M2.2-Server-Tests

- **Stand**: 2026-05-26
- **Entscheidung**: pgTAP für T5 (Property-Parität-Sweep), Dart-Integration als Backup für T6, falls Auth-Setup-Kosten überschreiten

## Befund

### Local Supabase Stack

Das Repo nutzt den Standard-Supabase-CLI-Stack (`supabase/config.toml`, `major_version = 15`, Docker-basiert via `supabase start`). Das offizielle Supabase-`postgres`-Image bringt die `pgtap`-Extension bereits mit; sie ist nicht voreingeschaltet, lässt sich aber per `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` aktivieren (Standard-Pattern in `supabase/migrations` oder im Test-Setup-File).

Der Test-Runner `supabase test db` ist Teil der Supabase CLI. Er startet einen Container mit `pg_prove` und mountet `supabase/tests/` als Volume. Eine separate Installation von `pg_prove` auf dem Dev-Host ist nicht nötig — die CLI bringt alles mit. Test-Files leben unter `supabase/tests/*.sql` und werden alphabetisch ausgeführt; Setup-Hooks per Naming-Konvention (`000-setup-tests-hooks.sql`) etablieren z. B. das `pgtap`-Schema und gemeinsame Fixtures.

Im Repo fehlt `supabase/tests/` bisher komplett — keine SQL-Tests, kein Setup-File. Neuanlage ist Teil von T5/T6.

### CI

Es existiert keine `.github/workflows/`-Konfiguration im Repo. Existierende Server-Smoke-Tests laufen als Bash-Scripts (`tools/auth-smoketest/run.sh`, `tools/auth-smoketest/postgrest_smoketest.sh`) gegen einen manuell gestarteten lokalen Stack. Es gibt kein automatisiertes CI-Gate für `flutter test` oder `supabase test db`.

Das heißt: "CI" ist aktuell `flutter test` auf dem Dev-Host (Proxy für Pre-Commit). Ein Pflicht-Gate "Property-Parität als Merge-Gate" (ADR-0017 §7 letzter Absatz) lässt sich heute nur als manueller Schritt im Sprint-Workflow durchsetzen oder per Pre-Push-Hook lokal — bis eine GitHub-Actions-Pipeline da ist. Beide Test-Varianten (pgTAP wie Dart-Integration) teilen sich dieses Limit.

### Hosted Supabase Frankfurt

Supabase-Cloud listet `pgtap` als unterstützte Extension; sie lässt sich pro Projekt via Dashboard (Database → Extensions) oder per Migration aktivieren. Keine bekannten Regional-Restriktionen für `eu-central-1`/Frankfurt — die Extension ist projektgebunden, nicht regionsgebunden. Tests gegen den Hosted-Stack laufen mit `supabase test db --linked`; dafür braucht das Repo ein verlinktes Projekt (`supabase link`), was im aktuellen Setup nicht der Default-Workflow ist (ADR-0009 trennt Hetzner-Produktion vom CLI-Stack).

Für M2.2 ist Hosted-Frankfurt nicht der Test-Zielpfad — Tests laufen gegen den lokalen Docker-Stack. Hosted-Verfügbarkeit ist nur dann relevant, falls man die Server-Logik gegen die echte Frankfurt-Instanz smoke-testen will (T7c o. ä.); das ist orthogonal zu T5/T6.

## Setup-Aufwand pro Option

### Option A: pgTAP

- **Setup-Aufwand**:
  - Neuer Ordner `supabase/tests/` plus Setup-File `000-setup-tests-hooks.sql` mit `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` und gemeinsamen Fixtures (Test-Veranstalter, Test-Turnier-Skeleton).
  - Property-Parität-Test (T5): SQL-File, das in pgplsql den Helper `_tournament_compute_ko_bracket(n, third_place)` aufruft und gegen die per JSON eingebettete Dart-Referenz-Bracket-Serialisierung vergleicht. Referenz kann vorab via einmaligem `dart run` als JSON-Fixture erzeugt werden (deterministisch, daher reproduzierbar).
  - Optional: `basejump-supabase_test_helpers` für Auth-Kontext-Switches in T6.
  - Lokaler Aufruf: `supabase test db`. Kein extra Tooling auf dem Dev-Host.
- **Coverage**:
  - T5 (Property-Parität): vollständig, läuft direkt gegen den plpgsql-Helper, schnelle Iteration.
  - T6 (RPC-Tests inkl. Authorization, Phase-Validierung, Idempotency, Walkover): vollständig möglich, aber Auth-Setup (`auth.uid()`-Mocking via `set local request.jwt.claim.sub`) braucht Sorgfalt oder den Basejump-Helper.

### Option B: Dart-Integration gegen lokale Supabase

- **Setup-Aufwand**:
  - Neue Test-Dateien unter `integration_test/` oder `test/features/tournament/integration/` (Pattern existiert: `tournament_happy_path_test.dart`, aber gegen `FakeTournamentRemote`, nicht gegen Live-DB).
  - Pre-Test-Hook: `supabase start` plus Migration-Reset (`supabase db reset`) zwischen Suites. Cleanup pro Test via Transaktion ist mit `supabase_flutter` nicht trivial — der Dart-Client öffnet eigene Connections über PostgREST, also kein gemeinsamer Tx-Scope. Workaround: `truncate`-Sweep im `setUp`, oder `supabase db reset` einmal pro Suite (langsam).
  - Real-User-Auth: anon-Key + Magic-Keypair-Flow aus M2-T05 nachbauen, oder Service-Role-Key direkt verwenden (umgeht RLS, dafür müssen Tests `auth.uid()`-Semantik explizit simulieren).
  - Stack: `supabase_flutter` ist als Dependency da. Test-Lifecycle: `flutter test integration_test/...` läuft auf Linux nur mit Flutter-Desktop-Embedder oder via Headless-Setup.
- **Coverage**:
  - T5: ginge, aber jeder Property-Sweep-Call wäre ein Roundtrip durch PostgREST — Faktor 100–1000× langsamer als pgTAP-in-DB. Bei n ∈ {8, 16, 32, 64} × {true, false} = 8 Calls noch erträglich; bei breiterem Sweep schmerzhaft.
  - T6: Authorization-Negativ-Cases lassen sich nur über echten Auth-Wechsel testen, was Kompromisse erzwingt (mehrere `signIn`-Calls pro Test). Walkover-Pfad braucht Trigger-Beobachtung über zwei Selects — geht, aber prosaisch.

### Option C: Hybrid (für den Fall, dass T6 Auth-Setup teuer wird)

- T5 (Property-Parität, reine plpgsql-Helper-Funktion ohne Auth-Kontext) als pgTAP.
- T6 (RPC-Tests mit `auth.uid()`-Logik und Trigger-Effekten) als Dart-Integration, falls die Basejump-Auth-Helper nicht reichen oder Reviewer auf Dart-Style-Assertions bestehen.

## Empfehlung für M2.2-T5 (Property-Parität)

**pgTAP**. Die Property-Parität ist ein reiner Funktions-Compare (`_tournament_compute_ko_bracket` vs. Dart-`bracket.dart`-Referenz als JSON-Fixture) ohne Auth, ohne Trigger, ohne Lifecycle. In pgTAP ein paar Zeilen, in Dart ein Stack-Setup mit dem Risiko, dass der Server-Roundtrip-Overhead die Iteration bremst. Der Dev-Host braucht nur `supabase` CLI (ist bereits Voraussetzung für M2-Arbeit).

Für **T6** Empfehlung **pgTAP mit Vorbehalt**: starten mit pgTAP plus Basejump-Helper. Falls sich beim ersten Authorization-Negative-Case herausstellt, dass das Auth-Setup gegen die `tournament_*`-RPCs aufwendiger wird als geplant (LOC-Budget ~100 reißen), Pivot auf Dart-Integration. Entscheidung trifft der T6-Worker auf Basis seines ersten Spike.

## Folge-Aktionen für T5/T6 Worker

- **T5**:
  1. `supabase/tests/000-setup-tests-hooks.sql` anlegen mit `CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;` und Test-Schema-Reset.
  2. Vor T5-Implementierung ein Dart-Script (Einmal-Lauf, nicht versioniert nötig) bauen, das die Referenz-Bracket-Outputs für n ∈ {8, 16, 32, 64} × `third_place ∈ {true, false}` als JSON-Strings dumpt.
  3. JSON-Strings als pgTAP-Fixtures in `supabase/tests/tournament_ko_bracket_parity.sql` einbetten und gegen `_tournament_compute_ko_bracket` vergleichen via `is(...)` oder `results_eq(...)`.
  4. Runner: `supabase test db` lokal. Gate manuell im PR-Review prüfen, bis CI da ist.

- **T6**:
  1. Erst-Spike (max. 30 min): einen Happy-Path-Case in pgTAP mit Basejump-`tests.authenticate_as()` schreiben. Wenn glatt durchläuft, mit pgTAP weiter.
  2. Falls Auth-Setup hakt (PostgREST-spezifische Claims-Erwartungen, `auth.uid()` liefert NULL trotz Setup): Pivot auf `integration_test/tournament_ko_rpcs_test.dart`, Pattern aus `integration_test/sniper_flow_test.dart` und `test/features/tournament/integration/tournament_happy_path_test.dart` kombinieren, Service-Role-Key für RPC-Calls, manueller `auth.uid()`-Override per `SET LOCAL` in einer SQL-Helper-Migration.
  3. CI-Lücke dokumentieren: T7-Wave braucht eine Aktion "GitHub Actions Workflow für `supabase test db` plus `flutter test`" als Folge-OD oder M2.3-Task, sonst bleibt das Merge-Gate manuell.

- **Beide**: keine `supabase test db --linked`-Calls gegen Hosted-Frankfurt im normalen Test-Lauf — Tests sind transient und sollen die Produktions-Migration-History nicht anfassen.
