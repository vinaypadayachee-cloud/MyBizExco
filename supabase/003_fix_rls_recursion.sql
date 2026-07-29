-- ============================================================================
-- MyBizExco — Fix RLS infinite recursion from 002_rls_policies.sql
-- ============================================================================
-- 002 caused "infinite recursion detected in policy for relation
-- org_members" (Postgres 42P17) on every table that references org_members
-- (i.e. nearly all of them), because org_members' own policy queried
-- org_members from within an org_members policy — a self-referential RLS
-- evaluation cycle that cascades to every other table's policy too, since
-- they all subquery org_members.
--
-- Fix: SECURITY DEFINER helper functions that look up org membership with
-- RLS bypassed internally. Safe by construction — each function hardcodes
-- auth.uid() as the filter, so it can only ever return the calling user's
-- own membership data, never anyone else's, regardless of who calls it.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Drop every policy from 002 that references org_members, directly or
--    transitively (i.e. all of them except the two reference-table policies,
--    which never touched org_members and are not recursive).
-- ----------------------------------------------------------------------------
drop policy if exists "profiles_select_self_or_org_colleagues" on profiles;
drop policy if exists "profiles_insert_own" on profiles;
drop policy if exists "profiles_update_own" on profiles;
drop policy if exists "organisations_select_member" on organisations;
drop policy if exists "organisations_insert_authenticated" on organisations;
drop policy if exists "organisations_update_owner" on organisations;
drop policy if exists "org_members_select_same_org" on org_members;
drop policy if exists "org_members_insert_bootstrap_or_owner" on org_members;
drop policy if exists "org_members_update_owner_only" on org_members;
drop policy if exists "leadership_log_select_management" on leadership_change_log;
drop policy if exists "leadership_log_insert_owner" on leadership_change_log;
drop policy if exists "priorities_select_member" on business_priorities;
drop policy if exists "priorities_write_management" on business_priorities;
drop policy if exists "meetings_select_member" on meetings;
drop policy if exists "meetings_write_management" on meetings;
drop policy if exists "attendees_select_member" on meeting_attendees;
drop policy if exists "attendees_write_management" on meeting_attendees;
drop policy if exists "minutes_select_member" on meeting_minutes_versions;
drop policy if exists "minutes_insert_management" on meeting_minutes_versions;
drop policy if exists "minutes_update_draft_only" on meeting_minutes_versions;
drop policy if exists "actions_select_member" on actions;
drop policy if exists "actions_write_management" on actions;
drop policy if exists "documents_select_member" on documents;
drop policy if exists "documents_insert_management" on documents;
drop policy if exists "documents_delete_management" on documents;
drop policy if exists "governance_scores_select_member" on governance_scores;
drop policy if exists "governance_scores_insert_management" on governance_scores;
drop policy if exists "org_compliance_select_member" on organisation_compliance_status;
drop policy if exists "org_compliance_write_management" on organisation_compliance_status;
drop policy if exists "dist_lists_select_member" on distribution_lists;
drop policy if exists "dist_lists_write_management" on distribution_lists;
drop policy if exists "dist_list_members_select_member" on distribution_list_members;
drop policy if exists "dist_list_members_write_management" on distribution_list_members;
drop policy if exists "comms_log_select_member" on communications_log;
drop policy if exists "comms_log_insert_management" on communications_log;
drop policy if exists "ai_log_select_member" on ai_deliberation_log;
drop policy if exists "ai_log_insert_management" on ai_deliberation_log;
-- compliance_frameworks_read_all and country_config_read_all are untouched.

-- ----------------------------------------------------------------------------
-- 1. SECURITY DEFINER helper functions
-- ----------------------------------------------------------------------------
create or replace function auth_user_org_ids()
returns setof uuid
language sql
security definer
stable
set search_path = public
as $$
  select organisation_id from org_members
  where profile_id = auth.uid() and is_active = true
$$;

create or replace function auth_user_management_org_ids()
returns setof uuid
language sql
security definer
stable
set search_path = public
as $$
  select organisation_id from org_members
  where profile_id = auth.uid() and is_active = true and role in ('owner','exco_member')
$$;

create or replace function is_org_owner(target_org_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from org_members
    where organisation_id = target_org_id and profile_id = auth.uid() and role = 'owner' and is_active = true
  )
$$;

create or replace function org_has_any_members(target_org_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from org_members where organisation_id = target_org_id)
$$;

grant execute on function auth_user_org_ids() to authenticated, anon;
grant execute on function auth_user_management_org_ids() to authenticated, anon;
grant execute on function is_org_owner(uuid) to authenticated, anon;
grant execute on function org_has_any_members(uuid) to authenticated, anon;

-- ----------------------------------------------------------------------------
-- 2. Re-create all policies using the helper functions instead of raw
--    self-referential subqueries. Same access rules as 002 throughout —
--    only the recursion-causing mechanics changed.
-- ----------------------------------------------------------------------------

-- PROFILES
create policy "profiles_select_self_or_org_colleagues"
  on profiles for select
  using (
    id = auth.uid()
    or id in (
      select om.profile_id from org_members om
      where om.organisation_id in (select auth_user_org_ids()) and om.is_active = true
    )
  );

create policy "profiles_insert_own"
  on profiles for insert
  with check (id = auth.uid());

create policy "profiles_update_own"
  on profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- ORGANISATIONS
create policy "organisations_select_member"
  on organisations for select
  using (id in (select auth_user_org_ids()));

