# Unified Messaging Framework — Plan

> Status: **Design only — no code changes**. Implementation happens in later
> sprints, sequenced per §4 / §7.
> Scope: replace interval polling with a unified realtime messaging layer so
> (A) cross-device updates feel instant and (B) battery lasts a full day, then
> formalise it as a **Messaging Framework** that *all* future cross-device,
> sync and notification work must use by default.
> Related ADRs: 0021 (realtime-subscription-architecture), 0022 (offline-sync-
> outbox), 0023 (spectator-public-read-rls), 0026 (anon-spectator-revision).
> New ADR to record this decision: **0029-unified-messaging-and-battery-lifecycle**
> (0027 / 0028 are already taken by double-elimination / consolation-bracket).

---

## 1. Goal + battery / instant rationale

### 1.1 The problem
The app today mixes two models. A **good** realtime layer already exists for
tournaments (per-tournament Postgres-CDC channels with refcount / backoff /
fallback, plus anon spectator Broadcast). But **server-state discovery on most
other screens is interval polling** via `Timer.periodic` + Riverpod invalidation:

- Friends list — **1 s** (`social_providers.dart`)
- Inbox — **1 s** (`inbox_controller.dart`)
- Teams list + detail — **4 s** (`team_providers.dart`)
- Tournament list / detail / bracket / standings — **5 s**
- Match live detail — **1 s** per match
- Public spectator fallback — **10 s** (only when live-mode off)

None of these pause when the app is backgrounded.

### 1.2 Why this kills battery
Battery drain is dominated by **radio wake-ups**, not CPU. A single user sitting
on the friends + inbox screens generates **~7 200 polling wake-ups/hour**;
add teams/tournaments and it climbs past ~9 000/hour. Worse, the timers keep
running while the app is paused, so a backgrounded app holds the radio awake and
can drain a battery in roughly ten minutes.

### 1.3 The fix, in one sentence
**One multiplexed WebSocket while foreground; zero sockets + zero timers while
backgrounded; OS push (future) as the only background wake path; polling demoted
to a rare ≥60 s-errored fallback.** Every server event the app cares about already
lands as a row write (chiefly into `public.user_inbox_messages`), so we can
*subscribe* to those writes instead of polling for them.

| Regime | Wake-ups/hour (today) | Wake-ups/hour (target) |
|---|---|---|
| Inbox + friends foreground | ~7 200 | ~1 socket frame per real event (≈0 idle) |
| Backgrounded | timers keep firing | 0 (push only) |
| Realtime down (fallback) | n/a | ~120 (30 s cadence) |

---

## 2. Concept primer + the DECISION RULE

Four mechanisms. The first three are in-app/foreground; push is out-of-app.

### 2.1 Postgres Changes (CDC) — `RealtimeChannel` port
Supabase streams row-level `INSERT`/`UPDATE`/`DELETE` over the shared WebSocket,
**RLS-gated** to what the signed-in user may read. Our port
(`packages/kubb_domain/lib/src/ports/realtime_channel.dart`) is **single-column-eq
only**: `subscribe(table, filterColumn, filterValue)` → one Postgres `eq` filter.
So a CDC target needs **(a) one filterable column** scoping rows to the user and
**(b) an RLS SELECT policy** matching that scope. Heavier than Broadcast
(per-row, RLS-evaluated) but **zero server code** — RLS does the auth.
Adapter `SupabaseRealtimeChannel` already gives refcount + 500 ms close-debounce +
1/2/4/8/30 s backoff + state stream.

### 2.2 Broadcast — `realtime.send()` + DB trigger
A trigger emits a **curated, column-whitelisted** payload to a named topic
(`realtime.send(payload, event, topic, private)`). Great for **fan-out to many /
anon subscribers**, **PII-stripped** payloads, and **derived events** that don't
map 1:1 to a row. Requires a DB trigger. Reference: migration
`20260601000031_public_tournament_realtime.sql` +
`public_tournament_realtime.dart`. Anon subscribe uses `private:false`.

