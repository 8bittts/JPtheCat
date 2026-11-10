# Data

Provider log formats and the model-price evidence ledger that feed JP the Cat.

Where each provider's usage comes from, and the evidence behind every price row.
Support status lives in `ProviderCatalog.swift`; rates live in `mac/Sources/JPtheCatCore/Resources/pricing-default.json`.
This doc owns the source formats and the provenance of each rate, never the rates themselves.

## Claude Code

- **Path:** `~/.claude/projects/<slug>/<sessionId>.jsonl`; the slug is the cwd with `/` and `.` replaced by `-`.
  `ClaudeProvider` reads only that default root; a relocated `CLAUDE_CONFIG_DIR` is not followed.
- **Filter:** `type == "assistant"`, `message.usage` present, and not `isApiErrorMessage`; other line types (`user`, `system`, `summary`, `file-history-snapshot`, meta lines) carry no usage.
- **Fields:** `message.model`; `message.usage.input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`; the write split `cache_creation.ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens`; `usage.speed` (`"fast"` → `-fast-mode` row); `usage.inference_geo` (`"us"` → `-us-inference` multiplier); dedup ids `message.id` + top-level `requestId`; `sessionId`, `cwd`, `timestamp`.
- **No cost field exists**; cost is always computed from tokens.
- **Streaming duplicates:** one `(requestId, message.id)` pair appears up to three times with monotonic `output_tokens`, so dedup is global across files and keeps the max output (keep-first undercounts, ccusage #888).
- **Not usage sources:** `~/.claude/stats-cache.json` (token rollups, `costUSD` always 0) and `history.jsonl` (prompt text).
- **No plan tier:** no non-privileged local source carries one; the Keychain item is off-limits (`PlanTierKeychainReadTests`).

**Official windows** exist only on the statusline command's stdin: `rate_limits.five_hour` and `rate_limits.seven_day`, each `{used_percentage, resets_at}` with `resets_at` in epoch seconds.
They appear only for Pro/Max after the first response in a session, each window can be absent, and nothing persists them; JP's opt-in capture tees them into an app-owned file.
Claude Code 2.1.318 sends a weekly-only payload, so the capture writes whenever any `five_hour` or `seven_day*` window is present and skips a null or gateway-only feed.
To re-verify the payload without editing `~/.claude/settings.json`, run one short `claude --settings <file> --model haiku` session whose `statusLine` command appends stdin to a scratch file.
The TUI needs a real terminal: `script` fails without one, so drive it from a Python `pty.fork()`.

### Per-model weekly windows

Claude Code's `/usage` panel draws per-model weekly bars ("Fable" from `seven_day_opus`, plus `seven_day_sonnet` and others), but the statusline payload carries only `five_hour` and `seven_day` (re-verified on Claude Code 2.1.318, whose payload carried only `seven_day`), and no file under `~/.claude` persists the others; `~/.claude.json` `cachedUsageUtilization` refreshes only when `/usage` runs, so it is not a live source.
In 2.1.318 the Fable cap is the scoped `seven_day_overage_included` window, which only `/usage` shows.
The capture forwards every `seven_day*` key and `ClaudeRateLimitStore.modelScopedWindows` decodes any it sees, so a future field renders with no code change; empty means "not reported", never 0%.
Model-scoped bars stay in provider detail only (guard: `ModelScopedWindowScopeTests`).

## Codex

- **Path:** `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
- **Usage lines:** `type == "event_msg"`, `payload.type == "token_count"`, with `info.total_token_usage`; reconcile the cumulative totals so duplicates and one-component wobbles never double-count, and treat reasoning tokens as part of output.
- **Model** from `turn_context.model`; provider and working directory from `session_meta`.
- **Rate limits** come from `rate_limits` even when `info` is null: accept the account pool (`limit_id: "codex"` or no id), order readings by event timestamp, and classify windows by `window_minutes`, not slot position.
- **Credits:** `rate_limits.credits` is a separate last-reported balance; missing or malformed balances never become zero.
- **Never read** the sibling SQLite databases (`state_5.sqlite` token totals overcount; `logs_2.sqlite` is large and off the hot path) or `history.jsonl` (prompts).

## Grok

- **Durable usage:** `~/.grok/sessions/**/updates.jsonl` `turn_completed` rows, priced from their `modelUsage` keys; local `grok-4.x-build` ids normalize to the published `grok-4.x` rows.
- **Mid-turn overlay:** `~/.grok/logs/unified.jsonl` `shell.turn.inference_done` (`prompt_tokens`, `cached_prompt_tokens`, `completion_tokens`, `reasoning_tokens`, `sid`); rounds sum to the later turn total.
- `_meta.totalTokens` on ACP chunks is context occupancy and is never billed.
- **Weekly window:** unified opt-in plan API usage takes precedence; opt-in capture through `~/.grok/hooks/` (`GrokRateLimitCapture`) is the fallback. See the unified source contract below.

## OpenCode (Muse Spark, Zen, Go, and brand rows)

- **Store:** `~/.local/share/opencode/opencode.db`, read-only, plus its WAL; each assistant message records `providerID` (`opencode` = Zen, `opencode-go` = Go, `meta` = Meta direct).
- **Two message tables:** the session-v2 store writes turns to `session_message` (`type` column, `$.model.id`, `$.model.providerID`) and stops appending to `message`, after copying most old rows across.
  JP reads both; an id in both resolves to the `session_message` copy, and project ids come from `session` and `session_v2`.
- Model-brand rows (Muse Spark, Nemotron, MiMo, Big Pickle, DeepSeek) claim messages by model id; gateway rows claim by `providerID`.
  Session totals are a fallback only when an unbounded message scan finds nothing; a pre-1.2.0 database falls back to the legacy log's token fields.
- **Free tiers:** Zen appends `-free` / `-contributor-free`; the suffix survives parsing and leaves the turn unpriced.
- **Gateway accounting ids** are created at parse time: `-go` for Go routes, `-zen` where Zen's rate differs, `-opencode` for gateway Grok (its 200K premium is exclusive, direct xAI's is inclusive), and `-peak` for DeepSeek Go requests created Monday–Friday 01:00–04:00 or 06:00–10:00 UTC.
- **Go caps:** published per-model monthly dollar limits, with 5-hour = 20% and weekly = 50% of that limit; no reset boundary or remaining quota exists locally.
  JP applies the base Go plan's caps and never infers Go Plus or Go Teams, so on those plans the gauge reads higher than the real share used.
  A promotion's expiry is midnight UTC after its published final day.
- **Console link:** the workspace id appears only in OpenCode's own quota and balance errors in `log/opencode.log` (`OpenCodeWorkspace.currentID`); without it no link is shown.
- **Dashboard:** one OpenCode row. Zen and Go stay separate warehouse ids and break out as labeled sections. The usage sentence links both consoles when a workspace id is present.
- **Muse Spark** usage is OpenCode on this Mac only; Meta's account dashboard aggregates every client, and Meta ships no usage-history API.
  The row owns Meta's token-billed Muse text models by name (`MuseSparkProvider.museFamilyNeedles`: `muse-spark`, `muse-wonder`) on any gateway.

## Copilot

- Opt-in OTel file export: JP's marked shell block sets `COPILOT_OTEL_FILE_EXPORTER_PATH` (enabling OTel alone keeps the network exporter); records land under `~/.copilot/otel/*.jsonl`.
- A `ChatSpan` suppresses an overlapping `InferenceLog` on the same trace, so the parser re-reads whole files (`canTailAppend: false`).
- `token_limit` / `current_tokens` are the model context window; the honest consumption signal is summed per-request `github.copilot.nano_aiu` deltas.
- No local file holds a quota or billing snapshot; `~/.copilot/data.db` token columns belong to Copilot and are never read.

## Unified Grok plan usage and Cursor local activity

Grok Build, Cursor, and Grok Bot have **one public Grok row**, not three provider rows.
`CursorProvider` retains the raw `.cursor` warehouse key so old indexed events, source-scoped cursors, rotation retention and idempotent ingestion survive upgrades unchanged.
Reporting (`UsageIndex` summary/model/day/rhythm projections) maps source IDs to `.grok`; callers explicitly include the opted-in Cursor source.
Independent source IDs avoid request-key collisions and never cause a second public row.

- **Local Cursor source:** the explicit opt-in Cursor CLI `stop` hook writes allowlisted model, timestamp, opaque generation/conversation IDs and token counts to `cursor-usage.jsonl`. It is a Cursor CLI hook, not Claude Code's `~/.claude` ledger, and never reads private chat databases. Distinct CLI requests are independent usage, even if they use the same model. Grok Build mid-turn/session deduplication remains owned by `GrokProvider`.
- **Accounting:** both local sources are priced at available model list rates under Grok's **notional** basis; those dollars enter All providers once. Unpriced model IDs retain tokens, never a fabricated price. A fully-unpriced window displays tokens; partial pricing visibly discloses the omitted models. Official quota percentages never enter dollar totals.
- **API:** one `GrokPlanUsageClient` requests only `DashboardService/{GetCurrentPeriodUsage,GetSandUsageStatus,GetPlanInfo}` on `api2.cursor.sh`, with `{}` bodies. A valid weekly-only Sand response is sufficient; monthly entitlement is not required. The single refresh task throttles attempts (including failures) to five minutes and persists the attempt timestamp before networking so failures stay throttled across launches too.
- **Credentials:** after explicit network opt-in only, try Cursor's existing access token, falling back to Grok Bot's saved sign-in when necessary. Cursor's app token key or CLI `/usr/bin/security` item and Grok Bot's `sand-secrets.json` safeStorage decryption remain the only credential paths. No Security framework, refresh tokens, secret logging, extra endpoints or local-usage uploads. Alternate sign-ins are complete fallback snapshots, never merged accounts.
- **Pools:** API weekly usage exists only with `hasNonZeroIncludedLimit`; it takes precedence over `GrokRateLimitCapture` weekly fallback, so one weekly pool renders once. Monthly `autoPercentUsed` / `apiPercentUsed` retain the reported Cursor Models / Other Models labels and billing-cycle end. `grokPlanLabel`, `cursorPlanName` and team seat metadata are display-only; never inferred tiers.
- **Primary rule:** current weekly API (otherwise current hook weekly) drives `weeklyUsedPct`, selector quota, menu bar/headroom and widget official capsule. If no weekly pool exists, Cursor Models → combined included usage → first reported pool drives the selector and plan-only hero, honestly labeled **billing-cycle**. Its duration is not invented, so it does not masquerade as 5-hour/weekly headroom.
- **Cache/opt-in migration:** `GrokPlanUsageStore` reads legacy Cursor / Grok Bot enabled markers immediately, preferring a complete Cursor cache before a standalone Bot cache; it never joins potentially different accounts. New successful responses are authoritative in `grok-plan-usage.json`; removed/expired entitlements cannot resurrect from an older cache. Opt-out removes unified and legacy plan markers/readings. Local hook capture remains an independent explicit consent, not automatic permission for credential/network use.
- **Presentation:** the detail usage sentence links Cursor spending and Grok usage together. With no local activity in the selected window, hero = official primary meter, selector = compact primary meter, detail = secondary pools only plus plan caption/link. No third primary gauge and no empty local metrics. With local activity, hero = cost/token trend, detail = each distinct quota pool once. Settings has one detection-gated Grok group with per-source feature controls. Legacy provider switches migrate by OR, including effective opted-in Cursor hook/plan and Grok Bot plan sources (Cursor previously had no master switch); an explicitly saved new unified switch always wins. Legacy selection/menu/widget IDs and CLI `cursor`, `grok-bot`, `grok_bot` aliases resolve to Grok. Homepage's frozen Cursor example remains a tool illustration, not another native/catalog provider.


## Gemini

Audit-only parser over `~/.gemini/tmp/*/chats/session-*.json`; excluded from every aggregate and surface except `jpthecat-cli --provider gemini`.

## Model-price ledger

Every row in `pricing-default.json` has a disposition and a first-party source; a populated field alone never proves accuracy.
Rates are standard global list prices and exclude account discounts, service-tier or region premiums, tool fees, and cache storage.
A missing cache field means no published rate; the calculator's fallback multiplier for it is an estimate, never a verified rate.
A promotional rate with no documented replacement keeps its current value; never invent an expiry increase.
The bundled JSON, `web/public/stable/pricing-v1.json`, and the web mirror change together.

Sources: [A] [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing) and per-model pages, [O] [OpenAI pricing](https://developers.openai.com/api/docs/pricing), [G] [Google Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing), [X] [xAI pricing](https://docs.x.ai/developers/pricing), [Z] [OpenCode Zen](https://opencode.ai/docs/zen/), [GO] [OpenCode Go](https://opencode.ai/docs/go/), [M] [Meta Model API](https://dev.meta.ai/products/meta-model-api), [C] [Cursor Composer 2.5](https://cursor.com/changelog/composer-2-5).

| Rows | Source | Disposition and qualification |
|---|---|---|
| `claude-fable-5-2`, `claude-opus-5-5`, `claude-opus-5`, `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-6`, `claude-opus-4-5`, `claude-fable-5-1`, `claude-mythos-5-1`, `claude-fable-5`, `claude-mythos-5`, `claude-sonnet-5`, `claude-sonnet-4-6`, `claude-sonnet-4-5`, `claude-haiku-4-5` | A | Verified; Sonnet 4.5's legacy context tier is corroborated by Zen. Fable 5.2 is its own row ($8/$40, cache read $0.20). Fast mode for Fable 5.2 is published at $16/$80, and no local turn has logged `usage.speed` fast, so there is no fast-mode row yet. |
| `claude-sonnet-5-5` | A | Corrected to the exact emitted id; flat through 1M context. |
| `claude-haiku-5-5` | A | Verified; exclusive 100K prompt boundary counting input, cache reads, and both cache writes, not output. |
| `claude-opus-5-5-fast-mode`, `claude-opus-5-fast-mode`, `claude-opus-4-8-fast-mode` | A | Verified fast mode; cache multipliers stack, no 200K premium. Opus 5.5 fast mode is generally available. Opus 5 and Opus 4.8 remain research preview. Opus 4.6 serves fast requests at standard speed and Opus 4.7 rejects them, so neither has a row. |
| `claude-opus-5-5-medium` | A | Alias of `claude-opus-5-5`. Cursor appends the effort, and Anthropic's effort parameter does not change the per-token rate. |
| `-us-inference` multiplier (1.1x) | A ([data residency](https://platform.claude.com/docs/en/build-with-claude/data-residency)) | Verified for Claude 4.6 and later, stacked on fast mode; other `inference_geo` values bill standard. |
| `claude-sonnet-5-5-zen` | Z | Verified; Zen keeps the prior cache-read rate and publishes no one-hour write rate, so that field is omitted. |
| `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.2` | O | Verified standard list price; subscription cost stays notional. GPT-5.6 Sol's rate is published as promotional. |
| `gpt-6.1-sol` | O | Verified; Codex and Zen share the rate, cached input is half of GPT-6 Sol's. |
| `gpt-6.1-terra` | O | Verified; Codex CLI can emit it, so it carries a row before the first local turn. |
| GPT-6 and GPT-5.6 12-hour cache writes | O | Corrected to 2x the 30-minute write; the `above_1hr` field holds the 12-hour rate, and Codex logs report no extended-retention writes. |
| `gpt-5.3-codex`, `gpt-5.2-codex`, `gpt-5.1-codex`, `gpt-5.1-codex-max`, `gpt-5.1-codex-mini`, `gpt-5-codex` | O | Verified from per-model pages; no context premium published. |
| `gpt-5.3-codex-spark` | O | Unverifiable: no exact model page; Zen's rate does not establish direct pricing, so the estimate is retained. |
| `gpt-5-codex-zen`, `gpt-5.1-codex-zen` | Z | Verified Zen list price. |
| `grok-4.7`, `grok-4.6`, `grok-4.5`, `grok-4.3`, `grok-4.20-0309-reasoning`, `grok-4.20-0309-non-reasoning`, `grok-4.20-multi-agent-0309`, `grok-build-0.1` | X | Verified; the direct xAI 200K threshold is inclusive. |
| `grok-4.7-fast` | X | Verified Grok 4.7 Fast (Cursor and Grok Build only): $4/$1/$12 below 200K and $6/$1.50/$18 once the prompt exceeds 200K. The locally emitted id `grok-4.7-high-fast` aliases here. `cursor-grok-4.6-high-fast` stays unpriced; xAI publishes no Grok 4.6 Fast rate. |
| `grok-4.7-opencode`, `grok-4.6-opencode`, `grok-4.5-opencode`, `grok-build-0.1-opencode` | Z | Verified; the gateway boundary is exclusive and Build is flat. |
| `grok-composer-2.5-fast`, `grok-composer-2.5` | C | Input and output verified; cache rates unpublished. |
| `gemini-3-flash-preview`, `gemini-2.5-pro`, `gemini-2.5-flash`, `gemini-2.5-flash-lite` | G | Verified text rates; audit-only provider. |
| `gemini-3.1-pro`, `gemini-3.5-flash`, `gemini-3.5-flash-lite` | G, Z | Verified; Google and Zen publish identical rates. |
| `gemini-3-pro-preview`, `gemini-3` | G | Unverifiable historical keys; retained rather than substituted with a newer model's rate. |
| `muse-spark-1.1`, `muse-spark-1.2`, `muse-spark-1.3`, `muse-spark-1.2-contributor`, `muse-spark-1.3-contributor`, `muse-wonder-1.0` | M, Z | Verified; contributor ids keep their own rates; no cache-write rate published. |
| `deepseek-v4-pro`, `deepseek-v4.1-flash-zen`, `big-pickle`, `glm-5.1`, `qwen3.5-plus` | Z | Verified gateway list price. |
| `deepseek-v4-flash`, `deepseek-v4-flash-vision-exp`, `deepseek-v4-flash-go`, `deepseek-v4-flash-vision-exp-go` and their `-peak` rows, `qwen3.7-max`, `space-bunny` | Z, GO | Historically retained: neither current table lists these ids; rows stay for old-log correctness. |
| `kimi-k3` cache write | Z, GO | Corrected: both tables publish a $3.00 cache-write rate. |
| `deepseek-v4.1-flash`, `deepseek-v4-pro-go`, `glm-5.3-flash`, `glm-5.3`, `glm-5.2`, `kimi-k3`, `kimi-k2.7-code`, `kimi-k2.6`, `longcat-2.0`, `mimo-v2.5`, `mimo-v2.5-pro`, `mimo-v2.6-flash`, `mimo-v2.6-pro`, `minimax-m2.7`, `qwen3.8-max`, `qwen3.8-flash`, `qwen3.7-plus`, `hy4-preview`, `hy3` | GO | Verified Go list price. |
| `kimi-k3.1-pro`, `step-5-preview`, `minimax-m3.1-flash` | GO | Verified Go list price and monthly cap. |
| `minimax-m3` | GO, Z | Base rate verified on both; Go's above-512K tier is not modeled until a Go-only accounting id exists (`todos.md`). |
| `gemini-4-argon` | GO, Z | Verified billed promotional rate (50% off list), now dated by both tables (`todos.md`); Google publishes no direct rate, so Gemini CLI turns share this row. |
| `deepseek-v4.1-flash-peak`, `deepseek-v4-pro-go-peak` | GO | Verified weekday peak rates; otherwise the off-peak row applies. |
| `qwen3.6-plus`, `minimax-m2.5` | Z | Historically retained: base fields verified by Zen; the retained 256K premium (Qwen) and cache-write rate (MiniMax, also M2.7) are absent from current tables. |
| `union-alpha` | GO | Unverifiable: a retired house model whose historical zero row is kept, not newly verified. |

Zen and Go publish one rate for Qwen3.7 Plus and MiniMax M2.7 with different tier and cache-write detail; JP's single row applies Go's fields to both routes.
Models Zen serves that JP has not seen locally stay unpriced until a local turn needs them; the open list is in `todos.md`.
