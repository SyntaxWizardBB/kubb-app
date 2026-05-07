# ADR-0012: Social graph (friends + groups) and consensus-based match scoring

- **Status**: Accepted (Phase 1: friends + groups). Match-mode (Phase 2) accepted in design but implementation deferred to a follow-up session.
- **Date**: 2026-05-07
- **Builds on**: ADR-0010 (auth model — OAuth + anonymous keypair, both with unique nicknames), ADR-0011 (BIP-39 mnemonic + in-app inbox).

## Context

The auth feature (ADR-0010/0011) gave each user a stable identity with a unique nickname, but no way to connect with anyone. The owner now wants:

1. A social graph so players can find each other across devices and form recurring groups.
2. A new "Match" training mode where multiple players can score a Kubb match together, scaling up to 6 vs. 6.
3. The match-engine to later become the foundation of a full Tournament feature.

## Decision

### Identity model — both auth paths participate equally

Both OAuth-based and BIP-39-keypair accounts are first-class citizens in the social graph. A friend search hits any account by its `user_profiles.nickname` (already `citext UNIQUE`), regardless of how the account was created. The user does not see whether a friend is OAuth or anonymous.

### Friendships (Phase 1)

Symmetric, opt-in, single confirmation.

- **Table**: `friendships(low_user_id, high_user_id, status, requested_by, requested_at, accepted_at)`. Pair stored canonically (`low < high`) so the relation is unique regardless of who sent the request. `status ∈ {pending, accepted, rejected, blocked}`.
- **Send**: `friend_request_send(target_user_id)` — service definer. Inserts a `pending` row, drops a `verification_request` inbox message to the target.
- **Respond**: `friend_request_accept(other_user_id)` / `friend_request_reject(other_user_id)`. Accept flips the row to `accepted`, sets `accepted_at`, drops a notice into both inboxes. Reject deletes the row (no record of having said no — keeps re-requesting clean).
- **Search**: `friend_search_by_username(p_query)` returns up to 20 nickname-prefix matches with the calling user's relationship state (`none`, `pending_outgoing`, `pending_incoming`, `accepted`). Excludes the caller themselves and any `blocked` rows.
- **Remove**: `friend_remove(other_user_id)` — drops the row, no notification.
- **QR-pairing**: deferred to a follow-up. The schema supports it without changes (the QR code carries `user_id`; the same `friend_request_send` RPC is the receiver). UI lands later.

### Groups (Phase 1)

Server-side, owned by one user, multiple members.

- **Tables**: `groups(id, owner_user_id, name, created_at)`, `group_members(group_id, user_id, role, joined_at)`. `role ∈ {owner, member}`. RLS scopes reads to `auth.uid() in (members)`; writes scope to the owner.
- **Lifecycle RPCs**: `group_create(p_name)`, `group_rename(p_group_id, p_name)`, `group_delete(p_group_id)`.
- **Membership RPCs**: `group_invite_member(p_group_id, p_user_id)` (auto-joins; with the friend-graph in place this is "add a friend to my group", not a separate consent step), `group_remove_member(p_group_id, p_user_id)`. The owner can leave only by deleting the group; members can leave themselves.
- **Listing**: `group_list_for_user()` returns the calling user's groups (owned + joined), each with a member count for the list view. `group_members_for(p_group_id)` returns the full member list.

### Match mode (Phase 2 — designed, deferred implementation)

Match is the **third training mode** alongside Sniper and Finisseur, surfaced as a card in the existing training sheet.

#### Configuration (single screen)

- **Teams**: 1–6 players per side. Sides A and B are equal — no host / guest asymmetry.
- **Format**:
  - **Best-of-N sets** (N ∈ {1, 3, 5}). Default 3.
  - **Scoring**: `wins` (count set wins, first to ⌈N/2⌉) or `points` (cumulative kubb count across all sets).
- **Field**: standard 5+1 (5 field kubbs + king) for v1. Custom field setup mirrors Finisseur and lands in Phase 2.5.