create policy "organisations_insert_authenticated"
  on organisations for insert
  to authenticated
  with check (true);

create policy "organisations_update_owner"
  on organisations for update
  using (is_org_owner(id))
  with check (is_org_owner(id));

-- ORG_MEMBERS
create policy "org_members_select_same_org"
  on org_members for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "org_members_insert_bootstrap_or_owner"
  on org_members for insert
  with check (
    (role = 'owner' and profile_id = auth.uid() and not org_has_any_members(organisation_id))
    or is_org_owner(organisation_id)
  );

create policy "org_members_update_owner_only"
  on org_members for update
  using (is_org_owner(organisation_id))
  with check (is_org_owner(organisation_id));

-- LEADERSHIP_CHANGE_LOG
create policy "leadership_log_select_management"
  on leadership_change_log for select
  using (organisation_id in (select auth_user_management_org_ids()));

create policy "leadership_log_insert_owner"
  on leadership_change_log for insert
  with check (is_org_owner(organisation_id));

-- BUSINESS_PRIORITIES
create policy "priorities_select_member"
  on business_priorities for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "priorities_write_management"
  on business_priorities for all
  using (organisation_id in (select auth_user_management_org_ids()))
  with check (organisation_id in (select auth_user_management_org_ids()));

-- MEETINGS
create policy "meetings_select_member"
  on meetings for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "meetings_write_management"
  on meetings for all
  using (organisation_id in (select auth_user_management_org_ids()))
  with check (organisation_id in (select auth_user_management_org_ids()));

-- MEETING_ATTENDEES
create policy "attendees_select_member"
  on meeting_attendees for select
  using (
    meeting_id in (select m.id from meetings m where m.organisation_id in (select auth_user_org_ids()))
  );

create policy "attendees_write_management"
  on meeting_attendees for all
  using (
    meeting_id in (select m.id from meetings m where m.organisation_id in (select auth_user_management_org_ids()))
  )
  with check (
    meeting_id in (select m.id from meetings m where m.organisation_id in (select auth_user_management_org_ids()))
  );

-- MEETING_MINUTES_VERSIONS
create policy "minutes_select_member"
  on meeting_minutes_versions for select
  using (
    meeting_id in (select m.id from meetings m where m.organisation_id in (select auth_user_org_ids()))
  );

create policy "minutes_insert_management"
  on meeting_minutes_versions for insert
  with check (
    meeting_id in (select m.id from meetings m where m.organisation_id in (select auth_user_management_org_ids()))
  );

create policy "minutes_update_draft_only"
  on meeting_minutes_versions for update
  using (
    status = 'draft'
    and meeting_id in (select m.id from meetings m where m.organisation_id in (select auth_user_management_org_ids()))
  )
  with check (
    meeting_id in (select m.id from meetings m where m.organisation_id in (select auth_user_management_org_ids()))
  );

-- ACTIONS
create policy "actions_select_member"
  on actions for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "actions_write_management"
  on actions for all
  using (organisation_id in (select auth_user_management_org_ids()))
  with check (organisation_id in (select auth_user_management_org_ids()));

-- DOCUMENTS
create policy "documents_select_member"
  on documents for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "documents_insert_management"
  on documents for insert
  with check (organisation_id in (select auth_user_management_org_ids()));

create policy "documents_delete_management"
  on documents for delete
  using (organisation_id in (select auth_user_management_org_ids()));

-- GOVERNANCE_SCORES
create policy "governance_scores_select_member"
  on governance_scores for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "governance_scores_insert_management"
  on governance_scores for insert
  with check (organisation_id in (select auth_user_management_org_ids()));

-- ORGANISATION_COMPLIANCE_STATUS
create policy "org_compliance_select_member"
  on organisation_compliance_status for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "org_compliance_write_management"
  on organisation_compliance_status for all
  using (organisation_id in (select auth_user_management_org_ids()))
  with check (organisation_id in (select auth_user_management_org_ids()));

-- DISTRIBUTION_LISTS / DISTRIBUTION_LIST_MEMBERS
create policy "dist_lists_select_member"
  on distribution_lists for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "dist_lists_write_management"
  on distribution_lists for all
  using (organisation_id in (select auth_user_management_org_ids()))
  with check (organisation_id in (select auth_user_management_org_ids()));

create policy "dist_list_members_select_member"
  on distribution_list_members for select
  using (
    distribution_list_id in (select dl.id from distribution_lists dl where dl.organisation_id in (select auth_user_org_ids()))
  );

create policy "dist_list_members_write_management"
  on distribution_list_members for all
  using (
    distribution_list_id in (select dl.id from distribution_lists dl where dl.organisation_id in (select auth_user_management_org_ids()))
  )
  with check (
    distribution_list_id in (select dl.id from distribution_lists dl where dl.organisation_id in (select auth_user_management_org_ids()))
  );

-- COMMUNICATIONS_LOG
create policy "comms_log_select_member"
  on communications_log for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "comms_log_insert_management"
  on communications_log for insert
  with check (organisation_id in (select auth_user_management_org_ids()));

-- AI_DELIBERATION_LOG
create policy "ai_log_select_member"
  on ai_deliberation_log for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "ai_log_insert_management"
  on ai_deliberation_log for insert
  with check (organisation_id in (select auth_user_management_org_ids()));

-- ============================================================================
-- END — supersedes the broken subset of 002_rls_policies.sql
-- ============================================================================