### 2.3 Inbox (`user_inbox_messages` + CDC) — the notification spine
`public.user_inbox_messages` is a **durable, user-addressed** table:
single `user_id` column, owner-read RLS (`user_inbox_messages_owner_read`,
migration `20260504000011`), a drift mirror, and `refreshFromRemote(userId)`.
Every durable notification already INSERTs here — tournament go-live
(`_tournament_notify_participants`, `20261201000010`), team invites
(`team_invitation_respond`, `20260901000011`), admin notices. So **one CDC
subscription on this table replaces the read-side of all of them at once** and is
the natural join point for future push.

### 2.4 Push (FCM/APNs) — separate, out-of-app layer (future)
The **only** mechanism that wakes a **backgrounded/closed** app. Realtime is dead
when paused; push is the background equivalent. Designed-for now (§6), built later.
No `firebase_messaging` exists today.

### 2.5 DECISION RULE — pick the lowest-cost transport that fits

```
Is the audience anonymous / fan-out / needs PII-stripped or derived payload?
   └─ YES → BROADCAST (realtime.send trigger, private:false for anon)
Is it a durable, user-addressed notification that must survive offline / cold
start / appear in the Inbox UI (and later drive push)?
   └─ YES → INBOX  (write to user_inbox_messages; client = ONE CDC sub on it)
Does an authenticated client need live row-state of a table it can already read,
filterable by ONE indexed column (tournament_id / team_id / user_id / id)?
   └─ YES → CDC  (RealtimeChannel.subscribe; no server code, RLS authorises)
Is it a LIST with no single-column user scope (my-teams, my-tournaments)?
   └─ Drive invalidation off the INBOX CDC event; keep poll only as fallback.
Out-of-app wake needed (backgrounded/closed)?
   └─ PUSH (future, §6) — fed by the SAME user_inbox_messages row.
```

Tie-breakers: anon → **must** be Broadcast. Needs offline durability / push →
**must** go through Inbox. Otherwise default to **CDC** (no migration).

---

## 3. The target Messaging Framework

### 3.1 Shared abstraction (built on what exists — do not replace)
- **CDC**: keep `RealtimeChannel` port + `SupabaseRealtimeChannel` adapter **as-is**.
  Reusable unchanged for any new CDC target — only new repository `watch*` methods
  + provider wiring are needed, mirroring `watchTournamentMatches`
  (`tournament_repository.dart:712`).
- **Broadcast**: lift the hard-coded Broadcast logic out of
  `SupabasePublicTournamentRealtime` into a **sibling port**
  `packages/kubb_domain/lib/src/ports/broadcast_channel.dart`:

  ```dart
  abstract interface class BroadcastChannel {
    Stream<BroadcastMessage> subscribe({
      required String topic,
      required Set<String> events,
      bool private = false,
    });
    Future<void> close(String topic);
    Stream<RealtimeChannelState> stateStream(String topic);
  }
  // value: BroadcastMessage { String event; Map<String,Object?> payload; DateTime receivedAt; }
  ```

  `SupabasePublicTournamentRealtime` then becomes a thin mapper on top of it.
- **Shared lifecycle mixin**: both Supabase adapters today carry a near-identical
  `_ChannelEntry` (refcount + debounce + backoff). Factor it into one shared mixin
  so CDC and Broadcast share refcount/debounce/backoff and a single fake.

### 3.2 Riverpod pattern — `StreamProvider` replaces `FutureProvider`+`Timer`
Every migrated feature exposes a realtime-backed **`StreamProvider`**, never a
`FutureProvider` re-invalidated by a timer. Two variants:

**(a) drift-cache variant** (inbox, anything with a local mirror) — subscribe to
the realtime stream; on each event, fire-and-forget `refreshFromRemote` into the
drift cache; return the drift `watch*` stream. Offline hydration unchanged;
realtime replaces only the *discovery* timer:

```dart
final inboxMessagesProvider = StreamProvider.autoDispose<List<InboxMessage>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);
  final repo = ref.read(inboxRepositoryProvider);
  final channel = ref.watch(realtimeChannelProvider);
  final sub = channel.subscribe(
    table: 'user_inbox_messages',
    filterColumn: 'user_id',
    filterValue: userId,
  ).listen((_) => unawaited(
    repo.refreshFromRemote(userId).catchError((_) => const <InboxMessage>[])));
  ref.onDispose(sub.cancel);
  ref.onDispose(() => unawaited(channel.close(inboxRealtimeChannelKey(userId))));
  unawaited(repo.refreshFromRemote(userId).catchError((_) => const <InboxMessage>[]));
  return repo.watchForUser(userId);
});
```

