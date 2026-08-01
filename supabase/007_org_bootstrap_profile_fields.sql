-- ============================================================================
-- MyBizExco — Extend create_organisation_with_owner with profile fields
-- ============================================================================
-- 006 added the columns; this wires the org-creation RPC (004) to actually
-- set them at creation time, instead of leaving them null until some later
-- update.
--
-- create or replace function does NOT replace a function with a different
-- parameter signature -- Postgres treats it as a second overload with the
-- same name, since overload resolution is keyed on the argument type list.
-- Left alone, the old 4-argument version from 004 would linger and could
-- still be matched by a 4-arg call. Drop it explicitly first so there is
-- exactly one version of this function.
-- ============================================================================

drop function if exists create_organisation_with_owner(text, text, text, text);

create or replace function create_organisation_with_owner(
  org_name text,
  org_sector text,
  org_country_code text,
  org_registration_number text,
  org_ceo_name text default null,
  org_company_size text default null,
  org_province text default null,
  org_revenue_band text default null,
  org_financial_context text default null,
  org_additional_regulator text default null,
  org_incorporation_date date default null,
  org_quorum_cfo_veto boolean default true,
  org_quorum_cro_veto boolean default true,
  org_quorum_cto_veto boolean default false,
  org_quorum_majority boolean default true
)
returns organisations
language plpgsql
security definer
set search_path = public
as $$
declare
  new_org organisations;
begin
  insert into organisations (
    name, sector, country_code, registration_number,
    ceo_name, company_size, province, revenue_band, financial_context,
    additional_regulator, incorporation_date,
    quorum_cfo_veto, quorum_cro_veto, quorum_cto_veto, quorum_majority
  )
  values (
    org_name, org_sector, org_country_code, org_registration_number,
    org_ceo_name, org_company_size, org_province, org_revenue_band, org_financial_context,
    org_additional_regulator, org_incorporation_date,
    org_quorum_cfo_veto, org_quorum_cro_veto, org_quorum_cto_veto, org_quorum_majority
  )
  returning * into new_org;

  insert into org_members (organisation_id, profile_id, role)
  values (new_org.id, auth.uid(), 'owner');

  return new_org;
end;
$$;

grant execute on function create_organisation_with_owner(
  text, text, text, text, text, text, text, text, text, text, date, boolean, boolean, boolean, boolean
) to authenticated;

-- ============================================================================
-- END
-- ============================================================================
