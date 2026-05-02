# ADR-0005: Per-platform persistence with web draft cache

- **Status**: Accepted
- **Date**: 2026-05-02
- **Depends on**: ADR-0001 (drift + Supabase chosen), ADR-0002 (Bounded Contexts), ADR-0004 (Scaling strategy)

## Context

ADR-0001 picked drift as the local DB and Supabase as the cloud backend, but it did not specify which clients persist locally and which do not. The implicit assumption was: every client uses drift, every client syncs.

Two facts make that assumption questionable for the Web target:

1. **Drift on Web** requires `sqlite3.wasm` running over either OPFS or IndexedDB. Both add a ~2 MB WASM bundle and a browser-compatibility surface (OPFS is solid on Chromium, partial elsewhere; IndexedDB-as-block-storage is universal but slower). Adopting drift on Web means owning that matrix.
2. **The Organizer use-case on Web is fundamentally online-bound.** Organizers run live tournaments where dozens of phones sync scores to the server. If the Organizer's network is down, phones keep working — they sync peer-to-server, not peer-to-Organizer. The Organizer's offline value is small.

But "no local storage on Web" is also wrong. Mature web apps (Slack, Gmail, Stripe Dashboard, Notion) all use IndexedDB for a narrow purpose: **rescue the user's in-flight UI state across connection blips and tab crashes, while leaving the canonical data in the server.** That pattern fits this project too — without paying the full cost of drift-on-Web.

This ADR codifies the asymmetry as an explicit architectural decision rather than letting it leak in implicitly.

## Decision

**Per-platform persistence with a single source of truth in Supabase, plus a narrow IndexedDB cache on Web for drafts and last-known-state.**

| Client | Canonical persistence | Local cache | Sync model | Offline behavior |
|---|---|---|---|---|
| **Phone (Player)** | drift (SQLite, native) | — | Append-only event log + outbox queue | Full offline scoring + training |
| **Web (Organizer)** | Supabase (no local replica of canonical state) | IndexedDB for form drafts + last-known view snapshots | Direct read/write against Supabase + Realtime subscriptions | Read-only stale view; drafts survive disconnect; canonical writes blocked |
| **Linux/Desktop** | drift (SQLite, native) | — | Same as Phone | Full offline |

### What goes in the Web IndexedDB cache (allow-list, not catch-all)

The IndexedDB layer is **deliberately narrow**. Only these categories are persisted on Web:

| Category | Example | Lifetime | Eviction |
|---|---|---|---|
| **Form drafts** | half-configured bracket, new tournament wizard, team registration form | until successful submit, or 7 days | TTL or submit |
| **Last-known view snapshots** | active matchplan, current pool standings | until next successful fetch overwrites | next fetch |
| **User preferences** | language, theme, last-opened tournament | until explicitly cleared | manual |
| **Pending optimistic UI state** | "you clicked submit, request is in flight" markers | until server response | response or timeout |

### What does **not** go in IndexedDB on Web

- Match events. They live in Supabase.
- Tournament canonical state. It lives in Supabase.
- Player or team records. They live in Supabase.
- Anything that would create a parallel truth or invite drift between local-Web and server.

The line is sharp: **IndexedDB on Web rescues UI state. It does not replicate domain state.**

### How the asymmetry is hidden behind the ports

The Application layer does not know which strategy is in use for canonical state. The DI container resolves the right adapter at boot:

```
MatchEventRepository (port, in packages/kubb_domain)
  ├── DriftMatchEventRepository      → Phone, Linux, Desktop
  └── SupabaseMatchEventRepository   → Web (no local fallback)
```

Same for `TournamentRepository`, `PlayerRepository`, `TeamRepository`.

The Web draft cache lives in a separate, Web-only port:

```
DraftCache (port, Web-only conditional import)
  └── IndexedDbDraftCache
```

`DraftCache` is consumed by Riverpod controllers in the presentation layer, never by the domain. It has no equivalent on Phone — phones save drafts to drift like any other state.

### Library pick for IndexedDB on Web

**`sembast_web`** for the IndexedDB layer. Reasons:

- NoSQL document store on top of IndexedDB. Matches the "small bag of typed JSON blobs" shape of drafts and snapshots better than a key-value wrapper.
- Mature, actively maintained, written by the same author as the well-known `sembast` package.
- Small footprint. No WASM, no codegen.
- Trivial to mock in tests.

Alternative considered: `idb_shim` (thinner, more boilerplate). Rejected for the second reason above.

### Single source of truth

Supabase Postgres remains canonical. Every event that matters has a server-side identity (UUIDv7) and a Lamport timestamp (per the still-pending ADR-0006). Local drift on phones is a **replica plus outbox**, not a parallel truth. IndexedDB on Web is a **UI-state rescue cache**, not a replica.

## Failure modes — explicit

The owner raised three concrete scenarios. Each is addressed below.

### Scenario A: Organizer's network drops mid-tournament