**(b) invalidate-on-tick variant** (no drift cache — teams, tournament list) — a
`StreamProvider` that `listen`s to the realtime stream and `invalidateSelf()` (or
invalidates the underlying read provider) per event. Same lever
`tournamentMatchListRealtimeProvider` / `publicTournamentEventsProvider` already
use, **minus** the parallel `Timer.periodic`.

**Rules:**
- Always `autoDispose`, `family`-keyed by entity id.
- Subscribe on first watch; `ref.onDispose` cancels → adapter refcount + 500 ms
  debounce tears the channel down. Subscribe-on-mount / dispose-on-unmount is free.
- **Delete the `*PollingProvider` sentinels** (see §4). They are pure
  `Timer.periodic` and have no place in the target.
- Global signals (inbox) are opened **at app-shell scope** so they survive
  navigation and feed the inbox badge; screen providers just `watch` the shared stream.

### 3.3 Channel / topic naming conventions
All keys derived by **one builder per concern**, colocated like the existing
`tournamentRealtimeChannelKey()`. The invariant: `stateStream` lookups must hit
the same entry as the subscription, so keys are never hand-built at call sites.

| Concern | Transport | Key / topic |
|---|---|---|
| CDC, row-filtered | Postgres Changes | `<table>:<column>=<value>` e.g. `user_inbox_messages:user_id=<uid>` |
| Broadcast, curated | `realtime.send` | `<domain>_events:<scope_id>` e.g. `public_tournament_events:<tid>` |

Add `kubb_domain` builders mirroring `tournamentRealtimeChannelKey`:
`inboxRealtimeChannelKey(UserId)`, `teamRealtimeChannelKey(TeamId)`,
`matchRealtimeChannelKey(MatchId)`, and rename the spectator topic helper to
`tournamentBroadcastTopic(TournamentId)`.

### 3.4 Subscribe / teardown lifecycle + reconnect-on-resume
- **One client / one socket** — `Supabase.initialize()` in `main.dart` is a
  singleton; every channel multiplexes over it. The framework **never** opens a
  second client. N screens on the same key = 1 channel (refcount).
- **App lifecycle** — extend the **existing** `AppLifecycleListener` in
  `lib/app/app.dart` (today only `onResume` → keypair re-sign). Add **one**
  `RealtimeLifecycleController` read once at the shell:
  - `resumed` → (1) run the existing `forceReSignWireSession` **first** (channels
    must rejoin with a fresh JWT or hit a join→401→backoff storm); (2) reconnect /
    re-open the channels that were active at pause (inbox always; tournament/match
    only if their screen is still mounted) — resubscribe rides the existing
    backoff; (3) resume `KeypairSessionRefresher`.
  - `inactive` → **no-op** (transient: app switcher, call, brief lock). Tearing
    down here causes reconnect thrash.
  - `paused` → debounce **~5 s**, then unsubscribe all channels + disconnect the
    socket + pause `KeypairSessionRefresher`. This closes the documented
    "timers keep running backgrounded" gap.
  - `detached` → same teardown, immediate (process dying).
  - Persist the **set of active channel keys** across pause→resume (the refcount
    map in `SupabaseRealtimeChannel` is the natural home — add a
    rehydrate-from-snapshot path rather than rebuilding from screens).

### 3.5 Fallback-polling-only-when-down
Polling is a **failure-mode-only** safety net, never steady state. Generalise the
tournament-only `realtimeFallbackProvider` into a reusable primitive keyed by
channel-key:

```dart
StreamProvider.autoDispose.family<bool, String /*channelKey*/>  // realtimePollingFallbackProvider
```

A migrated provider then:
```dart
final pollFallback = ref.watch(realtimePollingFallbackProvider(inboxRealtimeChannelKey(uid)));
if (pollFallback.value == true) {
  final t = Timer.periodic(const Duration(seconds: 30), (_) => /* refresh */);
  ref.onDispose(t.cancel);
}
```
- Trigger: channel `errored` for **≥60 s** (existing `kRealtimeFallbackErroredGrace`)
  — brief reconnect blips don't flap into polling.
