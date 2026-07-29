-- ============================================================================
-- MyBizExco — Row Level Security Policies
-- Phase 1b: replaces the commented-out stub in 001 (schema migration).
-- NOT YET APPLIED to the live project — under review.
-- ============================================================================
-- Design summary (see chat for full reasoning):
--   - Read access to org-scoped tables: any ACTIVE org_members row for that
--     organisation_id, regardless of role.
--   - Write access to operational tables: role in ('owner','exco_member').
--   - Membership management (org_members insert/update) and organisations
--     UPDATE: 'owner' only.
--   - Append-only / audit-trail tables (meeting_minutes_versions,
--     ai_deliberation_log, governance_scores, communications_log,
--     leadership_change_log): insert-only, no update/delete via RLS, except
--     meeting_minutes_versions which allows UPDATE only while status='draft'.
--   - profiles: self, or anyone sharing an active org with you, can SELECT;
--     only self can UPDATE; self can INSERT own row once (post-signup).
--   - country_config / compliance_frameworks: public reference data — RLS
--     enabled with an explicit open-read policy rather than left disabled.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Enable RLS on the tables missing from the original stub list
-- ----------------------------------------------------------------------------
alter table profiles enable row level security;
alter table business_priorities enable row level security;
alter table leadership_change_log enable row level security;
alter table meeting_attendees enable row level security;
alter table distribution_list_members enable row level security;
alter table country_config enable row level security;
alter table compliance_frameworks enable row level security;

-- ----------------------------------------------------------------------------
-- Helper predicate used throughout (inlined per-policy below, no function
-- needed to avoid recursive-RLS pitfalls on org_members itself):
--   organisation_id in (
--     select organisation_id from org_members
--     where profile_id = auth.uid() and is_active = true
--   )
-- ----------------------------------------------------------------------------

-- ============================================================================
-- 1. PROFILES
-- ============================================================================
create policy "profiles_select_self_or_org_colleagues"
  on profiles for select
  using (
    id = auth.uid()
    or id in (
      select om2.profile_id
      from org_members om1
      join org_members om2 on om1.organisation_id = om2.organisation_id
      where om1.profile_id = auth.uid() and om1.is_active = true and om2.is_active = true
    )
  );

create policy "profiles_insert_own"
  on profiles for insert
  with check (id = auth.uid());

create policy "profiles_update_own"
  on profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- ============================================================================
-- 2. ORGANISATIONS
-- ============================================================================
create policy "organisations_select_member"
  on organisations for select
  using (
    id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

-- Any authenticated user may create a new organisation (self-serve signup).
-- Ownership is established by the paired org_members insert below, not here.
create policy "organisations_insert_authenticated"
  on organisations for insert
  to authenticated
  with check (true);

create policy "organisations_update_owner"
  on organisations for update
  using (
    id in (select organisation_id from org_members where profile_id = auth.uid() and role = 'owner' and is_active = true)
  )
  with check (
    id in (select organisation_id from org_members where profile_id = auth.uid() and role = 'owner' and is_active = true)
  );

-- No delete policy: tenant deletion is deliberately not exposed via RLS.

-- ============================================================================
-- 3. ORG_MEMBERS
-- ============================================================================
create policy "org_members_select_same_org"
  on org_members for select
  using (
    organisation_id in (select organisation_id from org_members om2 where om2.profile_id = auth.uid() and om2.is_active = true)
  );

-- Bootstrap: allow inserting yourself as owner of a brand-new (memberless) org,
-- OR allow an existing active owner to add anyone to their org.
create policy "org_members_insert_bootstrap_or_owner"
  on org_members for insert
  with check (
    (
      role = 'owner'
      and profile_id = auth.uid()
      and not exists (select 1 from org_members existing where existing.organisation_id = org_members.organisation_id)
    )
    or exists (
      select 1 from org_members owner_row
      where owner_row.organisation_id = org_members.organisation_id
        and owner_row.profile_id = auth.uid()
        and owner_row.role = 'owner'
        and owner_row.is_active = true
    )
  );

-- Only an existing active owner can change roles / deactivate members
-- (soft-remove via is_active=false + removed_at, per the schema's own design
-- — no delete policy needed).
create policy "org_members_update_owner_only"
  on org_members for update
  using (
    organisation_id in (select organisation_id from org_members om2 where om2.profile_id = auth.uid() and om2.role = 'owner' and om2.is_active = true)
  )
  with check (
    organisation_id in (select organisation_id from org_members om2 where om2.profile_id = auth.uid() and om2.role = 'owner' and om2.is_active = true)
  );

-- ============================================================================
-- 4. LEADERSHIP_CHANGE_LOG (insert-only audit trail)
-- ============================================================================
create policy "leadership_log_select_management"
  on leadership_change_log for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

create policy "leadership_log_insert_owner"
  on leadership_change_log for insert
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role = 'owner' and is_active = true)
  );

-- ============================================================================
-- 5. BUSINESS_PRIORITIES
-- ============================================================================
create policy "priorities_select_member"
  on business_priorities for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "priorities_write_management"
  on business_priorities for all
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  )
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

-- ============================================================================
-- 6. MEETINGS
-- ============================================================================
create policy "meetings_select_member"
  on meetings for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "meetings_write_management"
  on meetings for all
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  )
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

