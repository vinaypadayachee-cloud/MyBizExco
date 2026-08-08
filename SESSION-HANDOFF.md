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

### 2026-08-06
- **Added a fresh UX/navigation review batch to `SNAGS.md`** (`5c3649d`,
  committed and pushed): meeting agenda page navigation, the Tools/More
  "Continue" dead-end, the "Use template" flow, an app-wide navigation
  labeling standard, input-field visual affordance, plus several
  smaller self-contained fixes (landing-screen flash, "Welcome" tab,
  score circle color, score breakdown copy). See `SNAGS.md` for the
  full list — two of these items (navigation labeling, input-field
  affordance) were picked up and closed the same day, below.
- **Navigation labeling standard + input-field visual affordance**
  — two distinct `SNAGS.md` items, worked together (shared a read-only
  audit pass) but landed as two separate commits per standing policy:
  - `ca744ed` — "Unify page navigation under a shared
    `renderNavFooter()` helper" (28 insertions/33 deletions, committed
    and pushed, confirmed live in production). Replaced three
    independent nav-generation mechanisms (bespoke per-wizard-step
    markup, the array-driven `renderAppNavBtns()`, and
    `renderAppConfig()`'s inline block) with one shared
    `renderNavFooter(back, next, wrapClass)` function — all 7 wizard
    steps, the 5 main-app tabs, and the 5 config pages now render
    through the same code path. A full read-only audit (via a
    background research agent) preceded any code: every page/screen
    with back/continue nav was mapped, along with every shared helper
    function (`show`, `setStep`, `nextStep`, `switchTab`,
    `goToSection`) already in the file. Two real edge cases surfaced
    only while drafting the actual diffs (not caught in the design
    phase) and were preserved via optional params rather than dropped:
    `renderAppNavBtns()`'s wrapper div uses a different CSS class
    (`app-nav-btns` vs `nav-btns`, different margin/padding) than every
    other nav block; step 2's Continue button carries `id="nextBtn"`,
    which `updateNextBtn()` live-toggles on every keystroke in the
    company-name field. Scope deliberately excluded (flagged, not
    silently dropped): auth/invite screens (different semantics —
    mode-toggle/form-submit, not step-navigation), the meeting session
    screen (has no nav at all today — that's a separate open
    `SNAGS.md` question about Cancel semantics), and the template
    modal.
  - `bdca24c` — "Add shared light-blue highlight for empty input
    fields" (19 insertions/1 deletion, committed and pushed, confirmed
    live in production). Empty `.field` inputs/textareas/selects get a
    light-blue border+background (`#bfdbfe`/`#eff6ff`, matching the
    existing `.info-box` blue — chosen over the landing-page tagline's
    `#93c5fd` since the landing page turned out to have no actual
    pre-existing "accent block" blue, only that one text color) via a
    shared `refreshFieldEmptyStates()` helper, wired into every render
    path that produces `.field` markup: the wizard (`renderStep()`),
    config pages (`renderTab()`), auth (`renderAuthBody()`), invite
    (`renderInviteBody()`), and modals generically (`openModal()`, so
    future modals get it for free — found and fixed two modals that
    would otherwise have been missed, `editDL()`/`editCustomDL()`).
    `:not(:focus)` keeps the new blue mutually exclusive with the
    existing amber `:focus` border by construction. Also removed a
    bespoke inline "has content" indicator on the meeting-focus
    textarea (`renderBoard()`) that would have silently fought the new
    shared mechanism — inline styles beat class selectors on
    specificity, so the old indicator would have won on `border-color`
    while the new rule won on `background`, producing a broken
    half-applied look.
  - Went with Option B (JS-driven `.value` check) over Option A
    (CSS-only `:placeholder-shown`) specifically so `<select>` elements
    are covered by the same mechanism as `<input>`/`<textarea>` — even
    though, once checked, the app's only 2 `<select>` elements
    (business size, province) never actually go empty in practice
    (both default to a real value, `sme`/`Gauteng`), so the highlight
    is currently input/textarea-only in visible effect. Not a mechanism
    gap, just current data behavior — visually confirmed via screenshot
    (5 empty text fields highlighted; the 2 selects, both carrying
    their real defaults, correctly showed no highlight).
  - QA passed: Puppeteer-core against real Edge, zero console/page
    errors, covering both commits together — all 7 wizard steps'
    nav-footer output, the step-2 `nextBtn`/field-empty interaction
    (typed into the company-name field, confirmed both the disabled
    state and the blue highlight cleared together), all 5 main-app
    tabs' back/next labels (including Home's disabled-but-present back
    button and More's known disabled Continue dead-end — both
    unchanged, confirmed not regressed), a config page, and a modal.
    Screenshot taken of wizard step 2 to visually confirm the blue
    highlight.
  - Split into two commits from one applied batch of 18 diff hunks
    using `git apply --cached` against a hand-built nav-footer-only
    patch (staging the index only, never touching the already-QA'd
    working tree), verified via hunk-count and content greps before
    each commit — chosen over a `git stash`-based split specifically to
    avoid any risk of merge-conflict markers landing in the real file.
  - Verified live: fetched `https://mybizexco-vanilla.vercel.app/`
    directly post-push, `Last-Modified` matched the fetch moment
    exactly. Confirmed present: `renderNavFooter()`,
    `refreshFieldEmptyStates()`, the `.field-empty` CSS rule, and the
    absence of the old bespoke inline meeting-context indicator.

