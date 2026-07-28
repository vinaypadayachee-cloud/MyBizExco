# Changelog

`MyBizExco_21.html` — single-file, vanilla-JS governance app for South African SMMEs. This is the canonical source going forward; the earlier React+Babel lineage (`MyBizExco-DevPack/MyBizExco.html`) is no longer maintained or referenced.

## 2026-07-28 — Baseline QA pass

First full-app regression pass on this file, run through a real headless Edge browser (`puppeteer-core` driving an actual browser instance, not `jsdom`) covering: Welcome screen → all 7 setup wizard steps → Board meeting → Shareholder meeting → governance score confirmation → Coffee Exco session → minutes generation → Contact Us → top-tab navigation from every screen.

**Result:** zero console errors, zero `window.onerror` triggers, across the entire session. One real bug found and fixed (below); everything else passed cleanly.

### Fixed

- **Coffee Exco was a dead end for any real user.** The "☕ Start coffee meeting →" button never became enabled after typing a problem description — the underlying `S.meetingContext` state updated correctly on every keystroke, but nothing re-rendered the button, so it stayed stuck on "Describe your problem above to start" (disabled) regardless of what was typed. Root cause: the textarea's `oninput` only set state (`oninput="S.meetingContext=this.value"`) with no follow-up UI update, unlike the adjacent company-name field which calls `updateNextBtn()` on every keystroke. Fixed by adding an analogous `updateCoffeeBtn()` — a targeted `getElementById` + direct property update (disabled/background/color/text), not a full re-render, since a full re-render would have blurred the textarea mid-keystroke. Verified character-by-character: the button now enables on the very first keystroke, stays enabled through continuous typing without losing focus, and correctly re-disables if the field is cleared.

### Verified working, no changes needed

- Welcome screen and the full 7-step setup wizard (About MyBizExco, About Your Business, Compliance & Legal, Leadership Team, Decision Needed, Communication, Meeting Types), including the required-field gating on company name
- `TOP_TABS` persistent navigation bar and `goToSection()` — jumping between all 7 sections from any screen, before and after launch, correctly routes to the setup wizard step or the in-app config view as appropriate
- `COUNTRY` config swap point (flag/name/demonym) and the dynamic `#flagCardIcon` element
- Board meeting creation, deliberation, and close (native `confirm()` quorum-warning dialog fires and is handled correctly)
- Shareholder meeting creation and close, including the quorum warning for undeliberated items
- **Governance score correctly reflects a held Shareholder Meeting** — `govScoreBreakdown()` marks "Shareholder meeting held" as met (✅, +15/15) immediately after closing one, visible on the Home tab score breakdown
- Minutes generation (`printMins`) — correct formatting, attendance, agenda, actions table, signature block, for all three meeting types exercised (Board, Shareholder, Coffee Exco)
- Contact Us modal (`openContactUs()`) — feedback/bug report, direct email link, response-time note
- No evidence of any meeting-type-picker duplication issue — the picker is a straightforward `Object.entries(MT)` map with no possibility of duplicate entries

### Known constraints (inherited, not bugs)

- File is 149,111 bytes / ~2,400 lines — well past the ~100-110KB ceiling that the old React-based app was designed around for Claude.ai artifact rendering. If this app ever needs to run inside that sandbox again, it will need a build/minification step.
- All persistence is manual JSON export/import (`saveData()` / `restoreSession()`) — no `localStorage`, same as the prior lineage.
