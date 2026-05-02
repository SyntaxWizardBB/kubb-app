# ADR-0006: Lamport clock invariants for match event ordering

- **Status**: Accepted
- **Date**: 2026-05-02
- **Depends on**: ADR-0001 (event log + Lamport ordering), ADR-0002 (Bounded Contexts), ADR-0005 (Per-platform persistence)

## Context

The implementation in `packages/kubb_domain/lib/src/values/lamport_clock.dart` works and has four passing tests. But the protocol invariants — what the clock guarantees, what it does not, when it is advanced, and how late events are handled — are not written down anywhere. Without that, sync code (M3+) becomes guesswork, and edge cases (app restart, late offline submission, post-finish events) get re-decided every time someone touches them.

This ADR fixes the rules. It does not decide the score-disagreement state machine (that is ADR-0007), nor does it decide whether match events are per-throw or per-result (open question — see "Followups").

## Decision

### Counter scope: per match

The Lamport counter resets to 0 at the start of every new match on every device. There is no cross-match counter.

- **Why**: Match replay is a per-match operation. A global counter would grow forever, would need to be filtered by matchId on every read, and would couple unrelated matches in tests.
- **Implication**: At app boot, the active match's clock is restored from `MAX(counter)` of the events for `(matchId, deviceId)` in local drift. New matches start at 0.

### Tick rule (local emission)

`counter += 1` BEFORE emitting an event. The returned `LamportTimestamp` carries `(counter, deviceId)`.

- **Already implemented** in `LamportClock.tick()`.
- **Invariant**: Two consecutive `tick()` calls on the same device produce strictly increasing counters.

### Observe rule (incoming remote event)

`counter = max(local_counter, remote.counter) + 1`.

- **Already implemented** in `LamportClock.observe()`.
- **Invariant**: After observing a remote event with counter R, any subsequently emitted local event has counter > R.
- **When called**: On every inbound remote event from Supabase Realtime AND on every event seen during reconnect-replay.

### Tie-break (equal counters across devices)

Lexicographic compare of `deviceId.value`.

- **Already implemented** in `LamportTimestamp.compareTo`.
- **Invariant**: Stable across all clients — same event set produces the same total order on every device.
- **Not a fairness statement**: Two events with equal counters are not "simultaneous in reality". They are concurrent, and the tie-break gives a deterministic ordering. Real conflicts (e.g., Team A says hit, Team B says miss) are handled via `DisputeRaised`, not via clock ordering.

### Wall-clock timestamp (separate from Lamport counter)

Every `MatchEvent` carries an additional `emittedAtWallClock: DateTime` (UTC).

- **Set by the emitting device at creation time** (Phone or Web), not by the server.
- **Purpose**: UI display only — "16:42 Uhr", "vor 3 Min", event log timeline.
- **NEVER used for ordering or causality**. Ordering is Lamport-only.
- **Tolerance for skew**: We accept that a phone with a wrong system clock will show wrong wall-clock times. We do not try to correct this server-side. Display shows phone-local time.
- **Implementation impact**: The `MatchEvent` base class needs a new field. Touches all variants. Captured as a follow-up task.

### Late submission policy (post-MatchFinished)

After a `MatchFinished` event for a match exists in the canonical store, the server REJECTS subsequent inbound events for that match.

- **Rejected events are logged**, not silently dropped. The organizer sees a "Late submission attempted by [device]" entry for review.
- **The legitimate path for a post-finish revision** is `DisputeRaised` raised before the result is final, then resolved by player agreement or `OrganizerOverride`. After the dispute window closes (defined in ADR-0007), no further changes are accepted.
- **Why**: A finished match feeds the bracket. Allowing nachträgliche revision would cascade into already-played downstream matches and is a UX disaster.

### Server is passive

The server has no Lamport clock of its own.

- **Storage**: append-only events, indexed by `(matchId, counter, deviceId)`.
- **Read**: returns events sorted by `(counter ASC, deviceId ASC)`.
- **Validation on write**:
  - matchId must exist
  - emittedBy device must be authorized for this match
  - reject if a `MatchFinished` event already exists for the matchId (per "Late submission policy" above)
