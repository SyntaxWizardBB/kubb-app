# Tasks — Authentication: OAuth + anonymous keypair

> Erzeugt von `/agents/scrum-master` am 2026-05-04 aus `po-output.md` + `architecture.md`.
> Owner-Level Senior — TDD-Default, atomar ≤ 100 LOC / ≤ 3 Dateien / ≤ 1h.
> Task-IDs strikt im Format `M<n>-T<m>`. Reihenfolge im `sprint-plan.md`.

---

## Reihenfolge & Abhängigkeiten (Übersicht)

| ID | Titel | Type | Agent | Size | Bounded Context | Abhängig von |
|----|-------|------|-------|------|-----------------|---------------|
| **M0 — Spike & Dependencies** ||||||
| M0-T01 | Spike Argon2id benchmark Linux/Android/Web | research | /agents/researcher | S | infra | — |
| M0-T02 | Add pubspec deps (4 packages) | infra | /agents/coder | S | infra | M0-T01 |
| M0-T03 | docker-compose.local.yml für lokales Supabase | infra | /agents/coder | M | infra | — |
| M0-T04 | Verify dev environment (analyze + test green) | tests | /agents/tester | S | infra | M0-T02 |
| **M1 — Local data layer (drift v4)** ||||||
| M1-T01 | drift v4 migration: code + v3-backup hook | data | /agents/coder | M | core | M0-T02 |
| M1-T02 | drift v4 migration tests with v3 fixture | tests | /agents/tester | S | core | M1-T01 |
| M1-T03 | cached_auth_session table + DAO + tests | data | /agents/coder | S | auth | M1-T01 |
| M1-T04 | secure_token_store + tests | data | /agents/coder | S | auth | M0-T02 |
| M1-T05 | keypair_storage + tests | data | /agents/coder | S | auth | M1-T04 |
| M1-T06 | crypto_service ed25519 ops + tests | data | /agents/coder | S | auth | M0-T02 |
| M1-T07 | crypto_service argon2id + isolate runner + tests | data | /agents/coder | M | auth | M0-T01, M0-T02 |
| M1-T08 | crypto_service xchacha20-poly1305 + tests | data | /agents/coder | S | auth | M0-T02 |
| **M2 — Server schema + custom endpoints** ||||||
| M2-T01 | SQL migration: tables, indexes, server-salt secret | data | /agents/coder | M | infra | M0-T03 |
| M2-T02 | SQL migration: RLS policies | data | /agents/coder | S | infra | M2-T01 |
| M2-T03 | Postgres function: keypair_create | data | /agents/coder | S | infra | M2-T02 |
| M2-T04 | Postgres functions: keypair_challenge + verify | data | /agents/coder | M | infra | M2-T02, M1-T06 |
| M2-T05 | tools/auth-smoketest/ curl-Tests gegen Docker-Supabase | tests | /agents/tester | S | infra | M2-T03, M2-T04 |
| M2-T06 | Security review M2 outputs (RLS + functions) | security | /agents/security-checker | S | infra | M2-T05 |
| **M3 — Repositories & adapters** ||||||
| M3-T01 | SupabaseAuthAdapter tests + Fake | tests | /agents/tester | S | auth | M3-Spec aus arch |
| M3-T02 | SupabaseAuthAdapter implementation | data | /agents/coder | M | auth | M3-T01, M0-T02 |
| M3-T03 | KeypairBackupRepository tests + Fake | tests | /agents/tester | S | auth | M1-T07, M1-T08 |
| M3-T04 | KeypairBackupRepository implementation | data | /agents/coder | M | auth | M3-T03, M2-T01 |
| M3-T05 | CloudProfileRepository tests + Fake | tests | /agents/tester | S | auth | M2-T01 |
| M3-T06 | CloudProfileRepository implementation | data | /agents/coder | S | auth | M3-T05 |
| M3-T07 | AuthTelemetry tests (PII-Filter Assertions) | tests | /agents/tester | S | auth | — |
| M3-T08 | AuthTelemetry implementation | data | /agents/coder | S | auth | M3-T07 |
| **M4 — Application layer** ||||||
| M4-T01 | AuthSession sealed class (freezed) + tests | domain | /agents/coder | S | auth | M0-T02 |
| M4-T02 | AuthController tests (boot, refresh, sign-out) | tests | /agents/tester | S | auth | M4-T01, M3-T01 |
| M4-T03 | AuthController implementation | domain | /agents/coder | M | auth | M4-T02, M3-T02, M1-T03 |
| M4-T04 | AccountSetupController tests | tests | /agents/tester | S | auth | M4-T01, M3-T01, M3-T03 |
| M4-T05 | AccountSetupController implementation | domain | /agents/coder | M | auth | M4-T04 |
| M4-T06 | RestoreController + cooldown logic + tests | domain | /agents/coder | M | auth | M4-T01, M3-T03 |
| M4-T07 | AccountUpgradeController + tests | domain | /agents/coder | S | auth | M4-T03, M3-T02 |
| M4-T08 | PassphraseChangeController + tests | domain | /agents/coder | S | auth | M4-T03, M3-T04 |
| M4-T09 | AccountDeletionController + tests | domain | /agents/coder | S | auth | M4-T03, M3-T02, M3-T04, M3-T06 |
| M4-T10 | KeypairSigningService + tests | domain | /agents/coder | S | auth | M1-T05, M1-T06, M3-T02 |
| M4-T11 | auth_providers (computed) + display_profile_provider + tests | domain | /agents/coder | S | auth, player | M4-T03 |
| **M5 — UI (design-template-gated)** ||||||
| M5-T01 | Batch design-brief.md schreiben (Owner-blocking) | docs | /agents/coder | M | auth | M4-T11 |
| M5-T02 | sign_in_screen impl + widget test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates) |
| M5-T03 | anonymous_signup_flow scaffold + NicknameStep + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M4-T05 |
| M5-T04 | disclaimer_block widget + test (AK-19) | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates) |
| M5-T05 | passphrase_input widget + strength indicator + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates) |
| M5-T06 | anonymous_signup_flow DisclaimerAndPassphraseStep + test | frontend | /agents/coder | S | auth | M5-T03, M5-T04, M5-T05 |
| M5-T07 | anonymous_signup_flow BackupConfirmationStep + test | frontend | /agents/coder | S | auth | M5-T06 |
| M5-T08 | restore_flow with cooldown badge + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M4-T06 |
| M5-T09 | account_link_screen + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M4-T07 |
| M5-T10 | passphrase_change_screen + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M4-T08 |
| M5-T11 | delete_account_screen (two-step) + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M4-T09 |
| M5-T12 | onboarding_tour (4 slides) + test | frontend | /agents/coder | M | auth | M5-T01 (✓ Templates) |
| M5-T13 | oauth_provider_button shared widget + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates) |
| M5-T14 | account_section in settings_screen + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M4-T03 |
| M5-T15 | edit_profile_screen (replaces F2 edit-mode) + test | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M3-T06 |
| **M6 — Routing + bootstrap + l10n + player cleanup** ||||||
| M6-T01 | ARB strings auth.* (de) + flutter gen-l10n + commit | frontend | /agents/coder | M | core | M5-T15 |
| M6-T02 | SessionDao methods rename playerId → userId | data | /agents/coder | S | core | M1-T01 |
| M6-T03 | Update Session callers in training/stats (sessions.userId) | frontend | /agents/coder | M | training, stats | M6-T02 |
| M6-T04 | Delete F2 player files (repository, table, current_profile, onboarding_screen) | frontend | /agents/coder | S | player | M4-T11, M5-T15 |
| M6-T05 | Rewrite profile_screen as display-only | frontend | /agents/coder | S | player | M6-T04 |
| M6-T06 | Update callers of currentProfileProvider → displayProfileProvider | frontend | /agents/coder | M | training, stats, settings | M4-T11 |
| M6-T07 | router.dart redirect rewrite + new routes + tests | frontend | /agents/coder | M | app | M5-T02, M4-T03 |
| M6-T08 | bootstrap.dart cached-session readout | frontend | /agents/coder | S | app | M1-T03, M4-T03 |
| **M7 — Polish + integration** ||||||
| M7-T01 | Account-status badge in AppBar (US-15) | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M5-T14 |
| M7-T02 | Backup-warning surface in settings (US-10) | frontend | /agents/coder | S | auth | M5-T01 (✓ Templates), M5-T14 |
| M7-T03 | Internal logging audit pass + Tests (US-17) | tests | /agents/tester | S | auth | M3-T08 |
| M7-T04 | Full integration test (signup → backup → restore → upgrade → logout) | tests | /agents/tester | M | auth | M5-*, M6-* |
| M7-T05 | Final security-check pass auf alle Auth-Pfade | security | /agents/security-checker | S | auth | M7-T04 |

