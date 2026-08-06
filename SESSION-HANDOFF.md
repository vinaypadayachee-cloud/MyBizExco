# Session Handoff — 2026-08-05

Not committed — local reference only. Delete or fold into CHANGELOG.md
once read.

## Completed

### 2026-08-04
- **Pushed the profile-fix + invite-screen work to `origin/main`.**
  Verified live in production (fetched `https://mybizexco-vanilla.vercel.app/`
  directly and confirmed `ensureProfileExists`, `handleInviteFlow`, and the
  other invite-flow function markers are present in the served HTML — not
  just checked Vercel's dashboard status).
  - `0f8c16e` — `009_org_invites.sql` (org_invites table, RLS,
    `get_invite_by_token`/`accept_org_invite` RPCs)
  - `eb379f7` — invite-accept screen + `ensureProfileExists` fix for both
    the general auth flow and the invite flow
- **Placeholder text cleanup** (`5837e78`): replaced the real values
  "Stage IS Insurance Solutions (Pty) Ltd" / "Vinay Padayachee" with
  generic examples "Johns Electrical" / "John Jones" in all 4 places they
  appeared.
- **Created `SNAGS.md`** (`82624bd`): tracks the WhatsApp manual-send
  limitation (not a bug) and the "About MyBizExco" dense-paragraph copy
  as an open, low-priority UX snag.
- **WhatsApp send-screen copy fix** (`34c4e2b`): added an on-screen hint
  above the "Send to {group}" button on both send screens explaining the
  copy-to-clipboard + pre-loaded-number + manual-paste flow.
- **Resolved the admin-log mystery.** Traced flagged
  `DELETE`/`PUT /admin/users/{id}` Auth Log entries fully to known test
  scripts from this session's persistence-cutover work — no unexplained
  activity, no leftover test data.

### 2026-08-05
- **Persona-copy fix, all 3 locations** (`02f5254`, confirmed committed —
  `git commit -F` returned `[main 02f5254] Add Deputy CEO to
  persona-list copy (3 locations)`, 1 file changed, 3 insertions(+), 3
  deletions(-)): a read-only mapping pass found that 3 places describing
  the Exco in copy only ever listed 5 roles (CFO, COO, CRO, CHRO, CTO),
  omitting **Deputy CEO** — the `EXCO` array's first entry (`id:"dceo"`),
  which has full mechanical parity with the other 5 in `deliberate()`
  (same AI call, same voice output, same majority-vote counting;
  correctly excluded from veto gates by design, same as coo/chro — only
  cfo/cro/cto ever had configurable veto). Fixed:
  - Line 1619 — `FAQS[0].a` ("What is MyBizExco?")
  - Line 1629 — `renderStepAbout()`'s "What it does" info-box
  - Line 1847 — `renderStep3()`'s "What is an Exco?" info-box
    (Leadership Team wizard step)
  
  QA passed: Puppeteer-core against real Edge, zero console errors, zero
  uncaught exceptions, all three locations verified to actually contain
  "Deputy CEO" in their rendered output. Committed and pushed, confirmed
  live in production.
- **Voice differentiation for the 6 exec personas via `speak()`**
  (`4f3bdbc`, "Add per-role voice differentiation to speak()", 1 file
  changed, 20 insertions/3 deletions — committed and pushed, confirmed
  live in production):
  - Read-only mapping pass first: found `speak()` at
    `MyBizExco_21.html:3286`, one call site inside `deliberate()`
    (`last.role` already in scope there), and enumerated the 6 real
    voices available via `speechSynthesis.getVoices()` in real Edge on
    this machine (David, Zira, Mark, Hazel, Susan, George — all
    `localService:true`, none `en-ZA` despite `speak()`'s hardcoded
    `u.lang='en-ZA'`, which was a silent no-op).
  - Designed and confirmed a per-role table: each of the 6 roles
    (`dceo/cfo/coo/cro/chro/cto`) mapped 1:1 to a distinct voice name
    (US/GB-alternating spread), then layered per-role `pitch`/`rate`
    on top from `MyBizExco-Manual.docx`'s table (`cro`/`chro`
    reassigned to female voices — Hazel/Zira — per the Manual's
    "female voice preferred" notes for those two roles).
  - Implemented: `ROLE_VOICE` table + `pickVoice(role)` (name-substring
    lookup against live `getVoices()`, not hardcoded indices, graceful
    fallback to browser default if no match) + `speak(text, role)`
    (drops the dead `en-ZA` line — lang now derived from whichever
    voice is actually picked, or left unset on fallback) + the one
    call-site update passing `last.role`.
  - QA passed: Puppeteer-core against real Edge, zero console/page
    errors, `speechSynthesis.speak` spied directly (not the
    constructor — an earlier version of the QA script hung, likely on
    `waitUntil:'networkidle0'` against this app's persistent Supabase
    connection; fixed by switching to `domcontentloaded`). Verified for
    3 of the 6 roles (`dceo`→David, `cro`→Hazel, `chro`→Zira) that the
    actual voice picked matches `ROLE_VOICE`; same code path covers the
    other 3 (`cfo`/`coo`/`cto`).