- **No causality enforcement**: server accepts events out of arrival order. Ordering is a read concern.

### Outbox order on phones

The outbox flushes in tick order (oldest first).

- **Why**: tick order is monotonic by construction. Sending in tick order means the server-side index stays roughly append-friendly even under bursty reconnects.
- **Server still does not depend on arrival order** (per above). This is an optimization, not a correctness requirement.

### Determinism guarantee

For a given complete event list of a match, the reconstructed `MatchState` is deterministic.

- **Test obligation**: replay-twice must produce equal state. This becomes a contract test for the rule engine.
- **Property test candidate** (via `glados`): generate random event sequences, replay in shuffled order with stable Lamport ordering, assert equal end state.

## Alternatives considered

### Alt 1: Vector clock instead of Lamport

- **Pro**: Concurrent events are explicitly identifiable, not collapsed into a deterministic-but-arbitrary total order.
- **Contra**: O(N devices) per event. Vector grows over the app's lifetime if devices ever change. Higher implementation cost.
- **Why rejected**: Real concurrency conflicts are surfaced via `DisputeRaised` + `OrganizerOverride`, not via clock semantics. Lamport's total order with deterministic tie-break is enough for our domain.

### Alt 2: Server timestamp as truth

- **Pro**: One source of ordering, no client state to manage.
- **Contra**: Breaks offline-first. A phone offline for 30 minutes would lose causal ordering of its own events — they would all collapse to "now" on arrival.
- **Why rejected**: Violates the offline-resilient live-scoring requirement (Phase 1 MUST).

### Alt 3: Counter global per device (not per match)

- **Pro**: One counter to manage, simpler bootstrap (only one MAX-query at startup).
- **Contra**: Counter grows over the app lifetime. Cross-match replay needs filtering by matchId anyway. Per-match scope is just as easy with proper indexing.
- **Why rejected**: per-match scope is cleaner with no real cost.

## Consequences

### Positive

- Sync code (M3+) can be written against firm rules. No "what exactly does observe do under condition X" debates.
- Replay tests have a clear contract: same events in → same state out.
- Wall-clock display is decoupled from ordering — phones with skewed clocks cannot break event order.
- Late-submission policy gives the organizer a clear answer to "can this be changed?" — yes during dispute window, no after.

### Negative

- `LamportClock` needs persistence at app boot. Implementation task: load `MAX(counter)` for the active match from drift, hydrate the clock. Tracked as a follow-up.
- `MatchEvent` base class needs `emittedAtWallClock: DateTime`. Touches all variants and the drift/Supabase schemas.
- Players who go offline for hours after a match has finished can lose their late-submitted events. Mitigation: outbox flushes per-event (not batched), keeping the loss window small. The dispute window in ADR-0007 will cover the legitimate revision path.

### Neutral

- The drift `match_events` table needs a `wall_clock_at` column.
- The Supabase `match_events` schema mirrors the same.
- The pure-Dart domain (`packages/kubb_domain/`) absorbs the new field on `MatchEvent`. Keeps the domain unchanged in shape, just enriched.

## Followups

- ADR-0007: Score-disagreement state machine (`Proposed → Confirmed → Disputed → Overridden`). Required before sync code.
- **Open decision (parked, not blocking this ADR)**: Match-event granularity. Per-throw events (current code shape) vs. per-match-result events (implied by recent owner clarification on tournament live-scoring). Both are compatible with this ADR. Resolution lives in a future ADR on live-scoring model.
- **Implementation task (M3 boundary)**: extend `MatchEvent` with `emittedAtWallClock: DateTime`. All variants updated.
- **Implementation task (M3 boundary)**: hydrate `LamportClock` at app boot from persisted events.
- **Implementation task (M3/M4 boundary)**: server-side validation rejecting events for matches with existing `MatchFinished`.
- **Test task (M3 boundary)**: property test on replay determinism via `glados`.