- Cadence: **30 s** foreground (not the old 1–5 s). Anon spectator keeps **10 s**
  (no CDC fallback for anon today).
- Kill-switch: keep `realtimeEnabledFlagProvider` (incident response + spectator
  "Live-Modus aus"). When off → always poll.
- The boolean gate guarantees **exactly one** active path; polling never runs
  concurrently with a healthy channel; cancels immediately on reconnect.

---

## 4. Per-feature migration roadmap

| Feature (today) | Mechanism | Subscribe to | Server-side change | Order / priority |
|---|---|---|---|---|
| **Inbox** (1 s poll) | **CDC** | `user_inbox_messages` `eq user_id=<uid>` | Hosted: publication membership + REPLICA IDENTITY. **No new trigger** (writes already exist). | **1 — quick win + foundational** |
| **Tournament match / bracket / standings** (5 s) | **CDC (already primary)** | existing per-tournament channel | none | **2 — quick win (gating cleanup)** |
| **Friends** (1 s poll) | **Inbox-driven** | (rides inbox CDC) | RPC already writes inbox on friend-accept; ensure relevant `kind` set | **3 — quick win, zero new channels** |
| **Tournament detail** (5 s) | **CDC** | `tournaments` `eq id=<tid>` | Hosted publication; verify participant SELECT RLS exists | **4 — medium (latency-critical go-live)** |
| **Teams detail** (4 s) | **CDC** | `team_memberships` `eq team_id=<tid>` (+`teams` `eq id` for header) | Hosted publication; member-read RLS exists (`20260615000001`) | **5 — medium** |
| **Teams list** (4 s) | **Inbox-driven** | (rides inbox CDC) | team-invitation-accepted already writes inbox (`20260901000011`) | **5 — medium** |
| **Tournament list** (5 s) | **Inbox-driven + poll fallback** | (rides inbox go-live event) | none new | **4 — medium** |
| **Match live detail** (1 s) | **CDC** | `<match table>` `eq match_id`, stop on terminal status | Hosted publication | **after 1–5, opportunistic** |
| **Training cloud sessions** (on-demand) | **CDC** | `training_sessions` `eq user_id=<uid>` | Hosted publication; clean RLS exists (`20260901000007`) | **6 — low / opportunistic** |
| **Public spectator** (10 s when live-off) | **Broadcast — DONE** | existing topic | none | — (reference pattern) |
| **Achievements / seasons** | **none / inbox** | — | optional inbox push on unlock | — |

### 4.1 Polling to be REMOVED explicitly
Delete these `Timer.periodic` sentinels:
- `inboxPollingProvider` (`inbox_controller.dart:39`)
- `friendsPollingProvider` (`social_providers.dart:26`)
- `teamListPollingProvider`, `teamDetailPollingProvider` (`team_providers.dart:19–37`)
- `matchPollingProvider` (`match_providers.dart:42`)
- `tournamentListPollingProvider`, `tournamentDetailPollingProvider`
  (`tournament_list_provider.dart:55–87`)
- `tournamentBracketPollingProvider`, `tournamentPoolStandingsPollingProvider`
  (`tournament_bracket_provider.dart:24–58`) — convert to fallback-gated, not
  unconditional
- `tournamentMatchPollingProvider`, `tournamentMatchListPollingProvider`
  (`tournament_match_providers.dart`) — already fallback-only; finish gating

### 4.2 Keep as polling (NOT a messaging concern — leave as-is)
- **Outbox pending (2 s)** — local Drift read, no radio; Drift DAO lacks reactive
  `watch()` for the non-`Selectable` `pending()` query (ADR-0022).
- **Offline-banner label (60 s)** — UI timestamp aging.
- **Match countdown (1 s)** / **auth restore cooldown (1 s)** — UI tickers, no network.

### 4.3 Filterability caveats (why some lists go inbox-driven, not CDC)
- **Friendships** has composite PK `(low_user_id, high_user_id)` and **no single
  `user_id` column** → cannot be expressed as one `eq` filter with the current
  port. Route through the inbox CDC event instead. (True CDC would need a
  denormalised `friendship_events(user_id, …)` fan-out table — only if inbox
  proves insufficient.)
