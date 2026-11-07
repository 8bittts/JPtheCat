# Go-To-Market

The Product Hunt launch package and the website funnel for JP the Cat; paste-ready copy is re-synced with the site before use.

> [NOTE] §2–§5 are verbatim customer-facing paste copy.
> They are exempt from the internal no-emoji style rule; the two emojis there are deliberate.

Ready-to-paste launch copy. **Every claim here is honesty-gated to what actually ships** (Claude Code,
Codex, Grok, Muse Spark, OpenCode Zen, and OpenCode Go are the `live` providers; non-Claude dollars are *notional*
list-price; the 64-provider catalog is roadmap, not shipped breadth).

Source of truth for the numbers: `web/lib/site.ts` (`SITE`), `mac/Sources/JPtheCatApp/Theme.swift`
(24 themes), `ProviderCatalog.all` (64 entries, pinned by `ProviderCatalogTests`) and the privacy posture in
`_docs/04-security.md`. If any of those change, re-sync this file before launching.

---

## 1. Core listing

- **Name:** JP the Cat
- **Tagline (≤60 chars):** The cat that counts your agent tokens.
- **Alt taglines (pick one, all ≤60 chars):**
  - Claude Code + Codex + Grok + Muse Spark, live in your menu bar.
  - See what your coding agents cost — to the cent.
  - AI coding costs in your menu bar. Your usage stays local.
- **Topics:** Developer Tools · Mac · Artificial Intelligence · Productivity · Menu Bar Apps
- **Pricing chip:** Free
- **Platform:** macOS 14+ (Apple Silicon), notarized, Sparkle auto-updates, Homebrew cask.

---

## 2. Description (the "What is it?" block)

