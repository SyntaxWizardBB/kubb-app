# Feature note: Live-scoring granularity (RESOLVED)

**Status**: Resolved 2026-05-02. Owner confirmed: **Tournament play uses per-match-result events only**. Per-throw events are reserved for training mode.

Captured 2026-05-02 during the Lamport-clock ADR discussion. There was a contradiction between the project memory and an owner clarification that needed resolution before M3 (Live-Scoring) was planned.

## Resolution

The per-match-result model is canonical for tournaments. Implications:

- `MatchEvent` variants `ThrowRecorded` and `KubbsThrownIn` move to the training context (or get duplicated there with a different name) — they are not part of the tournament-sync path.
- M3 (Live-Scoring) scope shrinks to: `MatchStarted` → `MatchResultProposed` (per team) → `MatchResultConfirmed` or dispute flow → `MatchFinished`.
- The score-disagreement state machine (ADR-0007) is built on this simpler event vocabulary.
- The "live spectator view" feature, if it ever exists, shows the current proposed state and the dispute status — not throw-by-throw progression.
- CLAUDE.md "Live scoring" description has been updated.

## Refactor task (M3 boundary)

Before M3 implementation starts:

- Audit `MatchEvent` sealed hierarchy. Remove or relocate `ThrowRecorded` and `KubbsThrownIn` from the tournament path.
- Existing tests in `packages/kubb_domain/test/` may reference these — adjust accordingly.
- Add the new tournament-result events: `MatchResultProposed`, `MatchResultConfirmed`, `MatchDisputed`. Keep `OrganizerOverride` and `MatchFinished`.

This is a small, targeted refactor — not a rewrite. The hexagonal layering and the Lamport invariants are unaffected.

---

## Original note (for context)



## The contradiction

### What CLAUDE.md says

> **Live scoring**: during a match, the two competing teams record points themselves on phone. Organizer screen and any scoreboard reflect live state. Offline-resilient.

This was interpreted (by the architecture and the existing `MatchEvent` variants) as **per-throw events**: every individual baton throw is an event (`ThrowRecorded`, `KubbsThrownIn`, etc.).

### What Lukas said on 2026-05-02

> "es muss nur ein Feld sein indem man das endresultat eintragen kann"
> "ja das macht lokal sinn aber wird eh nur immer ende match eingetragen, das pro wurf eintragen machen wir nur wenn wir trainieren"

This implies **per-match-result events only** for tournament play: at match end, each team types in the final result (e.g., 2:1), and that single result is the event that syncs. Per-throw scoring is reserved for **training mode** (8m-Ticker, Finisseur, 4m-Linie).

## Why this matters

The two models lead to substantially different architectures:

| Aspect | Per-throw model (current code) | Per-match-result model (owner clarification) |
|---|---|---|
| Events per match | dozens to hundreds | 2-5 (Started, Result-A, Result-B, optional Dispute, Finished) |
| Sync volume | high — every tap goes over the wire | trivial — couple of writes per match |
| Live spectator view | sees throw-by-throw progression | sees only final result |
| Rule engine role | reconstructs state from throws | not invoked during tournament play; only training |
| Conflict surface | per-throw disagreements possible | only result-disagreements |
| Existing `MatchEvent` variants (`ThrowRecorded`, `KubbsThrownIn`) | central to tournament play | only used in training |
| `RuleSet.swiss()` rule engine | drives validation during the match | only validates training inputs and computes match-result schemas |

## What this does not change

- Lamport clock invariants (ADR-0006) work for both models.
- `DisputeRaised` and `OrganizerOverride` make sense in both.
- Training mode (8m-Ticker etc.) is per-throw regardless.

## What this does change (if owner confirms per-match-result)

- The existing `MatchEvent` sealed hierarchy needs review. `ThrowRecorded` and `KubbsThrownIn` may move out of `match/` into `training/` or get removed from the tournament-sync path.
- M3 (Live-Scoring) becomes much smaller in scope — essentially "team enters result, server syncs, organizer sees it".
- The "spectator live view" concept (watching a match score evolve in real time) is no longer applicable to tournament matches.
- The CLAUDE.md "Live scoring" description needs rewriting.
- The first-feature-to-ship decision (8m-Ticker, offline-only) stands either way.

## Action

Resolve before planning M2 or M3. Options for resolution:

- **Confirm per-match-result for tournament play** (matches owner's recent statement). Update CLAUDE.md, prune unused MatchEvent variants from the tournament path, simplify M3 scope.
- **Hybrid**: per-match-result is the default, but per-throw is opt-in for tournaments that want a live scoreboard show. More complexity, more flexibility.
- **Stick with per-throw**: revisit owner's statement, perhaps the recent comment was about UX (only result-entry button visible) rather than the underlying model.

Recommend: confirm with owner explicitly before M2 planning. If per-match-result wins, schedule a small refactor before M3 starts.