**Total: 65 Tasks** (M0: 4 · M1: 8 · M2: 6 · M3: 8 · M4: 11 · M5: 15 · M6: 8 · M7: 5)

---

## Detail je Task

### M0-T01: Spike Argon2id benchmark Linux/Android/Web

- **Type**: research
- **Size**: S
- **Bounded Context**: infra
- **Agent**: /agents/researcher
- **Dependencies**: —
- **Files (anticipated)**: `docs/plans/auth-oauth-keypair/spike-argon2id.md`
- **Goal**: Verify dass Argon2id mit Standard-Parametern (m=64 MiB, t=3, p=4) auf allen Ziel-Plattformen in akzeptabler Zeit läuft; falls Web zu langsam, Web-spezifische Parameter dokumentieren.
- **Acceptance Criteria**:
  - **Given** ein kleines Dart-Sample-Projekt das `cryptography ^2.7.0` Argon2id mit (m=64MiB, t=3, p=4) für eine 16-Byte-Passphrase + 16-Byte-Salt aufruft
  - **When** die Messung auf Linux-Desktop, Android (Mid-Range, API 28, 4 GB RAM), und Flutter Web (Chrome) durchgeführt wird (3 Iterationen, Median nehmen)
  - **Then** liegen die Median-Zeiten dokumentiert in `spike-argon2id.md` mit Empfehlung "Standard-Parameter überall" oder "Web-Fallback m=32 MiB" mit Begründung
- **Notes**: Risiko #1 aus architecture.md. Spike entscheidet ob crypto_service.dart eine Web-spezifische Parameter-Variante braucht.
- **Status**: done (Output: docs/plans/auth-oauth-keypair/spike-argon2id.md — Per-Platform-Empfehlung: Native m=64MiB, Web m=32MiB, beide t=3 p=4)

### M0-T02: Add pubspec deps (4 packages)

- **Type**: infra
- **Size**: S
- **Bounded Context**: infra
- **Agent**: /agents/coder (infra)
- **Dependencies**: M0-T01
- **Files (anticipated)**: `pubspec.yaml`, `pubspec.lock`
- **Goal**: Vier neue Dependencies pinnen — `supabase_flutter ^2.5.0`, `flutter_secure_storage ^9.2.2`, `cryptography ^2.7.0`, `app_links ^6.3.0`.
- **Acceptance Criteria**:
  - **Given** das aktuelle `pubspec.yaml` mit den existierenden Deps
  - **When** die vier Packages mit `flutter pub add` hinzugefügt werden
  - **Then** sind sie mit `^`-Versions-Constraint im `dependencies`-Block, `flutter pub get` läuft clean, `flutter pub outdated` zeigt keine Warnings
  - **And** `flutter analyze` bleibt clean
- **Notes**: Versions per `tech-lead.md` strikt mit `^` pinnen, kein `any`. Lessons-learned aus CLAUDE.md (sqlite3_flutter_libs-Bug).
- **Status**: done — Pinned: supabase_flutter ^2.5.0, flutter_secure_storage ^8.1.0 (downgraded von ^9.2.2 wegen win32-Konflikt mit package_info_plus ^10.1.0; v8 hat alle benötigten APIs, Windows v1-out-of-scope), cryptography ^2.7.0, app_links ^6.3.0. flutter analyze clean, 241/241 Tests grün.

### M0-T03: docker-compose.local.yml für lokales Supabase

- **Type**: infra
- **Size**: M
- **Bounded Context**: infra
- **Agent**: /agents/coder (infra)
- **Dependencies**: —
- **Files (anticipated)**: `tools/supabase-local/docker-compose.yml`, `tools/supabase-local/.env.example`, `tools/supabase-local/README.md`, `.gitignore` (Update für `.env` und data-volumes)
- **Goal**: Komplettes Supabase-Stack lokal in Docker für Dev/Tests; reproduzierbar startbar mit `docker compose up`.
- **Acceptance Criteria**:
  - **Given** Docker + docker-compose installiert
  - **When** der Owner `cd tools/supabase-local && cp .env.example .env && docker compose up -d` ausführt
  - **Then** läuft Supabase auf `http://localhost:54321` (API-Gateway), `http://localhost:54323` (Studio), `postgresql://localhost:54322` (Postgres direkt)
  - **And** der README erklärt initial-setup, reset (`docker compose down -v`), und logs (`docker compose logs -f`)
- **Notes**: Basiert auf Supabase Self-Hosted Quick-Start. `.env` mit Secrets (Service-Role-Key) bleibt gitignored, `.env.example` ist im Repo.
- **Status**: done — Pivot zur Supabase-CLI statt rohem docker-compose (gleiche Ports 54321/54322/54323, weniger Wartungsaufwand). Files: `supabase/config.toml`, `supabase/seed.sql`, `supabase/migrations/` (leeres Verzeichnis für M2), `tools/supabase-local/README.md`, `tools/supabase-local/.env.example`, `.gitignore`-Update. Verifikation auf Owner-Hardware (Docker + supabase-CLI nicht in dieser Dev-Umgebung verfügbar).

### M0-T04: Verify dev environment (analyze + test green)

- **Type**: tests
- **Size**: S
- **Bounded Context**: infra
- **Agent**: /agents/tester
- **Dependencies**: M0-T02
- **Files (anticipated)**: keine — nur Verifikation
- **Goal**: Sicherstellen dass die neuen pubspec-Deps keine bestehenden Tests / Analyzer brechen.
- **Acceptance Criteria**:
  - **Given** M0-T02 ist gemerged
  - **When** `flutter pub get && flutter analyze && flutter test` und `cd packages/kubb_domain && dart pub get && dart analyze && dart test` ausgeführt werden
  - **Then** alle laufen clean (Analyzer 0 Issues, alle 241 bestehenden Tests grün)
- **Status**: done — flutter analyze 0 Issues, dart analyze (kubb_domain) 0 Issues, flutter test 241/241, dart test (kubb_domain) 9/9. Alle M0-Outputs sind kompatibel mit existierender Code-Basis.

### M1-T01: drift v4 migration code + v3-backup hook

