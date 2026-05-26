-- ----------------------------------------------------------------------
-- M3.1-T6: Inbox-Item-Type extension for team flows.
--
-- Extends the `kind` CHECK constraint on `public.user_inbox_messages`
-- with three new top-level kinds used by team RPCs (T4/T5):
--   * `team_invitation`       — invitee receives this when a team member
--                                invites them into a pool (FR-TEAM-12).
--   * `team_member_removed`   — fan-out notification to every remaining
--                                pool member when a teammate is removed
--                                (FR-TEAM-13, OD-M3-01).
--   * `team_dissolved`        — sent to the last registered member when
--                                a team is auto-dissolved (FR-TEAM-19).
--
-- The previous CHECK only allowed `notice`, `verification_request`,
-- `system`. Team RPCs need first-class kinds so the client can route
-- them via `InboxMessageKind` instead of inspecting `action_payload`.
-- ----------------------------------------------------------------------

ALTER TABLE public.user_inbox_messages
  DROP CONSTRAINT IF EXISTS user_inbox_messages_kind_check;

ALTER TABLE public.user_inbox_messages
  ADD CONSTRAINT user_inbox_messages_kind_check
    CHECK (kind IN (
      'notice',
      'verification_request',
      'system',
      'team_invitation',
      'team_member_removed',
      'team_dissolved'
    ));