- **My-teams / my-tournaments lists** likewise have no single-column user scope →
  drive invalidation off inbox events, keep poll as fallback. Don't force CDC.
- **Membership-grants-visibility edge case (teams):** a member being *added* sees
  their first CDC event only after the membership row granting read exists — fine
  for the common roster-change case.

---

## 5. Battery + lifecycle strategy

### 5.1 Three radio regimes
| App state | Transport | Who wakes radio | Target |
|---|---|---|---|
| Foreground / resumed | ONE multiplexed WebSocket, N channels | server push over live socket | instant (<1 s), socket already open |
| Inactive (transient) | keep socket, no-op | — | avoid teardown/reconnect thrash |
| Background / paused / detached / closed | OS push (future), **socket torn down** | OS push service (not our radio) | out-of-app wake, ~0 idle drain |

**Hard rule:** nothing holds the radio open while paused. Foreground = exactly one
WebSocket. Background = zero sockets + zero timers; push is the only background
wake. Per-second polling is **deleted**, not merely paused.

### 5.2 Foreground channel families (all over the one socket)
- `user_inbox_messages:user_id=<uid>` — CDC, shell-level. **Replaces the 1 s
  inbox poll AND 1 s friends poll AND 4 s team-list poll** because all those
  events already land as inbox rows.
- `tournament_matches:tournament_id=<tid>` — existing CDC, unchanged (ADR-0021).
- `public_tournament_events:<tid>` — existing anon Broadcast, unchanged.

### 5.3 Lifecycle = §3.4 (resume reconnect / 5 s pause-teardown / detached teardown).
### 5.4 Fallback = §3.5 (≥60 s errored → 30 s cadence; 10 s anon; kill-switch).
The only surviving timers are the cosmetic UI tickers in §4.2 — no radio wake-ups.

---

## 6. Push-notifications integration point (future, designed-for now)

The Inbox row is the **single seam** feeding both in-app realtime and future push.

### 6.1 The one fan-out hook
Add **one `AFTER INSERT` trigger on `public.user_inbox_messages`** (same proven
pattern as `20260601000031`):

```
AFTER INSERT on user_inbox_messages
   ├── (now, optional) realtime.send(curated nudge) on private topic user_inbox:<user_id>
   │      → low-latency in-app nudge (CDC remains the primary in-app feed)
   └── (later) enqueue a push job into push_outbox (device-token lookup → FCM/APNs)
          → wakes the device when backgrounded/closed
```

- **One write, two wakes.** Same INSERT feeds both → guaranteed parity between
  foreground realtime and background push. Build the trigger now with the push
  branch a clearly-marked stub (no-op `PERFORM` into a future `push_outbox`, or a
  `-- TODO push` block). **No mutation RPC changes** — every producer already
  writes here.
- **Curated payload, no PII.** Emit `id, kind, subject, sent_at` only (enough for
  a badge + toast); the client reads the full row RLS-gated via `refreshFromRemote`.
- **CDC vs Broadcast for inbox:** the **in-app** feed is **CDC** (auto RLS-gated to
  owner, no per-user topic management). The trigger exists primarily for the
  **push** branch (+ optional low-latency nudge).
- **Idempotency:** rows carry `id` + `sent_at`; drift upsert is keyed on `id`, so a
  realtime nudge racing the CDC row is harmless (upsert collapses duplicates) —
  same philosophy as the outbox Lamport index.

### 6.2 Future drop-in points (sketch, not built now)
1. `public.user_device_tokens (user_id, platform, token, last_seen_at)` — owner-RLS,
   the only net-new table; client registers token on login + refresh.
2. `public.push_outbox (user_id, inbox_message_id, payload, status)` — durable,
   retryable, idempotent; mirrors the outbox pattern (ADR-0022) server-side.
3. Delivery worker — Supabase **Edge Function** on a `push_outbox` webhook/drain:
   look up tokens → call FCM/APNs → mark sent/failed with backoff. Fire-and-forget.
4. Client receipt — `firebase_messaging` handler; payload carries only
   `inbox_message_id` (no PII); on tap/resume the §3.4 path re-opens the inbox
   channel and `refreshFromRemote` reconciles.

Turning push on later = "implement the Edge Function + token table" with **zero
RPC changes**. `pubspec.yaml` has no FCM today — that's the one net-new dependency.

