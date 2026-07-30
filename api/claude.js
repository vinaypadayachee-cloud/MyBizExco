// Vercel Edge Function — Anthropic API proxy for MyBizExco_21.html.
// Keeps ANTHROPIC_API_KEY and SUPABASE_SERVICE_ROLE_KEY server-side only;
// the browser never sees either.
//
// Every request must carry a valid Supabase session JWT (Authorization:
// Bearer <token>) identifying a real signed-in user who belongs to an
// organisation, and that organisation's subscription tier + usage counters
// gate whether we spend money calling Anthropic at all. See
// supabase/005_ai_usage_quotas.sql for the schema and the RPCs this calls.

export const config = { runtime: 'edge' };

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function jsonError(status, body) {
  const payload = typeof body === 'string' ? { error: body } : body;
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

async function getSupabaseUser(token, supabaseUrl, anonKey) {
  const r = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: anonKey },
  });
  if (!r.ok) return null;
  const user = await r.json();
  return user?.id ? user : null;
}

async function getOrgIdForUser(userId, supabaseUrl, serviceRoleKey) {
  const r = await fetch(
    `${supabaseUrl}/rest/v1/org_members?profile_id=eq.${userId}&is_active=eq.true&select=organisation_id&limit=1`,
    { headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` } }
  );
  if (!r.ok) return null;
  const rows = await r.json();
  return rows?.[0]?.organisation_id || null;
}

async function callUsageRpc(fnName, args, supabaseUrl, serviceRoleKey) {
  const r = await fetch(`${supabaseUrl}/rest/v1/rpc/${fnName}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
    },
    body: JSON.stringify(args),
  });
  if (!r.ok) return { ok: false };
  // decrement_ai_usage returns void -> PostgREST sends an empty body, which
  // .json() would throw on ("Unexpected end of JSON input"). Only parse if
  // there's actually something to parse.
  const text = await r.text();
  const data = text ? JSON.parse(text) : null;
  return { ok: true, data };
}

export default async function handler(req) {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return jsonError(405, 'Method not allowed');
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  const supabaseUrl = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!apiKey || !supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonError(500, 'Server is missing required environment configuration');
  }

  // ── 1. Authenticate ──────────────────────────────────────────────────
  const authHeader = req.headers.get('authorization') || '';
  const token = authHeader.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    return jsonError(401, 'Missing or invalid Authorization header');
  }
  const user = await getSupabaseUser(token, supabaseUrl, anonKey);
  if (!user) {
    return jsonError(401, 'Invalid or expired session');
  }

  // ── 2. Resolve the caller's organisation ────────────────────────────
  const organisationId = await getOrgIdForUser(user.id, supabaseUrl, serviceRoleKey);
  if (!organisationId) {
    return jsonError(403, { error: 'no_organisation' });
  }

  // ── 3. Parse body, pull out our own routing field, validate JSON ────
  let payload;
  try {
    const raw = await req.text();
    payload = JSON.parse(raw);
  } catch (e) {
    return jsonError(400, 'Request body must be valid JSON');
  }
  const isSynthesis = payload.mbxCallType === 'synthesis';
  delete payload.mbxCallType; // Anthropic doesn't know about this field

  // ── 4. Reserve a usage slot BEFORE spending money on Anthropic ──────
  const reserve = await callUsageRpc(
    'check_and_increment_ai_usage',
    { p_organisation_id: organisationId, p_is_synthesis: isSynthesis },
    supabaseUrl, serviceRoleKey
  );
  if (!reserve.ok) {
    return jsonError(500, 'Could not verify usage quota');
  }
  if (!reserve.data?.allowed) {
    return jsonError(402, {
      error: reserve.data?.error || 'usage_limit_reached',
      tier: reserve.data?.tier || null,
    });
  }

  // ── 5. Forward to Anthropic ──────────────────────────────────────────
  let upstream;
  try {
    upstream = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': ANTHROPIC_VERSION,
      },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    // Network failure — refund the reserved slot, this call never happened.
    await callUsageRpc('decrement_ai_usage', { p_organisation_id: organisationId, p_is_synthesis: isSynthesis }, supabaseUrl, serviceRoleKey);
    return jsonError(502, 'Network error reaching Anthropic API: ' + e.message);
  }

  if (!upstream.ok) {
    // Anthropic itself rejected the call (rate limit, invalid request, etc.)
    // — refund, since no usable deliberation actually happened.
    await callUsageRpc('decrement_ai_usage', { p_organisation_id: organisationId, p_is_synthesis: isSynthesis }, supabaseUrl, serviceRoleKey);
  }

  // Pass through Anthropic's own status and body as-is — this already covers
  // rate limits (429), invalid request errors (400), etc. with their real
  // structured error JSON. We just add CORS so the browser can read it.
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}
