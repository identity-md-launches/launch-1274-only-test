# Only test — implemented website design

## Overview

The site is a monochrome internet experiment for the Only test ($TEST) Ethereum token. The creator's explicit black-and-white, spacious direction and the supplied black wordmark take precedence over the generic saturated meme palette. The hero contains the name, real logo, a plain description, primary launch/buy action, chart and contract. The eight requested sections follow the full brief's order; the meme lab and sticker stress test provide the richer interaction below the initial view.

Source: `site/index.html`, `site/404.html`, `site/assets/style.css`, `site/assets/app.js`, and `site/assets/memes.js`. `dist/` is an exact runtime copy, not a separate implementation. No framework or runtime dependency is required.

## Colors

The hex primitives and semantic aliases are at the beginning of `site/assets/style.css`.

| Semantic token | Value | Role |
| --- | --- | --- |
| `--bg`, `--on-accent` | `#0b0b0b` | Page and dark text on light actions |
| `--surface` | `#141414` | Stats, tokenomics, lab and inset panels |
| `--surface-raised` | `#252524` | Secondary action hover |
| `--ink`, `--accent` | `#f2f1ed` | Main text, primary actions, pool allocation |
| `--muted` | `#b3b3af` | Supporting copy and labels |
| `--line` | `#424240` | Decorative structure and dividers |
| `--control-line` | `#80807b` | Input and secondary button boundaries |
| `--focus` | `#ffffff` | Two-pixel keyboard outline with five-pixel offset |

There is one dark theme. Light meme panels and the marquee are intentional inversions. Status is communicated in words, including unavailable, launching and stale-data states. Five browser-computed text/background pairs were measured: main text and primary action text 17.41:1, muted on the page 9.36:1, muted on a surface 8.76:1, and input text 17.41:1. These measurements do not cover every pixel of the supplied raster logo or SVG illustrations.

## Typography

Three Google Fonts families are bundled locally as Latin WOFF2 subsets with OFL licenses. All use `font-display: swap`.

| Role | Font and weight | Size |
| --- | --- | --- |
| Display | Archivo Black, 400; Impact/sans-serif fallback | `--text-display`: `clamp(5.5rem, 11.4vw, 10.5rem)` |
| Section heading | Archivo Black, 400 | `--text-heading`: `clamp(2.25rem, 4.7vw, 4rem)` |
| Card title | DM Sans, 700 | `--text-title`: `clamp(1.4rem, 2vw, 1.75rem)` |
| Lead / major control | DM Sans, 400–600 | `--text-lead`: `1.25rem` |
| Body / fields | DM Sans, 400–700; Arial/sans-serif fallback | `--text-body`: `1rem` |
| Labels / contract / numbers | Space Mono, 400; monospace fallback | `--text-small`: `0.8125rem` |

The DM Sans file supplies variable weights; the implementation uses 400–700. Headings use 1.08 line height and negative tracking; body uses 1.6. Copy has a 65-character maximum measure, balanced headings and pretty paragraph wrapping. Live numbers use tabular digits. Long IDs and enlarged text can wrap. Inputs remain at least 16px at the default browser font size. SVG artwork has its own fixed 600×600 coordinate system and system-font captions so downloaded PNGs do not depend on external font loading.

At 600px and below, the display role uses `min(--text-display, 24vw)` to keep the product name within its column during text enlargement. The mobile display token itself is `clamp(5.5rem, 24vw, 8rem)`. These are responsive variants of the display role, not additional type-scale steps.

## Layout

`--s1` through `--s9` define the 4, 8, 12, 16, 24, 32, 48, 64 and 96px spacing vocabulary. Components also use intermediate multiples of four where needed. `.wrap` shares the alignment edges and caps content at 1280px. Desktop gutters are 56px; they become 32px at 1120px and 20px at 600px. Section padding is 96px, 64px at 860px, and 56px at 600px.

Desktop has a two-column hero, three story cards, three stats, and a four-column meme wall. At 860px the navigation becomes an expandable mobile menu, story cards become illustration/text rows, and the meme wall becomes two columns. At 600px the primary layouts stack, stats become compact rows, the hero orbit becomes a small logo beside the name, and the ticker is positioned separately. The tiny-width rule at 370px simplifies spacing and stacks share buttons. The sticker stays bounded within its playground. Grid children use zero intrinsic minimums and the header can wrap during text enlargement.

