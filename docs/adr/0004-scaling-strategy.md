# ADR-0004: Scaling strategy & migration playbook

- **Status**: Accepted
- **Date**: 2026-05-02
- **Depends on**: ADR-0001 (Supabase chosen), ADR-0002 (Bounded Contexts), ADR-0003 (Auth & users)

## Context

The architecture from ADR-0001/0002 is scale-aware in its bones (Tactical DDD, append-only event log, UUIDv7, port-based Supabase access, pure-Dart domain). But the project plan has so far been feature-driven with no explicit scale milestones. The owner asked the right question: how do we know when to scale, what monitoring tells us, and how do we migrate off Supabase if we outgrow it?

This ADR fixes that — without falling into premature optimization. It defines tiers with concrete triggers, a monitoring strategy that surfaces those triggers proactively, and a migration playbook from Supabase to alternative backends.

## Tier model

Four growth tiers with concrete thresholds. We engineer for **one tier ahead** at most.

| Tier | Active users | Peak req/s | DB size | Realtime concurrent | Monthly cost | Status now |
|---|---|---|---|---|---|---|
| **0 — Pilot** | 0 – 500 | 0 – 50 | < 500 MB | < 200 | $0 (Supabase Free) | **WIR SIND HIER** |
| **1 — Adoption** | 500 – 5k | 50 – 500 | < 8 GB | < 500 | $25 (Supabase Pro) | next stage |
| **2 — Etabliert** | 5k – 50k | 500 – 5k | < 100 GB | < 5k | $100 – 600 (Supabase Team or self-host) | migration window |
| **3 — Skaliert** | 50k+ | 5k – 50k | 100 GB+ | 5k+ | $1k – 10k (custom backend) | replatform required |

Beyond Tier 3 (~100k req/s sustained) we would not be running a Kubb tournament tool — we would be running a multi-sport SaaS, which is a different product and a different ADR.

## Tier-transition triggers

A trigger fires when a metric stays above threshold for **3 consecutive days** (avoids spike-driven false alarms). When fired, the tier-prep checklist for the next tier becomes active work.

| Trigger | Threshold | Implies |
|---|---|---|
| MAU > 400 | sustained 3 days | Tier 0 → 1 prep |
| Supabase Free DB size > 80% | for 1 day | Tier 0 → 1 prep |
| Supabase Free bandwidth > 80% | for 1 month | Tier 0 → 1 prep |
| Realtime concurrent > 160 (80% of free 200) | sustained | Tier 0 → 1 prep |
| MAU > 4k | sustained 3 days | Tier 1 → 2 prep |
| Supabase Pro DB size > 80% | for 1 day | Tier 1 → 2 prep |
| Realtime concurrent > 400 (80% of Pro 500) | sustained | Tier 1 → 2 prep |
| p95 API latency > 800 ms | sustained 3 days | Tier 1 → 2 prep (regardless of MAU) |
| Auth email rate-limit hit | even once | Migrate magic-link SMTP off Supabase (Tier 0+) |

Tier transitions are **owner-decided** based on triggers — not automatic. Triggers are signals to start preparation work, not to flip a switch.

## Monitoring — what we measure and where

The owner asked specifically about knowing the user count before hitting limits. Answer: instrument from day one, lightweight, lo-fi.

### Stack (free / cheap, EU-hosted preferred)

