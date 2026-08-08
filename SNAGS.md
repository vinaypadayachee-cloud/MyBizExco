# MyBizExco — Snag List

## Known limitations (not bugs — not fixable within the app)

### WhatsApp sending is manual, not automatic
WhatsApp does not allow third-party apps to send messages directly into a
group — this is a platform restriction (no public API for unauthenticated
apps to post into a group chat), not something MyBizExco can work around.

Current behaviour: tapping "Send to {group}" (`sendWA()`,
`MyBizExco_21.html:2960`) copies the message to the clipboard and opens
`wa.me` with the group's first saved number pre-loaded. The user then has
to manually switch to the actual WhatsApp group and paste the message
themselves.

Investigated 2026-08-04: neither send screen currently has any on-screen
text explaining this manual step to the user —
- Post-meeting "Send hub" modal (line 2935-2957): WhatsApp section header,
  textarea, quick-fill buttons, "Send to {group}" button — no explanation.
- More tab → WhatsApp groups → compose (`composeWA()`, line 3183-3190):
  same — no explanation.
- Only feedback is a transient toast, "Message copied to clipboard"
  (line 2962), which fades and isn't persistent guidance.
- The only related copy anywhere is one setup-time line in the
  Communication step (line 1811): "Add phone numbers. After meetings,
  MyBizExco formats messages ready to paste." — not shown at send time.

Not tracked as an open item yet — no decision has been made on whether to
add/improve in-context copy on the send screens themselves. Revisit if so.

## Open snags

### 2026-08-06 batch (UX/navigation review)

#### Smaller, self-contained fixes
- **Landing screen flash for signed-in users** — landing page briefly renders
  before redirecting signed-in users to dashboard. Confirm whether
  auth-check can happen pre-render to eliminate the flash.
- **"Welcome" tab doesn't navigate anywhere** — tapping it on the dashboard
  doesn't return to landing page. Clarify intended destination first.
- **Score circle color** — solid red for low/starting scores reads as an
  error state. Recommend amber/grey scale for low scores, reserve red for
  genuine problems (if any exist).
- **Score breakdown page ("What's behind your score")** — needs a short
  explanatory line: what green vs. grey checkmarks mean, what the X/Y
  fraction represents, and whether the page is purely informational or
  expects user action. Also clarify how point caps (e.g. Board meetings
  +25/25) are determined — tied to configured meeting cadence, or fixed?

### 2026-08-08 (found during meeting-cancel navigation audit)
- **Meeting agenda page — Cancel unreachable after clicking Continue** —
  once Continue dismisses the Cancel/Continue footer
  (`dismissSessionNav()`), the only remaining action for the rest of the
  session is "Close meeting" — there's no way to cancel the meeting if
  the CEO changes their mind mid-session. Likely fix: add "Cancel
  meeting" as a standing option (e.g. alongside "Close meeting" at the
  bottom of the page) that stays available for the full session, rather
  than only appearing in the initial dismissible footer. Does NOT
  reopen the "should there be a Back button" question already settled
  in `b2c17f8` — Cancel's behavior (`cancelMeeting()`,
  `status:'cancelled'`) is already built, tested, and verified live.
  This is purely about reachability: Cancel needs to stay clickable
  after Continue, not disappear.

## Design decisions

Settled product decisions, not yet built. Ordered by build priority.

### 1. Procedural vs. Substantive agenda items — DECIDED 2026-08-08, not yet built
**Type:** Feature / data model change. **Priority:** 1 of 3 (build first).

Problem: currently every agenda item — including boilerplate items like
Welcome, Apologies, Conflicts of interest, Closure — goes through the
full multi-persona deliberation engine, even though there's nothing for
personas to have a perspective on. This also directly causes bloated,
repetitive minutes (see decision 3).

Decided:
- Add a manual Procedural/Substantive toggle at agenda item creation —
  NOT auto-detected by title, to keep classification explicit and
  auditable.
- Default state for new items: Substantive (deliberation) — safer to
  over-deliberate than silently skip real discussion.
- Standard boilerplate items (Welcome, Apologies, Conflicts of interest,
  Closure) ship pre-toggled as Procedural in templates and the AI-agenda
  flow, with the CEO able to flip any individual item to Substantive if
  something unusual comes up (e.g. a real conflict needing discussion).
- Procedural mode swaps the "Deliberate" button for a lightweight
  structured capture form (attendance, absentees, Y/N conflict declared
  + detail field) — not just a skip-to-free-text.
