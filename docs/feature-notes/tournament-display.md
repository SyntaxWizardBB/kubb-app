# Feature note: Tournament display & schedule

Captured 2026-05-02 during the Lamport-clock ADR discussion. Lukas described requirements for how a player sees their tournament day. Belongs in M2 (Tournament-Setup) or as its own feature after.

## Player-facing match view

Every player should always see in the app:

- **Current match**: opponent (team), playing field, scheduled time
- **Match status**: upcoming / playing now / finished
- **Pause until next match**: how long until the next scheduled match, displayed as a countdown or interval

When the current match has finished and results are entered, the view should switch to "Pause" mode showing the time until the next scheduled match.

## Organizer-side scheduling

The organizer can:

- View the full match plan for the tournament day
- Reschedule matches (move start times, swap fields, insert/extend pauses)
- Changes propagate to all affected players' views in real time (via Supabase Realtime)

Implication: the match schedule is mutable state during a tournament, distinct from match results which are immutable once finalized.

## Push notifications

Players should be notified at:

- **Match starting soon** (e.g., 5 min before scheduled start)
- **Match start** (when their match is called)
- **Match end** (after both teams have entered the result and it is confirmed or the dispute is resolved)
- **Schedule changes** affecting their next match

Tech note: Supabase does not natively send push notifications. Will need either Firebase Cloud Messaging (FCM) on Android, APNs on iOS, or a third-party service. Web push is a separate stack. To be decided in the feature ADR for notifications.

## Open questions for when this feature is planned

- What happens if a player misses a match start (no-show window)? Is there a forfeit-by-timeout rule, or does the organizer manually decide?
- Is the schedule view player-only (showing just their matches) or full-tournament (showing all matches with the player's highlighted)?
- Push notification opt-in/opt-out per category, or all-or-nothing?
