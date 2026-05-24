# ADR-0013: Solo-Match uses Supabase as the domain authority — server-shaped architecture

- **Status**: Accepted
- **Date**: 2026-05-24
- **Amends**: ADR-0002 (the `match/` row of the bounded-contexts table)
- **Related**: ADR-0012 (social graph + consensus-based Match)

## Context

ADR-0002 mapped `match/` to **full hexagonal**: a pure-Dart domain in `packages/kubb_domain/match/` (sealed `MatchEvent`, `Match` aggregate, `RuleEngine`), Ports in `packages/kubb_domain/ports/`, drift + Supabase adapters in `lib/features/match/data/`, Riverpod controllers in `application/`, scorer UI in `presentation/`. That picture fits a per-throw live-scoring engine with multi-device sync, Lamport ordering, and `DisputeRaised` events as a domain primitive.

The Match feature that actually shipped on `feature/auth-oauth-keypair` (per ADR-0012, Phase 2) is a different beast. It is a **result-consensus protocol**, not a per-throw engine. The rules — round reconciliation, vote tallying, status transitions, audit trail — live on the server, expressed as `SECURITY DEFINER` Postgres functions across five `20260507*_match_*.sql` migrations (~1500 LOC of SQL, with `_match_try_reconcile` as the single reconciliation point). The Flutter side does not encode any match rules; it shows a list, a lobby, a result form, and posts to the RPCs.

Concretely, the code in `lib/features/match/` looks like this:

- `data/match_models.dart` defines wire-shaped value types: `MatchStatus`, `MatchFormat`, `MatchScoring`, `MatchInvitationStatus`, `MatchRole`, `MatchSummary`, `MatchDetail`, `MatchResultProposal`, `MatchAuditEvent`. Every type has a `fromRow(Map<String, dynamic>)` constructor that parses one row of the corresponding RPC response.
- `data/match_repository.dart` is a thin wrapper over six RPCs: `match_create`, `match_list_for_caller`, `match_get`, `match_respond_to_invite`, `match_finish_play`, `match_propose_result`, `match_cancel`.
- `packages/kubb_domain/` has nothing under `match/`. The directory was reserved in ADR-0002 and is still empty.

This is a legitimate design choice for the current Match scope. The drift between ADR-0002 and reality is what this ADR fixes.

## Decision

For Solo-Match (the Match feature shipped via ADR-0012), Supabase is the **domain authority**. The Flutter client is a thin viewport over the RPC API.

Concretely:

- All match rules — round reconciliation, vote tallying, lifecycle transitions, audit-trail emission — live in `supabase/migrations/20260507000004_match_rpcs.sql` and its successor migrations.
- `lib/features/match/data/match_models.dart` mirrors the wire shapes returned by the RPCs. The types exist to give the Flutter side typed access to JSON payloads, not to encode rules.
- `packages/kubb_domain/match/` stays reserved, but is **not** populated for Solo-Match. It is held back for the tournament-live-scoring slice (M3+ in the roadmap), where per-throw events, Lamport ordering, and dispute resolution as a domain primitive make sense.

The Flutter side keeps the standard feature layout (`data/`, `application/`, `presentation/`) but the layering depth signals "thin client" rather than "hexagonal".

## Alternatives considered

### Full hexagonal as written in ADR-0002

Build a `MatchAggregate` in `packages/kubb_domain/match/` that models rounds, proposals, reconciliation outcomes, and exposes a `MatchRepository` port. Adapters call into Supabase RPCs and mirror state back into the aggregate.

Rejected because it duplicates logic. The reconciliation rules live in `_match_try_reconcile` as Postgres logic — that is where the row locks are, that is where the round bump happens, that is what the audit trail observes. Re-encoding the same state machine in Dart would mean keeping two implementations in sync; every rule change becomes a two-place edit. The Flutter side cannot apply proposals locally anyway (the server is the only place that can compare across participants), so the Dart aggregate would only ever observe state, never compute it.

### Realtime per-throw engine

The path ADR-0002 described, with `MatchEvent` streams, Lamport clocks, dispute events. Out of scope for Solo-Match — the consensus protocol per ADR-0012 explicitly traded per-throw realtime for a round-by-round vote, precisely so we do not need a websocket channel for v1. This path remains the plan for tournament live-scoring (M3+), which is why the `packages/kubb_domain/match/` slot stays reserved.

## Consequences

- `lib/features/match/` carries its own data models (`MatchSummary`, `MatchDetail`, `MatchResultProposal`, etc.). No domain-package dependency for this feature.
- Tests for Match are integration-style: they exercise the RPC contract via a Supabase test client and assert on the wire shapes. Property tests on a Dart rule engine do not apply — the rule engine is the SQL.
- Server-side reconciliation is the single source of truth. Any rule change ships as a new migration. The Flutter side gets the new behaviour for free once the migration is deployed.
- ADR-0002 is amended: the `match/` row of the bounded-contexts table now reads **server-shaped (Supabase RPCs as domain authority)** for the Solo-Match scope. The "full hexagonal" plan stays on file for tournament live-scoring (M3+).
- `packages/kubb_domain/match/` remains empty. When the tournament slice picks it up, this ADR is the marker that explains why it was untouched for the Solo-Match milestone.
