-- ============================================================================
-- MyBizExco — Org invite flow
-- ============================================================================
-- Lets an owner/exco_member add a real person to their organisation with a
-- pre-assigned role/title, instead of the wizard's free-text Leadership Team
-- names that were never backed by a real org_members row. Email delivery is
-- handled separately (Resend, called from api/invite.js) -- this migration
-- is the data layer only: the invite record, and the two RPCs that let an
-- invitee (not yet an org member, so normal RLS can't cover them) look up
-- and accept an invite safely.
-- ============================================================================

create table org_invites (
    id                uuid primary key default uuid_generate_v4(),
    organisation_id   uuid not null references organisations(id) on delete cascade,
    email             text not null,
    role              text not null check (role in ('exco_member','shareholder','subcommittee_member','viewer')), -- 'owner' deliberately excluded -- not an invitable role
    title             text,               -- e.g. "CFO" -- mirrors org_members.title
    token             uuid not null default gen_random_uuid() unique,
    status            text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
    invited_by        uuid references profiles(id),
    created_at        timestamptz not null default now(),
    expires_at        timestamptz not null default (now() + interval '7 days'),
    accepted_at       timestamptz,
    accepted_by       uuid references profiles(id)
);

-- RLS: only the inviting org's owner/exco_member can see, create, or revoke
-- (via a plain update to status='revoked') invites for their own org --
-- same "management" tier already used for meetings/actions/etc.
alter table org_invites enable row level security;

create policy "org_invites_select_management"
  on org_invites for select
  using (organisation_id in (select auth_user_management_org_ids()));

create policy "org_invites_insert_management"
  on org_invites for insert
  with check (organisation_id in (select auth_user_management_org_ids()));

create policy "org_invites_update_management"
  on org_invites for update
  using (organisation_id in (select auth_user_management_org_ids()))
  with check (organisation_id in (select auth_user_management_org_ids()));

-- ----------------------------------------------------------------------------
-- get_invite_by_token — lets someone who isn't signed in yet (or isn't an org
-- member yet, so the RLS policies above don't apply to them) see what
-- they're being invited to before they sign up/sign in. Safe by construction:
-- only ever returns the one row matching an exact, unguessable token, and
-- only non-sensitive display fields (no organisation internals beyond name).
-- ----------------------------------------------------------------------------
create or replace function get_invite_by_token(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite org_invites%rowtype;
  v_org_name text;
begin
  select * into v_invite from org_invites where token = p_token;
  if not found then
    return jsonb_build_object('found', false, 'error', 'invite_not_found');
  end if;
  if v_invite.status <> 'pending' then
    return jsonb_build_object('found', false, 'error', 'invite_' || v_invite.status);
  end if;
  if v_invite.expires_at < now() then
    update org_invites set status = 'expired' where id = v_invite.id;
    return jsonb_build_object('found', false, 'error', 'invite_expired');
  end if;

  select name into v_org_name from organisations where id = v_invite.organisation_id;

  return jsonb_build_object(
    'found', true,
    'email', v_invite.email,
    'role', v_invite.role,
    'title', v_invite.title,
    'organisation_name', v_org_name
  );
end;
$$;

grant execute on function get_invite_by_token(uuid) to authenticated, anon;

-- ----------------------------------------------------------------------------
-- accept_org_invite — the only way an org_members row gets created for an
-- invited (non-owner) person. Takes ONLY the token; the caller's identity
-- and email come from auth.uid()/auth.users, never from a client-supplied
-- parameter, so the email-match check below cannot be spoofed. Atomic:
-- membership creation and marking the invite accepted happen in one
-- transaction, same pattern as create_organisation_with_owner.
-- ----------------------------------------------------------------------------
create or replace function accept_org_invite(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite org_invites%rowtype;
  v_caller_email text;
  v_org_member_id uuid;
  v_previous_role text;
begin
  select * into v_invite from org_invites where token = p_token for update;
  if not found then
    return jsonb_build_object('accepted', false, 'error', 'invite_not_found');
  end if;
  if v_invite.status <> 'pending' then
    return jsonb_build_object('accepted', false, 'error', 'invite_' || v_invite.status);
  end if;
  if v_invite.expires_at < now() then
    update org_invites set status = 'expired' where id = v_invite.id;
    return jsonb_build_object('accepted', false, 'error', 'invite_expired');
  end if;

  select email into v_caller_email from auth.users where id = auth.uid();
  if v_caller_email is null or lower(v_caller_email) <> lower(v_invite.email) then
    return jsonb_build_object('accepted', false, 'error', 'email_mismatch');
  end if;

  -- Captured before the upsert so the audit log below can tell a brand-new
  -- membership apart from a reactivation (null previous_role = brand new).
  select role into v_previous_role from org_members
    where organisation_id = v_invite.organisation_id and profile_id = auth.uid();

  insert into org_members (organisation_id, profile_id, role, title)
  values (v_invite.organisation_id, auth.uid(), v_invite.role, v_invite.title)
  on conflict (organisation_id, profile_id)
    do update set is_active = true, role = excluded.role, title = excluded.title, removed_at = null
  returning id into v_org_member_id;

  -- change_type has no distinct value for "reactivated" -- a returning member
  -- logs as 'role_changed' rather than 'added', since previous_role was not
  -- actually null for them. Known, minor loss of granularity, not a bug.
  insert into leadership_change_log (organisation_id, org_member_id, change_type, previous_role, new_role, changed_by, reason)
  values (
    v_invite.organisation_id, v_org_member_id,
    case when v_previous_role is null then 'added' else 'role_changed' end,
    v_previous_role, v_invite.role, v_invite.invited_by,
    case when v_previous_role is null then 'Joined via invite' else 'Rejoined via invite' end
  );

  update org_invites set status = 'accepted', accepted_at = now(), accepted_by = auth.uid()
    where id = v_invite.id;

  return jsonb_build_object('accepted', true, 'organisation_id', v_invite.organisation_id, 'role', v_invite.role);
end;
$$;

grant execute on function accept_org_invite(uuid) to authenticated;

-- ============================================================================
-- END
-- ============================================================================