| Layer | Tool | What it gives us | When to add |
|---|---|---|---|
| **DB metrics** | Supabase Dashboard (built-in) | DB size, query volume, slow queries, auth events, bandwidth | Day 1 — already there |
| **Product metrics** | [Plausible](https://plausible.io) self-hosted OR [Umami](https://umami.is) | MAU, DAU, sessions, page-views, no cookies, GDPR-clean | M5 (Polish) at latest |
| **Error tracking** | [Sentry](https://sentry.io) (free tier 5k events/mo) | Flutter crashes, Dart errors, breadcrumbs | Sobald erste echte User da sind |
| **Performance / latency** | Sentry Performance OR custom timing logs in Supabase | p50 / p95 / p99 für Score-Events, Bracket-Generation, Sync | M3 (Live-Scoring) |
| **App-internal events** | Existing match-event log + new `app_telemetry_events` table | Custom counters: applications/day, check-ins/day, scoring-events/day | M2 (Tournament-Setup) |
| **Synthetic load test** | k6 oder Apache Bench, Cron-Job | Bestätigt Capacity vor Wachstum | Tier 1 prep |

### Concrete dashboards we build

Three Grafana-or-similar dashboards (or just markdown reports run weekly via a `/task` workflow):

**Dashboard 1: User health (weekly review)**
- MAU, DAU, week-over-week growth
- Active tournaments count
- Active matches count (peak per day)
- New player signups / week
- Walk-in vs registered ratio

**Dashboard 2: System health (daily review during launch, weekly after)**
- Supabase DB size + growth rate
- Bandwidth used / quota
- Realtime concurrent peak
- Auth email send count / quota
- p95 latency for: score-event-write, bracket-load, application-list-read
- Error rate (Sentry)

**Dashboard 3: Scale-trigger watchlist (daily auto-check via cron)**
- Each Tier-transition-trigger from the table above with current value vs threshold
- Auto-alert if any trigger has been > threshold for 2 consecutive days (warns before the 3-day rule fires)

### Implementation tasks (added to backlog)

These get scheduled when we hit the relevant milestone:

- **M3** (Live-Scoring): instrument score-event write/read with timing logs, send to Sentry Performance.
- **M4** (Sync + Dispute): add Sentry SDK to Flutter app, wire up errors.
- **M5** (Polish): set up Plausible / Umami and add page-view tracking; build Dashboard 1 and 2.
- **Post-M5**: build Dashboard 3 (scale-trigger watchlist) as a weekly automated report — first cheap version is a `/task` running every Monday morning.

## Migration playbook — Plan B for leaving Supabase

The owner asked: how do we migrate off Supabase if we outgrow it? Concretely.

### Why it's not a panic

**Supabase is just Postgres + an API + an auth layer.** Nothing we do today is locked-in beyond the cost of operating those three pieces ourselves. Our `TournamentRemote` port already abstracts the Supabase-specific code from the rest of the app. Migration cost = doing the operations work.

### Migration target options (in order of effort)

| Option | What it is | Effort | When it fits |
|---|---|---|---|
| **A — Supabase Team / Enterprise** | Same product, paid tier ($599+/mo) | Days (just upgrade) | Tier 2 if cost is acceptable |
| **B — Self-hosted Supabase** | Open-source Supabase on Hetzner / DigitalOcean | 1–2 weeks setup, ongoing ops | Tier 2 budget-conscious |
| **C — Postgres + PostgREST + custom auth** | Decompose Supabase into its components, run them yourself | 3–4 weeks setup | Tier 2 with technical preference for control |
| **D — Custom Rust / Go backend** | Replace Supabase entirely, custom API and auth | 2–4 months | Tier 3 only — for performance / multi-region |

**Default choice when we hit Tier 2 trigger**: Option B (self-hosted Supabase). Same APIs, same client SDKs, escapes Supabase pricing, keeps team productivity. Self-hosting cost on Hetzner ~€60/mo for the level of usage at Tier 2 entry.

### Pre-work that makes migration cheap (DO NOW, all are no-cost if done from start)

These are commitments enforced by `tech-lead.md` rules and the security-checker agent — already aligned with current architecture, just made explicit:

1. **All Supabase access through `TournamentRemote` port** — no `supabase_flutter` import outside `lib/features/<context>/data/`. Enforced by linter exclusion + tech-lead review.
2. **Schema-as-SQL, not Supabase-only migrations** — keep `*.sql` files in `db/migrations/` (or use drift's migration tool which generates plain SQL). Avoid Supabase-only migration features.
3. **Auth abstraction** — `AuthController` (Riverpod) wraps Supabase auth. Magic-link is portable across providers (mailgun, sendgrid, postmark, AWS SES, self-hosted). The auth-state interface stays the same.
4. **Don't use Supabase Edge Functions for business logic** — domain logic lives in `kubb_domain` (pure Dart). If we need server-side validation, we put it in our own backend later. Edge Functions are vendor-specific.
5. **Realtime subscriptions through an interface** — `RealtimeChannel` abstraction; concrete impl uses Supabase's WebSocket. At migration we swap impl (NATS / Pulsar / custom WebSocket).
6. **No Supabase Storage for critical assets** — if we need file uploads (avatars, tournament photos), use S3-compatible (Cloudflare R2 / Hetzner Storage Box). Supabase Storage is fine for prototypes, but it's not the easiest piece to migrate.
7. **Document the data export procedure** — `pg_dump` against the Supabase Postgres works. Run it monthly, store the dump in Hetzner Storage Box. Cheap insurance.
8. **Test the export quarterly** — restore the dump to a local Postgres, run `dart test` against it, confirm parity. Catches incompatible schema changes early.

### Migration runbook (when triggered)

This is the playbook for **Option B (self-hosted Supabase)**. Variations for other options noted at the end.

#### Phase 0 — Decision (Day 0)

- Trigger has fired (3+ days above threshold).
- Owner reviews dashboards, confirms migration is the right call (vs upgrading to paid tier).
- Open ADR-NNNN documenting the migration decision with target option.

#### Phase 1 — Parallel Infrastructure (Week 1)

- Provision new Postgres instance (Hetzner Cloud, Frankfurt).
- Self-host Supabase (Docker Compose from official repo) OR set up PostgREST + Postgres + GoTrue (auth) separately.
- Restore latest `pg_dump` to new infrastructure.
- Verify all rows match (count + checksum per table).
- Stand up parallel Supabase instance — does NOT serve traffic yet.

#### Phase 2 — Dual Write (Week 2)

- Modify `TournamentRemote` adapter to write to BOTH old and new infrastructure.
- Reads still go to old (Supabase Cloud).
- Run for 7 days.
- Daily diff-check: rows in new infra match rows in old (allowing for the dual-write latency).

#### Phase 3 — Canary Read (Week 3)

- Switch 10% of reads to new infra (feature-flag gate, randomized by user-id).
- Monitor: error rate, p95 latency on new infra vs old.
- If clean for 2 days: 50%. If clean for 2 days more: 100%.
- All writes still dual.

#### Phase 4 — Write Cutover (Week 4)

- Stop dual-write. New infra is now primary.
- Old Supabase Cloud is read-only for 7 more days (safety net).
- Full final verification.

#### Phase 5 — Decommission (Week 5)

- Delete the Supabase Cloud project.
- Update DNS, env vars, CI secrets.
- Final ADR-NNNN confirming migration complete.
- Remove dual-write code path.

**Total elapsed time: ~5 weeks if pre-work is done. ~3 months if pre-work was skipped (then Phase 0 includes ripping out vendor-specific code first).**

### Variations

- **Option A (paid Supabase)**: skip phases 1-5; just upgrade in the dashboard. Hours, not weeks.
- **Option C (decomposed)**: Phase 1 takes 2-3 weeks; rest unchanged.
- **Option D (custom backend)**: Phase 1 is months of work building API + auth + realtime. Not a 5-week playbook.

## Performance budgets (apply from M1)

These are non-functional requirements every feature is reviewed against:

| Operation | Budget (p95) | Measured how |
|---|---|---|
| 1-tap UI action (Training, Score-Tap) | < 100 ms | Sentry Performance, Flutter `Timeline` |
| Score-event write (local + sync trigger) | < 500 ms LAN, < 2 s LTE | Custom timing log in adapter |
| Bracket generation (64 teams) | < 1 s | Pure-function unit benchmark in `kubb_domain/test/` |
| Tournament list load (Organizer) | < 800 ms | Adapter timing log |
| Realtime sync propagation (write → other device read) | < 1 s LAN, < 3 s LTE | End-to-end test |
| App cold start (Flutter, Linux/Web) | < 2.5 s | `flutter run --profile` |

When a feature plan documents a likely budget violation, the owner is notified before implementation starts.

## Capacity assumptions (current architecture, single Supabase Pro instance)

Estimated ceiling without architecture change:

- **Concurrent users** (browsing, listing): ~5,000
- **Concurrent active matches** (live-scoring writes): ~500
- **Realtime subscriptions**: 500 concurrent (Pro tier hard limit)
- **Score events / sec**: ~50–100 sustained (Postgres handles this trivially; Realtime fan-out is the bottleneck)
- **Tournaments active simultaneously**: ~200

This covers Tier 1 comfortably and overlaps into Tier 2. At Tier 2 trigger we start migration prep with weeks of headroom, not days.

## Things we explicitly do NOT do

- ❌ **Pre-build microservices** — stays modular monolith until split is justified by team size or scaling pain
- ❌ **Pre-install Redis / caching layer** — Postgres handles our load; cache-invalidation bugs > performance wins at this scale
- ❌ **Multi-region deploy** — single-region (Frankfurt) until latency complaints from non-EU users justify it
- ❌ **Custom WebSocket / message queue** — Supabase Realtime carries us through Tier 2
- ❌ **Sharding** — vertical scaling on Postgres + read replicas covers Tier 2; sharding is a Tier 3 problem
- ❌ **CQRS / Event-Sourcing framework** — append-only log is enough; adding a framework on top adds complexity without value at our scale

## Consequences

- Adds explicit monitoring obligations to M3, M4, M5 milestones.
- Adds a recurring `/task` (weekly scale-trigger watchlist review) starting post-M5.
- Adds the scale-impact check to `tech-lead.md` rule (every feature plan is reviewed for Tier-1 / Tier-2 implications).
- Adds quarterly `pg_dump` export + restore-test as a maintenance task.
- Anchors Plan B: self-hosted Supabase (Option B) is the default migration target. Documented runbook exists; no panic if triggers fire.
- Adds 6-8 backlog tasks across M3-M5 (instrumentation work). All small (S), spread across milestones.

## Implementation order (suggested)

When the relevant milestones come up:

1. **M3** — instrument score-event write/read; first Sentry integration (errors only at first).
2. **M4** — Sentry Performance for sync paths; performance budget tests added to integration suite.
3. **M5** — Plausible / Umami self-hosted on Hetzner; Dashboard 1 & 2 (markdown weekly reports first, Grafana later).
4. **Post-M5** — Dashboard 3 (scale-trigger watchlist) as a weekly `/task`.
5. **First quarter post-launch** — quarterly `pg_dump` + restore-test.
6. **Tier 1 trigger fires** — Pro upgrade ($25/mo) + SMTP plug-in (SendGrid free tier).
7. **Tier 2 trigger fires** — start the 5-week migration runbook (Option B default).