-- ============================================================================
-- 7. MEETING_ATTENDEES (scoped via parent meeting's organisation_id)
-- ============================================================================
create policy "attendees_select_member"
  on meeting_attendees for select
  using (
    meeting_id in (
      select m.id from meetings m
      join org_members om on om.organisation_id = m.organisation_id
      where om.profile_id = auth.uid() and om.is_active = true
    )
  );

create policy "attendees_write_management"
  on meeting_attendees for all
  using (
    meeting_id in (
      select m.id from meetings m
      join org_members om on om.organisation_id = m.organisation_id
      where om.profile_id = auth.uid() and om.role in ('owner','exco_member') and om.is_active = true
    )
  )
  with check (
    meeting_id in (
      select m.id from meetings m
      join org_members om on om.organisation_id = m.organisation_id
      where om.profile_id = auth.uid() and om.role in ('owner','exco_member') and om.is_active = true
    )
  );

-- ============================================================================
-- 8. MEETING_MINUTES_VERSIONS (append-only; confirmed versions are immutable)
-- ============================================================================
create policy "minutes_select_member"
  on meeting_minutes_versions for select
  using (
    meeting_id in (
      select m.id from meetings m
      join org_members om on om.organisation_id = m.organisation_id
      where om.profile_id = auth.uid() and om.is_active = true
    )
  );

create policy "minutes_insert_management"
  on meeting_minutes_versions for insert
  with check (
    meeting_id in (
      select m.id from meetings m
      join org_members om on om.organisation_id = m.organisation_id
      where om.profile_id = auth.uid() and om.role in ('owner','exco_member') and om.is_active = true
    )
  );

-- UPDATE only permitted while the existing row is still a draft — once
-- confirmed, no policy matches and the row becomes immutable.
create policy "minutes_update_draft_only"
  on meeting_minutes_versions for update
  using (
    status = 'draft'
    and meeting_id in (
      select m.id from meetings m
      join org_members om on om.organisation_id = m.organisation_id
      where om.profile_id = auth.uid() and om.role in ('owner','exco_member') and om.is_active = true
    )
  )
  with check (
    meeting_id in (
      select m.id from meetings m
      join org_members om on om.organisation_id = m.organisation_id
      where om.profile_id = auth.uid() and om.role in ('owner','exco_member') and om.is_active = true
    )
  );

-- No delete policy: minutes versions are permanent once created.

-- ============================================================================
-- 9. ACTIONS
-- ============================================================================
create policy "actions_select_member"
  on actions for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "actions_write_management"
  on actions for all
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  )
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

-- ============================================================================
-- 10. DOCUMENTS
-- ============================================================================
create policy "documents_select_member"
  on documents for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "documents_insert_management"
  on documents for insert
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

create policy "documents_delete_management"
  on documents for delete
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

-- No update policy: documents are immutable once uploaded (re-upload instead).

-- ============================================================================
-- 11. GOVERNANCE_SCORES (append-only snapshots)
-- ============================================================================
create policy "governance_scores_select_member"
  on governance_scores for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "governance_scores_insert_management"
  on governance_scores for insert
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

-- No update/delete policy: score snapshots are permanent history.

-- ============================================================================
-- 12. COMPLIANCE_FRAMEWORKS & COUNTRY_CONFIG (public reference data)
-- ============================================================================
create policy "compliance_frameworks_read_all"
  on compliance_frameworks for select
  using (true);

create policy "country_config_read_all"
  on country_config for select
  using (true);

-- Intentionally no insert/update/delete policies for either — reference data
-- is maintained by the platform team via the Supabase dashboard/service role,
-- not by end users through the app.

-- ============================================================================
-- 13. ORGANISATION_COMPLIANCE_STATUS
-- ============================================================================
create policy "org_compliance_select_member"
  on organisation_compliance_status for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "org_compliance_write_management"
  on organisation_compliance_status for all
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  )
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

-- ============================================================================
-- 14. DISTRIBUTION_LISTS & DISTRIBUTION_LIST_MEMBERS
-- ============================================================================
create policy "dist_lists_select_member"
  on distribution_lists for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "dist_lists_write_management"
  on distribution_lists for all
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  )
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

create policy "dist_list_members_select_member"
  on distribution_list_members for select
  using (
    distribution_list_id in (
      select dl.id from distribution_lists dl
      join org_members om on om.organisation_id = dl.organisation_id
      where om.profile_id = auth.uid() and om.is_active = true
    )
  );

create policy "dist_list_members_write_management"
  on distribution_list_members for all
  using (
    distribution_list_id in (
      select dl.id from distribution_lists dl
      join org_members om on om.organisation_id = dl.organisation_id
      where om.profile_id = auth.uid() and om.role in ('owner','exco_member') and om.is_active = true
    )
  )
  with check (
    distribution_list_id in (
      select dl.id from distribution_lists dl
      join org_members om on om.organisation_id = dl.organisation_id
      where om.profile_id = auth.uid() and om.role in ('owner','exco_member') and om.is_active = true
    )
  );

-- ============================================================================
-- 15. COMMUNICATIONS_LOG (insert-only audit trail)
-- ============================================================================
create policy "comms_log_select_member"
  on communications_log for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "comms_log_insert_management"
  on communications_log for insert
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

-- No update/delete policy: log is permanent.

-- ============================================================================
-- 16. AI_DELIBERATION_LOG (insert-only audit trail, FAIS/FSCA defensibility)
-- ============================================================================
create policy "ai_log_select_member"
  on ai_deliberation_log for select
  using (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and is_active = true)
  );

create policy "ai_log_insert_management"
  on ai_deliberation_log for insert
  with check (
    organisation_id in (select organisation_id from org_members where profile_id = auth.uid() and role in ('owner','exco_member') and is_active = true)
  );

-- No update/delete policy: log is permanent, matching its defensibility purpose.

-- ============================================================================
-- END — NOT YET APPLIED. Awaiting review.
-- ============================================================================
