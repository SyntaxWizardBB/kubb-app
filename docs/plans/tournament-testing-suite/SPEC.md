# Tournament Testing Suite — SPEC (Source of Truth)

> **Status:** Design (Block T-Spec). This document is the single source of truth
> for the follow-up blocks (T-Harness, T-Client, T-Matrix). Code comments and test
> names in those blocks must trace back to a numbered config row and an assertion
> group defined here.
>
> **Branch:** `feat/tournament-scheduler-dashboard`.
> **Engine:** pgTAP via `supabase test db` (every file runs inside `BEGIN … ROLLBACK`).

---

## 0. Scope, axes source, and the IS-vs-WISH boundary

### 0.1 What is tested

The suite drives the **currently built** tournament lifecycle end-to-end through the
real RPCs and triggers, for the **full cartesian product** of the configuration axes
that the wizard emits today. The axes and their snake_case wire keys are extracted
from the Ist-Code description in
[`humanPlan/MilestoneTournaments.txt`](../../../humanPlan/MilestoneTournaments.txt)
(Stand 2026-06-06), cross-checked against:

- `lib/features/tournament/data/tournament_config_draft.dart` (`toSetupConfig` /
  `toMatchFormatConfig`; the client-only draft limits `participantsHardMax = 1000`
  (untested — the server clamp of 200 is the tested contract, see §0.2) and
  `koBracketSizeCap = 64`).
- `packages/kubb_domain/lib/src/tournament/{tournament_setup,ko_phase,pool_phase}.dart`.
- Server contract: `supabase/migrations/20261001000002_tournament_create_setup.sql`
  (`tournament_create(p_display_name, p_team_size, p_min_participants,
  p_max_participants, p_format, p_match_format_config, p_tiebreaker_order, p_setup)`),
  the `tournament_start*` family, `tournament_pair_round`, `tournament_set_seeding`,
  `tournament_propose_set_scores`, `tournament_organizer_override_pairing`, and the
  `advance_ko_winner` / `schedule_tick` triggers.

### 0.2 IS vs WISH — binding boundary

> **THE `#`-COMMENTS IN `humanPlan/MilestoneTournaments.txt` ARE FUTURE WISHES, NOT
> CURRENT STATE.** They describe desired changes (1000-player support that ignores
> the bracket cap, "Spasstournier ohne Wertung", required-instead-of-optional fields,
> Diggy default on, per-group pitch UI, year-suffix on names, etc.). **None of them
> are tested by this suite.** The suite asserts the behavior of the IST-Code only.

Concretely, the suite holds these IST facts constant and does **not** assert any
`#`-wish:

| IST fact (tested) | WISH (NOT tested) |
|---|---|
| KO bracket size is a power of two, `2 ≤ qualifierCount ≤ 64` (`koBracketSizeCap`). | "KO bracket size independent of participant cap / up to 1000". |
| **Two distinct participant caps:** the **server `tournament_create` clamp is `p_max_participants ≤ 200`** (the contract this pgTAP suite actually drives — `tournament_create_setup.sql` raises `max_participants must be in [min_participants, 200]`); the **client draft validator cap is `1000`** (`participantsHardMax`, `tournament_config_draft.dart:566`) and is **never exercised** by this suite (the wizard/draft path is not in scope). **Player sizes used here are 32 / 48 / 60**, which sit below **both** caps. | year-suffix uniqueness, 1000-player live run. |
| Every tournament has a KO phase; `withThirdPlacePlayoff = true` is fixed (no toggle). | "Spiel um Platz 3" toggle. |
| `ruleVariants` default `diggy=false`, `strafkubb_off_baseline=true`, `opening_rule='2-4-6'`. | "Diggy default on". |
| `club_id = null` ⇒ personal, `league_categories = []`. | rename to "Spasstournier ohne Wertung" / make required. |
| Optional stammdaten stay optional. | "all non-optional fields must be required". |

### 0.3 Player sizes

