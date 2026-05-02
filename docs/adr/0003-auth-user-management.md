# ADR-0003: Authentication & user management

- **Status**: Accepted
- **Date**: 2026-05-02
- **Depends on**: ADR-0001 (Supabase chosen as cloud backend)
- **Related**: ADR-0002 (bounded contexts — adds a `tournament` lifecycle component)

## Context

After ADR-0001 was accepted, the Phase 1 scope expanded. The owner clarified that the app needs full user management beyond what was originally captured:

- Each user has a profile (account-based, not anonymous).
- Tournament publication is a deliberate organizer action ("live schalten").
- Players register for a tournament with their account ("Anmeldung am Turnier").
- The organizer reviews each registration ("freischaltet") and confirms physical presence on-site before the player enters the bracket.

This makes registration + approval + check-in core MVP scope, not Phase 2.

## Roles

| Role | Auth state | Purpose | Gets into the bracket via |
|---|---|---|---|
| **Organizer** | authenticated | creates and runs tournaments | n/a (organizes; can also self-register if they play) |
| **Player (registered)** | authenticated, has a profile | regular participant | own application → organizer approval → on-site check-in |
| **Player (walk-in)** | no account | shows up on tournament day without prior registration | organizer adds them as a walk-in record → instant check-in |
| **Spectator** | anonymous | watches live tournaments | n/a (read-only) |

## Tournament lifecycle

```
draft ─publish→ published
                  ├─open-registration→ registration_open
                  │                          ├─close-registration→ registration_closed
                  │                          └─cancel→ cancelled
                  ├─cancel→ cancelled
                  │
registration_closed ─checkin-done→ live ─complete→ completed
```

State transitions are organizer-only. Each state controls what is readable / writable by which role (enforced at the database via Supabase RLS, not just the client).

## Flows

### Registration & approval

1. Organizer creates tournament (state `draft`), fills metadata.
2. Organizer publishes (`draft → published`). Spectators can now see the listing.
3. Organizer opens registration (`published → registration_open`). Authenticated players can apply.
4. Player submits an application (`tournament_applications` row, status `pending`).
5. Organizer reviews each application: `pending → approved | rejected`. Optional message back to the player.
6. On tournament day: organizer runs check-in. Each approved application gets a `checked_in_at` timestamp. Only applications with `checked_in_at IS NOT NULL` are eligible for the bracket.
7. Organizer closes registration; bracket is generated from the checked-in set.
8. Tournament transitions to `live`; live-scoring proceeds per ADR-0001 (event log, sync, etc.).

### Walk-ins

A player can show up without having registered. Organizer adds a `tournament_applications` row with `applicant_id = NULL` and `walk_in_name = "<name>"`, status `approved`, `checked_in_at = now()`. Walk-ins skip the apply/approve roundtrip but still show up in the same applications table — same downstream code path. Walk-ins do not score on their own device; a co-player or the organizer scores for them.

### Auth

Supabase Auth, **email + magic link only** (no passwords). Lower friction, no breach surface, simpler to operate. The trade-off is email-deliverability dependence (see Open questions).

## Data model (sketch)

Drift mirrors the Postgres schema. Authoritative is Supabase.

| Table | Key columns | Notes |
|---|---|---|
| `auth.users` | `id` (uuid), `email`, … | Supabase-managed |
| `user_profiles` | `user_id` PK/FK, `nickname`, `home_club`, `bio`, `created_at` | one row per user |
| `tournaments` | `id` (uuid), `organizer_id` FK, `name`, `state` (enum), `visibility`, `event_date`, `location`, `opening_rule_code`, `max_teams`, `created_at` | state machine above |
| `tournament_applications` | `id` (uuid), `tournament_id` FK, `applicant_id` FK NULL, `walk_in_name` text NULL, `status` (pending/approved/rejected), `applied_at`, `decided_at`, `decided_by` FK, `checked_in_at` NULL | exactly one of `applicant_id` / `walk_in_name` is non-null |
| `teams` | `id` (uuid), `name`, `created_at` | reusable across tournaments |
| `team_members` | `team_id` FK, `user_id` FK, `role` | join |
| `tournament_teams` | `tournament_id` FK, `team_id` FK, `seed`, `bracket_position` | only filled after check-in / bracket gen |
| `match_events` | per ADR-0001 | append-only event log; FKs to tournament + applications |

## RLS policy summary

| Table | Anon read | Auth read | Insert | Update |
|---|---|---|---|---|
| `tournaments` | where `state ∈ {published, live, completed}` and `visibility = public` | same as anon, plus full read by organizer | authenticated users (sets `organizer_id = auth.uid()`) | only by `organizer_id = auth.uid()` |
| `tournament_applications` | none | own applications (`applicant_id = auth.uid()`) + organizer of tournament | authenticated, where `tournament.state = registration_open` and `applicant_id = auth.uid()` | only organizer (status, decided_at, decided_by, checked_in_at) |
| `match_events` | where tournament is live/completed and visibility = public | same | only by a player who's checked-in to the tournament and is in one of the two teams of the match (or by the organizer) | append-only |
| `user_profiles` | basic columns (nickname) | full row by owner | on user creation | by owner |

Security-checker agent (per `.claude/`) treats "RLS policies present, tested, denial-tested" as a Quality Gate.

## Client integration

- `AuthController` (Riverpod) exposes the Supabase auth state as an `AsyncValue<AuthSession>`.
- Routes via `go_router`:
  - public: tournament listing, tournament viewer (live scoreboard), sign-in
  - auth-required: profile, my applications, my matches
  - organizer-only: tournament create/edit, application review, check-in flow, override events
- Magic-link callback URL handled by deep-link in mobile, normal route on web/desktop.

## Open questions deferred to implementation

1. **Magic-link deliverability**: Supabase free tier has a low rate limit (a few mails per hour). For a 32-team tournament where many people register near a deadline, that breaks. When traffic justifies, plug in a real SMTP (SendGrid / Postmark / AWS SES free tiers).
2. **Eligibility for ranked tournaments**: CH rules require teams to have ≥3 players with ≥2 CH-resident or Swiss. We don't model nationality/residency yet. Defer to ADR-0004 when ranked tournaments come into scope.
3. **Application audit-trail**: who approved/rejected and when is captured in `tournament_applications`. Anything more (history of state transitions) is YAGNI for v1; we can add a `tournament_application_events` log later if disputes arise.
4. **2FA / step-up auth for organizer**: not v1. Magic-link is the auth surface; if abuse or misuse becomes real, revisit.

## Consequences

- Phase 1 scope grows by ~2-3 weeks: registration UI, application list, approval flow, check-in flow. The 8m-Ticker remains "first feature to ship" because it's offline-only and decoupled from auth.
- The `tournament` bounded context (ADR-0002 — hexagonal-light) gets a non-trivial lifecycle and state machine. The pure-Dart `kubb_domain` package gains a `TournamentState` sealed union and lifecycle transition functions.
- Supabase RLS is the security perimeter. The security-checker agent must verify policies for every new table.
- The first user-facing screen is sign-in / sign-up. Onboarding flow precedes everything else in the UI.
- Organizer surface (laptop / web) is now a meaningful chunk of the app, not a side concern.

## Implementation order (suggested)

When the team picks this up:

1. Supabase project setup (Frankfurt region), tables, RLS policies — local docker for dev.
2. Auth flow (sign-in, magic-link, profile creation) — gates everything else.
3. Tournament list + create + publish.
4. Application apply + review + approve.
5. Check-in flow.
6. Bracket generation from checked-in applications.

Each step is a candidate for one `/feature` workflow run.
