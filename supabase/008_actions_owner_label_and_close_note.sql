-- ============================================================================
-- MyBizExco — actions.owner_label + actions.close_note
-- ============================================================================
-- assigned_to (existing) is a structured FK to org_members(id) -- only
-- usable once a person is a real, invited platform user. Today, almost every
-- action's "owner" is a free-text role or name (a manually typed value, or
-- S.exco[0]?.dn), since the invite flow doesn't exist yet (same root cause
-- as meeting_attendees/leadership_change_log being deferred). owner_label is
-- that free-text fallback -- not a duplicate of assigned_to, but the field
-- actually in use until real member assignment is possible.
--
-- close_note: the note captured when an action is closed (closeAction()'s
-- prompt, or the AI-drafted closure text from aiAction()). No prior column.
-- ============================================================================

alter table actions
  add column if not exists owner_label text,
  add column if not exists close_note  text;

-- ============================================================================
-- END
-- ============================================================================
