# Sprint-Plan — Authentication: OAuth + anonymous keypair

## Meta

- **Slug**: auth-oauth-keypair
- **Erstellt**: 2026-05-04
- **Branch**: feature/auth-oauth-keypair
- **Status**: sprint-done (ready for implement-loop)
- **Gesamt-Tasks**: 65 (in 8 Phasen M0–M7)
- **Geschätzte effektive Stunden**: ~52 h (siehe Time-Budget unten)
- **Owner-Level**: Senior — Faktor 0.8 auf Schätzungen

## Milestones

| # | Milestone | Tasks | Geschätzt (effektiv) | Beschreibung |
|---|---|---|---|---|
| M0 | Spike & Dependencies | 4 | 3 h | Argon2id-Spike, pubspec-Deps, Docker-Supabase, Dev-Environment-Verify |
| M1 | Local data layer (drift v4) | 8 | 7 h | Destruktive drift v4-Migration, cached_auth_session, secure_token_store, keypair_storage, crypto_service |
| M2 | Server schema + custom endpoints | 6 | 7 h | SQL-Migration, RLS, 3 Postgres-Funktionen, curl-Smoketests, Security-Review |
| M3 | Repositories & adapters | 8 | 8 h | SupabaseAuthAdapter, KeypairBackupRepo, CloudProfileRepo, AuthTelemetry — alle TDD |
| M4 | Application layer | 11 | 10 h | AuthSession, AuthController, 6 Sub-Controller, KeypairSigningService, Computed Provider |
| M5 | UI (design-template-gated) | 15 | 11 h | Batch-Design-Brief + 14 UI-Implement-Tasks (Sign-In, Anonymous-Flow, Restore, Account-Section, Onboarding-Tour, etc.) |
| M6 | Routing + bootstrap + l10n + player cleanup | 8 | 5 h | ARB-Strings, Router-Rewrite, F2-Player-Removal, Caller-Migrationen |
| M7 | Polish + integration | 5 | 4 h | Status-Badge, Backup-Warning, Logging-Audit, Full-Integration-Test, Final-Security |
| **Σ** | | **65** | **~55 h** brutto / **~52 h** netto Senior 0.8x | |

## Ausführungsreihenfolge (topologisch sortiert)

### Phase M0 — Spike & Dependencies (sequenziell in der Reihe; T03 kann parallel)

| Task | Titel | Size | Abhängig von |
|------|-------|------|---------------|
| M0-T01 | Spike Argon2id benchmark Linux/Android/Web | S | — |
| M0-T02 | Add pubspec deps (4 packages) | S | M0-T01 |
| M0-T03 | docker-compose.local.yml für lokales Supabase | M | — (kann parallel zu T01/T02) |
| M0-T04 | Verify dev environment | S | M0-T02 |

### Phase M1 — Local data layer (drift v4)

| Task | Titel | Size | Abhängig von |
|------|-------|------|---------------|
| M1-T01 | drift v4 migration code + v3-backup hook | M | M0-T02 |
| M1-T02 | drift v4 migration tests with v3 fixture | S | M1-T01 |
| M1-T03 | cached_auth_session table + DAO + tests | S | M1-T01 |
| M1-T04 | secure_token_store + tests | S | M0-T02 |
| M1-T06 | crypto_service ed25519 ops + tests | S | M0-T02 |
| M1-T08 | crypto_service xchacha20 + tests | S | M0-T02 |
| M1-T07 | crypto_service argon2id + isolate runner + tests | M | M0-T01, M0-T02 |
| M1-T05 | keypair_storage + tests | S | M1-T04, M1-T06 |

> Innerhalb M1: T04, T06, T08 sind parallel-lauffähig nach M0. T05 kommt nach T04+T06. T07 wartet auf das Spike-Ergebnis aus M0-T01.

### Phase M2 — Server schema + custom endpoints (in der Reihe)

