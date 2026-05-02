# kubb_domain — pure-Dart domain model

No Flutter imports. Imports are restricted to `meta`, `collection`, `uuid`. The public surface is the barrel export in `lib/kubb_domain.dart`.

## Why a separate package

- The rule engine for Kubb is non-trivial (helicopter-throw tolerance, advance-line on uncleared field kubbs, opening variants 6-6-6 / 4-6-6 / 3-6-6 / 2-4-6 with different player-distribution constraints, tie-break with KO sub-rules, etc.). Keeping it Flutter-free means it can be tested with `dart test` in seconds, and reused later by tooling outside the app (e.g. CLI tournament validator, server-side rule checker).
- Hexagonal boundary for the Match bounded context (see `docs/adr/0002-bounded-contexts.md`). Adapters live in the parent app; this package only defines the shape.

## Layout

```
lib/
├── kubb_domain.dart          barrel
└── src/
    ├── values/               typed ids, lamport timestamps
    ├── rules/                RuleSet, OpeningRule, ThrowValidation
    ├── match/                MatchEvent (sealed), MatchState (sealed)
    ├── tournament/           bracket / pool generation (planned)
    └── ports/                MatchEventRepository, TournamentRemote
```

## Run

```bash
dart pub get
dart analyze
dart test
```