- Procedural items render in minutes as a plain factual line (e.g.
  "Welcome — meeting opened, all directors present"), not a persona-
  response block.

Needs before build: read-only audit of current agenda-item data model,
template structure, and renderSession()/deliberation call path to scope
the actual change.

### 2. CEO chair commentary + explicit Chairman field — DECIDED 2026-08-08, not yet built
**Type:** Feature / schema addition. **Priority:** 2 of 3.

Problem (a): no place for the CEO to comment on or react to an AI
deliberation's output after seeing it — only a pre-deliberation note
field exists.
Problem (b): no concept of "chairman" exists in the app at all —
implicitly assumed to be the CEO, never recorded. Given MyBizExco's
King IV-aware SA governance positioning, chair/CEO separation is a
recognised governance practice worth supporting even if most SMMEs will
set them as the same person.

Decided:
- Add a post-deliberation "Chair's comment" field, distinct from the
  existing pre-deliberation "Add CEO note" field. Gives the CEO/chair a
  place to react to, challenge, or add context to AI output, and a
  natural home for the actual decision reached.
- Add an explicit Chairman name field to org setup, defaulting to the
  CEO/founder name, but recorded separately and shown in the minutes
  header ("Chaired by: [name]").

Needs before build: read-only audit of org setup schema/UI and the
minutes-rendering header to scope the field addition.

### 3. Minutes synthesis instead of concatenation — DECIDED 2026-08-08, not yet built
**Type:** Feature / AI pipeline change. **Priority:** 3 of 3 (build last —
most open-ended technically, and largely resolved for procedural items
once decision 1 ships).

Problem: for substantive items, minutes currently concatenate every
persona's full response verbatim, producing long minutes where personas
often restate similar points — reads like a transcript, not real board
minutes.

Decided: add a summarization pass after persona deliberation that
synthesizes the discussion into real-minutes style — e.g. "The Exco
supported proceeding, with the CFO flagging cash-flow timing and the
CTO flagging system capacity" — rather than printing all persona
responses in full.

Needs before build: a technical decision not yet made — HOW the
synthesis gets generated (a further API call summarizing the personas'
outputs? a local heuristic/template? something else). Audit current
minutes-generation code path and propose 2-3 concrete approaches before
writing any code.

## Resolved snags

### Abandoned 'open' meetings get silently treated as closed on reload — RESOLVED 2026-08-08
**Was:** found during meeting-cancel navigation audit, not yet fixed.
**Type:** data integrity / UX.

Original scope: `hydrateOrgData()` fetched every meeting row for an org
with no status filter, unconditionally mapping all of them — including
ones stuck at `status:'open'` — into `S.sessions`, rendering them in the
Minutes tab and counting them toward dashboard stats/governance score
exactly as if properly closed.

