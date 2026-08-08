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
- **Abandoned 'open' meetings get silently treated as closed on reload**
  — `hydrateOrgData()` (`MyBizExco_21.html:2364`) fetches every meeting
  row for an org with no status filter at all (`:2368`), and
  unconditionally maps all of them — including ones stuck at
  `status:'open'` (e.g. a session abandoned mid-meeting, browser closed
  before `closeMeeting()` ever ran) — into `S.sessions`, where they
  render in the Minutes tab, count toward the dashboard's "Meetings"
  stat, and count toward the governance score, exactly as if properly
  closed. Pre-existing, not introduced by the meeting-cancel work.
  Deliberately not fixed as part of that change — needs its own scoping
  (likely a status filter in the `SELECT`, or explicit separate handling
  for stuck-open meetings vs. genuinely closed ones).

## Resolved snags

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