| Task | Titel | Size | Abhängig von |
|------|-------|------|---------------|
| M2-T01 | SQL migration: tables, indexes, server-salt | M | M0-T03 |
| M2-T02 | SQL migration: RLS policies | S | M2-T01 |
| M2-T03 | Postgres function: keypair_create | S | M2-T02 |
| M2-T04 | Postgres functions: keypair_challenge + verify | M | M2-T02, M1-T06 |
| M2-T05 | curl-Tests gegen Docker-Supabase | S | M2-T03, M2-T04 |
| M2-T06 | Security review M2 | S | M2-T05 |

### Phase M3 — Repositories & adapters (TDD-Paare)

| Task | Titel | Size | Abhängig von |
|------|-------|------|---------------|
| M3-T01 | SupabaseAuthAdapter tests + Fake | S | — |
| M3-T02 | SupabaseAuthAdapter implementation | M | M3-T01, M0-T02 |
| M3-T03 | KeypairBackupRepository tests + Fake | S | M1-T07, M1-T08 |
| M3-T04 | KeypairBackupRepository implementation | M | M3-T03, M2-T01 |
| M3-T05 | CloudProfileRepository tests + Fake | S | M2-T01 |
| M3-T06 | CloudProfileRepository implementation | S | M3-T05 |
| M3-T07 | AuthTelemetry tests | S | — |
| M3-T08 | AuthTelemetry implementation | S | M3-T07 |

### Phase M4 — Application layer (TDD-Paare)

| Task | Titel | Size | Abhängig von |
|------|-------|------|---------------|
| M4-T01 | AuthSession sealed class + tests | S | M0-T02 |
| M4-T02 | AuthController tests | S | M4-T01, M3-T01 |
| M4-T03 | AuthController implementation | M | M4-T02, M3-T02, M1-T03 |
| M4-T04 | AccountSetupController tests | S | M4-T01, M3-T01, M3-T03 |
| M4-T05 | AccountSetupController implementation | M | M4-T04 |
| M4-T06 | RestoreController + cooldown logic + tests | M | M4-T01, M3-T03 |
| M4-T07 | AccountUpgradeController + tests | S | M4-T03, M3-T02 |
| M4-T08 | PassphraseChangeController + tests | S | M4-T03, M3-T04 |
| M4-T09 | AccountDeletionController + tests | S | M4-T03, M3-T02, M3-T04, M3-T06 |
| M4-T10 | KeypairSigningService + tests | S | M1-T05, M1-T06, M3-T02 |
| M4-T11 | auth_providers + display_profile_provider + tests | S | M4-T03 |

### Phase M5 — UI (design-template-gated)

| Task | Titel | Size | Abhängig von | Owner-blocking? |
|------|-------|------|---------------|------------------|
| M5-T01 | Batch design-brief.md | M | M4-T11 | **JA — blockt T02–T15** |
| M5-T02 | sign_in_screen + test | S | M5-T01 + Owner-Confirmation | nach T01 |
| M5-T03 | anonymous_signup_flow scaffold + NicknameStep | S | M5-T01 + Owner-Confirmation, M4-T05 | nach T01 |
| M5-T04 | disclaimer_block widget | S | M5-T01 + Owner-Confirmation | nach T01 |
| M5-T05 | passphrase_input widget | S | M5-T01 + Owner-Confirmation | nach T01 |
| M5-T06 | DisclaimerAndPassphraseStep | S | M5-T03, T04, T05 | nach T01 |
| M5-T07 | BackupConfirmationStep | S | M5-T06 | nach T01 |
| M5-T08 | restore_flow + cooldown badge | S | M5-T01 + Owner-Confirmation, M4-T06 | nach T01 |
| M5-T09 | account_link_screen | S | M5-T01 + Owner-Confirmation, M4-T07 | nach T01 |
| M5-T10 | passphrase_change_screen | S | M5-T01 + Owner-Confirmation, M4-T08 | nach T01 |
| M5-T11 | delete_account_screen | S | M5-T01 + Owner-Confirmation, M4-T09 | nach T01 |
| M5-T12 | onboarding_tour (4 Slides) | M | M5-T01 + Owner-Confirmation | nach T01 |
| M5-T13 | oauth_provider_button shared | S | M5-T01 + Owner-Confirmation | nach T01 |
| M5-T14 | account_section in settings | S | M5-T01 + Owner-Confirmation, M4-T03 | nach T01 |
| M5-T15 | edit_profile_screen | S | M5-T01 + Owner-Confirmation, M3-T06 | nach T01 |