All cartesian rows are instantiated for participant counts **N ∈ {32, 48, 60}**.
These sit below **both** participant caps — the **server `tournament_create` clamp
of 200** (the binding clamp on the tested contract; see §0.2) and the untested client
draft cap of 1000 — and exercise three bracket regimes:

- **32** — power of two; clean snake/seeded division by every group count that
  divides the bracket.
- **48** — not a power of two; bracket cap forces `qualifierCount = 32`
  (largest 2^n ≤ 48), 16 non-qualifiers ⇒ tests the cut and consolation `earlyKoLosers`.
- **60** — near the cap; `qualifierCount = 32`, 28 non-qualifiers, odd-ish group fills
  ⇒ exercises byes in group phase and schoch.

---

## 1. Config axes (snake_case wire values)

Each axis lists `UI label` → `wire key` → `{value → snake_case}`. Keys land in
`p_setup` unless noted as `p_match_format_config` (mfc).

| # | Axis | Wire key (target) | Values (snake_case) |
|---|---|---|---|
| A1 | Vorrunde | `p_setup.vorrunde_type` → derives `p_format` | `group_phase` (→ `round_robin_then_ko`), `schoch` (→ `swiss_then_ko`) |
| A2 | KO-System | `p_setup.ko_type` → derives `p_setup.bracket_type` | `single_out` (→ `single_elimination`), `double_out` (→ `double_elimination`), `consolation` (→ `single_elimination` + `consolation_bracket.enabled=true`) |
| A3 | KO-Matchup | `p_setup.ko_matchup` | `seed_high_vs_low`, `one_vs_two` |
| A4 | KO-Tiebreak | `p_setup.ko_tiebreak_method` | `classic_kingtoss_removal`, `mighty_finisher_shootout` |
| A5 | Scoring | `p_setup.scoring` | `ekc`, `classic` |
| A6 | Pool-Strategy | `p_setup.pool_phase_config.strategy` | `snake`, `seeded`, `random` — **only when A1 = group_phase** |
| A7 | Schoch-Runden | client-side `_swissRounds` (NOT in create-RPC; fed to `tournament_pair_round`) | representative value `7` (within `[5,9]`); see §1.2 |

### 1.1 Derived / coupled values (set automatically, asserted as invariants)

- `p_format` = `formatFor(vorrunde, ko)`: `group_phase → round_robin_then_ko`,
  `schoch → swiss_then_ko`.
- `p_setup.bracket_type` = `bracketTypeFor(ko)`: `double_out → double_elimination`,
  else `single_elimination`.
- `p_setup.ko_config.qualifier_count` = power-of-two ≤ N, capped at 64 (smart default
  per §0.3): **N=32 → 16**, **N=48 → 32**, **N=60 → 32**. The suite pins
  `qualifier_count` explicitly per row so the bracket size is deterministic.
- `p_setup.ko_config.with_third_place_playoff` = `true` (fixed).
- `p_setup.ko_config.seeding_mode` = `auto` (the suite uses auto-from-prelim seeding;
  `manual` is out of the cartesian scope — see §6 open item).
- For `ko_type = consolation`: `p_setup.consolation_bracket =
  { "enabled": true, "source": "early_ko_losers", "main_bracket_size": <next_pow2(qualifier_count)>,
  "direct_count": 0, "name": "Sieger der gebrochenen Herzen" }`, plus the mirror keys
  `consolation_main_bracket_size`, `consolation_direct_count`, `consolation_name`.
- For `vorrunde = schoch`: an auto single-pool config is emitted so the hybrid
  starts; **A6 is N/A** (no `snake/seeded/random` fan-out for schoch). Per
  `schochSinglePoolConfig` (`tournament_config_draft.dart:776`) the config is
  `pool_phase_config = { "group_count": 1, "strategy": "seeded",
  "qualifiers_per_group": <qualifier_count> }` — i.e. it **also carries
  `qualifiers_per_group` = the single-group qualifier cut (= `ko_config.qualifier_count`,
  N=32→16 / N=48→32 / N=60→32)**. T-Harness MUST emit this key; if the server derives it
  for `swiss_then_ko` start it is harmless, but omitting it would surface as a
  missing-key failure in T-Harness, so the suite sets it explicitly.
