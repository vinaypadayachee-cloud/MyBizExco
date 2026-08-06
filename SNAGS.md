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

_None currently open._

## Resolved snags

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