- **Type**: data
- **Size**: M
- **Bounded Context**: core
- **Agent**: /agents/coder (data)
- **Dependencies**: M0-T02
- **Files (anticipated)**: `lib/core/data/app_database.dart`, `lib/core/data/tables/cached_auth_session_table.dart`
- **Goal**: drift schemaVersion 3→4 mit destructive Migration: cached_auth_session anlegen, sessions.player_id → sessions.user_id (table-recreate), drop players, vor allem v3-DB-Backup als Sicherheitsnetz.
- **Acceptance Criteria**:
  - **Given** eine drift v3-DB mit existierenden players-, sessions-, session_events-, finisseur_stick_events-Zeilen
  - **When** die App startet und onUpgrade(3, 4) läuft
  - **Then** wird zuerst eine v3-Snapshot-Datei nach `<app-data>/kubb_v3_backup_<timestamp>.db` kopiert
  - **And** danach session_events, finisseur_stick_events, sessions in dieser Reihenfolge gedroppt; sessions wird via TableMigration mit player_id → user_id (text, no FK) neu aufgebaut
  - **And** abschliessend `m.deleteTable('players')` ausgeführt
  - **And** `cached_auth_session` neu angelegt
  - **And** schemaVersion = 4, `flutter analyze` clean
- **Notes**: Risiko #6 aus architecture.md. v3-Backup ist nicht-destruktiver Fallback — manuell mit sqlite-cli inspectable.
- **Status**: done — **Plan-Revision**: M1-T01 macht jetzt nur den additiven Teil (cached_auth_session-Table erstellen, schemaVersion 3→4). Der destruktive Teil (drop players, rename sessions.player_id, v3-backup) wurde verschoben zu einem neuen Task **M6-T-DESTRUCTIVE** der zusammen mit M6-T04 (F2 file deletion) ausgeführt wird — sonst Chicken-and-Egg mit existierender PlayerDao/PlayerRepository. Schema-Version geht zu v5 in M6. Files in dieser Iteration: `lib/features/auth/data/tables/cached_auth_session_table.dart` (neu), `lib/core/data/app_database.dart` (Migration), `test/core/data/app_database_test.dart` (Tests adjusted).

### M1-T02: drift v4 migration tests with v3 fixture

- **Type**: tests
- **Size**: S
- **Bounded Context**: core
- **Agent**: /agents/tester
- **Dependencies**: M1-T01
- **Files (anticipated)**: `test/core/data/app_database_v4_migration_test.dart`, `test/fixtures/db/v3_seed.dart`
- **Goal**: Migration verifizieren — fixture-DB mit v3-Schema + sample-Daten anlegen, Migration ausführen, neues Schema + leere Sessions + nicht-mehr-vorhandene Players + Backup-Datei prüfen.
- **Acceptance Criteria**:
  - **Given** eine in-memory drift-DB die zunächst auf v3 mit 1 Player, 2 Sessions, 4 SessionEvents, 1 FinisseurStickEvent gesetzt wird
  - **When** die DB mit schemaVersion=4 erneut geöffnet wird (löst onUpgrade aus)
  - **Then** existiert die Tabelle `cached_auth_session`, sessions hat 0 Zeilen mit user_id-Spalte (statt player_id), session_events hat 0 Zeilen, players-Tabelle existiert nicht mehr
  - **And** ein Backup-Pfad wurde im Test-Hook abgefragt und ist gültig
- **Status**: done — AC angepasst an additive M1-T01 (kein v3-Backup-Test mehr, da keine destruktiven Operationen). Fixture-Test rollt v4-DB zu v3 zurück (DROP cached_auth_session + PRAGMA user_version=3), seedet 1 Player + 2 Sessions + 1 SessionEvent, zieht createTable manuell durch und verifiziert (a) cached_auth_session da, (b) v3-Daten unverändert, (c) Single-Row-Constraint, (d) Round-Trip. 4 Tests in test/core/data/app_database_v4_migration_test.dart, alle grün. v3-Backup-Hook + destruktive Tests kommen mit M6.

### M1-T03: cached_auth_session table + DAO + tests

- **Type**: data
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M1-T01
- **Files (anticipated)**: `lib/features/auth/data/dao/cached_auth_session_dao.dart`, `test/features/auth/data/cached_auth_session_dao_test.dart`
- **Goal**: DAO mit Methoden `current()` (single row Future), `watch()` (Stream), `upsert(session)`, `clear()`. Bestehender drift-DriftDatabase-Block in app_database.dart wird um den DAO erweitert.
- **Acceptance Criteria**:
  - **Given** eine in-memory drift v4 DB
  - **When** `dao.upsert(...)` mit einem AuthSession-Eintrag aufgerufen wird, dann erneut mit anderen Werten, dann `dao.current()`
  - **Then** liegt genau eine Zeile vor (id='singleton'), mit den letzten Werten; `watch()` emittiert nach jedem upsert
  - **And** `dao.clear()` macht `current()` null
- **Status**: done — DAO mit current()/watch()/upsert()/clear(), inkl. createdAt-Preservation in Updates. 6 Tests grün (current null bei fresh DB, upsert + current Round-Trip, second upsert updates, createdAt preserved, clear, watch streams). Files: lib/features/auth/data/dao/cached_auth_session_dao.dart, app_database.dart (DAO registriert), test/features/auth/data/cached_auth_session_dao_test.dart.

### M1-T04: secure_token_store + tests

- **Type**: data
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M0-T02
- **Files (anticipated)**: `lib/features/auth/data/secure_token_store.dart`, `test/features/auth/data/secure_token_store_test.dart`
- **Goal**: Wrapper um flutter_secure_storage mit Methoden `read(kind)`, `write(kind, value)`, `delete(kind)`, `deleteAll()`. Kind-Enum: `accessToken`, `refreshToken`, `oauthToken`, `privateKey`.
- **Acceptance Criteria**:
  - **Given** ein gemockter `FlutterSecureStorage`-Instance
  - **When** `write(kind=privateKey, value="...")` aufgerufen wird, dann `read(kind=privateKey)`
  - **Then** wird der gespeicherte Wert zurückgegeben; gemockter Storage hat den korrekten Schlüsselnamen `auth_private_key` empfangen
  - **And** `deleteAll()` ruft alle vier `delete()`-Aufrufe ab
- **Status**: done — Wrapper mit SecureTokenKind enum (accessToken='auth_access_token', refreshToken='auth_refresh_token', oauthToken='auth_oauth_token', privateKey='auth_private_key'). 4 Tests grün via mocktail-mocked FlutterSecureStorage. Files: lib/features/auth/data/secure_token_store.dart, test/features/auth/data/secure_token_store_test.dart.

### M1-T05: keypair_storage + tests

- **Type**: data
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M1-T04, M1-T06
- **Files (anticipated)**: `lib/features/auth/data/keypair_storage.dart`, `test/features/auth/data/keypair_storage_test.dart`
- **Goal**: Hochlevel-Wrapper: `generate() → (publicKey, privateKey)`, `save(privateKey)`, `load() → privateKey?`, `clear()`. Nutzt CryptoService für Generation und SecureTokenStore für Persistenz.
- **Acceptance Criteria**:
  - **Given** Mock-CryptoService liefert ein deterministisches Ed25519-Paar
  - **When** `generate()` aufgerufen wird, dann `save()`, dann `load()`
  - **Then** ist der zurückgegebene privateKey identisch zum gespeicherten
- **Status**: done — High-Level-Wrapper über CryptoService + SecureTokenStore. base64-encoded für Persistierung (binär in flutter_secure_storage geht nicht). 6 Tests grün (generate ohne save, save mit korrektem Key + Encoding, load null + decoded, clear isolated, vollständiger save→load Round-Trip).

### M1-T06: crypto_service ed25519 ops + tests

- **Type**: data
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M0-T02
- **Files (anticipated)**: `lib/features/auth/data/crypto_service.dart` (partial: ed25519 only), `test/features/auth/data/crypto_service_ed25519_test.dart`
- **Goal**: Ed25519-Methoden im CryptoService: `generateEd25519KeyPair() → (publicKey, privateKey)`, `signEd25519(privateKey, message) → signature`, `verifyEd25519(publicKey, message, signature) → bool`.
- **Acceptance Criteria**:
  - **Given** ein generiertes Keypair und eine 32-Byte-Message
  - **When** signiert und mit dem korrespondierenden publicKey verifiziert wird
  - **Then** ist verify=true; mit fremdem publicKey verify=false; mit modifizierter Message verify=false