Resolved in `9edd476` ("Carry meeting status through hydration; badge
and exclude correctly"):
- Root-caused and reproduced first: mocked `hydrateOrgData()`'s real
  mapping logic against synthetic closed/open/cancelled rows before
  writing any fix — confirmed abandoned-open and the newly-shipped
  `'cancelled'` status were hydrating to byte-for-byte identical,
  indistinguishable empty "Draft · v1" cards, meaning the "Cancelled"
  badge from `b2c17f8` was itself silently broken across any reload,
  not just the older bug.
- Checked blast radius against real production data (read-only SELECT
  via the REST API): 4 real rows stuck at `status:'open'`, 0
  `cancelled`, none with dependent `actions`/`ai_deliberation_log`
  rows — confirmed not theoretical.
- Fix: `status:m.status` now carried through hydration; `renderLog()`
  renders a distinct "Cancelled" (red `badge-cancelled`) or "Abandoned"
  (amber `badge-abandoned`) badge instead of the misleading Draft
  badge. Both statuses stay visible in the Minutes tab (per the
  earlier confirmed design) but are excluded from `govScore()`,
  `govScoreBreakdown()`, and `renderHome()`'s Meetings stat/Last-meeting
  card — filtered inside the scoring functions themselves so every
  caller benefits automatically.

QA: Puppeteer-core against real Edge, zero console/page errors.
Verified programmatically: correct badge per status, Home's Meetings
stat correctly excludes both, `govScore()`/`govScoreBreakdown()` agree
with each other. Screenshot taken confirming the three visually
distinct badge colors. Confirmed live in production post-push.

### Meeting agenda page Cancel/Back/Continue navigation — RESOLVED 2026-08-08
**Was:** needs-your-decision item. **Type:** UX / navigation / data model.

Original ask: only "Close meeting" existed on the meeting agenda page.
Needed Cancel meeting, Back, Continue.

Resolved across two commits:
- `3b231a6` — backend: `cancelMeeting()` (a `closeMeeting()`-style
  Supabase status-update function) plus
  `supabase/010_meeting_cancelled_status.sql`, adding `'cancelled'` to
  `meetings.status`. Decided "Cancel" never deletes the meeting
  record — a physical delete would be blocked by FK constraints on
  `actions`/`ai_deliberation_log` once deliberation has started, and
  would destroy audit trail either way. Migration run directly against
  production (no separate staging DB), verified via a direct
  `pg_constraint` query.
- `b2c17f8` — UI: one "✕ Cancel meeting" button (calls
  `cancelMeeting()`) plus one "Continue" button that only dismisses the
  footer, nothing else. No separate "Back" button — since a real,
  permanent `'open'` `meetings` row already exists in Supabase the
  instant a session starts, there's no resumable-draft state for
  "Back" to safely mean anything distinct from Cancel. Reuses the
  existing `.nav-btns`/`.btn-back`/`.btn-next` CSS rather than
  extending `renderNavFooter()`'s signature. `S.sessionNavDismissed`
  resets on every `openSession()` call, so the footer reappears fresh
  each new session.

QA: Puppeteer-core against real Edge, zero console/page errors on both
commits. Verified programmatically (not just visually): footer labels,
Continue leaving the session open, footer reappearing on a new
session, and Cancel actually tearing down the session and pushing a
`status:'cancelled'` entry into `S.sessions`. Confirmed live in
production post-push via `git show`/direct `curl`+`grep`, pasted in
full each time per standing request.

### "Use template" flow — no back/exit/continue — RESOLVED 2026-08-08
**Was:** needs-your-decision item. **Type:** UX / navigation.

Original ask: the "Use template" flow had no back/exit/continue once
opened.

Resolved as a side effect of the meeting-agenda-nav work above, not a
separate implementation — required zero additional code. `useTmpl()`
calls the exact same `openSession()` that `openSession(null)` (AI
agenda) and `startCoffeeSession()` call, which renders the exact same
`renderSession()` with its new Cancel/Continue footer. Verified, not
assumed: drove the real UI (opened the template modal, clicked an
actual "Use" button, not calling `useTmpl()` directly), confirmed the
footer renders with identical labels/onclick handlers, and confirmed
Cancel behaves identically for a template-originated session
(`agendaItemTypes` all `'template'`, confirming the real template path
was exercised). Zero console/page errors.

### Tools/More page "Continue" button — RESOLVED 2026-08-07
**Was:** needs-your-decision item. **Type:** UX / navigation.

Original ask: the More tab's "Continue" button was greyed out with an
unclear destination.

Resolved in `67e167a` ("Wrap More tab's dead-end Continue button
around to Home") — same commit already logged in `SESSION-HANDOFF.md`
but never marked resolved here. `renderAppNavBtns()` gained a special
case for `S.tab==='more'`: the button now reads "Home →" and calls
`switchTab('home')`, since sign-in, launch, and session-restore all
land on the `'home'` tab, making it the app's genuine landing point.
Scoped narrowly — `prev` and every other tab's `next` computation are
untouched.

Confirmed 2026-08-08, during the meeting-cancel-navigation follow-up,
that this is the *only* "Continue" reference anywhere on the More
page — no second, separate button exists inside `renderMore()`'s own
content.

### Navigation labeling standard — RESOLVED 2026-08-06
**Was:** app-wide consistency pass. **Type:** UX / navigation.

Original ask: back/continue buttons should be labeled with their actual
destination/outcome (e.g. "← Leadership Team", "Done — back to app →"),
not generic "Back"/"Continue", applied everywhere except initial
landing/sign-in.

Resolved in `ca744ed` ("Unify page navigation under a shared
`renderNavFooter()` helper"): replaced three independent nav-generation
mechanisms (bespoke per-wizard-step markup, the array-driven
`renderAppNavBtns()`, and `renderAppConfig()`'s inline block) with one
shared `renderNavFooter(back, next, wrapClass)` function. All 7 wizard
steps, the 5 main-app tabs, and the 5 config pages now render their
back/continue buttons through the same code path, each still passing
its own destination-aware label (e.g. "← About MyBizExco", "Compliance
& Legal →", "🚀 Launch MyBizExco", "Done — back to app →") rather than
a generic one.

Scope deliberately excluded, not overlooked: auth/invite screens
(different semantics — mode-toggle/form-submit, not step-navigation,
so the sign-in edge case from the original ask doesn't apply the same
way there), the meeting session screen (has no nav at all — separate
open item above, "Meeting agenda page navigation," blocked on the
Cancel-semantics decision), and the template modal.

QA: Puppeteer-core against real Edge, zero console/page errors, all 7
wizard steps' and all 5 tabs' back/next labels verified against
expected values (including two pre-existing edge cases confirmed
unchanged: Home tab's back button still renders disabled-but-present
rather than omitted, and More tab's Continue still shows its known
disabled dead-end — that dead-end itself is untouched, tracked
separately as "Tools/More page Continue button" above). Confirmed live
in production post-push.

### Input-field visual affordance — RESOLVED 2026-08-06
**Was:** app-wide consistency pass. **Type:** UX / clarity.

Original ask: any field awaiting user input should get a light-blue
highlight, consistent with landing-page accent blocks, as a shared
CSS class/component rather than a per-page fix.

Resolved in `bdca24c` ("Add shared light-blue highlight for empty
input fields"): empty `.field` inputs/textareas/selects get a
light-blue border+background (`#bfdbfe`/`#eff6ff`) via a shared
`refreshFieldEmptyStates()` helper, wired into every render path that
produces `.field` markup — the wizard, config pages, auth, invite, and
modals generically (via `openModal()`, so future modals inherit it
automatically). `:not(:focus)` keeps the new blue mutually exclusive
with the pre-existing amber `:focus` border by construction, so the
two never compete.

Two things worth noting for future reference:
- The color came from `.info-box`'s existing blue, not the landing
  page — checked, and the landing page (`#welcome`/`.w-*`) turned out
  to have no actual "accent block" blue color at all, only the
  `.w-tagline` text color (`#93c5fd`). `.info-box`'s blue was judged
  the closer match to "consistent with existing accents."
- The app's only 2 `<select>` elements (business size, province)
  always default to a real value and so never actually go empty in
  practice — the highlight is currently input/textarea-only in visible
  effect, not a gap in the mechanism itself (it's written generically
  to cover `<select>` too).
- Removed a bespoke inline "has content" indicator on the
  meeting-focus textarea (`renderBoard()`) that would otherwise have
  silently fought the new shared mechanism (inline styles beat class
  selectors on specificity).

QA: Puppeteer-core against real Edge, zero console/page errors,
screenshot taken of wizard step 2 to visually confirm the highlight
(5 empty text fields highlighted, the 2 selects correctly not).
Confirmed live in production post-push.

### "About MyBizExco" copy is dense paragraphs, not scannable — RESOLVED 2026-08-05/06
**Was:** Low / not urgent. **Type:** UX / clarity.

Original scope: the "About MyBizExco" step (`renderStepAbout()`,
`MyBizExco_21.html`), most of it dense paragraph text rather than
scannable bullets — both info-boxes, the "Why MyBizExco Exists" and
"Who It Changes, and How" faq-items, and the `FAQS` array's answers.

Resolved across two commits:
- `905e90e` rewrote the wording of the "What it does" info-box (→ "What
  is MyBizExco?") and the "Why MyBizExco Exists" faq-item (→ "Welcome
  to MyBizExco"), and fixed a stale `FAQS[3].a` unrelated to formatting.
- `61b9b14` converted to bullets: both info-boxes ("What is MyBizExco?",
  "How to use it"), the "Who It Changes, and How" faq-item, and
  `FAQS[1]` ("What does it do?").

Deliberately left as prose, not overlooked: "Welcome to MyBizExco"
(reads as an argument/origin story, not a feature list — bulleting it
would flatten the rhetorical build) and `FAQS[0]`, `FAQS[2]`,
`FAQS[3]`, `FAQS[4]` (no natural list content, already short). The
"What the World Looks Like When It Exists" faq-item needed no change —
it was already 5 clean bullets.

QA: Puppeteer-core against real Edge, zero console/page errors on both
commits, screenshots reviewed before committing, both confirmed live in
production post-push.

(Note: the literal Welcome screen itself — `#welcome`, line 269-282 — was
never in scope here; it was already short and card-based, not
paragraph-dense. The density was one screen later, in "About MyBizExco".)
