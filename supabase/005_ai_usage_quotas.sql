-- ============================================================================
-- MyBizExco — AI usage quota enforcement (subscription tier gating)
-- ============================================================================
-- Locks down real money exposure on the /api/claude proxy. Pricing model:
--   free:     1 full AI-deliberated meeting, lifetime — capped at 8 items
--             within that meeting so an org can't dodge the cap by simply
--             never closing the meeting.
--   pro:      30 deliberated items per calendar month.
--   business: 100 deliberated items per calendar month.
--
-- "Deliberated item" = one agenda item taken through a full deliberate()
-- cycle (6 per-Exco-role calls + 1 synthesis call). Only the synthesis call
-- increments the counter — the 6 exec calls are gated against the same cap
-- (so a new item can't start once the org is already at its limit) but
-- don't themselves count, since an item isn't "deliberated" until synthesis
-- completes.
-- ============================================================================

alter table organisations
  add column if not exists free_meeting_used boolean not null default false,
  add column if not exists deliberated_items_this_period integer not null default 0,
  add column if not exists current_period_start timestamptz not null default now();

-- ----------------------------------------------------------------------------
-- check_and_increment_ai_usage — the single source of truth for whether a
-- call is allowed, called by the proxy BEFORE it spends money on Anthropic.
-- Runs as one atomic statement (via `for update` row lock) so concurrent
-- requests from the same organisation can never both pass the check and
-- both increment past the cap — the second request always sees the first
-- request's increment before deciding.
-- ----------------------------------------------------------------------------
create or replace function check_and_increment_ai_usage(
  p_organisation_id uuid,
  p_is_synthesis boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  org organisations%rowtype;
  cap integer;
  now_ts timestamptz := now();
begin
  select * into org from organisations where id = p_organisation_id for update;
  if not found then
    return jsonb_build_object('allowed', false, 'error', 'org_not_found');
  end if;

  -- Calendar-month rollover for paid tiers (free tier has no period concept
  -- — it's a lifetime cap). Resets exactly once when the calendar month
  -- changes, regardless of the exact day/time current_period_start holds.
  if org.subscription_tier in ('pro','business')
     and date_trunc('month', org.current_period_start) < date_trunc('month', now_ts) then
    update organisations
      set deliberated_items_this_period = 0, current_period_start = now_ts
      where id = p_organisation_id;
    org.deliberated_items_this_period := 0;
    org.current_period_start := now_ts;
  end if;

  if org.subscription_tier = 'free' then
    if org.free_meeting_used then
      return jsonb_build_object('allowed', false, 'error', 'usage_limit_reached', 'tier', 'free');
    end if;
    if org.deliberated_items_this_period >= 8 then
      -- Belt-and-braces: the synthesis increment below should already have
      -- flipped free_meeting_used the moment item 8 completed, but guard
      -- against ever serving a 9th item if that somehow didn't happen.
      update organisations set free_meeting_used = true where id = p_organisation_id;
      return jsonb_build_object('allowed', false, 'error', 'usage_limit_reached', 'tier', 'free');
    end if;
    if p_is_synthesis then
      update organisations
        set deliberated_items_this_period = deliberated_items_this_period + 1,
            free_meeting_used = (org.deliberated_items_this_period + 1 >= 8)
        where id = p_organisation_id;
    end if;
    return jsonb_build_object('allowed', true, 'tier', 'free');
  end if;

  cap := case org.subscription_tier when 'pro' then 30 when 'business' then 100 else 0 end;

  if org.deliberated_items_this_period >= cap then
    return jsonb_build_object('allowed', false, 'error', 'usage_limit_reached', 'tier', org.subscription_tier);
  end if;

  if p_is_synthesis then
    update organisations
      set deliberated_items_this_period = deliberated_items_this_period + 1
      where id = p_organisation_id;
  end if;

  return jsonb_build_object('allowed', true, 'tier', org.subscription_tier);
end;
$$;

grant execute on function check_and_increment_ai_usage(uuid, boolean) to service_role;

-- ----------------------------------------------------------------------------
-- decrement_ai_usage — refund a reserved slot when the Anthropic call that
-- followed a successful check_and_increment_ai_usage call itself failed
-- (network error, upstream 5xx, etc.) so failed calls never count against
-- the org's quota. Symmetric undo of exactly what the paired increment did;
-- safe to call unconditionally because a refund only ever follows a call
-- that itself just returned allowed:true.
-- ----------------------------------------------------------------------------
create or replace function decrement_ai_usage(
  p_organisation_id uuid,
  p_is_synthesis boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not p_is_synthesis then
    return; -- exec calls never increment anything, nothing to refund
  end if;
  update organisations
    set deliberated_items_this_period = greatest(deliberated_items_this_period - 1, 0),
        free_meeting_used = case when subscription_tier = 'free' then false else free_meeting_used end
    where id = p_organisation_id;
end;
$$;

grant execute on function decrement_ai_usage(uuid, boolean) to service_role;

-- ----------------------------------------------------------------------------
-- mark_free_meeting_used — called by closeMeeting() (client-side, any org
-- member, not just owner — closing a meeting isn't an owner-only action)
-- when a free-tier org closes a meeting that used AI deliberation. Ends
-- their lifetime free trial even if they didn't reach the 8-item cap.
-- Meetings closed with zero AI usage don't burn the free trial. Safe to
-- expose to any authenticated user: it only ever flips a flag on the
-- caller's own organisation (verified via org_members), and only from
-- false to true, never the reverse.
-- ----------------------------------------------------------------------------
create or replace function mark_free_meeting_used(p_meeting_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_ai_used boolean;
  v_is_member boolean;
begin
  select organisation_id, ai_deliberation_used into v_org_id, v_ai_used
    from meetings where id = p_meeting_id;
  if v_org_id is null then
    return;
  end if;

  select exists(
    select 1 from org_members
    where organisation_id = v_org_id and profile_id = auth.uid() and is_active = true
  ) into v_is_member;
  if not v_is_member then
    return;
  end if;

  if v_ai_used then
    update organisations
      set free_meeting_used = true
      where id = v_org_id and subscription_tier = 'free';
  end if;
end;
$$;

grant execute on function mark_free_meeting_used(uuid) to authenticated;

-- ============================================================================
-- END
-- ============================================================================
