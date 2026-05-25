# tournament — bounded context

**Layering**: hexagonal-light per [ADR-0002](../../../docs/adr/0002-bounded-contexts.md). Per [ADR-0014](../../../docs/adr/0014-tournament-match-coexistence.md) the tournament path is server-shaped: lifecycle, registration, match plan and score consensus live in Postgres RPCs under `supabase/migrations/`, the Dart side only wraps them.

Pure rules (bracket generation, pool generation, pairing, tiebreaker, EKC-Score, league points) live in `packages/kubb_domain/lib/src/tournament/`. Flutter-side state lives here under `lib/features/tournament/`.

```
tournament/
├── application/    Riverpod providers (M1-T9 onwards)
├── data/           Wire models + TournamentRemote adapter (this task)
└── presentation/   Setup wizard, list/detail, score entry (M1-T9..T15)
```

No event-log. Cloud writes go through the `TournamentRemote` port (`packages/kubb_domain/lib/src/ports/tournament_remote.dart`), implemented by `data/tournament_repository.dart` against Supabase RPCs `tournament_*`. Offline score draft / outbox land in M4 alongside realtime.