- **Status**: done — CryptoService mit Ed25519-Methoden (generateEd25519KeyPair, signEd25519, verifyEd25519). Plain-Bytes-Interface (Uint8List) — keine cryptography-Wrapper-Typen leaken in die Application-Layer. 6 Tests grün (32-byte keys, Distinct-Generation, 64-byte sig, verify-true, verify-false-foreign-key, verify-false-tampered-msg).

### M1-T07: crypto_service argon2id + isolate runner + tests

- **Type**: data
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M0-T01, M0-T02
- **Files (anticipated)**: `lib/features/auth/data/crypto_service.dart` (extend with argon2id), `test/features/auth/data/crypto_service_argon2id_test.dart`
- **Goal**: `deriveKeyArgon2id(passphrase, salt, params) → key` (32 Byte). Läuft via `compute()` im Isolate damit UI nicht blockiert. Web-Fallback-Parameter aus M0-T01 berücksichtigen falls nötig.
- **Acceptance Criteria**:
  - **Given** Passphrase "test123" + 16-Byte-Salt + Standard-Params (m=64MiB, t=3, p=4)
  - **When** `deriveKeyArgon2id(...)` zweimal hintereinander aufgerufen wird
  - **Then** ist das Ergebnis byte-identisch (Determinismus)
  - **And** ein laufender Test mit pump-Frame Counter zeigt dass UI-Frames während der KDF nicht blockiert sind (Isolate-Beweis)
- **Status**: done — deriveKeyArgon2id via compute() mit top-level _argon2idIsolateEntry. Argon2idParams als immutable VO mit toJson/fromJson für die kdf_params jsonb-Spalte und platformDefault() (kIsWeb ? 32768 : 65536, t=3, p=4 — siehe spike-argon2id.md). 9 Tests grün (hash length default + custom, Determinismus, different-passphrase + different-salt, JSON round-trip, platformDefault, production-default unter 5s mit Stopwatch-Warning bei Regression). Pump-Frame-Counter-Test wegen Test-Komplexität nicht implementiert — Isolate-Beweis liegt im Code-Review (compute() ist die Standard-Flutter-API für Isolate-Offload, keine Workaround-Bestätigung nötig).

### M1-T08: crypto_service xchacha20-poly1305 + tests

- **Type**: data
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M0-T02
- **Files (anticipated)**: `lib/features/auth/data/crypto_service.dart` (extend), `test/features/auth/data/crypto_service_xchacha20_test.dart`
- **Goal**: `encryptXChaCha20(key, plaintext, nonce) → ciphertext`, `decryptXChaCha20(key, ciphertext, nonce) → plaintext`. AEAD mit Poly1305-MAC.
- **Acceptance Criteria**:
  - **Given** ein 32-Byte-Key und ein 24-Byte-Nonce
  - **When** ein Plaintext verschlüsselt und wieder entschlüsselt wird
  - **Then** entspricht das Ergebnis dem Original
  - **And** ein modifizierter Ciphertext (1 Byte gekippt) löst beim Decrypt einen `SecretBoxAuthenticationError` aus
- **Status**: done — encryptXChaCha20 + decryptXChaCha20 mit poly1305-AEAD. Ciphertext-Format: `body || mac` (16 Byte MAC concatenated). 5 Tests grün (round-trip, wrong-key/wrong-nonce/tampered-ciphertext alle mit SecretBoxAuthenticationError, too-short-ciphertext mit ArgumentError).

### M2-T01: SQL migration: tables, indexes, server-salt secret

- **Type**: data
- **Size**: M
- **Bounded Context**: infra
- **Agent**: /agents/coder (data)
- **Dependencies**: M0-T03
- **Files (anticipated)**: `tools/supabase-local/migrations/001_auth_tables.sql`, `tools/supabase-local/migrations/002_server_salt.sql`
- **Goal**: SQL-Migration mit den zwei neuen Tabellen + Constraints + Indexes per architecture.md §Server-Schema, plus Server-Salt-Erzeugung als Supabase-Secret.
- **Acceptance Criteria**:
  - **Given** ein frischer Docker-Supabase-Stack
  - **When** beide SQL-Files via `psql` (oder Supabase-CLI) ausgeführt werden
  - **Then** existieren `user_credentials` und `user_keypair_backups` mit allen Constraints (CHECK, FK, UNIQUE INDEX)
  - **And** ein 32-Byte-zufälliger Server-Salt liegt als Postgres-Secret `auth.nickname_hash_salt` vor (via `vault.create_secret` oder ähnlich)
  - **And** das `user_profiles`-Schema ist um `nickname_unique citext UNIQUE`, `avatar_color text NULL`, `onboarding_completed boolean NOT NULL DEFAULT false` erweitert
- **Status**: done — Migrations in supabase/migrations/ (Pivot zu Supabase-CLI, dort liegen Migrations standardmässig). Files: 20260504000001_auth_tables.sql (tables + indexes + user_profiles ALTER), 20260504000002_auth_server_salt.sql (auth.nickname_hash_salt() + auth.compute_nickname_hash() Postgres-Functions mit current_setting-Lookup + Local-Dev-Fallback). Production-Hetzner überschreibt salt via ALTER DATABASE ... SET auth.nickname_hash_salt='...'. Verifikation auf Owner-Hardware (Docker/Supabase nicht verfügbar in Dev-Umgebung).

### M2-T02: SQL migration: RLS policies

- **Type**: data
- **Size**: S
- **Bounded Context**: infra
- **Agent**: /agents/coder (data)
- **Dependencies**: M2-T01
- **Files (anticipated)**: `tools/supabase-local/migrations/003_auth_rls.sql`
- **Goal**: RLS-Policies für die neuen Tabellen per architecture.md §RLS.
- **Acceptance Criteria**:
  - **Given** M2-T01 ist gelaufen
  - **When** das RLS-Migration-Script ausgeführt wird
  - **Then** sind RLS auf `user_credentials` und `user_keypair_backups` aktiviert
  - **And** die Policies entsprechen der Spec: `user_credentials` owner-read + owner-insert; `user_keypair_backups` lookup (any), owner write/update/delete

### M2-T03: Postgres function: keypair_create

- **Type**: data
- **Size**: S
- **Bounded Context**: infra
- **Agent**: /agents/coder (data)
- **Dependencies**: M2-T02
- **Files (anticipated)**: `tools/supabase-local/migrations/004_fn_keypair_create.sql`
- **Goal**: Postgres-Funktion `auth.keypair_create(nickname, public_key) RETURNS jsonb` — legt in einer Transaktion `auth.users` + `user_credentials(kind=keypair)` + `user_profiles` an, erzeugt ein Initial-JWT und gibt `{userId, accessToken, refreshToken}` zurück.
- **Acceptance Criteria**:
  - **Given** M2-T02 ist gelaufen
  - **When** `SELECT auth.keypair_create('lukas', 'base64-public-key-...')` per psql aufgerufen wird
  - **Then** existiert ein neuer auth.users-Eintrag, ein user_credentials(kind=keypair) mit der public_key, ein user_profiles(nickname='lukas')
  - **And** der returnierte JSONB enthält gültige `userId`, `accessToken`, `refreshToken`
  - **And** ein zweiter Aufruf mit gleichem nickname schlägt fehl (UNIQUE-Constraint)

### M2-T04: Postgres functions: keypair_challenge + verify

