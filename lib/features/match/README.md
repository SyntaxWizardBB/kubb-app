# match — bounded context

**Layering**: full hexagonal (per ADR-0002).

This is the rich-domain feature: rule validation, scoring event log, multi-device sync, dispute resolution.

```
match/
├── application/    Riverpod controllers exposing AsyncValue<MatchState>
├── data/           Adapters: DriftMatchEventRepository, SupabaseMatchEventAdapter
└── presentation/   Scorer keypad, live state view
```

Domain types (`MatchEvent`, `MatchState`, `RuleSet`, ports) live in `packages/kubb_domain/`. This feature provides the concrete adapters + Flutter UI on top of them.

Sync model: append-only events, UUIDv7 ids, Lamport ordering. Conflicts are domain operations (`DisputeRaised`, `OrganizerOverride`), never silent overwrites.