---

## 7. Testing, rollout, risks

### 7.1 Testing
- **Domain/port:** add a `FakeBroadcastChannel` mirroring `fake_realtime_channel.dart`;
  drive the shared refcount/debounce/backoff mixin with deterministic fakes.
- **Provider:** for each migrated provider, test (a) realtime event → stream
  re-emits; (b) `onDispose` cancels sub + closes channel via refcount; (c)
  fallback flips to 30 s polling after 60 s errored and cancels on rejoin.
- **Lifecycle:** unit-test `RealtimeLifecycleController` for resume-after-resign
  ordering, 5 s pause debounce, inactive no-op, detached immediate teardown,
  snapshot rehydrate.
- **Migration (SQL):** verify CDC each target table — hosted publication +
  REPLICA IDENTITY + RLS SELECT policy authorises the single-column filter.
- Keep existing tournament realtime + inbox repository tests green throughout.

### 7.2 Rollout (sequenced, lowest-risk first)
1. **Inbox CDC** + delete inbox poll (drift path unchanged → smallest blast radius).
2. **Finish tournament match/bracket/standings fallback-gating** (no server work).
3. **Friends → inbox-driven** invalidation; delete friends poll.
4. **Generalise `realtimePollingFallbackProvider`** to all families; 30 s cadence;
   delete remaining 5 s tournament polls.
5. **Lifecycle controller** (resume reconnect / pause teardown) + pause
   `KeypairSessionRefresher`.
6. **`user_inbox_messages` AFTER-INSERT fan-out trigger** with push branch stubbed.
7. **Tournament detail CDC**, then **teams detail CDC + team-list-via-inbox**.
8. **Training CDC** (opportunistic). **Push** (deferred): token table + push_outbox
   + Edge Function.

Use `realtimeEnabledFlagProvider` as the rollout/incident kill-switch — flip any
feature back to polling instantly without a deploy.

### 7.3 Risks
- **Hosted-vs-local publication gap (highest).** Local Supabase publishes
  `FOR ALL TABLES`, so CDC "just works" in dev and can **silently fail in prod**.
  Mitigation: every CDC target ships an explicit
  `ALTER PUBLICATION supabase_realtime ADD TABLE …` (+ `REPLICA IDENTITY FULL` where
  old-row columns are needed) migration; verify on staging before relying on it.
- **Missing/incorrect participant RLS** on `tournaments` (spectator path uses an
  RPC, not direct select). Confirm an authenticated-participant SELECT policy
  before CDC-ing tournament detail; otherwise the channel joins but delivers no rows.
- **Resume JWT ordering.** Re-sign must complete before resubscribe or channels
  hit join→401→backoff. Enforced in §3.4.
- **Background teardown debounce.** Too short → thrash on notification-shade
  glances; too long → idle radio. 5 s is the chosen balance; tune on-device.
- **List filterability** (friendships / my-teams / my-tournaments). Handled by
  inbox-driven invalidation, not forced CDC (§4.3).

---

## 8. Open questions for the user

1. **Push timing** — build the `user_inbox_messages` fan-out trigger (with push
   branch stubbed) now in this work, or defer the whole trigger until push is
   actually prioritised?
2. **Background teardown debounce** — is **5 s** acceptable, or do you want a
   shorter/longer pause-before-disconnect?
3. **Fallback cadence** — confirm **30 s** foreground fallback (vs the old 1–5 s);
   keep anon spectator at **10 s**?
4. **Friends transport** — accept inbox-driven invalidation (zero new channels),
   or invest later in a denormalised `friendship_events` fan-out table for true CDC?
5. **Tournament/team LIST views** — accept inbox-driven + poll-fallback, or is a
   per-user denormalised list table worth the server cost?
6. **ADR number** — confirm **0029-unified-messaging-and-battery-lifecycle**
   (0027/0028 are taken); should it formally supersede/extend ADR-0021?
7. **Branch** — which feature branch should the implementation sprints land on?

---

## 9. Entscheidungen (User, 2026-06-06)

1. **Push-Trigger jetzt bauen.** Der `user_inbox_messages` AFTER-INSERT-Fan-out-
   Trigger wird **früh** auf `feat/realtime-sync` gebaut, mit **gestubbtem
   Push-Branch** (läuft vorerst ins Leere / no-op), damit die spätere
   FCM/APNs-Schicht nur noch andockt und keine Nachrüstung der DB nötig ist.