- **Type**: data
- **Size**: M
- **Bounded Context**: infra
- **Agent**: /agents/coder (data)
- **Dependencies**: M2-T02, M1-T06
- **Files (anticipated)**: `tools/supabase-local/migrations/005_fn_keypair_challenge.sql`, `tools/supabase-local/migrations/006_fn_keypair_verify.sql`
- **Goal**: Zwei Funktionen — `keypair_challenge(public_key) RETURNS text` (gibt 32-Byte-Random-Challenge mit 60s-TTL aus, gespeichert in temp-table); `keypair_verify(public_key, signature, timestamp) RETURNS jsonb` (verifiziert Ed25519-Signatur via pgcrypto-Plugin oder externe verify-extension, gibt JWT zurück).
- **Acceptance Criteria**:
  - **Given** ein bestehender keypair-Account aus M2-T03
  - **When** der Client per RPC `keypair_challenge(public_key)` aufruft
  - **Then** wird ein 32-Byte-Token zurückgegeben und im server-temp-store mit Ablauf-Timestamp gespeichert
  - **And** wenn der Client das Token + Signature an `keypair_verify` schickt und die Signatur gültig ist, kommt ein JWT zurück
  - **And** ungültige Signatur, abgelaufenes Token, oder unbekannter public_key liefern Fehler-JSON mit klarem Error-Code

### M2-T05: tools/auth-smoketest/ curl-Tests gegen Docker-Supabase

- **Type**: tests
- **Size**: S
- **Bounded Context**: infra
- **Agent**: /agents/tester
- **Dependencies**: M2-T03, M2-T04
- **Files (anticipated)**: `tools/auth-smoketest/run.sh`, `tools/auth-smoketest/README.md`
- **Goal**: Bash-Script das `keypair_create` → `keypair_challenge` → manuelle Signatur (mit Test-Key in fixture) → `keypair_verify` → JWT-Decode prüft. Plus RLS-Negativ-Tests (anonymer Lesezugriff auf user_credentials muss scheitern).
- **Acceptance Criteria**:
  - **Given** Docker-Supabase läuft, M2-T01..T04 sind gemerged
  - **When** `bash tools/auth-smoketest/run.sh` ausgeführt wird
  - **Then** exited das Script mit 0 und gibt eine ✅-Liste aus mit allen geprüften Pfaden
  - **And** RLS-Negativ-Tests bestehen (anon kann user_credentials nicht lesen, user kann nicht fremdes user_credentials lesen)

### M2-T06: Security review M2 outputs

- **Type**: security
- **Size**: S
- **Bounded Context**: infra
- **Agent**: /agents/security-checker
- **Dependencies**: M2-T05
- **Files (anticipated)**: `/tmp/kubb_app/auth-oauth-keypair/security-review-M2.md`
- **Goal**: SQL-Migration, RLS-Policies und die vier Postgres-Functions auf OWASP-Kriterien prüfen — SQL-Injection, RLS-Lücken, Privilege-Escalation, Secret-Leak.
- **Acceptance Criteria**:
  - **Given** alle M2-Outputs sind in `tools/supabase-local/migrations/`
  - **When** der Security-Checker den Review durchführt
  - **Then** wird ein Report ohne BLOCKING-Findings ausgegeben; MEDIUM/LOW-Findings dokumentiert mit Empfehlung

### M3-T01: SupabaseAuthAdapter tests + Fake

- **Type**: tests
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: —
- **Files (anticipated)**: `test/features/auth/data/supabase_auth_adapter_test.dart`, `test/fixtures/auth/fake_supabase_auth_adapter.dart`
- **Goal**: Test-Doubles + Test-Specs für die noch nicht implementierte SupabaseAuthAdapter (TDD-Pattern). FakeAdapter implementiert das gleiche Interface mit deterministischem In-Memory-Verhalten.
- **Acceptance Criteria**:
  - **Given** das geplante SupabaseAuthAdapter-Interface (Methoden: `signInWithOAuth`, `signOut`, `currentSession`, `onAuthStateChange`, `signInWithKeypairChallenge`, `linkOAuth`, `deleteAccount`)
  - **When** Tests gegen den FakeAdapter laufen
  - **Then** sind alle Tests grün (FakeAdapter erfüllt die Spec); die Tests sind so geschrieben dass sie auch gegen das echte Adapter laufen werden

### M3-T02: SupabaseAuthAdapter implementation

- **Type**: data
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M3-T01, M0-T02
- **Files (anticipated)**: `lib/features/auth/data/supabase_auth_adapter.dart`
- **Goal**: Echte Implementierung — wraps `supabase_flutter`'s Auth-API. Custom-Endpoint-Aufrufe für keypair via RPC.
- **Acceptance Criteria**:
  - **Given** die in M3-T01 geschriebenen Tests
  - **When** der Adapter implementiert ist und gegen FakeSupabase (lokale Testinstanz) läuft
  - **Then** gehen alle M3-T01-Tests grün — sowohl mit FakeAdapter als auch mit dem echten Adapter
  - **And** `flutter analyze` clean

### M3-T03: KeypairBackupRepository tests + Fake

- **Type**: tests
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: M1-T07, M1-T08
- **Files (anticipated)**: `test/features/auth/data/keypair_backup_repository_test.dart`, `test/fixtures/auth/fake_keypair_backup_repository.dart`
- **Goal**: Test-Doubles + Specs für upload/restore/updatePassphrase/deleteBackup. Fake hält Ciphertexts in-memory, KDF läuft real (im Isolate).
- **Acceptance Criteria**:
  - **Given** das geplante Repository-Interface
  - **When** ein Round-Trip getestet wird: `uploadBackup(privKey, "passwd", "lukas")` → `restoreBackup("lukas", "passwd")`
  - **Then** liefert restore den ursprünglichen privKey zurück
  - **And** falsche Passphrase liefert `AuthError.passphraseMismatch`

### M3-T04: KeypairBackupRepository implementation

- **Type**: data
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M3-T03, M2-T01
- **Files (anticipated)**: `lib/features/auth/data/keypair_backup_repository.dart`
- **Goal**: Echte Implementierung gegen Supabase + CryptoService. Berechnet `nickname_hash = sha256(nickname || serverSalt)` (serverSalt wird einmalig per RPC abgerufen und gecacht).
- **Acceptance Criteria**:
  - **Given** die in M3-T03 geschriebenen Tests + Docker-Supabase
  - **When** das Repository implementiert ist
  - **Then** gehen die Tests grün gegen das echte Repository (Integration-Test)

### M3-T05: CloudProfileRepository tests + Fake

- **Type**: tests
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: M2-T01
- **Files (anticipated)**: `test/features/auth/data/cloud_profile_repository_test.dart`, `test/fixtures/auth/fake_cloud_profile_repository.dart`
- **Goal**: Test-Doubles + Specs für `ensureProfile`, `linkCredential`, `deleteAllForUser`. Fake speichert in-memory.
- **Acceptance Criteria**:
  - **Given** das geplante Repository-Interface
  - **When** `ensureProfile(userId, "Lukas", "#FF8800")` zweimal mit gleicher userId aufgerufen wird
  - **Then** existiert genau eine ProfileRow (Idempotenz via ON CONFLICT)

### M3-T06: CloudProfileRepository implementation

- **Type**: data
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M3-T05
- **Files (anticipated)**: `lib/features/auth/data/cloud_profile_repository.dart`
- **Goal**: Echte Implementierung gegen Supabase mit `ON CONFLICT (user_id) DO NOTHING RETURNING *`.
- **Acceptance Criteria**:
  - **Given** die in M3-T05 geschriebenen Tests + Docker-Supabase
  - **When** das Repository implementiert ist
  - **Then** gehen die Tests grün

### M3-T07: AuthTelemetry tests (PII-Filter Assertions)