### 2026-08-07
- **Fixed top tab bar showing wrong highlight on Home/Minutes/Actions**
  (`b1460bb`, "Fix top tab bar showing wrong highlight on
  Home/Minutes/Actions", 1 file changed, 1 insertion/1 deletion —
  committed and pushed, confirmed live in production):
  - Read-only audit first (via a background research agent), covering
    3 separate questions in one pass: the top-tab-bar/bottom-nav
    relationship, whether the governance score shown in 3 places is
    one shared computation or duplicated logic (confirmed: one shared
    `govScore()` function, called independently but with identical
    live state at each site — no duplication, no changes needed), and
    whether the "More" page reached via bottom-nav vs. the Actions
    page's "More →" button are the same page (confirmed: yes, both
    literally call `switchTab('more')`, no divergence).
  - The top-tab-bar audit found the actual bug: `switchTab()`
    collapsed `S.topActiveKey` to a hardcoded `'welcome'` for any
    bottom-nav tab without a `board`/`more` alias — meaning tapping
    Home, Minutes, or Actions left the top bar incorrectly showing
    "Welcome" highlighted, even though none of those three tabs have
    a corresponding button in the 8-entry `TOP_TABS` array to begin
    with.
  - Fix scoped deliberately narrow, confirmed before implementation:
    only `switchTab()`'s fallback changed (from hardcoded `'welcome'`
    to `tab` itself), preserving `board`→`meetingtypes` and
    `more`→`communication` unchanged. Explicitly out of scope by
    request: the `communication` label (rename tracked as a separate
    follow-up), the 5 wizard-only top-tab entries
    (about/business/compliance/leadership/decisions), and the
    `setStep()`/`renderStep()` writers of the same state variable.
  - Net effect, confirmed and flagged before applying (not assumed):
    since no `TOP_TABS` entry exists for `home`/`log`/`actions`, the
    fix results in **no top-tab highlight** for those three rather
    than a correctly-lit button — a real fix (stops showing the wrong
    highlight) but not a positive one, since no button exists yet.
    Adding one would be a separate, larger task.
  - QA passed: Puppeteer-core against real Edge, zero console/page
    errors, all 5 bottom-nav tabs checked — confirmed Home/Minutes/
    Actions now show no top-tab highlight (previously wrongly showed
    "Welcome"), Board/More unchanged ("Meeting Types"/"Communication"
    still correctly highlight).
  - Verified live: `curl`'d `https://mybizexco-vanilla.vercel.app/`
    directly (not the Vercel dashboard), grepped the served
    `switchTab()` body directly rather than summarizing — confirmed
    line 2138 reads `: tab` (not the old hardcoded `: 'welcome'`).
    `Last-Modified: Fri, 07 Aug 2026 08:10:20 GMT` postdates the push.
