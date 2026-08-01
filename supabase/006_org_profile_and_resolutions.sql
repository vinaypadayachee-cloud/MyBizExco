-- ============================================================================
-- MyBizExco — Org profile fields + structured resolutions table
-- ============================================================================
-- Part of the persistence cutover pass. Two additions, per user decision:
--
-- 1. organisations was missing columns for several fields the setup wizard
--    already captures (quorum veto rules, company size band, revenue band,
--    financial context, incorporation date, CEO name, province, additional
--    regulator). Without these, hydrating a signed-in user's profile back
--    from the server is impossible -- calcGovRem() in particular depends on
--    incorporation_date for the CIPC governance-calendar feature.
--
-- 2. Resolutions previously had no table of their own -- they only existed
--    baked into meeting_minutes_versions.content as free text. govScore(),
--    buildAudit(), and hydration all need a structured source instead of
--    parsing prose out of a minutes document.
-- ============================================================================

alter table organisations
  add column if not exists ceo_name             text,
  add column if not exists company_size         text,
  add column if not exists province             text,
  add column if not exists revenue_band         text,
  add column if not exists financial_context    text,
  add column if not exists additional_regulator text,
  add column if not exists incorporation_date   date,
  add column if not exists quorum_cfo_veto       boolean not null default true,
  add column if not exists quorum_cro_veto       boolean not null default true,
  add column if not exists quorum_cto_veto       boolean not null default false,
  add column if not exists quorum_majority       boolean not null default true;

create table resolutions (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    meeting_id        uuid not null references meetings(id) on delete cascade,
    resolution_text   text not null,
    quorum_reason     text,
    passed_at         timestamptz not null default now()
);

-- RLS: same read/write shape as every other org-scoped governance table
-- (org_members-derived visibility, management-role writes), using the
-- existing SECURITY DEFINER helper functions from 003_fix_rls_recursion.sql.
alter table resolutions enable row level security;

create policy "resolutions_select_member"
  on resolutions for select
  using (organisation_id in (select auth_user_org_ids()));

create policy "resolutions_insert_management"
  on resolutions for insert
  with check (organisation_id in (select auth_user_management_org_ids()));

-- ============================================================================
-- END
-- ============================================================================
