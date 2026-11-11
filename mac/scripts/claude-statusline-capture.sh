# JPtheCat — Claude official rate-limit capture (statusline snippet)
#
# Claude Code does NOT persist its official usage limits; the ONLY local source is the statusline
# stdin JSON, which (for Pro/Max, after the first response) carries:
#   .rate_limits.five_hour.{used_percentage, resets_at}
#   .rate_limits.seven_day.{used_percentage, resets_at}
# Each window is optional: Claude Code 2.1.318 sends a weekly-only payload, so the block writes
# whenever ANY window is present (a 5-hour-only gate froze the file at a days-old reading).
#
# The block also forwards `rate_limits.model_scoped`, the per-model weekly array Claude Code 2.1.322
# sends (a row's `display_name` is the label, for example "Fable"). `seven_day` stays the all-models
# bar. `utilization` on those rows is already a 0–100 percent. JP never turns a missing name or a
# non-numeric utilization into 0%, and never reconstructs a limit from token counts. Legacy
# `seven_day_*` keys are still forwarded. A later payload that omits `model_scoped` keeps the rows
# already in the file. An explicit empty array clears them.
#
# Paste this block into your statusline command (the script referenced by
# `~/.claude/settings.json` → `statusLine.command`), AFTER it has captured stdin into `$input`
# (e.g. `input=$(cat)`). It is a pure side effect — no stdout, non-destructive, atomic write — so it
# never changes what your statusline prints. Delete the marked block to remove it.
#
# The JPtheCat menu-bar app reads the written file
# (`~/Library/Application Support/JPtheCat/claude-rate-limits.json`) via `ClaudeRateLimitStore` and
# shows the official 5-hour, all-models weekly, and per-model weekly percentages and reset times.

# BEGIN JPTHECAT-RATE-LIMIT-CAPTURE
# jpthecat-capture-revision: 4
if echo "$input" | jq -e '([.rate_limits | objects | to_entries[] | select(.key == "five_hour" or (.key | startswith("seven_day"))) | .value.used_percentage | numbers] | length > 0) or ([.rate_limits.model_scoped // [] | .[]? | .utilization | numbers] | length > 0)' >/dev/null 2>&1; then
  __jpc_dir="$HOME/Library/Application Support/JPtheCat"
  mkdir -p "$__jpc_dir" 2>/dev/null
  __jpc_file="$__jpc_dir/claude-rate-limits.json"
  __jpc_next=$(echo "$input" | jq -c '{capturedAt:(now|floor)} + (.rate_limits | with_entries(if .key == "model_scoped" then .value = [.value[]? | {display_name, utilization, resets_at}] else . end | select(.key == "five_hour" or (.key | startswith("seven_day")) or .key == "model_scoped")))' 2>/dev/null) || __jpc_next=""
  # A later statusline payload often repeats seven_day and omits model_scoped. Keep the Fable
  # row already on disk. An explicit empty array still clears it: that means "none reported".
  if [ -n "$__jpc_next" ] && [ -f "$__jpc_file" ] && ! echo "$__jpc_next" | jq -e 'has("model_scoped")' >/dev/null 2>&1; then
    __jpc_kept=$(jq -c 'if (.model_scoped | type) == "array" then .model_scoped else empty end' "$__jpc_file" 2>/dev/null) || __jpc_kept=""
    if [ -n "$__jpc_kept" ]; then
      __jpc_next=$(echo "$__jpc_next" | jq -c --argjson kept "$__jpc_kept" '.model_scoped = $kept' 2>/dev/null) || __jpc_next=""
    fi
  fi
  if [ -n "$__jpc_next" ]; then
    printf '%s\n' "$__jpc_next" > "$__jpc_file.tmp" 2>/dev/null \
      && mv -f "$__jpc_file.tmp" "$__jpc_file" 2>/dev/null
  fi
fi
# END JPTHECAT-RATE-LIMIT-CAPTURE
