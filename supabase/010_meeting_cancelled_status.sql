-- Adds 'cancelled' to meetings.status. A cancelled meeting is never
-- deleted -- its actions/ai_deliberation_log rows have no cascade-delete
-- FK and are part of the governance audit trail, so the record and its
-- children are preserved, just marked cancelled instead of closed.

ALTER TABLE meetings DROP CONSTRAINT meetings_status_check;
ALTER TABLE meetings ADD CONSTRAINT meetings_status_check
  CHECK (status IN ('draft', 'open', 'closed', 'cancelled'));