#### Result-consensus protocol

This is what makes Match different from solo training. After play, every participant proposes their version of the result; the server reconciles.

- **Lifecycle**: `pending_invites → active → awaiting_results → finalized | voided`.
- **Result rounds**: up to 3.
- For each round:
  - Every participant submits a proposal: `(winner_team_id, score_a, score_b)` (winner_team_id implied for `wins` mode, explicit for `points` mode in case of a draw call).
  - The RPC `match_propose_result(p_match_id, p_winner_team_id, p_score_a, p_score_b)` upserts the proposal under `(match_id, round, user_id)`.
  - Once all participants have submitted in the current round, a SECURITY DEFINER function compares them:
    - **All match** → finalize. Match becomes immutable.
    - **Disagreement** → start round N+1 (drop new inbox messages, "Resultat neu eintragen — Round {N}/3"). Reset the round-N proposals are kept for audit.
- **Round 3 disagreement** → `voided`. No stats credited. Inbox notice to all participants.

#### Schema sketch (for Phase 2)

```
matches(id, mode, settings_jsonb, status, started_at, completed_at, voided_at)
match_teams(match_id, team_id, name)              -- team_id: 'A' | 'B'
match_participants(match_id, user_id, team_id, invitation_status, joined_at)
match_result_proposals(match_id, round, user_id, winner_team_id, score_a, score_b, proposed_at)
match_audit_events(match_id, kind, payload_jsonb, at)  -- finalize, void, round-bumped, etc.
```

The match-engine emits a neutral `MatchResult { teamA, teamB, winnerTeamId?, scoreA, scoreB, durationSec, finishedAt }` value object on finalize. Tournament (future) consumes this without knowing the internals.

### Hub-modal integration

The "Freunde" and "Gruppen" rows in [PlayerHubSheet](../../lib/features/player/presentation/player_hub_sheet.dart) become live entries (no more "bald"-pill) and route to the new screens. Match does not appear in the hub — it is reached through the Training sheet.

## Data model deltas

| Table | Phase | Notes |
|---|---|---|
| `friendships` | 1 | New. Canonical `(low, high)` pair |
| `groups` | 1 | New |
| `group_members` | 1 | New |
| `matches` | 2 | New |
| `match_teams` | 2 | New |
| `match_participants` | 2 | New |
| `match_result_proposals` | 2 | New |
| `match_audit_events` | 2 | New |

All Phase-1 RPCs are SECURITY DEFINER, called from authenticated sessions, scoped to `auth.uid()` for the caller's identity. No service-role secrets on the device.

## Alternatives considered

- **Friends as a separate concept from "favourites"** — rejected: a single friendship table covers both with less surface area.
- **Group membership = "follow"** (asymmetric, no consent) — rejected: the Match-invite flow needs to know that adding someone to a group implies they consent to being match-invited under that group.
- **Match score sheet on a single device, no consensus** — rejected by the owner: the consensus protocol is the explicit anti-cheat mechanism. The cost (3-round reconciliation) is bounded.
- **Realtime live-match mode** (websocket per-throw sync) — out of scope. The consensus protocol gives us multi-device matches without a realtime channel.

## Consequences

- One more inbox kind in active use — `verification_request` for friend / group / match invites and result-prompt rounds. The inbox is now load-bearing.
- The friend graph touches every piece of social UX from here on. Username uniqueness becomes a hard contract (already enforced via `user_profiles.nickname` UNIQUE — the constraint moves from "nice to have" to "must never be relaxed").
- Match's result-consensus needs a server-side comparator that is bulletproof. Phase-2 implementation will include unit tests for the comparator and an end-to-end scenario test (3 players, round-1 disagreement, round-2 consensus).
- A bad actor could try to grief by always disagreeing in Round 3. Mitigation: the match is voided, no stats are credited, and the inbox audit trail makes it visible to all participants. A repeat-offender block list can be added later if abuse becomes a real pattern; deferred until we see it.