- `p_match_format_config` (prelim, fixed across rows): `{ "max_sets": 2,
  "sets_to_win": 2, "round_time_seconds": 1800, "break_between_matches_seconds": 300,
  "basekubbs_per_side": 5 }`. **Note:** `max_sets=2` / `sets_to_win=2` /
  `round_time_seconds=1800` / `basekubbs_per_side=5` are the draft defaults
  (`tournament_config_draft.dart`); **`break_between_matches_seconds=300` is an
  intentionally non-default fixed test value** (the draft default is `0`,
  `tournament_config_draft.dart:45/166`) chosen so the schedule-tick path exercises a
  non-zero inter-match break — a follow-up implementer must not treat `300` as "the
  default". KO per-round formats use `ko_round_formats` default profiles (Bo5
  final/semis, Bo5+tiebreak quarters/eights, Bo3 earlier) and are asserted
  structurally, not fanned out.

### 1.2 Schoch round definition (A7)

One schoch round = every confirmed team has exactly one pairing (vs an opponent or a
bye); when all that round's matches are terminal the next round is computed. The
representative `_swissRounds = 7` is used; the harness plays rounds until the steered
target reaches the qualifier cut (it does not need to play all 7 if the cut is decided
earlier, but it asserts round count ≤ 7).

---

## 2. Full cartesian config matrix

Two sub-products, because A6 (pool strategy) only applies to `group_phase`:

- **group_phase product:** A2(3) × A3(2) × A4(2) × A5(2) × A6(3) = **72** combos.
- **schoch product:** A2(3) × A3(2) × A4(2) × A5(2) = **24** combos (A6 N/A,
  A7 fixed = 7).

= **96 config combos**, each instantiated for **N ∈ {32, 48, 60}** ⇒ **288 runs**.
The 96 combos are enumerated below as numbered rows. Each row gives its non-derived
snake_case setup values; derived values per §1.1 are implied. `qualifier_count`
shown is the N-dependent value (`16|32|32` for N `32|48|60`).

### 2.A group_phase combos (rows G01–G72)

Field order per row: `vorrunde=group_phase` · `ko_type` · `ko_matchup` ·
`ko_tiebreak_method` · `scoring` · `pool_phase_config.strategy`.

