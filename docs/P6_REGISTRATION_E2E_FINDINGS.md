# P6 Tournament Registration — Live-DB End-to-End Findings

Date: 2026-06-01
Environment: live local Supabase DB (`supabase_db_kubb-app-local`). All RPCs invoked as real `SECURITY DEFINER` calls with `auth.uid()` set via `request.jwt.claims` (`sub`/`role`), verified before each call. Not Flutter fakes. Each scenario wrapped in a transaction (BEGIN…ROLLBACK) or explicitly cleaned up; all post-run leak checks returned 0 residual rows.

Scenarios covered:
1. Solo happy-path (create → publish → register → list → withdraw)
2. Waitlist + dynamic promotion (solo, max=2)
3. Team registration (team_size=2, max=4 teams, waitlist)
4. Permissions + lifecycle (per-tournament manage authority, club roles, start)

---

## SUMMARY

### WORKS

- **Solo happy-path** — 7/7 PASS. No deviations.
- **Waitlist + dynamic promotion (solo)** — ALL PASS. No deviations.
- **Team registration** — ALL PASS. No deviations.
- **Permissions + lifecycle** — ALL PASS. No deviations.

All four scenarios passed every assertion against the live DB. No scenario failures. No setup failures (team/club/user creation all worked).

### BROKEN

- **None.** No assertion failed in any scenario. See "Observations / latent risks" below for two non-blocking behaviors flagged during testing that are worth a product decision but did NOT fail any test.

---

## Confirmed behavior (the new open-registration model)

- `tournament_create` → status `draft`. Solo uses `team_size=1`; team uses `team_size=2`. Name is auto-suffixed with the year (e.g. "TEAMREG Cup 2026").
- `tournament_publish` → status `registration_open` directly (NOT a separate `published` step). This is the new open-registration model; publish opens registration in one step.
- `tournament_register_single` / `tournament_register_team`:
  - Within capacity → `registration_status = 'confirmed'` immediately (NOT `pending`).
  - Over capacity → `registration_status = 'waitlist'`.
  - Capacity is counted in **participant rows** (one row per team), so `max_participants=4` means 4 teams fill the field, not 4 players. By design per migration comments.
  - Inbox: confirmation (`tournament_registration_confirmed`, "Anmeldung bestätigt") or waitlist (`tournament_waitlisted`, "Auf der Warteliste") messages are sent to **all roster members including the captain** (the earlier `<> v_caller` exclusion from `20261101000003` was dropped in `20261201000040`).
- `tournament_withdraw`:
  - Owner can withdraw → `registration_status = 'withdrawn'`.
  - If the withdrawn participant was `confirmed`, the oldest `waitlist` participant is **auto-promoted to `confirmed`** in the same transaction, emits `tournament_promoted` ("Du bist nachgerückt") inbox + a `waitlist_promoted` audit event.
  - If the withdrawn participant was on the `waitlist`, NO promotion fires (`IF v_prior = 'confirmed'` gate). Verified: promotion count stayed at 1.
- `tournament_list_my_registrations` returns only `pending`/`confirmed`/`waitlist` rows; `withdrawn` is excluded (withdrawn registrations correctly disappear from the list).
- `tournament_caller_can_manage`: per-tournament authority = creator OR active owner/admin/organizer of THAT tournament's `club_id`. NULL `club_id` ⇒ creator only. The global `tournament_caller_is_organizer()` is no longer referenced.
- All lifecycle/update RPCs (`tournament_publish`, `tournament_start`, …) gate on `tournament_caller_can_manage` and raise SQLSTATE `42501` ("tournament not found or not authorised") for unauthorized callers. Tournament status is unchanged on a rejected call.
- `tournament_start` is permitted from `registration_open` → `live`, and can be triggered by a club admin (not only the creator).
- `block_guest_team_registration` trigger blocks a captain whose membership role is `guest`; `admin` captains are unaffected.

---

## Observations / latent risks (NOT test failures, but flag for product/dev decision)

These passed all scenario assertions but surfaced behavior worth deciding on explicitly.

### O1 — Re-registration after withdrawal raises a raw `23505` instead of a friendly domain error

- **Scenario:** Waitlist + promotion (step 7 mechanism, before switching to a fresh user).
- **Symptom:** Calling `tournament_register_single` for a user who previously `withdrew` from the same tournament raises raw SQLSTATE `23505` from the unconditional unique index `tournament_participants_unique_user (tournament_id, user_id)`. The function's friendly "already registered" guard explicitly excludes `withdrawn` status, so it does NOT catch this case.
- **Effect:** A user who withdrew can **never re-register** for the same tournament, and the error surfaced to the client is a raw DB unique-violation rather than a domain message.
- **Likely offending wiring:** Unique index `tournament_participants_unique_user` (full unique on `tournament_id, user_id`, ignores status) combined with the "already registered" guard in `tournament_register_single` that filters out `withdrawn`. The guard and the index disagree about whether `withdrawn` rows count.
- **Fix suggestion (pick one based on intended product behavior):**
  - If re-registration after withdrawal should be **supported**: in `tournament_register_single`/`_team`, detect an existing `withdrawn` row for `(tournament_id, user_id)` and re-activate it (UPDATE back to `confirmed`/`waitlist`) instead of INSERTing; or make the unique index partial (`WHERE registration_status <> 'withdrawn'`) so a fresh INSERT is allowed.
  - If re-registration should stay **blocked**: catch `23505` in the RPC and re-raise a friendly domain message (e.g. "Du hast dich von diesem Turnier abgemeldet und kannst dich nicht erneut anmelden.") so the client never sees the raw `23505`.

### O2 — Capacity is measured in participant rows, not players

- **Scenario:** Team registration.
- **Symptom:** None — works as designed and documented in the migration. Flagged only because it is a common source of product confusion: `max_participants=4` for a team tournament means 4 teams (8 players), not 4 players.
- **Fix suggestion:** No code change required. Ensure the client UI labels this clearly ("max. 4 Teams" vs. "max. 4 Teilnehmer") to avoid organizer confusion.

---

## Relevant files

- `KubbProj/supabase/migrations/20261201000040_tournament_open_registration_model.sql` — live `tournament_register_team`/`tournament_publish`, open-registration model, dropped captain-exclusion on inbox.
- `KubbProj/supabase/migrations/20260615000006_tournament_team_rpcs.sql` — roster slot logic.
- `KubbProj/supabase/migrations/20261001000002_tournament_create_setup.sql` — 8-arg `tournament_create` (`p_setup` variant).
- `KubbProj/supabase/migrations/20261201000031` / `…032` — per-tournament manage authority (`tournament_caller_can_manage`).