- **Tagline "Intelligence that protects. Insight that grows."**
  (`29244f7`, "Add tagline to hero and About pages", 1 file changed, 3
  insertions/1 deletion — committed and pushed, confirmed live in
  production):
  - Placement agreed before implementation, with exact diffs shown for
    review first: hero (Welcome) screen gets a new `.w-tagline` line
    (line 273) between the `.w-logo` wordmark and the existing `.w-sub`
    subhead, styled via a new CSS rule (line 20:
    `font-size:18px;font-weight:600;color:#93c5fd;margin-bottom:14px`);
    About page (`renderStepAbout()`, line 1630) has its `.step-sub`
    text replaced outright (was "Everything you need to know before
    you begin.") rather than adding a new line — no new CSS needed
    there, reused the existing subhead styling.
  - QA passed: Puppeteer-core against real Edge, zero console/page
    errors, screenshots taken of both screens for visual review before
    committing. (Note for future QA scripts: `.step-sub` is used by
    more than one screen — a bare `$eval('.step-sub', ...)` grabbed the
    auth screen's hidden copy instead of the About page's; scoping to
    `#setupBody .step-sub` fixed it.)
  - Verified live: fetched `https://mybizexco-vanilla.vercel.app/`
    directly post-push, `Last-Modified` matched the push moment exactly
    (fresh deploy, not stale cache), and both the new CSS rule and both
    tagline instances are present in the served HTML.
- **About MyBizExco copy rewrite** (`905e90e`, "Rewrite About
  MyBizExco copy and fix stale storage FAQ", 1 file changed, 4
  insertions/5 deletions — committed and pushed, confirmed live in
  production):
  - Full structure/wording mapping agreed before any edit, then exact
    diffs shown and confirmed one at a time. Final scope: Info-box 1
    retitled "What it does" → "What is MyBizExco?" with new merged
    copy; the "Why MyBizExco Exists" card's first faq-item renamed
    "Welcome to MyBizExco" with new copy (paragraph breaks via
    `<br><br>`); the "Who It Changes, and How" and "What the World
    Looks Like When It Exists" faq-items left unchanged (confirmed the
    bullets were already byte-for-byte identical to the new copy
    supplied); `FAQS[3].a` ("Is my data stored anywhere?") corrected —
    was still describing the pre-Supabase browser-session storage
    model, now describes cloud storage scoped per organisation with
    Save/Restore as a manual local-backup option.
  - Caught and fixed a duplicate-heading issue before commit: renaming
    the faq-item to "Welcome to MyBizExco" made it read identically to
    the card's own `.card-title` (which had also been renamed to
    match) — visible in the QA screenshot. Fixed by removing the
    `.card-title` line entirely rather than inventing new wording not
    supplied.
  - QA passed twice (before and after the duplicate-heading fix):
    Puppeteer-core against real Edge, zero console/page errors,
    screenshots taken of the full rendered About page for visual
    review before committing.
  - Verified live: fetched `https://mybizexco-vanilla.vercel.app/`
    directly post-push, `Last-Modified` matched the fetch moment
    exactly, and all of the above (new info-box title, new faq-item
    heading, corrected FAQS[3].a, absence of the old "Why MyBizExco
    Exists" text and the duplicate card-title) confirmed present/absent
    as expected in the served HTML.
- **"About MyBizExco" bullets rewrite** (`61b9b14`, "Convert dense
  About-page paragraphs to scannable bullets", 1 file changed, 5
  insertions/5 deletions — committed and pushed, confirmed live in
  production). Closes the `SNAGS.md` "dense paragraphs, not scannable"
  item:
  - Drafted bulleted versions of all 5 in-scope blocks for review
    before any diff. Converted: both info-boxes ("What is MyBizExco?"
    — lead sentence + 5 bullets; "How to use it" — 3 bullets, no lead
    sentence), the "Who It Changes, and How" faq-item (lead sentence +
    4 bullets), and `FAQS[1]` ("What does it do?" — lead sentence + 5
    bullets). Left as prose by deliberate choice, not oversight:
    "Welcome to MyBizExco" (reads as an argument/origin story, not a
    feature list — bulleting it would flatten the rhetorical build)
    and `FAQS[0]`/`FAQS[2]`/`FAQS[3]`/`FAQS[4]` (no natural list
    content, already short).
  - Found and fixed a rendering blocker before it shipped: the `FAQS`
    card renders every answer through `esc()` (`MyBizExco_21.html:1208`,
    HTML-escapes `<`/`>`/`&`/`"`), so raw `<ul><li>` markup placed
    directly in a `FAQS[n].a` string would've rendered as visible
    literal text, not a real list. Fixed by adding a `raw:true` flag
    scoped to just the `FAQS` entries that needed unescaped markup
    (`FAQS[1]` only) and branching on it at the render line
    (`f.raw?f.a:esc(f.a)`) — confirmed this does *not* blanket-disable
    escaping for the other 4 entries, which still run through `esc()`
    as before.
  - Flagged and resolved a duplicate-heading question before
    implementing: `FAQS[0].q` ("What is MyBizExco?") is identical text
    to the info-box title above it. Judged this to be normal FAQ
    convention (re-asking a question already covered in the intro
    copy, for people who skip to the FAQ), not the same
    back-to-back-duplicate problem fixed in the prior task — left
    unchanged by explicit decision, not missed.
  - QA passed: Puppeteer-core against real Edge, zero console/page
    errors, confirmed 5 `<ul>` elements present in `#setupBody` (4 new
    + the 1 pre-existing "What the World Looks Like" list), full-page
    screenshot taken for visual review before committing.
  - Verified live: fetched `https://mybizexco-vanilla.vercel.app/`
    directly post-push, `Last-Modified` matched the fetch moment
    exactly. Confirmed present: the `raw:true` flag and bulleted
    `FAQS[1]` content, the bulleted "How to use it" info-box, and the
    render-line `esc()` scoping fix. Also re-confirmed (separately,
    since it wasn't part of this commit's diff) that "Why MyBizExco
    Exists" is still absent from the live page — that check was
    originally run for the *previous* commit (`905e90e`) and was
    re-verified fresh here rather than assumed still true.

## Next up

- **Send-invite UI** (More tab) — not yet built. Must restrict role
  selection to exactly the four valid roles (`exco_member`, `shareholder`,
  `subcommittee_member`, `viewer`) — `owner` explicitly excluded.
- **Resend account + `RESEND_API_KEY`** — you're setting this up
  separately and adding it to Vercel. Blocks the invite-email send step
  (`api/invite.js`, server-side). Flag me again once it's in place.
- **SMTP migration** — move Supabase Auth's outbound email off its
  default sender (source of the earlier bounce-rate warning) onto a
  custom SMTP provider, likely Resend once that account exists.

## Standing constraints (carried over, still in force)

- No further live `signUp()` calls without asking each time.
- Show exact SELECT queries before any INSERT/DELETE against production;
  get explicit approval before every migration; show complete verbatim
  code before every change is applied; separate commits for separate
  concerns; commit messages via `git commit -F <file>` (not inline `-m`,
  due to a ~965-byte PowerShell command-length limit).
- Local commits accumulate and get pushed together on explicit request —
  don't assume "committed" means "pushed."