```
G01  group_phase | single_out  | seed_high_vs_low | classic_kingtoss_removal  | ekc     | snake
G02  group_phase | single_out  | seed_high_vs_low | classic_kingtoss_removal  | ekc     | seeded
G03  group_phase | single_out  | seed_high_vs_low | classic_kingtoss_removal  | ekc     | random
G04  group_phase | single_out  | seed_high_vs_low | classic_kingtoss_removal  | classic | snake
G05  group_phase | single_out  | seed_high_vs_low | classic_kingtoss_removal  | classic | seeded
G06  group_phase | single_out  | seed_high_vs_low | classic_kingtoss_removal  | classic | random
G07  group_phase | single_out  | seed_high_vs_low | mighty_finisher_shootout  | ekc     | snake
G08  group_phase | single_out  | seed_high_vs_low | mighty_finisher_shootout  | ekc     | seeded
G09  group_phase | single_out  | seed_high_vs_low | mighty_finisher_shootout  | ekc     | random
G10  group_phase | single_out  | seed_high_vs_low | mighty_finisher_shootout  | classic | snake
G11  group_phase | single_out  | seed_high_vs_low | mighty_finisher_shootout  | classic | seeded
G12  group_phase | single_out  | seed_high_vs_low | mighty_finisher_shootout  | classic | random
G13  group_phase | single_out  | one_vs_two       | classic_kingtoss_removal  | ekc     | snake
G14  group_phase | single_out  | one_vs_two       | classic_kingtoss_removal  | ekc     | seeded
G15  group_phase | single_out  | one_vs_two       | classic_kingtoss_removal  | ekc     | random
G16  group_phase | single_out  | one_vs_two       | classic_kingtoss_removal  | classic | snake
G17  group_phase | single_out  | one_vs_two       | classic_kingtoss_removal  | classic | seeded
G18  group_phase | single_out  | one_vs_two       | classic_kingtoss_removal  | classic | random
G19  group_phase | single_out  | one_vs_two       | mighty_finisher_shootout  | ekc     | snake
G20  group_phase | single_out  | one_vs_two       | mighty_finisher_shootout  | ekc     | seeded
G21  group_phase | single_out  | one_vs_two       | mighty_finisher_shootout  | ekc     | random
G22  group_phase | single_out  | one_vs_two       | mighty_finisher_shootout  | classic | snake
G23  group_phase | single_out  | one_vs_two       | mighty_finisher_shootout  | classic | seeded
G24  group_phase | single_out  | one_vs_two       | mighty_finisher_shootout  | classic | random
G25  group_phase | double_out  | seed_high_vs_low | classic_kingtoss_removal  | ekc     | snake
G26  group_phase | double_out  | seed_high_vs_low | classic_kingtoss_removal  | ekc     | seeded
G27  group_phase | double_out  | seed_high_vs_low | classic_kingtoss_removal  | ekc     | random
G28  group_phase | double_out  | seed_high_vs_low | classic_kingtoss_removal  | classic | snake
G29  group_phase | double_out  | seed_high_vs_low | classic_kingtoss_removal  | classic | seeded
G30  group_phase | double_out  | seed_high_vs_low | classic_kingtoss_removal  | classic | random
G31  group_phase | double_out  | seed_high_vs_low | mighty_finisher_shootout  | ekc     | snake
G32  group_phase | double_out  | seed_high_vs_low | mighty_finisher_shootout  | ekc     | seeded
G33  group_phase | double_out  | seed_high_vs_low | mighty_finisher_shootout  | ekc     | random
G34  group_phase | double_out  | seed_high_vs_low | mighty_finisher_shootout  | classic | snake
G35  group_phase | double_out  | seed_high_vs_low | mighty_finisher_shootout  | classic | seeded
G36  group_phase | double_out  | seed_high_vs_low | mighty_finisher_shootout  | classic | random
G37  group_phase | double_out  | one_vs_two       | classic_kingtoss_removal  | ekc     | snake
G38  group_phase | double_out  | one_vs_two       | classic_kingtoss_removal  | ekc     | seeded
G39  group_phase | double_out  | one_vs_two       | classic_kingtoss_removal  | ekc     | random
G40  group_phase | double_out  | one_vs_two       | classic_kingtoss_removal  | classic | snake
G41  group_phase | double_out  | one_vs_two       | classic_kingtoss_removal  | classic | seeded
G42  group_phase | double_out  | one_vs_two       | classic_kingtoss_removal  | classic | random
G43  group_phase | double_out  | one_vs_two       | mighty_finisher_shootout  | ekc     | snake
G44  group_phase | double_out  | one_vs_two       | mighty_finisher_shootout  | ekc     | seeded
G45  group_phase | double_out  | one_vs_two       | mighty_finisher_shootout  | ekc     | random
G46  group_phase | double_out  | one_vs_two       | mighty_finisher_shootout  | classic | snake
G47  group_phase | double_out  | one_vs_two       | mighty_finisher_shootout  | classic | seeded
G48  group_phase | double_out  | one_vs_two       | mighty_finisher_shootout  | classic | random
G49  group_phase | consolation | seed_high_vs_low | classic_kingtoss_removal  | ekc     | snake
G50  group_phase | consolation | seed_high_vs_low | classic_kingtoss_removal  | ekc     | seeded
G51  group_phase | consolation | seed_high_vs_low | classic_kingtoss_removal  | ekc     | random
G52  group_phase | consolation | seed_high_vs_low | classic_kingtoss_removal  | classic | snake
G53  group_phase | consolation | seed_high_vs_low | classic_kingtoss_removal  | classic | seeded
G54  group_phase | consolation | seed_high_vs_low | classic_kingtoss_removal  | classic | random
G55  group_phase | consolation | seed_high_vs_low | mighty_finisher_shootout  | ekc     | snake
G56  group_phase | consolation | seed_high_vs_low | mighty_finisher_shootout  | ekc     | seeded
G57  group_phase | consolation | seed_high_vs_low | mighty_finisher_shootout  | ekc     | random
G58  group_phase | consolation | seed_high_vs_low | mighty_finisher_shootout  | classic | snake
G59  group_phase | consolation | seed_high_vs_low | mighty_finisher_shootout  | classic | seeded
G60  group_phase | consolation | seed_high_vs_low | mighty_finisher_shootout  | classic | random
G61  group_phase | consolation | one_vs_two       | classic_kingtoss_removal  | ekc     | snake
G62  group_phase | consolation | one_vs_two       | classic_kingtoss_removal  | ekc     | seeded
G63  group_phase | consolation | one_vs_two       | classic_kingtoss_removal  | ekc     | random
G64  group_phase | consolation | one_vs_two       | classic_kingtoss_removal  | classic | snake
G65  group_phase | consolation | one_vs_two       | classic_kingtoss_removal  | classic | seeded
G66  group_phase | consolation | one_vs_two       | classic_kingtoss_removal  | classic | random
G67  group_phase | consolation | one_vs_two       | mighty_finisher_shootout  | ekc     | snake
G68  group_phase | consolation | one_vs_two       | mighty_finisher_shootout  | ekc     | seeded
G69  group_phase | consolation | one_vs_two       | mighty_finisher_shootout  | ekc     | random
G70  group_phase | consolation | one_vs_two       | mighty_finisher_shootout  | classic | snake
G71  group_phase | consolation | one_vs_two       | mighty_finisher_shootout  | classic | seeded
G72  group_phase | consolation | one_vs_two       | mighty_finisher_shootout  | classic | random
```

