# Design System

Brand thesis, the homepage provider boundary, color, typography, motion, charts and icons, the website, and the brand assets of JP the Cat.

**The cat that counts your agent tokens.**
Naming and domain casing are owned by root `AGENTS.md` ("Identity & Branding").
Exact values live in code: `web/app/globals.css` for the site, `mac/Sources/JPtheCatApp/Theme.swift` (`JPTheme`) and `JPAppDesignTokens.swift` (`JPAppColor`, `JPAppFont`, `JPAppSpacing`) for the app.
Native surface contracts live in [12-ui-surface-invariants.md](12-ui-surface-invariants.md).

## 1. Thesis

*A quiet daylight instrument for your AI spend — the calm, legible opposite of a blinking dashboard.*

1. **Legible** — the numbers are the hero, never the chrome.
2. **Calm** — color appears only when something needs attention.
3. **Precise** — tabular figures, exact resets, honest provenance labels.
4. **Warm** — cream paper, one warm accent, humanist type.
5. **Trustworthy** — no dark patterns and no hidden telemetry.

Not a hacker terminal (no pixel fonts, scanlines, god-rays, film grain, or dithering), not a notch spectacle, not a neon AI-SaaS gradient, not a dense trading terminal.

**Brand fidelity:** start every design from the live homepage or app and resolve each color in its established role; the incident behind the rule is [00-foundation.md#brand-fidelity](00-foundation.md#brand-fidelity).

## Homepage provider boundary

The homepage is a fixed curated presentation of All providers, Claude, Codex, Grok, Muse Spark, Cursor, and OpenCode Go, in that order.
All providers is an aggregate control, not a vendor or a catalog entry.
The six provider identities apply to homepage copy, marquee, FAQ, demo selection, analytics, Live Data, and menu-format examples.
Do not add providers to the homepage when the native app or `/library` gains support.
Keep the existing homepage layout, dimensions, typography, color roles, controls, motion, and responsive behavior; native geometry experiments do not change homepage geometry.
Shared controls retain semantic parity for units, provenance, badges, actions, and themes.
The frozen homepage Cursor illustration stays token-based and non-aggregable; OpenCode Go stays a measured, non-aggregable gateway. The native unified Grok source/accounting contract is owned by [03-data.md](03-data.md#unified-grok-plan-usage-and-cursor-local-activity); a homepage illustration never creates another native provider.
Demo aggregate and composition figures sum only represented aggregable rows, with no hidden-provider contribution or gateway double counting.
The full native catalog, CLI, widget eligibility, and `/library` remain independent of this boundary.
`web/lib/homepage-providers.ts` owns the allowlist; `homepage-providers.test.tsx` pins it.

## 2. Color

Light is canonical and designed first; the app's dark themes are faithful inversions, and the marketing site is light-only.

**Core roles.** `paper` (warm cream canvas), `paper2` (recessed wells), `card` (raised near-white cream, never pure `#FFFFFF`), `ink` / `inkSoft` / `inkFaint` (primary, secondary, tertiary text), `line` / `lineStrong` (hairlines, edges), `track` (empty meter groove).

**Accent.** Three distinct shipped tokens, never interchangeable:
- `--color-ginger` `#df7a2e` — the accent itself (wordmark dot, active state, sparkline stroke).
- `--color-ginger-deep` `#a84d14` — accent-colored *text*.
- `--color-cta` `#a84f16` with `--color-cta-deep` and `--color-cta-text` — the CTA button fill and its label.
The accent steps off Anthropic terracotta toward amber-honey, because JP is multi-provider.

**Status.** `sage` = healthy headroom and `official` provenance; `honey` = approaching limit and `notional`/`est.` provenance; `coral` = near or over limit.
Provenance is carried by sage and honey badges; there is no separate estimate hue.

**Provider colors** (`--color-p-*`, `JPAppColor.tintHex(for:)`) appear only as a dot, a sparkline stroke, a thin rail, or the icon chip behind a white glyph — never as text.
Status color drives the gauge; provider color stays on identity.
Accent, status, and provider color are three channels and never mix.

**Gradient.** The one shipped gradient is the warm `honey`→`ginger` ribbon (estimate gauge, email accent rule); everything else is flat.

**Interactive rollover (hard).** Every clickable control has a visible warm hover: Sticker Bomb word CTAs use `.sb-btn`, the support modal keeps `.btn-primary` or `.btn-ghost`; icon controls (modal close, mobile-nav summary, FAQ toggle) turn `hover:border-ginger` + `hover:text-ginger-deep` over a `hover:bg-paper-2` wash.

### App themes

`JPTheme.all` is the catalog: Sunlit Ledger (light) and Midnight Ledger (dark) show inline in Settings; the rest (`inMoreThemes: true`) live in the More themes window. Every theme is free.
Adding a theme is data in `Theme.swift`; color resolution and the pickers need no view changes, and the web demo catalog regenerates (`web/components/site/demo-themes.ts`).
Palette roles per theme: `paper`, `paper2`, `card`, `ink`, `inkSoft`, `inkFaint`, `line`, `lineStrong`, `track`, `ginger`, `gingerDeep`, `sage`, `sageSoft`, `sageDeep`, `honey`, `creamDeep`, `gold`, `cta`, `ctaDeep`, `ctaText`, `coral`.
Derived helpers in `JPAppColor`: `trackFill` draws every groove (never `paper2`, which collapses onto the card in dark themes); `barFillOpacity` keeps a fill distinct from its track; `providerTint(_:)` lifts a too-dark brand tint on dark cards, while the icon chip keeps the raw tint; `ctaGradient` is the one accent-button gradient with `ctaText` on it (never `.white` on bright ginger).
Every theme passes the WCAG-AA gate in `ThemeTests` and must make a recognizable choice: no `paper == card` recolor and no near-copy of another pack.

### Contrast pitfalls

The warm palette's failure mode is two semantically different roles that look identical, so an element disappears.
- A visible graphical object needs ≥3:1; a threshold that only proves "not identical" (`track` vs `card` passed at 1.15:1) is worthless.
- Every meter groove carries a hairline `inkFaint` border, because a selected selector row's background IS `trackFill`; `ThemeTests` requires that border to clear 3:1 against `card` and `track`.
- Verify the composited fill over its track, not the raw tint.

## 3. Typography

| Role | Font |
|---|---|
| App UI | SF Pro Text |
| App numbers | SF Mono / `monospacedDigitSystemFont` |
| Website body (Sticker Bomb) | Space Grotesk (`--sb-font-body`) |
| Website display (Sticker Bomb) | Bagel Fat One (`--sb-font-display`) |
| Website asides (Sticker Bomb) | Gaegu (`--sb-font-hand`) |

Every number, percentage, and dollar uses tabular numerals so digits never jitter.
Letter spacing is `0` everywhere on marketing surfaces; no negative tracking and no inline `text-[…]` arbitrary sizes on public routes (guard: `web/tests/sticker-typography.test.ts`).
App roles live in `JPAppDesignTokens.swift`; add a role there before using a new size.
Money uses only `metricHero`, `metric`, and `metricSmall` ([12-ui-surface-invariants.md](12-ui-surface-invariants.md#typography)); `metricCaption` is reserved for non-money metric annotations.

**Web normalization contract.** Public marketing routes (homepage Sticker Bomb shell, `/contact`, `/library` and nested pages, combined `/terms`, 404, download and support modals) use **`web/app/sticker.css` `sb-*` type roles only** — pick a role by meaning, never a one-off pixel size.
- Page chrome: `sb-page-kicker`, `sb-page-title`, `sb-page-title--doc`, `sb-page-lede`, `sb-page-meta`, `sb-h2`, `sb-lede`.
- Prose: `sb-body`, `sb-body--measure`, `sb-meta`, `sb-small`, `sb-section-title` (+ `--sm` / `--xs`), `sb-text-link`, `sb-eyebrow`, `sb-money-figure`.
- Hand accents: `sb-hand` (+ `--lg` / `--xl`), `sb-hand-accent`, `sb-accent`, `sb-cap`.
- Footer: `sb-footer-brand`, `sb-footer-body`, `sb-footer-support`, `sb-footer-legal`, `sb-footer-signoff`.
- Dialogs on marketing surfaces: `sb-dialog-title`, `sb-dialog-body`, `sb-dialog-fine`, `sb-ui-title`, `sb-ui-copy`, `sb-ui-label`; forms `sb-form-label`, `sb-form-control`, `sb-form-panel`.
- Layout widths: `sb-shell`, `reading-shell`, `copy-measure`; `<dialog>` geometry stays on `dialog-panel` in `globals.css`, with `dialog-panel-sb` for Sticker Bomb surfaces.
- Palette: cream dot-grid canvas (`--sb-bg`), ink outlines, ginger/orange CTAs (`--sb-orange`, `--sb-orange-ink`, `--sb-honey`, `--sb-yellow`, `--sb-pink`). No mint/seafoam panel fills on public routes (guard: `web/tests/sticker-typography.test.ts`).
The homepage **demo card** keeps Sunlit Ledger compact roles in `globals.css` (`ui-*`, `demo-*`, `compact-*`) — native parity, not the Sticker Bomb marketing scale.
Email may duplicate values inline, but `design-system-normalization.test.ts` proves its brand colors equal the site tokens.

## 4. Motion

Calm and physical; motion confirms, never decorates.
- Continuous motion uses `TimelineView(.animation)` natively, never `repeatForever` in `.onAppear`.
- Idle heartbeats are slow (the all-providers pulse is a 28s round trip) and share one radar-ping with the chart end dot.
- Gauges fill by width only; height never animates.
- Threshold crossings may get one gentle pulse; when nothing changes, nothing moves.
- Reduce Motion collapses everything to static states on both platforms: tickers, marquees, card floats, pulse riders, and face-enter.
- Never animate a wrapper that contains live controls; animate decorative layers instead.
The homepage mascot meows on hover or focus only after a real user activation unlocks audio, and the global logo stays silent.

## 5. Charts and icons

Charts are quiet and number-first: no gridlines beyond one hairline baseline, no boxed legends, 2px sparkline strokes with one endpoint dot, flat bars, and the literal figure beside every chart.
Gauges read as a temperature ramp: sage below 70%, honey at 70–89%, coral at 90% and above.
SF Symbols are the base glyph set; the JP badge is the emotional brand mark and is never replaced with a generic gauge.
Provider marks are self-hosted with a source note in `web/public/provider-icons/SOURCE-NOTES.md`; a geometric monogram is only a fallback. Cursor marks remain used by the frozen homepage and native hook setup, and legacy Cursor/Grok Bot marks remain available for older widget snapshots and cached pages; retiring a public catalog row does not invalidate those assets.
No emoji in chrome, navigation, badges, or provider identity; the first-run empty state may use one paw print.

## 6. Homepage demo mirror

`web/components/site/menubar-demo.tsx` is a marketing counterpart of the native card, not a second source of truth.
- It starts at the rounded card: no faux menu-bar strip and no outer JP + `Settings` + dollar-pill title bar above it.
- The desktop card is 384px at most and shrinks to the viewport; theme variables are scoped to the card and its dialogs.
- Chrome maps the native 32pt row to a 32px (`h-8`) row with 26px icon slots and a 4px settings gap; footer Help opens `SITE.url`.
- It mirrors app-owned controls: the timeframe picker, settings chrome, footer quick actions, update dot, widget guidance, theme picker, and notional labels.
`advanced-analytics-demo.tsx` mirrors the native deep-dive within the browser: 960px maximum width, 252px sidebar, intrinsic height with a viewport cap, a 14px chrome inset (no fake traffic-light gutter), and the native geometry tokens.
Its Events / Tokens / $ measure drives the heatmap, peak callout, and table order; the timeframe control is real state; it opens a genuine modal `<dialog>`; CSV stays visibly disabled with an app-only explanation.
Run `scripts/verify-app-demo-parity.sh` whenever either side changes.

## 7. Website

The site is light-only, server-rendered per request for the nonce CSP, and fonts self-host through `next/font`.
- **Texture without dark crutches:** the Sticker Bomb canvas is a cream dot grid with ink outlines and offset shadows; the demo surfaces keep Sunlit Ledger ruling and paper grain; no decorative orbs or blobs.
- **Navigation** has no download button; links are root-relative homepage anchors.
- **Homepage scroll order:** after the hero and provider marquee, the interactive `#demo` (`Go on, poke her.`) precedes `#how` (Four small jobs) so visitors reach the product mirror first; guard: `site-copy.test.ts`.
- **Open source:** `#open-source` sits between `#honest` and `#download`, built only from `sb-h2`, `sb-lede`, and `sb-cta-row`; it, the `open-source` FAQ entry, and the footer line link `SITE.repoUrl` and `SITE.contributingUrl` (guard: `site-copy.test.ts`).
- **One real download path:** every homepage download button (hero, pricing, and FAQ in `components/sticker/home.tsx`) and the `/library` CTAs start the download through `DownloadCta` with `prefetch={false}`.
  Homebrew is a quiet secondary callout under those controls, never a conversion CTA.
- **Footer:** `sb-shell` width, `Ping @8bit for support` (X link), one legal credit line `Built with: YEN · Bitcoin Email · Terms` (colon + spaced middots; inline nav, not flex — guard: `FOOTER_CREDITS_VISIBLE` / `site-copy.test.ts`), copyright line, the `Free and open source (MIT).` line linking the repository, and the real JP photo with `Hi, I'm JP.`; no Contact link, no bare support email, no bottom-only `@8bit`.

### Legal pages

Combined `/terms` opens on the full-width three.js snow-globe scene (`components/legal/`), then switches to plain, scan-friendly content built from homepage roles: a one-line H1 and subhead, the shared "On this page" list, and headed paragraphs.
- Constraints: strict nonce CSP with 100% procedural geometry plus the one self-hosted mascot image (no GLTF, HDRI, eval, CDN, or workers); three.js loads client-only; Reduce Motion or no WebGL shows the static SVG poster with no rAF.
- Verify every visual change with a headless screenshot.
- `/privacy` permanently redirects to `/terms#privacy-policy`; the Vercel-telemetry disclosure sentences in that privacy section are load-bearing (`tests/site-copy.test.ts`).
### Email — the Owner Ledger

Every email reads its tokens from `web/emails/email-styles.ts`: colors mirrored from `app/globals.css` `--color-*` and admin radii from `--radius-*`, both parity-tested; change a value there, never at a call site.
JP sends no customer mail; the one shell is the owner/admin "Owner Ledger".

**Owner/admin mail, the "Owner Ledger"** (`web/emails/admin-email-shell.tsx`: the daily report, download notices, support reports) is spartan and gets straight to the point.
- A 640px card: a 36px logo and wordmark row, a coral `Needs attention` block when something is wrong, a 26px Fraunces heading in `gingerDeep`, a one-line lede, uppercase mono section labels over `Label: value` bullets, and a one-line footer.
- A ranked list (top pages, sources, queries) sits one level under its label as a numbered 1. 2. 3. list with each count's unit, never one `·`-joined line; a JPtheCat.com page links to the live page.
- No hero, badge, button, signature, or privacy paragraph.
- Each template builds one `AdminEmailContent`, and the HTML and plain-text parts both render from it; null rows and empty sections drop out.
- Issues lead and stay rare: support reports, automated-looking download networks, and the digest's failed legs.
  A routine download never raises one, and `coral` is used for nothing else.
- Sections run who / what first and forensic IDs last; the digest runs Health, Downloads, Traffic, Search, Signals.
- Humanize values (friendly browser, labelled Pacific time); a raw string kept for forensics, such as the user agent, gets its own row.
- Every value, list item, and block uses the same body text; the mono face marks only the uppercase section labels (guard: `web/tests/admin-email-shell.test.tsx`).
- An absent value uses the one vocabulary `OWNER_VALUE` in `web/lib/email/owner-vocabulary.ts`, where each word means one thing (`not configured` never ran, `failed` errored, `none in this window` ran and found nothing); a real zero prints as a number (`0`), never a word.

Client robustness: Row/Column tables, an explicit background on every surface, `color-scheme: light` plus the dark-mode re-assertion CSS through the shared `email-head.tsx`, AA-passing pairs, absolute `https://jpthecat.com/*` images with size and alt, HTML well under Gmail's 102KB clip, and a curated plain-text part.
One download template renders exactly two channel variants.
Guard: `web/tests/admin-email-shell.test.tsx`.

## JP the Cat — Brand Assets

Source-of-truth inventory for JP's static assets, mascot animation, and packaged sounds, with the commands that regenerate them.
Naming rules live in root `AGENTS.md`; how assets are used lives in [02-design-system.md](02-design-system.md).

### Static assets

| Path | Purpose |
|---|---|
| `brand/jp-cat-yellow-icon-2048.png` | Master source: hand-drawn tortoiseshell JP face on the gold badge. Never overwrite. |
| `brand/jp-cat-yellow-icon-2048-transparent.png` | Transparent badge for compositing (1000×1000 despite the name); not the master. |
| `brand/jp-eyes.png` | The eyes-and-nose close-up: the single source for favicons, the site logo, the menu-bar mark, and the app icon. |
| `brand/jp-the-cat.jpeg` | Real-photo master; `web/public/jp-the-cat.jpeg` is the footer copy (`SITE.photo`). |
| `web/public/jpthecat-logo.png` | Site logo (`SITE.logo` / `BrandMark`); byte-identical to the menu-bar mark. |
| `web/public/og.jpg` | Open Graph / Twitter card (1200×630), Sticker Bomb dot-grid + Bagel Fat One wordmark; regenerate with `web/scripts/generate-og-image.mjs`. Guard: `web/tests/social-assets.test.ts`. |
| `web/app/icon.png`, `web/public/icon-512.png`, `web/public/icon-192.png` | Rounded-square web icons (`purpose: any`); the first two are byte-identical. |
| `web/public/icon-maskable-512.png` | PWA `maskable` icon: face in safe zone on full-bleed Sticker Bomb cream (`#fff6e6`). Regenerate with `web/scripts/generate-web-icons.mjs` (or `./scripts/generate-brand-icons.sh` on macOS). Never point `maskable` at `icon-512.png`. |
| `web/app/apple-icon.png` | 180×180, full-bleed and OPAQUE, because iOS composites transparency over black. |
| `web/app/favicon.ico` | Multi-resolution browser favicon. |
| `mac/Sources/JPtheCatApp/Resources/jp-menubar.png` | Menu-bar mark, drawn full-size inside the pill with a radial feather; the loading-only mark is hard-clipped to a circle. |
| `mac/AppIcon.icns` | App icon (`CFBundleIconFile`). |
| `web/public/dmg-bg.png` | DMG background source (1440×900, opaque sRGB); `mac/scripts/dmg-resources/background{,@2x}.png` derive from it. |

The DMG Finder layout is part of the brand and is frozen in `mac/scripts/dmg-resources/README.md`, enforced by `mac/scripts/verify-dmg-layout.sh`.

Regenerate the icon family from `brand/jp-eyes.png` with `./scripts/generate-brand-icons.sh`: it redraws the rounded PNGs, the opaque Apple and maskable icons, `mac/AppIcon.iconset`, and `mac/AppIcon.icns`, and keeps both byte-identical pairs identical.

### Canonical JP appearance

Real-photo references live in the operator-local, gitignored `brand/reference/` (metadata stripped): `jp-core-view-loaf.jpeg` for face and expression; `jp-dark-paws-close.jpeg`, `jp-full-body-dark-paws.jpeg`, and `jp-real-photo-dark-paws.jpeg` for forelegs and body.
JP is a tortoiseshell with mottled black, deep brown, orange, tan, and cream markings, green-gold eyes, a dark center face blaze, orange-cream cheek and chest patches, and asymmetric patterning.

**[HARD REQUIREMENT] Front paws stay dark.** Viewer-left is dark mottled tortoiseshell with warm patches and darker toes; viewer-right is nearly solid black.
Illustrations may simplify JP into big round eyes, pink cheeks, sketchy outlines, a yellow badge, and a white ring, but never into white mittens.

### Packaged sounds

| Path | Purpose |
|---|---|
| `web/public/meow.m4a` | Canonical JP sound (AAC/M4A); production code points here. |
| `mac/Sources/JPtheCatApp/Resources/jp-meow.m4a` | The app's alert and Test-meow sound, byte-identical to `web/public/meow.m4a`. |
| `web/public/meow-1.mp3`, `web/public/meow-2.mp3` | Backup candidates; never the default. |
| `ui-*.m4a` (app Resources and `web/public/`) | Four UI cues generated by `mac/scripts/generate-ui-sounds.py` into both trees. |

The cues share a loudest-window RMS of −15 dBFS; the captured meow is normalized to about −23 LUFS so it sits just under them (played at volume 1.0 against the cues' 0.6).
To swap the canonical meow, normalize, copy to both trees, and confirm identical hashes (guard: `web/tests/ui-sound-assets.test.ts`):

```sh
ffmpeg -i SOURCE.m4a -af loudnorm=print_format=json -f null -   # read input_i (LUFS)
GAIN=$(python3 -c 'print(-23 - (INPUT_I))')
ffmpeg -y -i SOURCE.m4a -af "volume=${GAIN}dB" -ar 48000 -ac 2 -c:a aac -b:a 128k -profile:a aac_low OUT.m4a
cp OUT.m4a web/public/meow.m4a && cp OUT.m4a mac/Sources/JPtheCatApp/Resources/jp-meow.m4a
shasum -a 256 web/public/meow.m4a mac/Sources/JPtheCatApp/Resources/jp-meow.m4a   # must match
```

### Mascot animation

The canonical loop is v4: JP sits, gently licks a dark paw, and rests, with transparency outside the white circular badge.
The web and app ship only its transparent poster still; the video masters stay in the operator-local, gitignored `brand/generated/`.
The yellow badge and white ring are artwork; only the corners outside the badge are transparent.

| Path | Purpose |
|---|---|
| `brand/generated/jp-cat-paw-lick-purr-v4-start.png` | Corrected still, used as both the start and end image (local-only) |
| `brand/generated/transparent/jp-paw-lick-purr-v4-transparent.mov` | ProRes 4444 alpha master (local-only) |
| `web/public/jp-paw-lick-purr-poster.webp` | Transparent poster, used by the `/terms` scene and its static fallback |
| `mac/Sources/JPtheCatApp/Resources/jp-first-run-peek.png` | First-run app derivative of the poster |
| `brand/jp-cat-paw-lick-purr-v4-still.prompt.txt`, `brand/jp-cat-paw-lick-purr-v4.prompt.txt` | Exact still and video prompts |

**Exposure drift:** a badge that starts light and darkens is model drift in the source video, not an export bug; generate from a corrected still passed as both start and end image with the background color and brightness locked.
Reference order for the still: the illustrated mascot for style, the core real-JP view for the face, then the paw and body photos.

#### Regeneration

```bash
# 1. Normalize the generated video to the 640px source
ffmpeg -y -i brand/generated/jp-cat-paw-lick-purr-v4.mp4 -vf "scale=640:640" -c:v libx265 -tag:v hvc1 \
  -pix_fmt yuv420p -crf 28 -preset medium -an brand/generated/jp-paw-lick-purr-v4-source.mp4

# 2. Build the ProRes alpha master
python3 -m venv /tmp/jp-alpha-venv
/tmp/jp-alpha-venv/bin/python -m pip install -r scripts/requirements-alpha.txt
/tmp/jp-alpha-venv/bin/python scripts/make_jp_transparent_alpha.py \
  --input brand/generated/jp-paw-lick-purr-v4-source.mp4 --output-stem jp-paw-lick-purr-v4-transparent \
  --circle-center-x 320 --circle-center-y 320 --circle-radius 292 --feather 2.5

# 3. Publish the poster and its app derivative
ffmpeg -y -i brand/generated/transparent/jp-paw-lick-purr-v4-transparent.mov -vf "scale=640:640" -frames:v 1 /tmp/jp-cat-v4-poster.png
cwebp -q 86 /tmp/jp-cat-v4-poster.png -o web/public/jp-paw-lick-purr-poster.webp
sips -s format png web/public/jp-paw-lick-purr-poster.webp --out mac/Sources/JPtheCatApp/Resources/jp-first-run-peek.png
```

`scripts/animate_jp_higgsfield.py` is the Python API fallback for environments using `HF_KEY` or `HF_API_KEY`/`HF_API_SECRET` instead of the CLI login.