- **Phones**: keep working. They sync scores directly to Supabase over their own connections. Match events are append-only — no Organizer coordination needed for normal play.
- **Web canonical operations**: blocked. Buttons disabled, banner "Verbindung verloren — schreibgeschützt".
- **Web draft state**: survives. The half-configured bracket, the partly-typed registration form, the in-flight wizard step — all sit in IndexedDB. When the Organizer reconnects, the draft is restored and they continue from where they were.
- **Web read views**: show last-known snapshot from IndexedDB, with a clear "Stand vom HH:MM" banner. Better than a blank page during a 30-second blip.
- **On Organizer reconnect**: Web re-subscribes to Supabase Realtime, re-fetches affected views, draft state is preserved and the user can submit. **No data loss for tournament progression. No loss of in-flight UI work.**

### Scenario B: Supabase / server is down

- **Phones**: continue scoring. Outbox fills. UI shows a sync indicator ("3 Würfe ausstehend"). No user-facing blockage on the match itself.
- **Web**: cannot read or write canonical state. Draft cache and last-known snapshots remain available — Organizer can keep typing, but cannot submit until the server is back.
- **On Supabase recovery**: phones drain their outbox in Lamport order. Web re-fetches and lets the Organizer submit any drafts that were waiting.
- **Server redundancy**: delegated to Supabase as a managed service. Tier 0 (Free) has no SLA; Tier 1 (Pro, $25/mo) has daily PITR backup and 99.9% uptime. Migration path to self-hosted Postgres + Realtime with HA is documented in ADR-0004 and triggered at Tier 2.

### Scenario C: Phone breaks or is lost during a match

- Out of scope for this ADR. Player switches to a backup device, signs in, the server has every event up to the last successful sync. Outbox flushes aggressively (per event, not batched on a timer) to keep the loss window small.

## Alternatives considered

### Alt 1: Drift everywhere including Web (full symmetry)

- **Pro**: symmetric architecture, one mental model, full offline on every client.
- **Contra**: WASM bundle (~2 MB) hurts Web first-paint. Browser-compatibility matrix to maintain (OPFS is partial outside Chromium; IndexedDB-as-block-storage is slower). Schema migration becomes a per-platform testing burden. Organizers do not actually need offline scoring — wrong cost for the use case.
- **Why rejected**: pays a heavy architecture and bundle cost for a capability the Organizer does not need.

### Alt 2: No local storage on Web at all (initial draft of this ADR)

- **Pro**: simplest possible Web build. One adapter, no cache layer, smallest bundle.
- **Contra**: half-typed forms vanish on connection blips. Brief outages produce blank screens. Feels amateur compared to Slack / Gmail / Stripe — apps that operate in similar conditions.
- **Why rejected**: too binary. The cost of a narrow IndexedDB cache is small; the UX gain is real.

### Alt 3: Drift on Web with IndexedDB backend (drift's web mode)

- **Pro**: keeps one persistence API and one schema across clients.
- **Contra**: still ships the WASM bundle. SQLite-over-IndexedDB is a workaround, not a native fit — slower than OPFS, slower than direct IndexedDB. Bundle size and bootstrap time dominate over the API-uniformity gain.
- **Why rejected**: pays most of Alt 1's cost without its full benefit.

## Consequences

### Positive

- Web build stays small. No WASM bundle, no OPFS fallback, no SQLite-on-Web compatibility matrix.
- Organizer Web feels resilient: form drafts survive disconnects, last-known view snapshots cover short blips. Matches what users expect from modern web apps.
- Drift-on-Web spike (currently a MUST-FIX in the project memory) is no longer needed.
- The `MatchEventRepository` port stays clean. The asymmetry is a swap-in adapter for canonical state, plus a Web-only auxiliary port for UI rescue. No leaky special cases in the domain.

### Negative

- **Organizer Web cannot do canonical work offline.** Trade-off accepted. Organizer can fall back to a phone (full drift, full offline) if extended outage occurs.
- **One additional Web-only library to maintain** (`sembast_web`). Mitigation: small surface, well-isolated behind the `DraftCache` port, easy to swap if needed.
- **Cache-eviction discipline required.** A draft that lives forever in IndexedDB after the form is gone is a paper cut. Mitigation: explicit TTL on each draft entry, cleanup on successful submit, defensive expiry on app boot.
- **Tests need a fake `DraftCache` implementation.** Standard mocktail pattern, not a real burden.

### Neutral

- The project memory's "MUST-FIX 1: Drift-on-Web Spike" is closed by this ADR. Update CLAUDE.md to remove that item.
- The pure-Dart domain in `packages/kubb_domain/` is unaffected — it never knew which adapter persisted its events, and it does not know about `DraftCache` either.
- Future Web-only features default to the same pattern: canonical state via Supabase, narrow rescue cache in IndexedDB. New categories of cached data go through this ADR (or a follow-up) before being added to the allow-list.

## Followups

- ADR-0006: Lamport-clock invariants (already pending per project memory).
- Implementation note: when M3 (Live-Scoring) starts, the `SupabaseMatchEventRepository` adapter is the first concrete instance of this ADR's port-swap pattern. Build it side-by-side with the drift adapter so both go through the same contract tests from day one.
- Define the `DraftCache` port and the `IndexedDbDraftCache` adapter as part of the M0/M1 boundary, before the first Web form (Tournament-Setup) is built.
- Remove the "Drift-on-Web Spike" line from CLAUDE.md `Next session` and from `Open decisions` once this ADR is Accepted.
