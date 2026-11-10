# AGENTS.md — jpthecat/web

Marketing and programmatic-SEO site for JP the Cat.
The repo root's [AGENTS.md](../AGENTS.md) owns cross-cutting rules (branding, mac/web parity, the provider model, worktrees, release, privacy) and is not restated here.
Design lives in [_docs/02-design-system.md](../_docs/02-design-system.md), `/library` in [_docs/08-growth.md](../_docs/08-growth.md), and growth telemetry in [_docs/08-growth.md](../_docs/08-growth.md).

## Stack

Next.js 16 (App Router) with React 19, Tailwind v4 (via `@tailwindcss/postcss` + `postcss.config.mjs`), Biome 2.6, TypeScript 7, and `three` for the legal-page 3D scene; `package.json` is canonical for versions.
The package is ESM, pins `node` `24.x` in `engines`, and pins the toolchain via `"packageManager": "bun@1.4.4"` only — never `engines.bun`, which Vercel ignores and warns about when paired with `engines.node`.

## Commands

```bash
bun run dev          # kills port 4444, wipes .next, then next dev -p 4444
bun run build        # next build (server-rendered, see force-dynamic below) && scan:secrets
bun run start        # next start -p 4444
bun run type-check   # tsc --noEmit
bun run lint:check   # biome check (read-only)
bun run lint         # biome check --write (auto-fixes)
bun run format       # biome format --write
bun run check        # tsc --noEmit && biome check
bun test             # Bun's native test runner over tests/
bun run knip         # dead-code / unused-dependency check
bun run doctor       # react-doctor . --verbose --blocking warning
bun run doctor:diff  # react-doctor . --verbose --scope changed --base main
bun run quality      # check && test && knip && doctor && build — the full gate, in that order
bun run scan:secrets # byte-scan the built browser output for secret VALUES (last step of build)
```

The dev server runs on port 4444, not 3000.

`scripts/scan-client-bundle-secrets.ts` is the final step of `bun run build`, so it never runs on a stale tree.
It byte-scans `.next/static` and `.next/server/app` for every credential-shaped env VALUE in four encodings, and fails closed when zero artifacts or zero credential values were scanned.

**[CRITICAL] A green/READY Vercel deploy is NOT proof the quality gate passed — run `bun run quality` locally before any web-touching push.**
Vercel's build runs only `next build`, not `bun test`, knip, or react-doctor, so a failing test or doctor regression ships while Vercel still shows READY.
`.github/workflows/ci.yml` is disabled on purpose, so the local run is the only gate; a WCAG target-size failure once deployed "green" this way.
`react-doctor` must score 100/100 to deploy; `--blocking warning` makes any warning fail `bun run doctor`, because the tool exits 0 on warnings by default.
Justified exceptions live in `doctor.config.json` — never suppress a finding the code could fix instead.

Every tool in the `quality` chain (Biome, knip, react-doctor) is a pinned devDependency resolved from `node_modules/.bin` — never reintroduce `bunx <tool>@latest`.
Playwright is pinned on the same terms but is NOT in the `quality` chain and has no browser specs; consumers are `scripts/generate-og-image.mjs` (OG/Twitter card) and asset guards in `tests/social-assets.test.ts`.
Regenerate PWA PNGs with `scripts/generate-web-icons.mjs` (macOS can still use repo-root `./scripts/generate-brand-icons.sh`).
The `react-email` preview CLI (`bunx react-email dev -d emails -p 4445`) is the one deliberate unpinned carve-out: it gates nothing.

## Tests

