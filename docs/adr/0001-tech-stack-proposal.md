# ADR-0001: Tech stack proposal — state, persistence, sync, routing

- **Status**: **Proposed** (awaits owner approval)
- **Date**: 2026-05-02

## Context

After bootstrap (ADR-0000) the app needs concrete library picks for:
1. State management
2. Local persistence
3. Cloud backend / multi-device sync
4. Routing
5. Forms / validation
6. Code generation / immutable models

The owner has explicitly delegated this set of decisions to a deliberate review (informally referred to as the "Architekturagent-Gremium"). The picks below are this author's recommendation; they are **not** locked into `pubspec.yaml` until accepted.

## Functional drivers (recap)

- **Hybrid offline + cloud sync**: during a tournament, both teams enter scores on their phones; organizer screen reflects live state; resilient to flaky networks.
- **Real-time updates** between players' phones and the organizer / scoreboard view.
- **Offline-capable training modes** (no network required for 8m-Ticker etc.).
- **Type-safe domain modeling** (rule engine, score state, bracket).
- **Mobile + web + desktop** from one codebase.

## Proposal

| Concern | Choice | Why this | Why not the alternatives |
|---|---|---|---|
| State mgmt | **Riverpod 2** with `riverpod_generator` | async-first; fits realtime streams; testable without widget tree; no `BuildContext` lookups. | Bloc: more ceremony, less ergonomic for streams. Provider: legacy. GetX: opinionated and harder to test. |
| Local DB | **`drift`** (SQLite, type-safe DAO) | type-safe queries, migrations, runs on all targets including web (via `sqlite3.wasm`). Mature. | Isar: faster but unstable maintenance. Hive: schemaless, painful to query. Sembast: too low-level. |
| Cloud backend | **Supabase** (Postgres + Realtime + Auth + Storage) | open-source, EU-hostable, native realtime subscriptions perfect for live scoring; Postgres is honest about constraints. Free tier ample for early stage. | Firebase: vendor lock-in, less honest about constraints, EU-data-residency story weaker. PocketBase: lighter but realtime less mature. Self-hosted: ops overhead too early. |
| Sync | **Repository + per-feature sync layer** on top of drift + Supabase Realtime | simple optimistic write-through, conflict policy per entity (last-write-wins for scores, manual merge for bracket changes). | CRDTs: overkill for tournament scope, hard to reason about. Powersync: paid. |
| Routing | **`go_router`** | declarative, deep-link friendly, web-friendly URLs (organizer dashboard works in browser). | auto_route: codegen overhead for marginal gains here. |
| Forms | **`reactive_forms`** | declarative validation, plays well with Riverpod. | `flutter_form_builder`: heavier surface area. Manual: too much boilerplate at our scale. |
| Models | **`freezed` + `json_serializable`** | immutable unions for game/match state, structural equality, sealed exhaustiveness in `switch`. | Manual `==`/`hashCode`: error-prone. `dart_mappable`: smaller community. |
| Code gen | **`build_runner`** (watch mode while developing) | standard. | — |

### Indicative dependency block (would land in `pubspec.yaml` after approval)

```yaml
dependencies:
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0
  go_router: ^14.0.0
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.1.0
  path: ^1.9.0
  supabase_flutter: ^2.5.0
  reactive_forms: ^17.0.0
  freezed_annotation: ^2.4.0
  json_annotation: ^4.9.0

dev_dependencies:
  build_runner: ^2.4.0
  drift_dev: ^2.18.0
  riverpod_generator: ^2.4.0
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  custom_lint: ^0.6.0
  riverpod_lint: ^2.3.0
```

(Versions are indicative — actual resolution by `flutter pub get` will pick the latest compatible.)

## Alternatives considered (high-level)

- **No backend, all local + manual export**: rejected — multi-device live scoring is a core MVP requirement.
- **Firebase + no local DB**: rejected — offline play during a tournament with flaky reception is non-negotiable.
- **Bloc + Hive + Firebase**: a perfectly viable stack many production apps use; the Riverpod + drift + Supabase combination wins on type-safety, async ergonomics, and EU data hosting.
- **Server-authoritative scoring (custom backend)**: ops cost too high for v1; revisit if Supabase row-level rules can't cover the trust model.

## Consequences

- Adds non-trivial code generation: developers must run `dart run build_runner watch -d` while editing freezed/riverpod-annotated files.
- Supabase implies an external account; for v1 we will use a free-tier project owned by Lukas.
- `drift` on web needs the `sqlite3.wasm` worker; `flutter run -d chrome` requires loading it (drift docs cover this).

## Decision

**Pending.** Lukas to approve, modify, or trigger an alternative review path before any of the above libraries are added to `pubspec.yaml`.