### Phase M6 — Routing + bootstrap + l10n + player cleanup

| Task | Titel | Size | Abhängig von |
|------|-------|------|---------------|
| M6-T01 | ARB strings auth.* + flutter gen-l10n | M | M5-T15 |
| M6-T02 | SessionDao methods rename playerId → userId | S | M1-T01 |
| M6-T03 | Update Session callers in training/stats | M | M6-T02 |
| M6-T04 | Delete F2 player files | S | M4-T11, M5-T15 |
| M6-T05 | Rewrite profile_screen as display-only | S | M6-T04 |
| M6-T06 | Update callers of currentProfileProvider | M | M4-T11 |
| M6-T07 | router.dart redirect rewrite + new routes | M | M5-T02, M4-T03 |
| M6-T08 | bootstrap.dart cached-session readout | S | M1-T03, M4-T03 |

### Phase M7 — Polish + integration

| Task | Titel | Size | Abhängig von |
|------|-------|------|---------------|
| M7-T01 | Account-status badge in AppBar | S | M5-T01, M5-T14 |
| M7-T02 | Backup-warning surface in settings | S | M5-T01, M5-T14 |
| M7-T03 | Internal logging audit pass + tests | S | M3-T08 |
| M7-T04 | Full integration test | M | M5-*, M6-* |
| M7-T05 | Final security-check pass | S | M7-T04 |

## Critical Path

Längster Pfad durch das DAG (definiert die Mindest-Dauer):

```
M0-T01 → M0-T02 → M1-T07 → M3-T03 → M3-T04 → M4-T08 → M4-T11 → M5-T01 (Owner-blocking) → M5-T10 → M6-T01 → M7-T04 → M7-T05
```

Davon ist **M5-T01 ein Owner-Synchronisations-Punkt** — alles ab M5-T02 wartet auf vom Owner gelieferte Templates aus Claude Design.

**Geschätzte Critical-Path-Dauer**: ~28 h reine Arbeit + Owner-Wartezeit für Templates (variabel — typisch 1–2 Tage).

## Risiken (aus architecture.md übernommen + Sprint-Erweiterungen)

| # | Risiko | Wahrsch. | Impact | Mitigation |
|---|---|---|---|---|
| 1 | Argon2id auf Web zu langsam (>10 s) | Mittel | Mittel | M0-T01 als Spike-Task FIRST. Bei Problem: Web-Parameter m=32 MiB (Spec-Update in M1-T07) |
| 2 | Lokal-Docker-Supabase ≠ Hetzner-Supabase Verhalten | Niedrig | Mittel | M2-T05 curl-Smoketest dokumentiert die Aufrufe; Hetzner-Verifikation als Owner-Task post-feature |
| 3 | Custom Postgres-Functions fehleranfällig | Mittel | Hoch | M2-T05 Smoketest + M2-T06 Security-Review explizit; SQL kompakt halten (~80 Zeilen) |
| 4 | OAuth-Deep-Link auf Linux-Desktop | Niedrig | Niedrig | Linux-OAuth deferred; Sign-In zeigt "auf Linux noch nicht unterstützt"-Hint, nur Keypair-Pfad aktiv |
| 5 | Profile-Creation-Race | Niedrig | Mittel | M3-T06 nutzt `ON CONFLICT (user_id) DO NOTHING RETURNING *` für Idempotenz |
| 6 | drift v4 destruktive Migration | Mittel | Hoch | M1-T01 schreibt v3-Backup vor Migration; M1-T02 Test verifiziert Backup-Existenz |
| 7 | **NEU** — Owner produziert Design-Templates verspätet | Mittel | Hoch (blockt M5+M6+M7) | M5-T01 möglichst früh fertigstellen (so detailliert wie möglich, damit Owner alles in einer Claude-Design-Session abdeckt). Bei Verspätung: M6-T02 bis T06 (non-UI-Tasks) können parallel laufen |
| 8 | **NEU** — Schema-Drift zwischen drift v4 und Server-Schema | Niedrig | Mittel | Beide Schemas in `architecture.md` zusammen dokumentiert; Pull-Request enthält beide Migrations als atomares Pair |

