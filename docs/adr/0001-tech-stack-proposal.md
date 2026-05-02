# ADR-0001: Tech stack — Tactical DDD with pragmatic backbone

- **Status**: **Accepted**
- **Date**: 2026-05-02
- **Supersedes**: prior Proposed version of this ADR

## Context

After bootstrap (ADR-0000) the app needed library picks for state, persistence, cloud sync, routing, forms, models, code-gen, DI, networking, logging, folder structure, and testing. Three competing proposals were produced (pragmatic veteran, modern DX, DDD/hexagonal) and reviewed by three independent reviewers (risk/maintainability, product/delivery, ops/realtime).

Outcome of the review:
- Pragmatic Veteran proposal won 2 of 3 reviewer lenses (risk: 9/10, product: 9/10, ops: 7.5/10).
- DDD/Hexagonal proposal won the ops lens (9/10) primarily because of its event-log + Lamport-clock + first-class-dispute design.
- Modern DX scored mid in all three.

The owner expressed a strong preference for the professionalism implied by the DDD/Hexagonal plan but acknowledged the velocity tax of applying full hexagonal to CRUD-heavy features.

## Decision

**Tactical DDD**: pragmatic backbone (Riverpod + drift + Supabase) with hexagonal discipline applied **only where the domain is rich**. Hexagonal ceremony is not paid for CRUD-shaped features.

### Picks

| Concern | Pick | Notes |
|---|---|---|
| State management | **Riverpod 2.x** + `riverpod_generator` | Doubles as DI. AsyncNotifier maps cleanly onto drift streams + Supabase realtime. |
| Local DB | **drift 2.x** | Type-safe SQL, runs on Android + Linux native + Web (sqlite3.wasm). |
| Cloud / realtime | **Supabase** (Frankfurt, EU region) | Postgres + Realtime + Auth + RLS. Free tier ample for early stage. Exit: pg_dump + adapter swap. |
| Sync model | **Append-only event log** keyed by UUIDv7, **Lamport ordering**, `DisputeRaised` + `OrganizerOverride` as first-class events | NOT last-write-wins per field. Score events are immutable; conflict resolution is a domain operation, not a sync race. |
| Routing | **go_router 14.x** | Web-friendly URLs for backoffice; deep links for mobile. |
| Forms | **reactive_forms** | Declarative validation; plays well with Riverpod. |
| Models | **freezed 2.x** + `json_serializable` | Sealed unions for match state, structural equality. |
| Code-gen | **build_runner** (watch mode in dev) | Standard Flutter codegen toolchain. |
| DI | Riverpod (no separate container) | Avoids redundancy of get_it + injectable + Riverpod. |
| Networking | Supabase SDK + `dio` for any direct HTTP | Most network goes through the Supabase client. |
| Logging | `package:logging` initially; Sentry later if needed | Defer paid observability until real usage. |
| Folder structure | **Bounded-context-aware** — see ADR-0002 | Hexagonal where complex, pragmatic where simple. |
| Testing | `flutter_test`, `mocktail`, `glados` (property tests for the rule engine), `golden_toolkit` for goldens, `integration_test` | Property tests on rules; mocktail at the port boundary; in-memory drift for repository tests. |

### Indicative dependency block

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  cupertino_icons: ^1.0.8
  intl: any

  # Domain (path)
  kubb_domain:
    path: packages/kubb_domain

  # State + DI + routing
  flutter_riverpod: any
  riverpod_annotation: any
  go_router: any

  # Persistence
  drift: any
  sqlite3_flutter_libs: any
  path_provider: any
  path: any

  # Cloud
  supabase_flutter: any

  # Forms / models / utils
  reactive_forms: any
  freezed_annotation: any
  json_annotation: any
  uuid: any
  logging: any
  collection: any

dev_dependencies:
  flutter_test:
    sdk: flutter
  very_good_analysis: any
  build_runner: any
  drift_dev: any
  riverpod_generator: any
  freezed: any
  json_serializable: any
  custom_lint: any
  riverpod_lint: any
  mocktail: any
  glados: any
```

`any` is used here for clarity; the actual lock file will pin specific versions resolved by `flutter pub get`.

## MUST-FIXes before non-trivial code

These are consensus blockers from the three-reviewer panel. They are not optional.

1. **Drift-on-Web WASM spike** (day 1). All three reviewers flagged this. Verify `flutter build web` with `sqlite3.wasm` + OPFS persistence works on target Chromium versions before any Web-specific code is written. If it doesn't, the web target is a thinner read-only client.
2. **Lamport-clock protocol pinned on paper** before any data row exists. Document: clock advance rule, tie-break by device_id, monotonic invariant. Migrating after data exists is expensive.
3. **Score-disagreement state machine** designed before sync code. States: `Proposed → Confirmed → Disputed → Overridden`. Documented in `packages/kubb_domain/`.
4. **Offline JWT policy** for Supabase Auth: how long can a player keep scoring after losing reception? What happens on token expiry mid-set?

## First feature

Reviewer R2's recommendation, accepted: ship **offline-only 8m-Ticker** as the first feature. No cloud, no sync, only drift + Riverpod. Derisks the boring slice and decouples sync complexity from the MVP start.

## Consequences

- Two layering depths in the same repo (intentional). Match feature is hexagonal; Training is pragmatic. See ADR-0002 for the bounded-context map.
- The pure-Dart `kubb_domain` package establishes the rule engine as a Flutter-free island. Tested with `dart test` (fast) and `glados` for property-based coverage.
- Code generation is part of normal dev flow: `dart run build_runner watch -d` while editing freezed/riverpod annotations.
- Supabase is a real external dependency; an account is owned by the project owner. Free tier is sufficient until real-world usage.
- Exit cost from Supabase is `pg_dump` + a new adapter behind the existing port (`TournamentRemote`).
