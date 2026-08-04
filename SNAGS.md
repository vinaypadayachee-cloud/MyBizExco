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

### "About MyBizExco" copy is dense paragraphs, not scannable
**Priority:** Low / not urgent — worth doing before wider testing.
**Type:** UX / clarity.

Scope: the "About MyBizExco" step (top tab right after Welcome, setup
wizard step 1, `renderStepAbout()` at `MyBizExco_21.html:1625`). This is
the first real content a new user reads, and most of it is dense
paragraph text rather than scannable bullets:

- Info box "What it does" (line 1629) — one dense paragraph
- Info box "How to use it" (line 1630) — one dense paragraph
- FAQ-style card "Why MyBizExco Exists" (line 1634-1635) — one ~100-word
  paragraph
- FAQ-style card "Who It Changes, and How" (line 1638-1639) — one
  ~100-word paragraph
- The standard FAQ list below (`FAQS` array, rendered at line 1654) —
  plain-paragraph answers throughout

Already fine, no change needed: the third card, "What the World Looks
Like When It Exists" (line 1643-1649), is already formatted as 5 clean
bullet points.

Fix: reformat every paragraph block above into scannable bullet points,
matching the style already used in "What the World Looks Like When It
Exists".

(Note: the literal Welcome screen itself — `#welcome`, line 269-282 — is
already short and card-based, not paragraph-dense. No change needed
there; the actual density is one screen later, in "About MyBizExco".)
