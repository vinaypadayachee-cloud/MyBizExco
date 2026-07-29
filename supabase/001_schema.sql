-- ============================================================================
-- MyBizExco — Supabase Schema Migration
-- Phase 1: Backend Foundation
-- ============================================================================
-- Notes:
--   - Multi-tenant: every business using MyBizExco is an "organisation".
--   - auth.users (Supabase Auth) is the source of truth for login identity;
--     this schema links to it via profiles.id = auth.users.id.
--   - RLS (Row Level Security) policies are stubbed at the bottom — enable
--     and refine these before any real customer data enters the tables.
--   - country_code + country_config exist from day one so the SA build
--     doesn't need to be rearchitected for Kenya/Ghana/SADC later —
--     expansion is config, not schema change.
--   - Governance trail tables (resolutions, minutes, compliance_items) are
--     designed to be append-only / versioned, not update-in-place, to keep
--     the audit trail defensible for FSCA/FAIS purposes.
-- ============================================================================
-- Already applied to the live project (confirmed via Table Editor). Saved
-- here for reference / reproducibility. The stub RLS section (15) below is
-- superseded by 002_rls_policies.sql.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. EXTENSIONS
-- ----------------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. COUNTRY CONFIGURATION (supports the multi-country expansion thesis)
-- ----------------------------------------------------------------------------
create table country_config (
    country_code        text primary key,        -- 'ZA', 'KE', 'GH', 'NG'
    country_name         text not null,
    regulator_names       jsonb not null default '[]',   -- e.g. ["FSCA","FAIS"]
    currency_code         text not null,                 -- 'ZAR','KES','GHS','NGN'
    provinces_or_regions  jsonb not null default '[]',
    filing_calendar       jsonb not null default '{}',
    default_locale        text not null default 'en',
    is_active             boolean not null default true,
    created_at            timestamptz not null default now()
);

insert into country_config (country_code, country_name, regulator_names, currency_code, default_locale)
values ('ZA', 'South Africa', '["FSCA","FAIS","POPIA"]', 'ZAR', 'en-ZA');

