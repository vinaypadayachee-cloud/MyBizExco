-- ============================================================================
-- MyBizExco — Fix org-creation chicken-and-egg RLS failure
-- ============================================================================
-- Found via live end-to-end test (real signUp -> insert into organisations):
--   "new row violates row-level security policy for table organisations" (42501)
--
-- Cause: sb.from('organisations').insert({...}).select().single() asks
-- PostgREST to return the inserted row (RETURNING). Postgres filters
-- RETURNING rows through the table's SELECT policy, same as any other read.
-- organisations_select_member requires
--   id in (select auth_user_org_ids())
-- i.e. the org must already have an org_members row for this user — but at
-- the moment of the very first insert, that membership row doesn't exist yet
-- (it was being created in a second, separate insert right after). So the
-- brand-new row always fails its own SELECT check and the whole insert
-- errors out, even though the INSERT's own WITH CHECK (true) passed.
--
-- Fix: a single SECURITY DEFINER function that creates the organisation and
-- its owner org_members row in one atomic, RLS-bypassed transaction, then
-- returns the organisation row directly (no RETURNING-triggers-SELECT-policy
-- step involved). Safe by construction: it hardcodes auth.uid() as the new
-- owner, so a caller can only ever make themselves the owner of a brand-new
-- org, never touch an existing one.
-- ============================================================================

create or replace function create_organisation_with_owner(
  org_name text,
  org_sector text,
  org_country_code text,
  org_registration_number text
)
returns organisations
language plpgsql
security definer
set search_path = public
as $$
declare
  new_org organisations;
begin
  insert into organisations (name, sector, country_code, registration_number)
  values (org_name, org_sector, org_country_code, org_registration_number)
  returning * into new_org;

  insert into org_members (organisation_id, profile_id, role)
  values (new_org.id, auth.uid(), 'owner');

  return new_org;
end;
$$;

grant execute on function create_organisation_with_owner(text, text, text, text) to authenticated;

-- ============================================================================
-- END
-- ============================================================================