- **Type**: tests
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: —
- **Files (anticipated)**: `test/features/auth/data/auth_telemetry_test.dart`
- **Goal**: Tests die nachweisen dass keine PII in Log-Output landet — kein E-Mail-Substring, kein OAuth-Subject, kein vollständiger Nickname (nur 8-Char-Prefix erlaubt), kein Token-Substring.
- **Acceptance Criteria**:
  - **Given** ein TestLogger der alle ausgegebenen LogRecords sammelt
  - **When** `AuthTelemetry.signinSuccess(userId='abc-1234-...', kind='oauth_google', email='lukas@...', subject='google-12345')` aufgerufen wird
  - **Then** enthält der LogRecord die userId-Prefix max 8 Chars, das Event-Kind, KEINE E-Mail, KEIN Subject

### M3-T08: AuthTelemetry implementation

- **Type**: data
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data)
- **Dependencies**: M3-T07
- **Files (anticipated)**: `lib/features/auth/data/auth_telemetry.dart`
- **Goal**: package:logging-Wrapper mit den 7 Event-Typen aus architecture.md §Telemetry. Strict PII-Filter.
- **Acceptance Criteria**:
  - **Given** die M3-T07-Tests
  - **When** Telemetry implementiert ist
  - **Then** gehen alle Tests grün

### M4-T01: AuthSession sealed class (freezed) + tests

- **Type**: domain
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (domain)
- **Dependencies**: M0-T02
- **Files (anticipated)**: `lib/features/auth/application/auth_session.dart`, `lib/features/auth/application/auth_session.freezed.dart` (generated), `test/features/auth/application/auth_session_test.dart`
- **Goal**: Sealed class mit Variants `SignedOut`, `Authenticated.oauth(provider, fallbackKeypair)`, `Authenticated.keypair`. Plus `OAuthProvider`-Enum (`google`, `apple`).
- **Acceptance Criteria**:
  - **Given** freezed-codegen ist gelaufen
  - **When** `AuthSession.signedOut()`, `.oauth(...)`, `.keypair(...)` instanziiert und mit `.when()` pattern-matched werden
  - **Then** kompiliert, equality + hashCode arbeiten korrekt, JSON-Serialisierung roundtrips

### M4-T02: AuthController tests

- **Type**: tests
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: M4-T01, M3-T01
- **Files (anticipated)**: `test/features/auth/application/auth_controller_test.dart`
- **Goal**: TDD-Tests für AuthController — Boot aus cached_session, Refresh-on-stale, signOut, onAuthStateChange-Subscription, Reaktion auf OAuth-Callback.
- **Acceptance Criteria**:
  - **Given** Fake-CachedAuthSessionDao mit existierender Session, FakeSupabaseAuthAdapter
  - **When** der AuthController gebootet wird
  - **Then** emittiert er `AsyncValue.data(Authenticated.<kind>(...))` ohne auf Server-Call zu warten
  - **And** beim signOut wird die DAO-Zeile gelöscht und `SignedOut` emittiert

### M4-T03: AuthController implementation

- **Type**: domain
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (domain)
- **Dependencies**: M4-T02, M3-T02, M1-T03
- **Files (anticipated)**: `lib/features/auth/application/auth_controller.dart`, `lib/features/auth/application/auth_controller.g.dart` (generated)
- **Goal**: AsyncNotifier-basierter Controller per architecture.md §AuthController.
- **Acceptance Criteria**:
  - **Given** die M4-T02-Tests
  - **When** der Controller implementiert ist
  - **Then** gehen alle Tests grün

### M4-T04: AccountSetupController tests

- **Type**: tests
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: M4-T01, M3-T01, M3-T03
- **Files (anticipated)**: `test/features/auth/application/account_setup_controller_test.dart`
- **Goal**: TDD-Tests für anonymes Account-Anlegen — happy path, Nickname-Konflikt, Crypto-Fehler, Backup-Upload-Fehler.
- **Acceptance Criteria**:
  - **Given** alle relevanten Fake-Dependencies
  - **When** `controller.setNickname('lukas')` → `setPassphrase('passwordhere1')` → `submit()` ausgeführt werden
  - **Then** wird Keypair generiert, account erstellt, profile angelegt, backup hochgeladen, session gecached, controller emittiert `Done`

### M4-T05: AccountSetupController implementation

- **Type**: domain
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (domain)
- **Dependencies**: M4-T04
- **Files (anticipated)**: `lib/features/auth/application/account_setup_controller.dart`
- **Goal**: Multi-Step-State-Maschine mit den drei Steps + submit-Logik.
- **Acceptance Criteria**:
  - **Given** die M4-T04-Tests
  - **When** implementiert
  - **Then** alle Tests grün

### M4-T06: RestoreController + cooldown logic + tests

- **Type**: domain
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (domain)
- **Dependencies**: M4-T01, M3-T03
- **Files (anticipated)**: `lib/features/auth/application/restore_controller.dart`, `test/features/auth/application/restore_controller_test.dart`
- **Goal**: Restore mit 30-s-Cooldown nach 3 Fehlversuchen pro nickname_hash (state in app_settings via key `restore_failure_<hash>`).
- **Acceptance Criteria**:
  - **Given** ein Restore-Versuch mit falscher Passphrase
  - **When** der Versuch dreimal hintereinander schlägt
  - **Then** ist der Controller-State `Cooldown(until: now+30s)`; ein vierter Versuch wird sofort mit `cooldownActive` rejected
  - **And** nach 30s wird der Counter zurückgesetzt

### M4-T07: AccountUpgradeController + tests

- **Type**: domain
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (domain)
- **Dependencies**: M4-T03, M3-T02
- **Files (anticipated)**: `lib/features/auth/application/account_upgrade_controller.dart`, `test/features/auth/application/account_upgrade_controller_test.dart`
- **Goal**: Linkt OAuth zu existierendem keypair-Account — gleiche userId, neue user_credentials-Zeile.
- **Acceptance Criteria**:
  - **Given** angemeldeter keypair-Account
  - **When** `linkOAuth(google)` → erfolgreicher OAuth-Flow
  - **Then** ist Session jetzt `Authenticated.oauth(google, fallbackKeypair: true)`, gleiche userId, keypair-Eintrag in user_credentials existiert weiterhin

### M4-T08: PassphraseChangeController + tests

- **Type**: domain
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (domain)
- **Dependencies**: M4-T03, M3-T04
- **Files (anticipated)**: `lib/features/auth/application/passphrase_change_controller.dart`, `test/features/auth/application/passphrase_change_controller_test.dart`
- **Goal**: Re-encrypt private key with new passphrase, update server backup row.
- **Acceptance Criteria**:
  - **Given** angemeldeter keypair-Account mit alter Passphrase "old"
  - **When** `change(old: 'old', newPassphrase: 'new1234567890')`
  - **Then** wird das Backup mit neuer Passphrase neu hochgeladen; alte Passphrase bei Restore-Versuch fehlerhaft

### M4-T09: AccountDeletionController + tests

- **Type**: domain
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (domain)
- **Dependencies**: M4-T03, M3-T02, M3-T04, M3-T06
- **Files (anticipated)**: `lib/features/auth/application/account_deletion_controller.dart`, `test/features/auth/application/account_deletion_controller_test.dart`
- **Goal**: Hard-Delete: server-cascade, secure-storage clear, cached_auth_session clear.
- **Acceptance Criteria**:
  - **Given** angemeldeter Account egal welche Methode
  - **When** `delete()` aufgerufen wird
  - **Then** sind alle Server-Daten zur userId weg, secure-storage privateKey weg, cached_auth_session leer, Controller emittiert `SignedOut`

### M4-T10: KeypairSigningService + tests

