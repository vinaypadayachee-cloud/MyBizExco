// Vercel Edge Function — Anthropic API proxy for MyBizExco_21.html.
// Keeps ANTHROPIC_API_KEY server-side only; the browser never sees it.

export const config = { runtime: 'edge' };

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function jsonError(status, message) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

export default async function handler(req) {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return jsonError(405, 'Method not allowed');
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return jsonError(500, 'ANTHROPIC_API_KEY environment variable not set');
  }

  let body;
  try {
    body = await req.text();
    JSON.parse(body); // reject malformed JSON before forwarding upstream
  } catch (e) {
    return jsonError(400, 'Request body must be valid JSON');
  }

  let upstream;
  try {
    upstream = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': ANTHROPIC_VERSION,
      },
      body,
    });
  } catch (e) {
    return jsonError(502, 'Network error reaching Anthropic API: ' + e.message);
  }

  // Pass through Anthropic's own status and body as-is — this already covers
  // rate limits (429), invalid request errors (400), auth errors (401), etc.
  // with their real structured error JSON. We just add CORS so the browser can read it.
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}