### 2.B schoch combos (rows S01–S24)

Field order per row: `vorrunde=schoch` · `ko_type` · `ko_matchup` ·
`ko_tiebreak_method` · `scoring`. (`schoch_rounds = 7` fixed; pool strategy N/A.)

```
S01  schoch | single_out  | seed_high_vs_low | classic_kingtoss_removal  | ekc
S02  schoch | single_out  | seed_high_vs_low | classic_kingtoss_removal  | classic
S03  schoch | single_out  | seed_high_vs_low | mighty_finisher_shootout  | ekc
S04  schoch | single_out  | seed_high_vs_low | mighty_finisher_shootout  | classic
S05  schoch | single_out  | one_vs_two       | classic_kingtoss_removal  | ekc
S06  schoch | single_out  | one_vs_two       | classic_kingtoss_removal  | classic
S07  schoch | single_out  | one_vs_two       | mighty_finisher_shootout  | ekc
S08  schoch | single_out  | one_vs_two       | mighty_finisher_shootout  | classic
S09  schoch | double_out  | seed_high_vs_low | classic_kingtoss_removal  | ekc
S10  schoch | double_out  | seed_high_vs_low | classic_kingtoss_removal  | classic
S11  schoch | double_out  | seed_high_vs_low | mighty_finisher_shootout  | ekc
S12  schoch | double_out  | seed_high_vs_low | mighty_finisher_shootout  | classic
S13  schoch | double_out  | one_vs_two       | classic_kingtoss_removal  | ekc
S14  schoch | double_out  | one_vs_two       | classic_kingtoss_removal  | classic
S15  schoch | double_out  | one_vs_two       | mighty_finisher_shootout  | ekc
S16  schoch | double_out  | one_vs_two       | mighty_finisher_shootout  | classic
S17  schoch | consolation | seed_high_vs_low | classic_kingtoss_removal  | ekc
S18  schoch | consolation | seed_high_vs_low | classic_kingtoss_removal  | classic
S19  schoch | consolation | seed_high_vs_low | mighty_finisher_shootout  | ekc
S20  schoch | consolation | seed_high_vs_low | mighty_finisher_shootout  | classic
S21  schoch | consolation | one_vs_two       | classic_kingtoss_removal  | ekc
S22  schoch | consolation | one_vs_two       | classic_kingtoss_removal  | classic
S23  schoch | consolation | one_vs_two       | mighty_finisher_shootout  | ekc
S24  schoch | consolation | one_vs_two       | mighty_finisher_shootout  | classic
```