-- ----------------------------------------------------------------------------
-- 2. ORGANISATIONS (tenants — one row per subscribing SMME)
-- ----------------------------------------------------------------------------
create table organisations (
    id                    uuid primary key default uuid_generate_v4(),
    name                  text not null,
    sector                text,
    country_code          text not null references country_config(country_code),
    registration_number   text,               -- CIPC / company reg no.
    tax_reference_number  text,
    subscription_tier     text not null default 'free' check (subscription_tier in ('free','pro','business')),
    subscription_status   text not null default 'trialing' check (subscription_status in ('trialing','active','past_due','cancelled')),
    billing_provider      text,               -- 'payfast' | 'peach'
    billing_customer_ref  text,
    popia_consent_at      timestamptz,        -- date org accepted POPIA data processing terms
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 3. PROFILES (linked 1:1 to Supabase auth.users)
-- ----------------------------------------------------------------------------
create table profiles (
    id            uuid primary key references auth.users(id) on delete cascade,
    full_name     text not null,
    email         text not null,
    phone_number  text,
    avatar_url    text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 4. ORG MEMBERSHIP / EXCO MEMBERS
-- ----------------------------------------------------------------------------
create table org_members (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    profile_id        uuid not null references profiles(id) on delete cascade,
    role              text not null check (role in ('owner','exco_member','shareholder','subcommittee_member','viewer')),
    title             text,               -- e.g. "CFO", "Non-Exec Director"
    is_active         boolean not null default true,
    joined_at         timestamptz not null default now(),
    removed_at        timestamptz,
    unique (organisation_id, profile_id)
);

-- Leadership changes audit log (feature already implemented in the HTML app —
-- this persists it server-side instead of in-memory)
create table leadership_change_log (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    org_member_id     uuid references org_members(id),
    change_type       text not null check (change_type in ('added','removed','role_changed')),
    previous_role     text,
    new_role          text,
    changed_by        uuid references profiles(id),
    reason            text,
    created_at        timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 5. BUSINESS PRIORITIES (numbered, open-ended list from setup wizard)
-- ----------------------------------------------------------------------------
create table business_priorities (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    sequence_number   integer not null,
    description       text not null,
    created_by        uuid references profiles(id),
    created_at        timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 6. MEETINGS
-- ----------------------------------------------------------------------------
create table meetings (
    id                    uuid primary key default uuid_generate_v4(),
    organisation_id       uuid not null references organisations(id) on delete cascade,
    meeting_type          text not null check (meeting_type in (
                              'shareholder','board','subcommittee','exco','management','coffee_exco'
                          )),
    subcommittee_name     text,               -- populated only when meeting_type = 'subcommittee'
    title                 text not null,
    scheduled_at          timestamptz,
    status                text not null default 'draft' check (status in ('draft','open','closed')),
    ai_deliberation_used  boolean not null default false,
    created_by            uuid references profiles(id),
    created_at            timestamptz not null default now(),
    closed_at              timestamptz
);

create table meeting_attendees (
    id            uuid primary key default uuid_generate_v4(),
    meeting_id    uuid not null references meetings(id) on delete cascade,
    org_member_id uuid not null references org_members(id),
    attended      boolean default true,
    unique (meeting_id, org_member_id)
);

-- ----------------------------------------------------------------------------
-- 7. MINUTES (append-only version history — never overwrite a confirmed version)
-- ----------------------------------------------------------------------------
create table meeting_minutes_versions (
    id                uuid primary key default uuid_generate_v4(),
    meeting_id        uuid not null references meetings(id) on delete cascade,
    version_number    integer not null,
    content           text not null,
    status            text not null default 'draft' check (status in ('draft','confirmed')),
    authored_by       uuid references profiles(id),
    confirmed_by      uuid references profiles(id),
    confirmed_at      timestamptz,
    created_at        timestamptz not null default now(),
    unique (meeting_id, version_number)
);

-- ----------------------------------------------------------------------------
-- 8. ACTION REGISTER (per-Exco-member action capture, consolidated)
-- ----------------------------------------------------------------------------
create table actions (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    meeting_id        uuid references meetings(id),
    assigned_to       uuid references org_members(id),
    description       text not null,
    due_date          date,
    status            text not null default 'open' check (status in ('open','in_progress','completed','overdue','cancelled')),
    priority          text default 'medium' check (priority in ('low','medium','high')),
    created_by        uuid references profiles(id),
    created_at        timestamptz not null default now(),
    completed_at      timestamptz
);

-- ----------------------------------------------------------------------------
-- 9. DOCUMENTS (attachments on actions, meetings, or priorities)
-- ----------------------------------------------------------------------------
create table documents (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    storage_path      text not null,       -- Supabase Storage object path
    file_name         text not null,
    file_size_bytes   bigint,
    mime_type         text,
    -- Polymorphic link: exactly one of these should be set
    action_id         uuid references actions(id) on delete cascade,
    meeting_id        uuid references meetings(id) on delete cascade,
    priority_id       uuid references business_priorities(id) on delete cascade,
    uploaded_by       uuid references profiles(id),
    uploaded_at       timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 10. GOVERNANCE SCORING (seven-factor breakdown)
-- ----------------------------------------------------------------------------
create table governance_scores (
    id                    uuid primary key default uuid_generate_v4(),
    organisation_id       uuid not null references organisations(id) on delete cascade,
    calculated_at         timestamptz not null default now(),
    overall_score         numeric(5,2) not null,
    -- seven scoring factors, stored individually for the breakdown panel
    factor_meeting_cadence       numeric(5,2),
    factor_minutes_completion    numeric(5,2),
    factor_action_closure_rate   numeric(5,2),
    factor_compliance_coverage   numeric(5,2),
    factor_exco_participation    numeric(5,2),
    factor_documentation_quality numeric(5,2),
    factor_communication_reach   numeric(5,2),
    notes                 text
);

-- ----------------------------------------------------------------------------
-- 11. COMPLIANCE FRAMEWORK
-- ----------------------------------------------------------------------------
create table compliance_frameworks (
    id                uuid primary key default uuid_generate_v4(),
    country_code      text not null references country_config(country_code),
    framework_name    text not null,    -- e.g. 'FAIS Fit & Proper', 'POPIA Data Processing'
    description       text,
    legal_disclaimer  text,
    is_active         boolean not null default true
);

create table organisation_compliance_status (
    id                 uuid primary key default uuid_generate_v4(),
    organisation_id    uuid not null references organisations(id) on delete cascade,
    framework_id       uuid not null references compliance_frameworks(id),
    status             text not null default 'not_started' check (status in ('not_started','in_progress','compliant','non_compliant','na')),
    last_reviewed_at   timestamptz,
    reviewed_by        uuid references profiles(id),
    evidence_document_id uuid references documents(id),
    unique (organisation_id, framework_id)
);

-- ----------------------------------------------------------------------------
-- 12. COMMUNICATION & DISTRIBUTION
-- ----------------------------------------------------------------------------
create table distribution_lists (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    list_name         text not null,      -- e.g. "All Exco", "Shareholders", custom "Other" list
    channel           text not null check (channel in ('email','whatsapp')),
    is_custom         boolean not null default false,
    created_at        timestamptz not null default now()
);

create table distribution_list_members (
    id                    uuid primary key default uuid_generate_v4(),
    distribution_list_id  uuid not null references distribution_lists(id) on delete cascade,
    org_member_id          uuid not null references org_members(id) on delete cascade,
    unique (distribution_list_id, org_member_id)
);

create table communications_log (
    id                    uuid primary key default uuid_generate_v4(),
    organisation_id       uuid not null references organisations(id) on delete cascade,
    meeting_id            uuid references meetings(id),
    distribution_list_id  uuid references distribution_lists(id),
    channel               text not null check (channel in ('email','whatsapp')),
    subject               text,
    popia_notice_included boolean not null default true,
    sent_by               uuid references profiles(id),
    sent_at               timestamptz not null default now(),
    delivery_status       text default 'sent' check (delivery_status in ('queued','sent','failed'))
);

-- ----------------------------------------------------------------------------
-- 13. AI DELIBERATION LOG (for FAIS/FSCA defensibility — deterministic trail)
-- ----------------------------------------------------------------------------
create table ai_deliberation_log (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    meeting_id        uuid references meetings(id),
    persona           text not null,        -- e.g. 'Market Analyst', 'Compliance Officer'
    used_web_search   boolean not null default false,   -- false = deterministic/reproducible call
    prompt_summary    text,
    response_summary  text,
    model_used        text,
    created_at        timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 14. INDEXES
-- ----------------------------------------------------------------------------
create index idx_org_members_org on org_members(organisation_id);
create index idx_meetings_org on meetings(organisation_id);
create index idx_actions_org_status on actions(organisation_id, status);
create index idx_minutes_meeting on meeting_minutes_versions(meeting_id);
create index idx_documents_org on documents(organisation_id);
create index idx_governance_scores_org_date on governance_scores(organisation_id, calculated_at desc);
create index idx_comms_log_org on communications_log(organisation_id);

-- ----------------------------------------------------------------------------
-- 15. ROW LEVEL SECURITY (stub — superseded by 002_rls_policies.sql)
-- ----------------------------------------------------------------------------
alter table organisations enable row level security;
alter table org_members enable row level security;
alter table meetings enable row level security;
alter table meeting_minutes_versions enable row level security;
alter table actions enable row level security;
alter table documents enable row level security;
alter table governance_scores enable row level security;
alter table organisation_compliance_status enable row level security;
alter table distribution_lists enable row level security;
alter table communications_log enable row level security;
alter table ai_deliberation_log enable row level security;

-- Example baseline policy pattern — repeat per table, tightened per role later:
-- create policy "org_members_can_select_own_org_data"
--   on meetings for select
--   using (
--     organisation_id in (
--       select organisation_id from org_members
--       where profile_id = auth.uid() and is_active = true
--     )
--   );

-- ============================================================================
-- END OF PHASE 1 SCHEMA
-- ============================================================================