Tests live in `tests/*.test.ts(x)` and run on Bun's built-in runner, importing from `bun:test` — not vitest or jest.
`knip.json` treats `tests/**/*.test.ts` and `scripts/**/*.ts` as entry points, so a test file that imports nothing reachable surfaces as dead code.
Many tests are content guardrails (SEO length limits, copy pins, no-fiction/honesty checks, security headers, pricing parity); when marketing copy or library data changes, update the asserted source rather than the test.
`tests/site-copy.test.ts` renders several components as raw function calls (`renderToStaticMarkup(Hero())`), which crashes once that component adopts a hook — swap to `createElement(Component, props)` first ([incident](../_docs/00-foundation.md#hook-crash-in-site-copy-tests)).

## Layout and conventions

- `proxy.ts` is the Next 16 proxy (successor to `middleware.ts`); it exports `proxy()` and applies the per-request nonce CSP and document security headers.
- `app/layout.tsx` sets `export const dynamic = "force-dynamic"`, so every page renders per request; this is required for the nonce CSP, not something to "optimize" into static generation.
- `@/*` is the TypeScript path alias for this directory.
- `lib/site.ts` is the single source of truth for brand name, domain, copy, prices, and the provider list; `lib/homepage-providers.ts` owns the fixed homepage roster, which never narrows `lib/site.ts` or `/library`.
- `components/sticker/` holds the Sticker Bomb homepage, `components/site/` the shared chrome and the homepage demo, `components/library/` the pSEO blocks, `components/legal/` the three.js scene, and `emails/` the owner/admin React Email templates on `emails/admin-email-shell.tsx`.
- `scripts/` holds standalone utilities; Biome allows `console` there and errors on it everywhere else.

`biome.json` formats with tabs, a 100-character line width, and double quotes for JS and JSX.
`noExplicitAny`, `noUnusedVariables`, `noUnusedImports`, `useConst`, `useImportType`, and `useTemplate` are errors; `noConsole` is a warning globally and off under `scripts/**`.

## Deployment gate

This directory is the Vercel project root.
Install and build run through `scripts/run-pinned-bun.cjs`, which derives and verifies Bun from `packageManager`.
`ignoreCommand` builds only when the SUBJECT line of the most recent commit carries `[deploy]`; a `[deploy]` written only in a commit body does not build (`tests/vercel-deploy-marker.test.ts` runs the real command).
Vercel Cron hits `app/api/cron/growth-digest` at `0 3 * * *` AND `0 4 * * *`, guarded by `CRON_SECRET`; only the firing that is 20:00 in Los Angeles sends (`lib/analytics/rollup-schedule.ts`), so keep both entries or the report skips half the year.

## Security headers and CORS

`proxy.ts` applies `script-src 'nonce-...' 'strict-dynamic'`, `connect-src 'self' https://api.jpthecat.com`, `object-src 'none'`, `frame-src 'none'`, and `frame-ancestors 'none'` to documents and dynamic routes.
Static assets and release metadata stay outside the proxy matcher, so cached responses never carry a stale nonce.
`/stable/:path*` is the only intentionally public-CORS surface; the crawler text routes (`/robots.txt`, `/sitemap.xml`, `/manifest.webmanifest`, `/llms.txt`) are pinned back to `https://jpthecat.com` with `Cross-Origin-Resource-Policy: same-origin` in `vercel.json`, because Vercel otherwise serves them with `Access-Control-Allow-Origin: *`.
Never add public CORS to the homepage, `/download`, or `/api/support-report`.

## Downloads

Public CTAs may point at `/download`, which fails closed unless `public/stable/version.json` carries a valid trusted DMG URL, sha256, and date.

**Download always starts on first click.**
`startDownload()` fires a programmatic `<a>` click to `/download` BEFORE the modal opens, and the modal is a non-blocking download-started note (no email field) that never re-triggers the download.
A download never emails the owner on its own: `/download` only persists the row, and the 8pm Pacific daily report counts it (guard: `tests/download.test.ts`).
`DownloadCta` links keep `prefetch={false}`, and `/download` prefetch requests (`next-router-prefetch`, `Purpose`/`Sec-Purpose: prefetch`) return 204/no-store with no redirect and no owner notice.


## Email

JP sends no customer mail (no license, newsletter, or broadcast).
Every owner/admin notice uses the spartan `emails/admin-email-shell.tsx`, which reads `email-styles.ts` (hex mirrored from `app/globals.css`), and the design is owned by [02-design-system.md](../_docs/02-design-system.md#email--the-owner-ledger).
**A new owner notice builds an `AdminEmailContent` for `AdminEmail`, with anything wrong in `issues`** (guard: `tests/admin-email-shell.test.tsx`).
**The headline must be `emailColors.gingerDeep`, NOT ink** — Gmail mobile dark mode force-lightens large near-black inline text to white (guard: `tests/admin-email-shell.test.tsx`).
Layout is Row/Column tables, never CSS flex or grid; every surface needs an explicit background plus `color-scheme: light`; every text/CTA pair passes WCAG AA.
Idempotency keys include body-shaping event fields, never an hour bucket, because Resend rejects a reused key whose body changed within 24h.
Resend tag values are ASCII letters, numbers, underscore, and dash only; today's senders tag with fixed literals and enum values, and a tag built from request data must be reduced to that set first.
`RESEND_API_KEY` is required in production; `RESEND_FROM_EMAIL` defaults to `JP the Cat <downloads@jpthecat.com>`.

## Accessibility — WCAG 2.1 AA (required)

Text contrast >= 4.5:1 (>= 3:1 for large text and UI objects), full keyboard operability, visible `:focus-visible`, semantic landmarks, ordered headings, and `alt` on every image.
The download-started modal keeps `aria-labelledby`/`aria-describedby`, moves focus to its Got it button, traps Tab, and preserves Esc, backdrop, and button dismissal.
Honor `prefers-reduced-motion`: the universal reset in `app/globals.css` stops every animation and hides demo confetti, and `app/sticker.css` drops the sticker tilt and marquee motion.
Do not animate wrappers containing live controls.

## Responsive

Mobile-first: every layout must hold at 375px with no horizontal overflow, and modal work needs an opened-state 375px check plus a desktop check.
Take 375px evidence from a real 375px viewport (Playwright `viewport`), never Chrome `--headless --window-size=375`, which lays out wider than 375px and fakes a clipped right edge.
Pair `md:` font-size growth with `xl:whitespace-nowrap`, never `md:whitespace-nowrap`, which overflows only in a narrow mid-range band.
A persistent `position: fixed` bar that looks like "space below the footer" is a visibility bug: hide it once `getBoundingClientRect().bottom <= window.innerHeight` for the real CTA, never via `scrollHeight` or `IntersectionObserver`.
Public marketing routes use Sticker Bomb type roles in `app/sticker.css` (`sb-*`); see `_docs/02-design-system.md` §3 and `tests/sticker-typography.test.ts`.
The homepage demo card keeps Sunlit Ledger roles in `globals.css` (`ui-*`, `compact-*`).
Never inline arbitrary `text-[…]` sizes on marketing surfaces.
Incidents: [_docs/00-foundation.md#responsive-overflow](../_docs/00-foundation.md#responsive-overflow).

## SEO & crawlers

Crawlers are deliberately allowed: `app/robots.ts` allows `*` and `public/llms.txt` gives an AI-readable summary.
Keep `sitemap.ts`, `robots.ts`, `manifest.ts`, the OG image, and JSON-LD current; the canonical host is `https://jpthecat.com`; never add a fabricated `aggregateRating`.
`/library` is crawlable-but-unlinked (in `sitemap.ts` only, never nav or footer — `tests/library-chrome.test.ts`) with hard-fail honesty guards: exactly claude+codex+grok+muse_spark+opencode+opencodego live, and every non-Claude `$` beside a notional marker (`tests/library-honesty.test.ts`).
One `lib/library/eligibility.ts` gate serves both routes and the sitemap.

## Growth analytics

A raw `/download` hit is NOT an install — always report `mac_human_downloads`, never `human_downloads` alone and never `all_hits`.
`/download` persists one bot-classified row per redirect to Supabase `public.downloads` (insert-only under RLS), with `is_mac` set from the frozen `Macintosh; Intel Mac OS X 10_15_7` token so the platform survives the 30-day UA redaction.
Bot classification is the UA denylist in `lib/analytics/download-bot.ts` at write time plus the read-time burst, hosting-network, repeat-monitor, and durable `exclusion` rules in `lib/analytics/growth-download-sql.ts`, which both the CLI reader and the digest must use (guard: `tests/growth-download-sql.test.ts`).
A `null` hosting flag is "lookup returned nothing", never "clean": readers print the flag coverage and the digest raises an issue for any gap, because the ipapi.is free tier silently dropped the flags once and the headline rose 36% ([incident](../_docs/00-foundation.md#download-telemetry)).
Readers: `bun scripts/growth-metrics.ts [days] [--json]`, `bun scripts/growth-extra.ts [days] [--json]`, and `bun scripts/analytics-pull.ts`.

## Legal pages and mascot

The combined `/terms` page uses `components/legal/legal-document.tsx` and opens on one full-width WebGL scene (`/privacy` redirects to its privacy section; `/release` is retired): procedural geometry plus the single self-hosted mascot image (strict nonce CSP — no GLTF or HDRI), lazy-imported client-only, with a static SVG poster and no rAF for reduced motion or missing WebGL.
Always verify visual changes there with a headless screenshot.

The homepage mascot renders with NO thought bubbles — that treatment is native-app-only, guarded by `tests/site-copy.test.ts`.

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