> **Run cardinality:** 96 rows × 3 sizes = 288 lifecycle runs. The harness derives
> the `p_setup` JSON for each `(row, N)` purely from §1/§1.1; the rows above carry
> only the non-derived axes.

---

## 3. Harness design (pgTAP helpers in `supabase/tests/`)

All helpers live in test files under `supabase/tests/` (pattern of
`000-setup-tests-hooks.sql`, `tournament_ko_rpcs.sql`), inside `BEGIN … ROLLBACK`.
**No production migration**; helper functions are `CREATE OR REPLACE FUNCTION` defined
in-transaction (auto-dropped on rollback) under a `_tts_*` prefix to avoid collisions.
Auth-actor switching uses the established `set_config('request.jwt.claims', …)` /
`SET LOCAL ROLE postgres` patterns. Fixed test clock `p_now := '2026-06-09 12:00:00+00'`
for all schedule ticks (K7: pgTAP freezes `now()`).

### 3.1 Config builder

```sql
-- Returns the full p_setup jsonb + p_match_format_config jsonb for a row+N,
-- applying all derived/coupled rules from §1.1 (format, bracket_type,
-- qualifier_count, consolation_bracket, schoch auto-pool, ko_round_formats).
_tts_config(p_row text, p_n int) RETURNS TABLE(p_format text, p_setup jsonb, p_mfc jsonb)
```

### 3.2 Seed + register

```sql
-- Creates organiser user + N auth.users + calls tournament_create with the
-- config; returns tournament_id. Deterministic, zero-padded UUIDs.
_tts_seed_tournament(p_row text, p_n int, p_organiser uuid) RETURNS uuid

-- Registers + confirms N participants (writes tournament_participants
-- 'confirmed', staggered registered_at for stable seeding order).
-- Returns the participant_id of the steered TARGET account (seed-sensitive).
_tts_register_n(p_tid uuid, p_n int) RETURNS uuid   -- target participant_id

-- Lookup helpers (mirror _t6_participant / _pid).
_tts_participant(p_tid uuid, p_seed int) RETURNS uuid
_tts_target(p_tid uuid) RETURNS uuid
```

### 3.3 Start

```sql
-- Dispatches to the correct start path by p_format:
--   round_robin_then_ko / swiss_then_ko prelim -> tournament_start
--                                                 (or tournament_start_stage_graph
--                                                  for stage-graph formats),
--   KO entry              -> tournament_start_ko_phase (auto-seed gate satisfied).
-- Asserts status transitions draft -> open/live and that prelim matches exist.
_tts_start(p_tid uuid) RETURNS void
```

### 3.4 Play a round with steering

```sql
-- Plays EVERY scheduled match of the current round to a terminal result via
-- tournament_propose_set_scores (consensus path) or the walkover/forfait path.
-- p_steer drives the winner choice so the TARGET advances toward final/consolation
-- per §4. p_steer in {'target_wins','seed_order','target_to_consolation'}.
-- For schoch prelim it also calls tournament_pair_round for the next round.
_tts_play_round(p_tid uuid, p_steer text) RETURNS int   -- matches finalized
```

### 3.5 Advance + tick