## Time-Budget-Berechnung (Senior-Faktor 0.8x)

Annahmen aus `rules/scrum-master.md`:
- Owner verfügbare Stunden pro Woche: 10 h (Default `available-hours-per-week`)
- Buffer-Prozent: 10% (Default `buffer-percent`)
- Test-/Review-Anteil: 20% (Default `test-review-percent`)

```
Brutto-Schätzung Tasks (Senior 0.8x angewandt):
M0: 4 Tasks × ~0.7 h ≈ 3 h
M1: 8 Tasks × ~0.85 h ≈ 7 h
M2: 6 Tasks × ~1.2 h ≈ 7 h
M3: 8 Tasks × ~1 h ≈ 8 h
M4: 11 Tasks × ~0.9 h ≈ 10 h
M5: 15 Tasks × ~0.75 h ≈ 11 h (Owner-Wartezeit nicht eingerechnet)
M6: 8 Tasks × ~0.65 h ≈ 5 h
M7: 5 Tasks × ~0.8 h ≈ 4 h
─────────────────────────────────
Σ Brutto: ~55 h Implementation
─────────────────────────────────
Effektiv (= Brutto, der Buffer + Test-Review-Aufschlag wären für noch nicht
geplante Tasks reserviert; wir haben Tests bereits in der Brutto-Summe)
```

**Kalenderdauer (10 h/Woche)**: ~5–6 Wochen reine Implementierungs-Zeit, plus Owner-Wartezeit für Design-Templates in M5.

**Eskalations-Hinweis**: Diese Schätzung ist signifikant grösser als die typischen "Phase-1-Feature"-Pakete (Sniper-MVP war ~25 h). Wenn der Owner kürzer auslegen will, sind folgende Scope-Reduktionen möglich:
- **SHOULD/COULD-Stories abschneiden**: US-10, US-11, US-12, US-15, US-16 → spart ~5 h (M7 + Teile von M5)
- **OAuth-Pfad nur Google in v1**, Apple deferred → spart ~3 h (Apple-spezifische UI + Tests)
- **Server-Salt deferred** (initial: nickname_hash = sha256(nickname) ohne Salt; späteres Backfill geplant) → spart ~1 h
- **Logging-Audit + Telemetry-Tasks deferred** zu späterem Polish-Cycle → spart ~2 h

Total mögliche Reduktion: ~11 h → effektiv ~44 h, ~4 Wochen.

## Fortschritt

| Milestone | Done | In Progress | Blocked | Pending | Total |
|---|---|---|---|---|---|
| M0 | 4 | 0 | 0 | 0 | 4 |
| M1 | 8 | 0 | 0 | 0 | 8 |
| M2 | 6 | 0 | 0 | 0 | 6 |
| M3 | 8 | 0 | 0 | 0 | 8 |
| M4 | 11 | 0 | 0 | 0 | 11 |
| M5 | 1 | 0 | 14 | 0 | 15 |
| M6 | 0 | 0 | 0 | 8 | 8 |
| M7 | 0 | 0 | 0 | 5 | 5 |
| **Gesamt** | **38** | **0** | **14** | **13** | **65** |

## Nächste Schritte (Übergabe an /workflows/feature Phase 3)

1. Owner liest sprint-plan.md + tasks.md, akzeptiert oder fordert Scope-Reduktion (siehe Eskalations-Hinweis oben)
2. Branch `feature/auth-oauth-keypair` erstellen
3. Implement-Loop startet bei M0-T01 (Spike)
4. M5-T01 ist der Owner-Synchronisations-Punkt — wenn der Loop dort ankommt, wird das design-brief.md geschrieben und der Loop pausiert auf Owner-Bestätigung "Templates sind da"
5. Nach allen 65 Tasks: Final-Review → Commit-Guard → Push
