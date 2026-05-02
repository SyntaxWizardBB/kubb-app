# tournament — bounded context

**Layering**: hexagonal-light (per ADR-0002).

Bracket and pool generation are pure functions in `packages/kubb_domain/src/tournament/`. Persistence and orchestration are pragmatic — drift directly, no per-entity repository interfaces.

```
tournament/
├── application/    Riverpod providers, calls into kubb_domain
├── data/           Drift tables (Tournaments, Pools, Brackets, MatchPlans)
└── presentation/   Tournament setup, bracket viewer, match plan
```

Cloud writes go through the same `TournamentRemote` port the Match context uses.