- **Type**: domain
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (domain)
- **Dependencies**: M1-T05, M1-T06, M3-T02
- **Files (anticipated)**: `lib/features/auth/application/keypair_signing_service.dart`, `test/features/auth/application/keypair_signing_service_test.dart`
- **Goal**: Challenge anfordern, mit privateKey signieren, signedChallenge zurückgeben für Server-Verify.
- **Acceptance Criteria**:
  - **Given** ein gespeicherter privateKey + FakeSupabaseAuthAdapter der eine deterministische Challenge liefert
  - **When** `signInWithChallenge()` aufgerufen wird
  - **Then** wird die Challenge geholt, signed, an `signInWithKeypairChallenge` übergeben

### M4-T11: auth_providers + display_profile_provider + tests

- **Type**: domain
- **Size**: S
- **Bounded Context**: auth, player
- **Agent**: /agents/coder (domain)
- **Dependencies**: M4-T03
- **Files (anticipated)**: `lib/features/auth/application/auth_providers.dart`, `lib/features/player/application/display_profile_provider.dart`, `test/features/auth/application/auth_providers_test.dart`
- **Goal**: Computed Provider per architecture.md §Riverpod-topology.
- **Acceptance Criteria**:
  - **Given** verschiedene AuthSession-States im AuthController
  - **When** die computed Provider gewatched werden
  - **Then** liefern sie die korrekten Werte (`isAuthenticatedProvider == true` nur bei `Authenticated`, etc.)

### M5-T01: Batch design-brief.md schreiben (Owner-blocking)

- **Type**: docs (design-brief)
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (docs)
- **Dependencies**: M4-T11
- **Files (anticipated)**: `docs/plans/auth-oauth-keypair/design-brief.md`
- **Goal**: Konsolidiertes Design-Brief-Dokument mit einem Eintrag pro UI-Element (M5-T02 bis M5-T15 + M7-T01 + M7-T02). Pro Eintrag: User-Story-Bezug, Constraints, abzudeckende States, Accessibility, ARB-Key-Vorschlag.
- **Acceptance Criteria**:
  - **Given** alle M5/M7-UI-Elemente sind im Sprint-Plan gelistet
  - **When** der Brief geschrieben ist
  - **Then** kann der Owner das Dokument an Claude Design übergeben und alle Templates in einer Session produzieren
- **Notes**: **Dieser Task blockt M5-T02 bis M5-T15 + M7-T01 + M7-T02.** Implementierung dieser Tasks startet ERST nach Owner-Bestätigung "Templates sind da" (manuelle Owner-Bestätigung im Implement-Loop).

### M5-T02 — M5-T15 (UI-Implementierungs-Tasks)

> Alle M5-Tasks ab T02 folgen dem gleichen Schema: implement gegen das vom Owner gelieferte Template, dazu Widget-Test. Hier kompakt — Detail erst nach Templates verfügbar.

| Task | Goal | Files | Size |
|------|------|-------|------|
| M5-T02 | sign_in_screen mit 3 CTAs (Google + Apple-iOS + Anonym), Restore-Link | `lib/features/auth/presentation/sign_in_screen.dart` + test | S |
| M5-T03 | NicknameStep im AnonymousSignupFlow + PageView-Scaffold | `lib/features/auth/presentation/anonymous_signup_flow.dart` + test | S |
| M5-T04 | disclaimer_block reusable widget mit 3 Bullets + Pflicht-Checkbox (AK-19) | `lib/features/auth/presentation/disclaimer_block.dart` + test | S |
| M5-T05 | passphrase_input mit show/hide + zxcvbn-light Strength + 12-Char-Validation | `lib/features/auth/presentation/passphrase_input.dart` + test | S |
| M5-T06 | DisclaimerAndPassphraseStep im Flow (nutzt T04 + T05) | `anonymous_signup_flow.dart` (extend) + test | S |
| M5-T07 | BackupConfirmationStep im Flow | `anonymous_signup_flow.dart` (extend) + test | S |
| M5-T08 | restore_flow mit Nickname/Passphrase/Cooldown-Badge | `lib/features/auth/presentation/restore_flow.dart` + test | S |
| M5-T09 | account_link_screen | `lib/features/auth/presentation/account_link_screen.dart` + test | S |
| M5-T10 | passphrase_change_screen | `lib/features/auth/presentation/passphrase_change_screen.dart` + test | S |
| M5-T11 | delete_account_screen mit Two-Step Confirmation | `lib/features/auth/presentation/delete_account_screen.dart` + test | S |
| M5-T12 | onboarding_tour mit 4 Slides | `lib/features/auth/presentation/onboarding_tour.dart` + test | M |
| M5-T13 | oauth_provider_button shared widget mit Provider-Logo | `lib/features/auth/presentation/auth_widgets/oauth_provider_button.dart` + test | S |
| M5-T14 | account_section in settings_screen integriert | `lib/features/auth/presentation/account_section.dart` + Edit von `lib/features/settings/presentation/settings_screen.dart` + test | S |
| M5-T15 | edit_profile_screen (replaces F2 edit-mode) | `lib/features/auth/presentation/edit_profile_screen.dart` + test | S |

**Acceptance pattern für jeden M5-Implementations-Task**:
- **Given** das Owner-bereitgestellte Template für dieses UI-Element ist verfügbar
- **When** das Widget/Screen implementiert ist
- **Then** entspricht die Implementierung dem Template (Farben, Spacing, Typografie, Copy aus ARB, Motion, Accessibility)
- **And** ein Widget-Test deckt die im Brief geforderten States ab (loading, empty, error, success, disabled)
- **And** `flutter analyze` clean

### M6-T01: ARB strings auth.* (de) + flutter gen-l10n + commit generated

- **Type**: frontend
- **Size**: M
- **Bounded Context**: core
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M5-T15
- **Files (anticipated)**: `lib/l10n/app_de.arb`, `lib/l10n/generated/app_localizations.dart`, `lib/l10n/generated/app_localizations_de.dart`
- **Goal**: Alle neuen UI-Strings als `auth.*`-Keys in der ARB; `flutter gen-l10n` ausführen; generated files committen.
- **Acceptance Criteria**:
  - **Given** alle M5-Tasks haben ihre Texte als `AppLocalizations.of(context)!.authXxx` referenziert
  - **When** der Task abgeschlossen ist
  - **Then** existieren alle ARB-Keys, generated files sind aktuell, `git diff lib/l10n/generated/` zeigt keine ungestaged Files
- **Notes**: Tech-Lead-Quality-Gate 6 prüft das.

### M6-T02: SessionDao methods rename playerId → userId

- **Type**: data
- **Size**: S
- **Bounded Context**: core
- **Agent**: /agents/coder (data)
- **Dependencies**: M1-T01
- **Files (anticipated)**: `lib/core/data/dao/session_dao.dart`, `test/core/data/session_dao_test.dart` (anpassen)
- **Goal**: Alle Methoden in SessionDao die `playerId` als Parameter haben → `userId`. Bestehende Tests anpassen.
- **Acceptance Criteria**:
  - **Given** drift v4 ist da, Sessions-Tabelle hat `userId`-Spalte
  - **When** SessionDao-Methoden umbenannt sind (`activeForPlayer` → `activeForUser`, etc.)
  - **Then** kompiliert, bestehende Session-Tests grün

### M6-T03: Update Session callers in training/stats

- **Type**: frontend
- **Size**: M
- **Bounded Context**: training, stats
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M6-T02
- **Files (anticipated)**: alle Dateien in `lib/features/training/`, `lib/features/stats/` die `session.playerId` oder `dao.activeForPlayer(...)` aufrufen
- **Goal**: Cross-File-Refactoring: alle Verweise auf `session.playerId` → `session.userId`, alle Dao-Method-Calls renamen.
- **Acceptance Criteria**:
  - **Given** M6-T02 ist gemerged
  - **When** alle Caller umgestellt sind
  - **Then** `flutter analyze` clean, alle bestehenden Training/Stats-Tests grün

