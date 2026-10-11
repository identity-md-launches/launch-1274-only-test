# Website validation — Only test

Complete for the stated website scope. Checked locally on 2026-10-11. This records worker evidence, not an independent certification or a production deployment.

## Scope and design decisions

Read the complete JSON `brief` from `https://www.si-md.xyz/api/chat?op=site-brief&label=onlytest`, the pinned Better Interface workflow and core principles of all six domains, the pinned Ethereum testing reference and protected token test input. The previously accepted token, tests, launch manifest, dependencies and Foundry configuration were preserved.

The creator specifically requested black and white, generous space and a simple first screen; the supplied logo is itself a monochrome wordmark. That product-specific preference takes precedence over the brief's generic saturated-color description. Eight sections, original SVG compositions and motion carry the meme direction. The “CSS/SVG only” rendering option governs the visible page; the explicitly requested PNG downloads use an offscreen canvas only during export. No canvas is mounted in the page.

Both `index.html` and `404.html` were reviewed. `site/` is runnable source; `dist/` is its exact static runtime copy. Developer tools live in `web/`; no runtime packages, trackers, wallets, forms that submit data or hardcoded TEST address were added. The nullable X field was not replaced with a guessed account: the fallback is an explicit conversation search.

## Six-domain Better Interface review

| Domain | Coverage and evidence | Limits / not applicable |
| --- | --- | --- |
| Accessibility — checked | Semantic landmarks/headings; skip link; native buttons and labeled fields; keyboard menu/Escape/focus return; complete contract copy; pointer and keyboard sticker paths; persistent status feedback; visible focused mobile menu observed in the supplied browser; reduced motion and pause control; four axe WCAG A/AA scans with zero reported violations. | No screen-reader session, physical device, forced-colors visual review, or claim of complete WCAG conformance. No modal, wallet or data-submission flow exists. |
| Layout — checked | Real screenshots of both pages; ten widths between 320 and 1920px; no document/body overflow; primary action above the fold at 390×844; 200% text enlargement at 390px; fixed image dimensions, bounded sticker, responsive grids and real launch-state address wrapping. | Text enlargement is not native browser zoom. English only; RTL/localization is not an assigned variant. Host-level nested missing-route handling depends on publication configuration. |
| Writing — checked | Short product heading and plain description; all eight sections written for Only test; action labels match their state; no fabricated data, official account or return promises; “token tax” distinguished from the 1.25% pool fee; meter explicitly fictional; useful error and retry copy. | No translated copy. The token itself and live launch have not been redeployed by this task. |
| Typography — checked | Six site text roles, actual loading of all three local WOFF2 families, 16px inputs, appropriate body measure/line height, tabular market values and wrapping full addresses. Reviewed desktop/mobile text and SVG captions; long text and markup are safe in exports. | Supplied 96px logo is not high-resolution type. Rasterized meme captions use system fonts for standalone export. |
| Colors — checked | Dark monochrome tokens taken from logo/creator direction; solid reading surfaces; supporting text and controls checked; five rendered foreground/background pairs measured at 8.76:1–17.41:1, all above 4.5:1. | Axe reports the color-contrast rule as incomplete. Measured pairs do not establish every raster-logo pixel or every decorative stroke. No alternate theme was requested. |
| UI — checked | Empty/live/stale data states, explicit disabled copy state, hover/active/focus styles, menu, step guide, all nine downloads, bounded drag/click meter, share/copy controls, pause/reduced motion, animated numeric updates and buy confetti. | No browser Animations-panel replay at 10% speed. No Safari/Firefox session. X intent URLs were verified without posting. |

## Findings fixed and rechecked

