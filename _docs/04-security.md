# Security

The privacy invariant, the permissions posture, Keychain access rules and update-feed trust for JP the Cat; `AGENTS.md` carries the rules as hard requirements and this doc explains the posture.

## Privacy invariant

Prompts, code, transcripts, provider credentials and local usage databases never leave the Mac.
Unified opt-in Grok plan usage sends only a saved Cursor or Grok Bot access token to the existing three DashboardService methods on `api2.cursor.sh`, on one shared five-minute throttle. Alternate sign-ins are fallback accounts, never merged quota pools. Turning it off clears unified and legacy plan markers/readings; a local-hook opt-in does not authorize network access. The public privacy policy discloses this exception.
Every telemetry, analytics and email surface honors the invariant; Mac app product analytics stay opt-in and off by default.

## Keychain

JP the Cat makes no Security-framework Keychain access of its own (guard: `PlanTierKeychainReadTests`).
Reading another app's Keychain item for a cosmetic label makes macOS prompt for the login password, so plan tiers are never read that way; the reviewed Keychain exceptions use `/usr/bin/security` only and never a refresh token. Cursor can also supply its existing app access token from the exact opt-in store documented in [03-data.md](03-data.md#unified-grok-plan-usage-and-cursor-local-activity).
The incident is in [00-foundation.md](00-foundation.md#keychain-and-identity).

## Harness configuration

Provider setup changes require explicit opt-in. Claude-limits capture only reads `~/.claude/settings.json` and edits the user's own statusline script; Grok capture writes its marked `~/.grok/hooks/` file; Cursor capture installs only JP's entry in the designed `~/.cursor/hooks.json`, preserving unrelated hooks.

## Permissions posture

JP requests neither Full Disk Access nor Accessibility, and must never start.
- **Nothing it reads is TCC-protected.** Sources read exact home-root provider dotfolders, JP's own container/App Group, and the opted-in sign-in stores documented in `03-data.md`; no recursive home-directory walk is needed.
- **It controls no other app:** no `AXUIElement`, `CGEventTap`, synthesized input, or Apple events in shipped code; the only `osascript` is build-time DMG layout.
- **Full Disk Access breaks on every update,** because macOS pins the grant to a code signature and Sparkle ships a new one each release.
- **Trust:** "no Full Disk Access, no Accessibility, reads only your own AI-tool logs" is a shipped marketing claim (`web/tests/site-copy.test.ts`).
- **Never enumerate `$HOME`.** TCC attributes access up the chain, so a recursive walk can trip Desktop, Documents, or Downloads prompts; providers read exact paths only.
- **What JP does need:** `UNUserNotificationCenter` `.alert` authorization (opt-in), the `SMAppService` login item, and Developer ID signing.
- **A future source inside another app's container** is TCC-protected; prefer an App Group (apps we own), then an `NSOpenPanel` security-scoped bookmark, never Full Disk Access.

`Info.plist` keeps `LSUIElement = false`, so the default install is Dock-visible; the Settings toggle switches the runtime activation policy between `.regular` and `.accessory` (never `.prohibited`, since the app presents windows).

## Update-feed trust

Release DMGs are Developer ID signed and notarized, and Sparkle verifies an EdDSA-signed appcast; the pipeline, the vendoring pin and the release-notes policy are [05-infrastructure.md](05-infrastructure.md).