3. **Fallback-Kadenz = 30 s** (Foreground) bestätigt; anon-Spectator 10 s.
4. **Echtes CDC überall** für authentifizierten Per-User-State (gewünscht).
   Konsequenz:
   - Teams- und Tournament-**Listen** → CDC direkt auf der Mitglieds-/
     Teilnehmer-Tabelle, gefiltert über die Single-Column `user_id`
     (`team_memberships.user_id` / `tournament_participants.user_id`). Funktioniert
     ohne Sonderbau.
   - **Freunde** sind die **eine Ausnahme**: `friendships` ist kanonisch
     low/high-gekeyt → Realtime kann nur auf *einer* Spalte `=` filtern, also
     kein „meine Freunde"-CDC direkt. Dafür kommt eine **denormalisierte
     `friend_edges(owner_user_id, friend_user_id, status)`-Tabelle** (per Trigger
     gepflegt), CDC-gefiltert auf `owner_user_id`.
   - **Anon-Spectator bleibt Broadcast** — das ist eine *Constraint*, keine Wahl
     (CDC würde den Zeilensatz an anon leaken, kein Per-Row-RLS für anon; ADR-0026).
   - **Durable Notifications bleiben Inbox-CDC** (`user_inbox_messages`).
5. **Mehr Server-Aufwand für sauberes CDC akzeptiert.** Die denormalisierten
   Per-User-Tabellen (friend_edges; ggf. listen-spezifisch) werden via Trigger
   gepflegt — Last ist minimal (wenige Trigger-Writes pro Mitgliedschafts-/
   Freundschaftsänderung), dafür echtes CDC statt inbox-getriebener Umweg.
7. **Branch `feat/realtime-sync`** angelegt — hier landen die Sprints.

Zusätzlich bestätigt:
- (2) **Background-Teardown-Debounce = 5 s.** ✓
- (4) **Anon-Zuschauer bleiben** (öffentliche Live-Links ohne Login). Damit
  bleibt **Broadcast** der Pflicht-Transport für den anon-Spectator-Pfad; alle
  authentifizierten Per-User-Daten laufen auf **CDC** (+ `friend_edges` für
  Freunde). Der `public/`-Bereich bleibt bestehen.
- (6) **ADR-0029-unified-messaging-and-battery-lifecycle** bestätigt; sie
  **erweitert** ADR-0021 (ersetzt es nicht).

Alle 7 Entscheidungen sind damit final.

---

## Key files (absolute paths)

- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/lib/core/data/realtime/supabase_realtime_channel.dart` — CDC adapter to reuse; add shared lifecycle mixin + pause/resume snapshot.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/packages/kubb_domain/lib/src/ports/realtime_channel.dart` — CDC port; add sibling `broadcast_channel.dart`.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/packages/kubb_domain/lib/src/values/realtime_change.dart` — `RealtimeChannelState`/`RealtimeChange`/`RealtimeEventType` to reuse.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/lib/features/tournament/application/realtime_fallback_provider.dart` — `realtimeChannelProvider`, `realtimeEnabledFlagProvider`, `tournamentRealtimeChannelKey`, the fallback to generalise.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/lib/features/tournament/data/public_tournament_realtime.dart` — Broadcast impl to lift behind the new port.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/lib/features/inbox/application/inbox_controller.dart` — drift-cache + realtime provider reference; delete `inboxPollingProvider`.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/lib/features/inbox/data/inbox_repository.dart` — `refreshFromRemote` / drift mirror is the read path CDC drives.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/lib/app/app.dart` — extend existing `AppLifecycleListener` (resume reconnect / pause teardown).
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/lib/features/auth/application/keypair_session_refresher.dart` — pause on `paused`, resume on `resumed`.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/supabase/migrations/20260601000031_public_tournament_realtime.sql` — template for the new `user_inbox_messages` AFTER-INSERT fan-out trigger.
- `/home/lukas/Workbench/FlutterKubbClub/KubbProj/supabase/migrations/20260504000011_mnemonic_admin_inbox.sql` — inbox table + owner-read RLS; CDC target.
