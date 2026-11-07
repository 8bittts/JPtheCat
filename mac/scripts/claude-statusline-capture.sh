# JPtheCat — Claude official rate-limit capture (statusline snippet)
#
# Claude Code does NOT persist its official usage limits; the ONLY local source is the statusline
# stdin JSON, which (for Pro/Max, after the first response) carries:
#   .rate_limits.five_hour.{used_percentage, resets_at}
#   .rate_limits.seven_day.{used_percentage, resets_at}
# Each window is optional: Claude Code 2.1.318 sends a weekly-only payload, so the block writes
# whenever ANY window is present (a 5-hour-only gate froze the file at a days-old reading).
#
# The block forwards EVERY `seven_day*` window the feed carries, not just the two above. Claude Code
# tracks per-model weekly windows internally (`seven_day_opus` — the bar its `/usage` panel labels
# "Fable" — and `seven_day_sonnet`), but as of Claude Code 2.1.318 it does NOT put them in this
# statusline payload, so JP shows no per-model bar. That is deliberate: an absent window means "not
# reported", never 0%, and JP never reconstructs a limit from token counts. If Anthropic adds the
# field, this block already forwards it and the gauge appears on its own.
#
# Paste this block into your statusline command (the script referenced by
# `~/.claude/settings.json` → `statusLine.command`), AFTER it has captured stdin into `$input`
# (e.g. `input=$(cat)`). It is a pure side effect — no stdout, non-destructive, atomic write — so it
# never changes what your statusline prints. Delete the marked block to remove it.
#
# The JPtheCat menu-bar app reads the written file
# (`~/Library/Application Support/JPtheCat/claude-rate-limits.json`) via `ClaudeRateLimitStore` and
# shows your TRUE official 5-hour + weekly percentages and reset times (labelled "official").

# BEGIN JPTHECAT-RATE-LIMIT-CAPTURE
# jpthecat-capture-revision: 3
if echo "$input" | jq -e '[.rate_limits | objects | to_entries[] | select(.key == "five_hour" or (.key | startswith("seven_day"))) | .value.used_percentage | numbers] | length > 0' >/dev/null 2>&1; then
  __jpc_dir="$HOME/Library/Application Support/JPtheCat"
  mkdir -p "$__jpc_dir" 2>/dev/null
  echo "$input" | jq -c '{capturedAt:(now|floor)} + (.rate_limits | with_entries(select(.key == "five_hour" or (.key | startswith("seven_day")))))' \
    > "$__jpc_dir/claude-rate-limits.json.tmp" 2>/dev/null \
    && mv -f "$__jpc_dir/claude-rate-limits.json.tmp" "$__jpc_dir/claude-rate-limits.json" 2>/dev/null
fi
# END JPTHECAT-RATE-LIMIT-CAPTURE