- **Renamed the "Communication" top-tab label to "More"** (`2a47e12`,
  "Rename top-tab label from \"Communication\" to \"More\"", 1 file
  changed, 1 insertion/1 deletion — committed and pushed, confirmed
  live in production). This was the piece explicitly deferred from the
  top-tab-highlight fix above:
  - Reported the full contents of `renderMore()` (all 8 sections —
    Session data, Governance health, Email distribution lists,
    WhatsApp groups, Communication items, Registers, Tools &
    generators, CIPC filing guide) before proposing anything, since
    only 3 of the 8 sections are actually communication-related.
    Offered label directions as discussion starters rather than
    picking one — you chose "More," matching the bottom-nav tab's own
    name.
  - Scope confirmed narrow before implementation: only the `label`
    string in the `TOP_TABS` array changed (`MyBizExco_21.html:382`).
    The `k:'communication'` key itself is untouched (still used
    internally by `S.topActiveKey` and `switchTab()`'s
    `tab==='more'` mapping) — renaming that would be a separate,
    larger-blast-radius change, not done here. Also confirmed and left
    alone: `STEP_LABELS`'s own, differently-scoped "Communication"
    entry (`:1607`) — the wizard's step-6 progress header ("Step 6 of
    7 — Communication"), which accurately describes that setup step
    and isn't the same thing as this top-tab alias.
  - QA passed: Puppeteer-core against real Edge, zero console/page
    errors — confirmed the top-tab bar now reads "More" when on the
    More tab, the word "Communication" no longer appears anywhere in
    the top-tab bar, and the wizard's step-6 label is unchanged.
  - Verified live: `curl`'d `https://mybizexco-vanilla.vercel.app/`
    directly, grepped the served `TOP_TABS` entry directly — confirmed
    line 382 reads `label:'More'`. Response headers also pasted in
    full rather than summarized, per explicit request each time.

- **Fixed the More tab's dead-end "Continue →" button** (`67e167a`,
  "Wrap More tab's dead-end Continue button around to Home", 1 file
  changed, 4 insertions/1 deletion — committed and pushed, confirmed
  live in production):
  - Answered a prerequisite question before proposing anything: is
    "the page that loads when signed in" the same as the `'home'`
    entry in `APP_TAB_ORDER`, or a separate screen? Traced 4 separate
    entry points (sign-in success, session restore, first-time
    `launchApp()`, and clicking the top-tab "Welcome" entry while
    launched) — all 4 funnel into `switchTab('home')`. Confirmed:
    Home is genuinely the app's landing point, not a separate concept.
  - Fix: `renderAppNavBtns()` gains a special case for
    `S.tab==='more'` only — its Continue button now wraps around to
    Home instead of dead-ending (disabled, `onclick=""`). Label
    changed from `"Continue →"` to `"Home →"` since it's now honest
    about its actual destination, calling the same `switchTab('home')`
    every other nav button already uses. Turns the 5 tabs into a full
    loop: Home→Board→Minutes→Actions→More→Home.
  - Scoped deliberately narrow, confirmed before implementation: only
    More's `next` branch changed; `prev` and every other tab's `next`
    computation in `renderAppNavBtns()` are untouched — verified
    byte-for-byte identical for Home/Board/Minutes/Actions after the
    change (same labels, same onclick targets, same disabled states
    as before).
  - QA passed: Puppeteer-core against real Edge, zero console/page
    errors, all 5 tabs' nav-footer output checked, and the "Home →"
    button was actually clicked (not just inspected) to confirm
    `S.tab` becomes `'home'` afterward.
  - Verified live: `curl`'d `https://mybizexco-vanilla.vercel.app/`
    directly, grepped the served code — confirmed lines 2178-2184
    match exactly, including the `moreWrapsToHome` variable name and
    both branches of the ternary. `Last-Modified: Sat, 08 Aug 2026
    04:04:59 GMT` postdates the push. Raw curl/grep output pasted in
    full each time, not summarized, per explicit standing request.
  - Separately discussed, deliberately left as-is (not a bug, a scope
    decision): the "More →" button on the Actions tab, which leads to
    the same More tab. A narrower label (e.g. "Send Communication")
    would misrepresent 5 of the More tab's 8 sections — same reasoning
    already applied when the top-tab label was renamed to "More"
    earlier. Splitting the More tab into two separate tabs
    ("Communication" and "Tools") was raised as a future option but
    explicitly deferred — flagged as a real feature restructure, not
    a bug fix, and not part of the current priority queue.

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