> JP the Cat is a light, elegant macOS menu-bar app that shows what your AI coding agents cost —
> today, live, to the cent.
>
> Right now it tracks **Claude Code** (real dollars, from your local usage logs), **Codex** and
> **Grok** (official rate-limit windows where available, plus clearly-labelled *notional* list-price
> figures), **Muse Spark**, and **OpenCode Zen / Go** (notional list prices from local OpenCode usage).
> Gateway rows stay separate from combined totals.
> A
> dashboard breaks spend down by provider and model; a menu-bar pill keeps today's total one glance
> away; a real WidgetKit widget puts it on your desktop; and usage alerts meow at you at 80% and 95%
> of a provider's limit.
>
> The part JP cares about most: **your usage stays on your Mac.** No Full Disk Access, no Accessibility
> permission, no provider account login, no usage uploads. JP reads a few known home-root paths (`~/.claude`,
> `~/.codex`, `~/.grok`, OpenCode's local DB for Muse Spark) and its own container — that's it. Your
> prompts, code, and token history never touch a network.
>
> 24 hand-tuned themes (Sunlit light, Midnight dark, plus 22 terminal-inspired packs — YEN,
> Dracula, Nord, Tokyo Night, Catppuccin, and more), all contrast-checked so every figure stays
> legible. A 64-provider catalog is on the roadmap; Claude Code, Codex, Grok, Muse Spark,
> OpenCode Zen, and OpenCode Go ship live today.
>
> Meet JP: a highly opinionated tortoiseshell with impeccable taste and zero patience for wasted
> tokens.

---

## 3. Maker's first comment (post immediately on launch)

> Hey Product Hunt 👋
>
> I built JP the Cat because I kept opening three terminals to answer one question: *what am I
> actually spending on Claude Code and Codex right now?* I wanted the answer in my menu bar, to the
> cent, without wiring my usage through anyone's server.
>
> So that's the whole design constraint: **JP keeps usage accounting on your Mac.** No Full
> Disk Access, no Accessibility, no account, no gateway. It parses the usage files the tools already
> write to your home folder (`~/.claude`, `~/.codex`) and shows you Claude's real dollars and Codex's
> official rate-limit windows (with a clearly-labelled notional list-price estimate, since a ChatGPT
> subscription has no real per-call dollar figure).
>
> Today it's honest about scope: **Claude Code, Codex, Grok, Muse Spark, OpenCode Zen, and OpenCode Go are live.** The 64-provider
> catalog includes roadmap entries; it does not claim every provider is supported.
>
> It's free — no account, no trial, no license key. There are 24 themes because JP
> has opinions about how your desk should look.
>
> Would genuinely love feedback on: which provider should be live next, and whether the
> "nothing-leaves-your-Mac" posture matters to you or if you'd trade it for a hosted dashboard. JP is
> reading every comment (and judging your token spend). 🐾

---

## 4. Pre-empting the top predictable questions (paste as replies as they come up)

**"What actually leaves my machine?"** (the #1 question — the maker comment above already front-runs it)
> Nothing about your usage.
> The app's outbound requests are disclosed: update and pricing checks, an optional support report, and optional product analytics.
> The separate Cursor plan-usage opt-in sends Cursor's saved sign-in token only to Cursor's own API.
> Your prompts, code, transcripts, token counts, costs, project paths, and the local usage database are never sent anywhere.
> No analytics SDK in the app reads any of that.
> Full posture: least-privilege, no Full Disk Access, no Accessibility, ever.

**"Why is Codex a range / estimate and Claude isn't?"**
> Claude Code writes real per-call token usage locally, so JP can compute actual dollars. A Codex
> ChatGPT subscription doesn't have a real per-call price — so JP shows available official
> subscription windows, separately reported credits, and a *notional* "what this would cost at API list price" figure,
> always labelled notional so it's never mistaken for a bill.

**"Does it support Cursor / Gemini / Copilot / <tool>?"**
> Live today: Claude Code, Codex, Grok, Muse Spark, OpenCode Zen, and OpenCode Go.
> Further support depends on local usage evidence; JP never routes your prompts through a gateway.
> GitHub Copilot CLI remains a non-aggregated token estimate. Cursor CLI activity is an explicit opt-in source inside the unified Grok view: known models contribute notional list-price cost, entirely unpriced activity shows tokens, and official plan percentages never enter dollar totals. Gemini CLI remains audit-only.
> Vote for the one you want next.

**"Is it a subscription?"**
> No. It's free: every feature, no account, no trial.

**"Open source?"**
> Yes. The Mac app and website code is MIT-licensed at github.com/8bittts/JPtheCat, and contributions are welcome.
> The JP the Cat name, logo, and mascot art stay reserved.
> The trust model is still least-privilege and local-only, and a network monitor will show it stay quiet.

---

## 5. Gallery / screenshot captions (order matters — lead with the hero)

1. **Today, to the cent.** The menu-bar pill + dashboard: Claude Code real dollars and Codex official
   limits, one glance away.
2. **Break it down.** Per-provider and per-model spend, newest model first, over a 7/14/30/90-day
   window you pick.
3. **On your desktop.** The WidgetKit widget in Small / Medium / Large, Sunlit + Midnight.
4. **24 ways to make JP yours.** The theme picker — Sunlit light through 22 terminal-inspired dark
   packs, every figure contrast-checked.
5. **Nothing leaves your Mac.** The permissions story: no Full Disk Access, no Accessibility, reads
   only local logs.
6. **JP has opinions.** The mascot / first-run screen — flavor shot to close.

---

## 6. First-day operating checklist (human)

The launch-day checklist lives in the Product Hunt section of `_docs/todos.md`, the only active
backlog — never a second copy here.

---

*Recruiting a hunter and choosing the date are human-gated. The copy is launch-ready and
honesty-gated to shipped scope; re-sync against `SITE` + the theme count before going live.*

## 6. Website funnel

- Pages: the single-page homepage plus `/privacy`, `/terms`, `/contact`, `/download`, and the `/library` hub. Retired paths (`/pricing`, `/buy`, `/release-notes`, `/changelog`, `/release`, `/thanks`, `/confirmed`) redirect in one hop (`web/next.config.ts`).
- Every download CTA goes through `DownloadCta` → `/download`; the download section links `SHA256` to the checksum derived from `public/stable/version.json`.
- The FAQ keeps the order free tools → providers → notch apps (`web/tests/site-copy.test.ts`).
