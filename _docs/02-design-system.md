# Design System

Brand thesis, color, typography, motion, charts and icons, and the brand assets of JP the Cat.

**The cat that counts your agent tokens.**
Naming and domain casing are owned by root `AGENTS.md` ("Identity & Branding").
Exact values live in code: `mac/Sources/JPtheCatApp/Theme.swift` (`JPTheme`) and `mac/Sources/JPtheCatApp/JPAppDesignTokens.swift` (`JPAppColor`, `JPAppFont`, `JPAppSpacing`) for the app.
Native surface contracts live in [12-ui-surface-invariants.md](12-ui-surface-invariants.md).

## 1. Thesis

*A quiet daylight instrument for your AI spend — the calm, legible opposite of a blinking dashboard.*

1. **Legible** — the numbers are the hero, never the chrome.
2. **Calm** — color appears only when something needs attention.
3. **Precise** — tabular figures, exact resets, honest provenance labels.
4. **Warm** — cream paper, one warm accent, humanist type.
5. **Trustworthy** — no dark patterns and no hidden telemetry.

Not a hacker terminal (no pixel fonts, scanlines, god-rays, film grain, or dithering), not a notch spectacle, not a neon AI-SaaS gradient, not a dense trading terminal.

**Brand fidelity:** start every design from the app (or `brand/homepage.jpg`, the retired site's last full-page screenshot) and resolve each color in its established role; the incident behind the rule is [00-foundation.md#brand-fidelity](00-foundation.md#brand-fidelity).

## 2. Color

Light is canonical and designed first; the app's dark themes are faithful inversions.

**Core roles.** `paper` (warm cream canvas), `paper2` (recessed wells), `card` (raised near-white cream, never pure `#FFFFFF`), `ink` / `inkSoft` / `inkFaint` (primary, secondary, tertiary text), `line` / `lineStrong` (hairlines, edges), `track` (empty meter groove).

**Accent.** Three distinct shipped tokens, never interchangeable:
- `ginger` `#df7a2e` — the accent itself (wordmark dot, active state, sparkline stroke).
- `gingerDeep` `#a84d14` — accent-colored *text*.
- `cta` `#a84f16` with `ctaDeep` and `ctaText` — the CTA button fill and its label.
The accent steps off Anthropic terracotta toward amber-honey, because JP is multi-provider.

**Status.** `sage` = healthy headroom and `official` provenance; `honey` = approaching limit and `notional`/`est.` provenance; `coral` = near or over limit.
Provenance is carried by sage and honey badges; there is no separate estimate hue.

**Provider colors** (`JPAppColor.tintHex(for:)`) appear only as a dot, a sparkline stroke, a thin rail, or the icon chip behind a white glyph — never as text.
Status color drives the gauge; provider color stays on identity.
Accent, status, and provider color are three channels and never mix.

**Gradient.** The one shipped gradient is the warm `honey`→`ginger` ribbon (estimate gauge); everything else is flat.


### App themes

`JPTheme.all` is the catalog: Sunlit Ledger (light) and Midnight Ledger (dark) show inline in Settings; the rest (`inMoreThemes: true`) live in the More themes window.
Every theme is free.
Adding a theme is data in `mac/Sources/JPtheCatApp/Theme.swift`; color resolution and the pickers need no view changes.
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

Every number, percentage, and dollar uses tabular numerals so digits never jitter.
App roles live in `mac/Sources/JPtheCatApp/JPAppDesignTokens.swift`; add a role there before using a new size.
Money uses only `metricHero`, `metric`, and `metricSmall` ([12-ui-surface-invariants.md](12-ui-surface-invariants.md#typography)); `metricCaption` is reserved for non-money metric annotations.

## 4. Motion

Calm and physical; motion confirms, never decorates.
- Continuous motion uses `TimelineView(.animation)` natively, never `repeatForever` in `.onAppear`.
- Idle heartbeats are slow (the all-providers pulse is a 28s round trip) and share one radar-ping with the chart end dot.
- Gauges fill by width only; height never animates.
- Threshold crossings may get one gentle pulse; when nothing changes, nothing moves.
- Reduce Motion collapses everything to static states: tickers, pulse riders, and face-enter.
- Never animate a wrapper that contains live controls; animate decorative layers instead.

## 5. Charts and icons

Charts are quiet and number-first: no gridlines beyond one hairline baseline, no boxed legends, 2px sparkline strokes with one endpoint dot, flat bars, and the literal figure beside every chart.
Gauges read as a temperature ramp: sage below 70%, honey at 70–89%, coral at 90% and above.
SF Symbols are the base glyph set; the JP badge is the emotional brand mark and is never replaced with a generic gauge.
Provider marks are bundled SVGs in the app and widget Resources; a geometric monogram is only a fallback.
Cursor marks remain used by native hook setup, and legacy Cursor/Grok Bot marks remain available for older widget snapshots; retiring a public catalog row does not invalidate those assets.
No emoji in chrome, navigation, badges, or provider identity; the first-run empty state may use one paw print.

## Brand assets

Source-of-truth inventory for JP's static assets, mascot animation, and packaged sounds, with the commands that regenerate them.
Naming rules live in root `AGENTS.md`; how assets are used is in the sections above.

### Static assets

| Path | Purpose |
|---|---|
| `brand/jp-cat-yellow-icon-2048.png` | Master source: hand-drawn tortoiseshell JP face on the gold badge. Never overwrite. |
| `brand/jp-cat-yellow-icon-2048-transparent.png` | Transparent badge for compositing (1000×1000 despite the name); not the master. |
| `brand/jp-eyes.png` | The eyes-and-nose close-up: the single source for the README logo, the menu-bar mark, and the app icon. |
| `brand/jp-the-cat.jpeg` | Real-photo master. |
| `brand/jpthecat-logo.png` | README logo; byte-identical to the menu-bar mark. |
| `brand/homepage.jpg` | The retired website's full-page screenshot (1600px wide), shown in the README. |
| `mac/Sources/JPtheCatApp/Resources/jp-menubar.png` | Menu-bar mark, drawn full-size inside the pill with a radial feather; the loading-only mark is hard-clipped to a circle. |
| `mac/AppIcon.icns` | App icon (`CFBundleIconFile`). |
| `brand/dmg-bg.png` | DMG background source (1440×900, opaque sRGB); `mac/scripts/dmg-resources/background{,@2x}.png` derive from it. |

The DMG Finder layout is part of the brand and is frozen in `mac/scripts/dmg-resources/README.md`, enforced by `mac/scripts/verify-dmg-layout.sh`.

Regenerate the icon family from `brand/jp-eyes.png` with `./scripts/generate-brand-icons.sh`: it redraws the README logo, the menu-bar mark, `mac/AppIcon.iconset`, and `mac/AppIcon.icns`, and keeps the logo and menu-bar mark byte-identical.

### Canonical JP appearance

Real-photo references live in the operator-local, gitignored `brand/reference/` (metadata stripped): `jp-core-view-loaf.jpeg` for face and expression; `jp-dark-paws-close.jpeg`, `jp-full-body-dark-paws.jpeg`, and `jp-real-photo-dark-paws.jpeg` for forelegs and body.
JP is a tortoiseshell with mottled black, deep brown, orange, tan, and cream markings, green-gold eyes, a dark center face blaze, orange-cream cheek and chest patches, and asymmetric patterning.

**[HARD REQUIREMENT] Front paws stay dark.** Viewer-left is dark mottled tortoiseshell with warm patches and darker toes; viewer-right is nearly solid black.
Illustrations may simplify JP into big round eyes, pink cheeks, sketchy outlines, a yellow badge, and a white ring, but never into white mittens.

### Packaged sounds

| Path | Purpose |
|---|---|
| `mac/Sources/JPtheCatApp/Resources/jp-meow.m4a` | Canonical JP sound (AAC/M4A): the app's alert and Test-meow sound. |
| `ui-*.m4a` (app Resources) | Four UI cues generated by `mac/scripts/generate-ui-sounds.py`. |

The cues share a loudest-window RMS of −15 dBFS; the captured meow is normalized to about −23 LUFS so it sits just under them (played at volume 1.0 against the cues' 0.6).
To swap the canonical meow, normalize and copy it into the app Resources:

```sh
ffmpeg -i SOURCE.m4a -af loudnorm=print_format=json -f null -   # read input_i (LUFS)
GAIN=$(python3 -c 'print(-23 - (INPUT_I))')
ffmpeg -y -i SOURCE.m4a -af "volume=${GAIN}dB" -ar 48000 -ac 2 -c:a aac -b:a 128k -profile:a aac_low OUT.m4a
cp OUT.m4a mac/Sources/JPtheCatApp/Resources/jp-meow.m4a
```

### Mascot animation

The canonical loop is v4: JP sits, gently licks a dark paw, and rests, with transparency outside the white circular badge.
The app ships only a still derived from its transparent poster; the video masters stay in the operator-local, gitignored `brand/generated/`.
The yellow badge and white ring are artwork; only the corners outside the badge are transparent.

| Path | Purpose |
|---|---|
| `brand/generated/jp-cat-paw-lick-purr-v4-start.png` | Corrected still, used as both the start and end image (local-only) |
| `brand/generated/transparent/jp-paw-lick-purr-v4-transparent.mov` | ProRes 4444 alpha master (local-only) |
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

# 3. Publish the app still
ffmpeg -y -i brand/generated/transparent/jp-paw-lick-purr-v4-transparent.mov -vf "scale=640:640" -frames:v 1 \
  mac/Sources/JPtheCatApp/Resources/jp-first-run-peek.png
```

`scripts/animate_jp_higgsfield.py` is the Python API fallback for environments using `HF_KEY` or `HF_API_KEY`/`HF_API_SECRET` instead of the CLI login.