The site was checked at 320, 360, 375, 390, 600, 768, 860, 1024, 1440 and 1920px. It had no horizontal page overflow. At 390×844 the primary action ends at approximately 464px. A separate 200% text-enlargement check passed; native browser zoom was not measured.

## Elevation & depth

The design is mostly flat. One-pixel dividers organize surfaces; thick outlines and offset solid shadows distinguish paper stickers. The hero has a dotted grid, SVG orbit and a faint static SVG noise texture, confined to decoration. Reading surfaces have solid backgrounds. The toast uses a conventional translucent shadow and sits above content. The sticky header is layer 40, notifications 80 and temporary confetti 90.

## Shapes

`--radius` is 4px for controls and small panels, `--radius-card` is 8px, and `--radius-pill` is 100px for the ticker. Circular orbit, donut, download controls and allocation dots complement the rectangular terminal, receipt and meme prints. Rotated elements are decorative except the deliberately draggable sticker.

## Components

- **Actions:** `.button.primary` is the filled action; `.button.secondary` is outlined. Actual launch links come only from `/simd-coin.json`. Before a URL arrives, links have no `href`, retain a keyboard path and explain their unavailable state. With a launch URL but no token, the primary action says “View launch”; it changes to “Buy $TEST” when a valid token arrives. External actions open a new tab with `noopener noreferrer`. A live buy click produces CSS confetti unless motion is paused or reduced.
- **Navigation:** `.site-header`, `.navigation`, `.menu-toggle`. A native button controls an expanded, nonmodal navigation region. Escape closes it and returns focus; selecting a section closes it. The skip link targets `main`.
- **Data and contract:** `refreshData`, `applyData`, `showStat` and `setLaunchLink` in `app.js`. The same-origin feed refreshes every 30 seconds while visible, and immediately on return to the tab. Updates time out after eight seconds. Missing values are dashes, not zeros. Failed updates retain previous data with a stale label. Full contract text remains selectable; both copy buttons activate only after a valid address arrives. HTTPS destinations are validated before assignment.
- **Guide:** `.guide-step` buttons expose `aria-pressed`; `selectStep` updates the associated region and Next step advances through all three instructions. No wallet connection is included.
- **Allocation:** `.donut` uses an animated SVG with a text equivalent. The 90% pool / 10% swarm split and one-billion supply are explicit. Copy distinguishes zero token tax from the pool's separate 1.25% trading fee.
- **Meme wall and generator:** eight original SVG compositions in `memes.js`; `memeSvg` escapes user text and fits captions. Labeled native fields update a live visual preview. All nine download controls export 1200×1200 PNGs. Canvas exists only temporarily for file export; visible artwork is SVG/CSS. User text never leaves the browser.
- **Sticker stress test:** pointer capture or arrow keys move the supplied logo within a bounded area. A tap, Enter or completed drag adds five points to an explicitly fictional vibe meter, capped at 100. Home recenters it; Reset experiment clears the meter and position. Native image dragging is disabled.
- **Motion:** 4-second logo bob, 32-second marquee, 650ms reveals with 100ms story-card staggers, animated data updates and donut entrance. The header's pause control and `prefers-reduced-motion` disable motion. Hover is gated to hover-capable devices. Page content never depends on JavaScript hiding/revealing it.
- **Notifications:** a stable `role=status` announces copy/download feedback. The dismissible toast stays available until dismissed; download feedback also appears next to its control.
- **404:** the same type, surfaces and buttons, a descriptive heading and a relative home link. It has no application script.

## Do's and don'ts

Reuse `.wrap`, section headings, the six type roles and the action variants. Keep contract text complete and selectable. Treat market, pool fee, token tax and the fictional vibe meter as separate facts. Keep the original logo as the fallback and prefer a supported, loadable `logo` from the live feed. The provided 96×96 wordmark is intentionally preserved; the site does not invent a replacement logo or official X profile.

For another page, create its own folder under `site/`, use `../assets/style.css` and other relative assets, add its title/social metadata, and include it in browser checks before regenerating `dist/`. Do not add runtime package dependencies, trackers, wallet infrastructure, invented market values, or a build requirement to view the source.

Design guidance: Jakub Krehel's Better Interface, pinned commit `267330e1adfc66a718fb65fa6918c1f06d0a689e` (MIT). Documentation structure: Paul Bakaus's Impeccable, pinned commit `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8` (Apache-2.0). Notices and license texts are retained in `web/licenses/better-interface.txt`. The implemented tokens and behavior above are extracted from the final source; see `SITE-VALIDATION.md` for verification coverage and limits.