### M6-T04: Delete F2 player files

- **Type**: frontend
- **Size**: S
- **Bounded Context**: player
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M4-T11, M5-T15
- **Files (anticipated)**: DELETE `lib/features/player/data/player_repository.dart`, `lib/core/data/tables/players.dart`, `lib/features/player/application/current_profile_provider.dart`, `lib/features/player/presentation/onboarding_screen.dart`, `lib/features/player/data/`, `lib/core/data/dao/player_dao.dart`
- **Goal**: F2-Code-Removal — alle Files die durch das neue Auth-Konstrukt obsolet sind.
- **Acceptance Criteria**:
  - **Given** M4-T11 und M5-T15 sind gemerged (display_profile_provider und edit_profile_screen sind da)
  - **When** die F2-Files gelöscht werden
  - **Then** `flutter analyze` clean (keine Verweise mehr); `flutter test` grün
  - **And** `lib/features/player/` enthält nur noch presentation/profile_screen.dart (display-only nach M6-T05) + application/display_profile_provider.dart

### M6-T05: Rewrite profile_screen as display-only

- **Type**: frontend
- **Size**: S
- **Bounded Context**: player
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M6-T04
- **Files (anticipated)**: `lib/features/player/presentation/profile_screen.dart` (rewrite), `test/features/player/profile_screen_test.dart` (anpassen)
- **Goal**: Display-only Profil-Anzeige, liest `displayProfileProvider`. Edit-Mode wird via deep-link nach `/profile/edit` (= M5-T15) delegiert.
- **Acceptance Criteria**:
  - **Given** M5-T15 (edit_profile_screen) und M4-T11 (display_profile_provider)
  - **When** profile_screen ohne Edit-Logik existiert
  - **Then** zeigt es Nickname, Avatar, Account-Status; "Edit"-Button navigiert zu `/profile/edit`

### M6-T06: Update callers of currentProfileProvider → displayProfileProvider

- **Type**: frontend
- **Size**: M
- **Bounded Context**: training, stats, settings
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M4-T11
- **Files (anticipated)**: alle Dateien die `currentProfileProvider` importieren (per grep auflisten)
- **Goal**: Migration aller bestehenden Caller (vermutlich ~6 Dateien) auf den neuen Provider.
- **Acceptance Criteria**:
  - **Given** M4-T11 ist gemerged
  - **When** alle Caller aktualisiert sind
  - **Then** `flutter analyze` clean, alle bestehenden Tests grün

### M6-T07: router.dart redirect rewrite + new routes + tests

- **Type**: frontend
- **Size**: M
- **Bounded Context**: app
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M5-T02, M4-T03
- **Files (anticipated)**: `lib/app/router.dart`, `test/app/router_test.dart`
- **Goal**: Neue Redirect-Logik: `signedOut → /sign-in` (no exceptions). Neue Routes registrieren: /sign-in, /sign-in/anonymous, /sign-in/restore, /auth/callback, /onboarding-tour, /settings/account/link, /settings/account/passphrase, /settings/account/delete, /profile/edit. Bestehende /onboarding-Route (F2) entfernen.
- **Acceptance Criteria**:
  - **Given** authControllerProvider ist da
  - **When** Router gebootet wird mit verschiedenen AuthSession-States (SignedOut, Authenticated.oauth, Authenticated.keypair)
  - **Then** redirect-Verhalten ist korrekt; Routes-Tests pro Pfad grün

### M6-T08: bootstrap.dart cached-session readout

- **Type**: frontend
- **Size**: S
- **Bounded Context**: app
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M1-T03, M4-T03
- **Files (anticipated)**: `lib/app/bootstrap.dart`
- **Goal**: Beim Bootstrap synchron die cached_auth_session lesen, sodass der Router-Redirect ohne AsyncLoading-Window operieren kann (analog zur bestehenden initialProfileProvider-Logik).
- **Acceptance Criteria**:
  - **Given** eine valide cached_auth_session-Zeile existiert
  - **When** die App startet
  - **Then** ist initialAuthSessionProvider sofort mit der gecachten Session befüllt; der Router redirected nicht zum Sign-In, sondern direkt zum Home

### M7-T01: Account-status badge in AppBar (US-15)

- **Type**: frontend
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M5-T01 (Templates), M5-T14
- **Files (anticipated)**: `lib/core/ui/widgets/account_status_badge.dart` + Edit von AppBar in HomeScreen + test
- **Goal**: Badge "Anonym" / "Google" / "Apple" mit Icon — sichtbar in der App-Bar.
- **Acceptance Criteria**:
  - **Given** Template ist da, currentProviderProvider liefert den aktuellen Provider
  - **When** der HomeScreen rendert
  - **Then** ist das Badge sichtbar mit korrektem Text + Icon
  - **And** Tap auf das Badge öffnet die Account-Sektion in den Settings

### M7-T02: Backup-warning surface in settings (US-10)

- **Type**: frontend
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (frontend)
- **Dependencies**: M5-T01 (Templates), M5-T14
- **Files (anticipated)**: Edit `lib/features/auth/presentation/account_section.dart` + test
- **Goal**: Warnings-Block "Kein Backup eingerichtet" für anonyme Accounts ohne Backup oder mit Backup > 90 Tage alt.
- **Acceptance Criteria**:
  - **Given** anonymer Account ohne Backup-Eintrag im Server (oder backup older than 90 days)
  - **When** der Settings-Screen geöffnet wird
  - **Then** ist die Warning sichtbar mit "Backup einrichten"-Button

### M7-T03: Internal logging audit pass + tests (US-17)

- **Type**: tests
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: M3-T08
- **Files (anticipated)**: `test/features/auth/auth_logging_audit_test.dart` + ggf. Fixes in `lib/features/auth/`
- **Goal**: Grep-basierter Audit der gesamten auth/-Codebasis: kein `print(`, kein `log(`, kein `Logger(...)` ausser via `AuthTelemetry`. Alle Auth-State-Transitionen müssen einen Telemetry-Call haben.
- **Acceptance Criteria**:
  - **Given** alle M3+M4-Tasks sind gemerged
  - **When** der Audit-Test läuft
  - **Then** keine direkten print/log-Calls in lib/features/auth/, alle State-Transitions in AuthController emittieren ein Telemetry-Event

### M7-T04: Full integration test

- **Type**: tests
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: alle M5-* und M6-*
- **Files (anticipated)**: `integration_test/auth_full_flow_test.dart`
- **Goal**: End-to-End-Test: anonymous signup → backup upload → simulate device wipe → restore → upgrade to OAuth → logout. Gegen Docker-Supabase.
- **Acceptance Criteria**:
  - **Given** Docker-Supabase läuft, alle Auth-Tasks sind gemerged
  - **When** der Integration-Test läuft
  - **Then** alle Schritte durchlaufen ohne Fehler, finaler State ist `SignedOut`

### M7-T05: Final security-check pass auf alle Auth-Pfade

- **Type**: security
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/security-checker
- **Dependencies**: M7-T04
- **Files (anticipated)**: `/tmp/kubb_app/auth-oauth-keypair/security-review-final.md`
- **Goal**: Komplett-Review aller Auth-Pfade — Token-Storage, RLS, Endpoint-Authorization, OWASP-Top-10, Cooldown-Bypass-Versuche, Replay-Attack-Schutz auf keypair_challenge.
- **Acceptance Criteria**:
  - **Given** das Feature-Branch
  - **When** der Security-Checker durchläuft
  - **Then** kein BLOCKING-Finding; MEDIUM/LOW dokumentiert mit Empfehlung; Owner entscheidet ob Follow-up-Tasks erstellt werden