```sql
-- Drives the round-clock: published->running->...->completed by injecting the
-- fixed p_now into tournament_schedule_tick; lets the advance_ko_winner trigger
-- propagate winners/losers into the next bracket slots.
_tts_advance(p_tid uuid, p_now timestamptz DEFAULT '2026-06-09 12:00:00+00') RETURNS void
```

### 3.6 Assertion helpers (return SETOF text, one TAP line each)

```sql
_tts_assert_placement_dense(p_tid uuid, p_n int)        -- §4 A1: 1..N gapless
_tts_assert_bracket_consistent(p_tid uuid, p_row text)  -- §4 A2
_tts_assert_schedule_timestamps(p_tid uuid)             -- §4 A3
_tts_assert_notifications(p_tid uuid)                   -- §4 A4
_tts_assert_no_orphan_participants(p_tid uuid)          -- §4 A5
_tts_assert_target_reached(p_tid uuid, p_row text)      -- §4 A6 (steering proof)
```

### 3.7 Per-row driver

```sql
-- Glue that runs the full lifecycle for one (row, N) and emits all assertion
-- lines, so a matrix file is a flat list of _tts_run(row, N) calls.
_tts_run(p_row text, p_n int) RETURNS SETOF text
```

---

## 4. Assertion set per combo

Every `(row, N)` run emits exactly this assertion group (helper → invariant):

- **A1 — Dense placement 1..N** (`_tts_assert_placement_dense`): the final standings
  projection assigns every confirmed participant a rank in `[1, N]` with **no gaps and
  no duplicates** (`COUNT(DISTINCT rank) = N` and `MIN=1, MAX=N`). For `consolation`,
  ranks below the main bracket are filled by the consolation bracket; for `double_out`
  the loser-bracket order fills the lower ranks.
- **A2 — Bracket consistency** (`_tts_assert_bracket_consistent`): per `bracket_type`:
  - `single_elimination`: round count = `ceil(log2(qualifier_count))`, exactly one
    `phase='final'` + one `phase='third_place'`, every non-leaf slot fed by a finalized
    feeder, every winner appears in exactly its parent slot (advance trigger parity).
  - `double_elimination`: a winners and a losers bracket exist; the grand-final feeder
    comes from both; no participant is eliminated before two losses.
  - `consolation`: `consolation_bracket.enabled`, main bracket size =
    `next_pow2(qualifier_count)`, early-KO losers routed into the consolation root,
    consolation final exists and is finalizable.
- **A3 — Schedule timestamps set** (`_tts_assert_schedule_timestamps`): every
  `tournament_round_schedule` row that the run advanced has non-null `published_at`,
  `starts_at`, `ends_at` with `starts_at < ends_at`, and the terminal rounds reached
  `status='completed'`.
- **A4 — Notifications created** (`_tts_assert_notifications`): go-live / round-publish
  drove at least one durable row into `public.user_inbox_messages` for participants
  (per the `tournament_golive_inbox` / `round_publish_notify` migrations); no run ends
  with zero notifications when at least one round was published.
- **A5 — No orphan participants** (`_tts_assert_no_orphan_participants`): every
  `tournament_participants` row of the tournament appears in at least one match (group/
  schoch/KO/consolation) OR carries a recorded bye; no participant is left unmatched
  and unranked.
- **A6 — Steering proof** (`_tts_assert_target_reached`): the steered TARGET account
  reached the configured endpoint for the run's KO model (§5): the KO/main final for
  `single_out`/`double_out`, and the consolation final for the `target_to_consolation`
  steer of `consolation`.

> **Total assertions:** the `plan(...)` count per matrix file = `Σ rows·N · 6`
> assertion lines plus the structural `has_function` preamble. Matrix files are split
> (§5) so each stays runnable.

---

## 5. Steering strategy "target reaches final / consolation final"

The TARGET is the lowest-`registered_at` participant (seed 1 under auto seeding). The
harness wins every match the target plays and, for the rest of a round, finalizes by
seed order, so the bracket stays deterministic.

