# ADR-0002: Bounded contexts and per-context architecture

- **Status**: Accepted
- **Date**: 2026-05-02
- **Depends on**: ADR-0001 (Tactical DDD)

## Context

ADR-0001 picked a Tactical DDD approach: hexagonal layering where the domain is rich, pragmatic patterns where it is CRUD-shaped. To make that concrete, this ADR maps the application into bounded contexts and assigns an architectural style to each.

## Bounded contexts

### 1. Match (HIGH complexity → full hexagonal)

The single live game between two teams. Owns: rule validation, throw/round bookkeeping, score event log, multi-device sync, dispute resolution, king-fall semantics, advance-line logic, opening-rule variants.

- **Domain** lives in `packages/kubb_domain/lib/src/match/` (pure Dart). Sealed `MatchEvent` types, `Match` aggregate, `RuleEngine` validation.
- **Ports** in `packages/kubb_domain/lib/src/ports/`: `MatchEventRepository`, `TournamentRemote`.
- **Adapters** in `lib/features/match/data/`: `DriftMatchEventRepository`, `SupabaseMatchEventAdapter`.
- **Application layer** in `lib/features/match/application/`: Riverpod controllers expose `AsyncValue<MatchState>` to the UI; transitions are explicit (`recordThrow`, `raiseDispute`, `applyOverride`).
- **UI** in `lib/features/match/presentation/`: scorer keypad, live state view.

Sync model: append-only events. UUIDv7 IDs (lex-sortable). Lamport clock per device. Conflict resolution is a domain operation (the `DisputeRaised` event), not a sync hack.

### 2. Tournament (MEDIUM complexity → hexagonal-light)

The structure around matches: registration, pool generation, KO bracket, match plan, results.

- Bracket generation is a **pure function** in `packages/kubb_domain/lib/src/tournament/`.
- Persistence and orchestration are pragmatic: `lib/features/tournament/data/` uses drift directly (no per-entity repository interface).
- The cloud side reuses the `TournamentRemote` port from the Match context (same Supabase project).

### 3. Training (LOW complexity → pragmatic)

Solo-user training modes: 8m-Ticker, Finisseur, 4m-Linie. Local-only by default; offline-first.

- No domain package needed. `lib/features/training/data/` is drift tables for `TrainingSession` and `TrainingThrow`.
- Riverpod providers go directly to drift. No event log, no ports, no adapters.
- 1-tap UI is the architectural goal; everything else serves that.

### 4. Player / Team (LOW complexity → pragmatic CRUD)

Identity and grouping. Mostly CRUD.

- `lib/features/player/`, `lib/features/team/`: drift tables, Riverpod providers, simple list/detail UI.
- Cloud sync is a thin write-through (one direction: organizer pushes; players read). Uses the same `TournamentRemote` port.

## Per-context summary

| Context | Domain package | Ports | Adapters | Bloc-style state machine | Riverpod-direct |
|---|---|---|---|---|---|
| Match | yes (`packages/kubb_domain`) | yes | yes | yes (sealed `MatchState`) | no |
| Tournament | yes (shared package) | partial | shared | no | yes |
| Training | no | no | no | no | yes |
| Player/Team | no | no | no | no | yes |

## Folder layout

```
kubb_app/
├── packages/
│   └── kubb_domain/                    # pure Dart, no Flutter imports
│       ├── lib/
│       │   ├── kubb_domain.dart        # barrel export
│       │   └── src/
│       │       ├── rules/              # RuleSet, OpeningRule, ThrowValidation
│       │       ├── match/              # Match, MatchEvent, MatchState, RuleEngine
│       │       ├── tournament/         # Bracket, Pool generation
│       │       ├── ports/              # MatchEventRepository, TournamentRemote
│       │       └── values/             # PlayerRef, TeamRef, MatchId, etc.
│       ├── test/
│       └── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart
│   │   ├── router.dart
│   │   └── theme.dart
│   ├── core/
│   │   ├── data/                       # drift database, supabase client
│   │   └── ui/                         # shared widgets, theme tokens
│   ├── features/
│   │   ├── match/
│   │   │   ├── application/            # Riverpod controllers (sealed states)
│   │   │   ├── data/                   # adapters: drift + supabase
│   │   │   └── presentation/           # screens, widgets
│   │   ├── tournament/
│   │   │   ├── application/
│   │   │   ├── data/
│   │   │   └── presentation/
│   │   ├── training/
│   │   │   ├── application/
│   │   │   ├── data/
│   │   │   └── presentation/
│   │   └── player/
│   │       ├── application/
│   │       ├── data/
│   │       └── presentation/
│   └── l10n/
│       └── app_de.arb
└── test/
    ├── unit/
    ├── widget/
    └── integration/
```

## Consequences

- A reader sees layering depth as a hint about complexity. `features/match/` having `application/data/presentation/` plus a domain dependency signals "this is the hard part". `features/training/` being thin signals "do not over-engineer here".
- The `kubb_domain` package can be imported by future tooling (CLI tournament validator, server-side rule checker) without dragging Flutter along.
- Cross-context references go through value objects (`PlayerRef`, `TeamRef`) — no direct DB joins between contexts.
- When in doubt about which style to use for a new feature: default to pragmatic. Move toward hexagonal only when the domain proves rich enough to justify the structure.

> Amended 2026-05-24 by ADR-0013: the `match/` row above describes the future tournament live-scoring slice. Solo-Match (per ADR-0012) is server-shaped — see ADR-0013.