| Severity / domain | Source location | Evidence and correction | Recheck |
| --- | --- | --- | --- |
| Medium / layout | `site/assets/style.css:1615` | At 390px the decorative hero grid extended the page to 415px. Confined its mobile inset to the art frame; kept the artwork and ticker within the hero. | All ten widths now have no horizontal page overflow. |
| Low / UI | `site/index.html:384`, `site/assets/style.css:2007`, `site/assets/app.js:54` | Browser screenshots showed missing-font boxes for the full-width plus and copy glyph. Replaced the plus with ASCII and both copy glyphs with outlined SVG. | Mobile header and desktop guide inspected again; all interaction and accessibility checks passed after the change. |
| Medium / accessibility + layout | `site/assets/style.css:1925` | 200% text enlargement made the 375px page expand to 469px. Allowed header wrapping, removed intrinsic grid minimums, bounded mobile display sizing and enabled long-text wrapping. | Supplied-browser 375px enlarged check had 375px document width; automated 390px enlarged check passed. |
| Medium / UI | `site/index.html:587`, `site/assets/app.js:565` | Native image drag interrupted pointer capture: the pointer drag left the meter at 5% instead of the expected 10%. Disabled native image dragging and prevented `dragstart`. | Real mouse drag now moves the sticker and advances the meter. Arrow keys, Enter, cap and reset also pass. |
| Medium / accessibility | `site/index.html:199` | Axe reported `aria-prohibited-attr` on the generic marquee label. The marquee repeats existing content, so it is now decorative and hidden from the accessibility tree. | Zero reported violations in all four final page/viewport scans. |

Caption sizing and XML escaping were also reviewed: 48-character captions wrap and fit, and input containing `<script>`, quotes and ampersands remains inert text in both the SVG preview and PNG. This is implemented in `site/assets/memes.js:56`.

## Commands and outcomes

- `forge build`: successful with the existing Solidity 0.8.26/Cancun configuration.
- `forge test`: **17 passed, 0 failed, 1 skipped**. Includes 3,000 fuzz cases, 256 invariant sequences / 16,384 handler calls, and both local Uniswap v4 currency-order integrations. The optional mainnet fork test skipped without `MAINNET_RPC_URL`. No live-state fork was run; the supplied protected verifier was read, not misrepresented as a locally runnable suite.
- `node scripts/build-site.mjs`: **passed**, 13 runtime files / **183,446 bytes**. The command packages the runnable static source without a compilation step.
- `/tmp/onlytest-tools/node_modules/.bin/tsc -p web/tsconfig.json`: **passed**, strict JavaScript/JSDoc typecheck with no emit.
- `node scripts/check-site.mjs`: **29 checks passed**, four axe scans, zero reported violations. The report includes exact viewport results and measured contrast pairs.
- `diff -qr site dist`: **passed**; source and export are identical.
- `python3 scripts/check-site-delivery.py`: checks runtime parity, relative asset references, no embedded TEST address, protected-file diffs, no dependency/cache/archive candidates or submodules, and the complete candidate file payload against 8 MiB. The final uncompressed candidate payload is approximately **5.30 MiB**, below the 8 MiB limit; the exact current count is printed by the command.

The standalone browser suite uses Chromium with intercepted requests fulfilled from the actual exported files, under an HTTPS `/preview/` subpath. This is an offline service fixture, not a copy of the page implementation. No package registry or API snapshot ships in the runtime. The browser clock tests a 30-second refresh without waiting in real time. A random address exists only in test memory and is never used as a deployment value.

The supplied browser additionally inspected the real HTTP export under `/preview/` at 375/390 and 1440px. Its local preview served the actual launch feed captured during this run: status `building`, no token, no market data, and the real launch URLs. All 11 observed document/script/font/logo/feed requests returned 200; the current external logo returned 200 too. Its console reported zero errors or warnings. Hero, story, guide, allocation, meme wall, generator, community and 404 were visually inspected. Browser observations are distinct from source review and axe results.

## Evidence

- [Machine-readable browser results](web/review/site-checks.json)
- [Desktop full page, 1440px](web/review/site-desktop-1440.jpg)
- [First screen, 390px](web/review/site-mobile-390.jpg)
- [404 page](web/review/site-404.jpg)
- [Design system](DESIGN.md)

The checked-in screenshots use the documented empty-launch fixture so they contain no invented live address or market value. All generated PNG downloads were checked for a PNG signature, nonempty content and 1200×1200 dimensions. A resulting custom PNG was also opened and visually inspected. Temporary downloads and exploratory screenshots are not shipped as runtime assets.

## Remaining limitations

The launch feed currently has no deployed token or market figures. The site handles that state and will use real values when the platform provides them. A failed or unsupported remote logo falls back to the bundled original. The original logo is only 96×96; no higher-resolution logo was invented, and social-network card rendering was not tested. Mainnet fork execution still requires an externally supplied RPC URL. The publication itself, external social services, physical-device behavior, screen readers and browser-native zoom remain outside the locally verified scope. No unresolved defect was found in the required primary interactions after correction.