- **single_out:** steer `target_wins`. Target wins each KO round → lands in
  `phase='final'`. A6 asserts target in the final and as rank 1 if it wins it.
- **double_out:** steer `target_wins`. Target stays in the winners bracket through to
  the grand final (never takes a first loss). A6 asserts target in the grand-final
  feeder from the winners side.
- **consolation:** two driver modes per row:
  - main path (`target_wins`): target reaches the main final (same as single_out).
  - consolation path (`target_to_consolation`): target is **deliberately lost** in an
    early KO round so the advance trigger routes it via `early_ko_losers` into the
    consolation bracket; the harness then wins the target's consolation matches → A6
    asserts target in the **consolation final**.
  Each `consolation` row therefore runs **both** drivers (so both endpoints are proven)
  while non-target slots follow seed order.
- **schoch (prelim):** the steer applies to the KO phase identically once qualifiers are
  cut; during prelim the harness keeps the target winning every schoch pairing so it
  finishes top of the standings and qualifies. `tournament_pair_round` is fed the
  client pairing each round (rounds ≤ 7), respecting no-repeat / max-one-bye.

---

## 6. Playbook structure (follow-up blocks)

### 6.1 File layout (`supabase/tests/`)

To keep each pgTAP file runnable under `supabase test db`, the matrix is sharded; the
helper file is shared and re-`CREATE OR REPLACE`d at the top of every shard (each runs
in its own transaction):

```
supabase/tests/tts_harness.sql              -- §3 helpers only (sourced/duplicated head)
supabase/tests/tts_matrix_group_single.sql  -- rows G01..G24 × {32,48,60}
supabase/tests/tts_matrix_group_double.sql  -- rows G25..G48 × {32,48,60}
supabase/tests/tts_matrix_group_cons.sql    -- rows G49..G72 × {32,48,60}
supabase/tests/tts_matrix_schoch.sql        -- rows S01..S24 × {32,48,60}
```

### 6.2 Block sequence (4-role pipeline per block, per AGENT_PIPELINE_PLAYBOOK §A)

1. **T-Spec** (this document) — DoD = §7.
2. **T-Harness** — implement §3 helpers in `tts_harness.sql`; smoke-test one row
   (G01, N=32) end-to-end; assert helpers compile and the lifecycle reaches a final.
3. **T-Client** — close minimal `lib/` read-model gaps only if an assertion needs a
   projection that is missing (no production-logic change beyond read models); strictly
   scoped.
4. **T-Matrix** — generate the four matrix shards from the row tables in §2 and the
   helpers; all shards green under `supabase test db`.

### 6.3 Guardrails (binding, every block)

- No production migration for tests; helpers live in `supabase/tests/` only.
- Never `supabase db reset` / seeding/deleting against the real DB; everything inside
  `BEGIN … ROLLBACK`.
- `git add` only scope files; never `git add -A`.
- Do not touch `docs/plans/realtime-messaging/`, `docs/adr/0029*`,
  `messaging-framework-implementation-plan.md`, or anything under
  `lib/features/training/`.
- Test names English; doc/comment conventions per repo.
- `flutter test` needs `--no-pub`; DB tests via `supabase test db`.

### 6.4 Known open items (NOT in the cartesian scope; tracked, not silently dropped)

- `seeding_mode = manual` (organiser sets bracket during the run) — out of scope; auto
  seeding only.
- `pitch_plan` / `group_assignment` placement variants — fixed range plan only; A3
  asserts timestamps, not pitch packing.
- `mighty_finisher_quali` (distinct from the `mighty_finisher_shootout` tiebreak) — has
  no wizard UI, stays null, not exercised.
- `schoch_rounds` other than 7 ∈ [5,9] — only the representative value is run.

---

## 7. Definition of Done (verifiable, design-only)

See the criteria list returned with this block. Each criterion is checkable against the
two axis sources (`humanPlan/MilestoneTournaments.txt` IST-Code description and the
`tournament_create_setup` / kubb_domain wire contract) and against this document's own
internal consistency.
