# Infrastructure

The release pipeline, Sparkle vendoring and update UI, release hosting and the Homebrew tap for JP the Cat.

JP the Cat ships as an unsandboxed, hardened-runtime, Developer ID app with Sparkle 2 auto-update.
The App Sandbox cannot read the `~/.claude` and `~/.codex` dotfolders the product exists to read, so the Mac App Store is impossible; those dotfolders are not TCC-protected, so the app needs no file-access entitlement and shows no permission prompt.
The Sparkle release-notes rule lives in root `AGENTS.md`.

## Release pipeline

One command owns it: `bash mac/scripts/release-jpthecat.sh [version]` (also `/jp release`, `.claude/commands/jp.md`).

- **Signing:** Developer ID Application (team `GRNGR33Z8A`), hardened runtime, no sandbox; `mac/JPtheCat.entitlements` carries only the `com.apple.security.application-groups` array for the widget snapshot.
  Sign inner to outer (Sparkle XPC services → `Updater.app` → framework → app) and never use `--deep`, which corrupts the XPC signatures.
- **Notarization:** the DMG goes through the keychain profile `JPtheCat-Notarization`, then `stapler staple`, `stapler validate`, and `spctl` (`source=Notarized Developer ID`).
  The default `build-dmg.sh` mode stops before the build when the Developer ID identity, the notary profile or the vendored Sparkle framework is missing; `--unsigned` and `--local` are the only ways to skip signing or notarization.
  HTTP 403 from the notary check can mean an unsigned developer agreement rather than a missing profile.
  If `notarytool submit --wait` succeeds with an empty JSON capture, recover the submission from `notarytool history` / `info` and proceed only if the DMG staples and validates.
- **DMG:** `build-dmg.sh` builds a read-write HFS+ image, applies the Finder layout, verifies `.DS_Store` kept the background, and converts to UDZO; `verify-dmg-layout.sh` guards the frozen geometry in `mac/scripts/dmg-resources/README.md`.
  Drag-to-Applications un-quarantines the copy and avoids app translocation; a notarized, stapled app still shows one friendly first-launch prompt.
- **Versions:** `CFBundleVersion` is a monotonic integer floored above the latest published `<sparkle:version>`, because Sparkle compares build numbers; the bump math is covered by `VersionBumpTests`.
- **Appcast:** `generate-appcast.sh` publishes exactly one `<item>` (`--maximum-versions 1`), feeds the last five DMGs in only to build deltas, and purges Sparkle's never-pruned extraction cache on every run.
- **Hosting:** the public Supabase Storage `releases` bucket behind `https://api.jpthecat.com`.
  `/download` (`web/app/download/route.ts`) validates `version.json` (sha256, release date, trusted host) and redirects; it trusts `api.jpthecat.com` and the raw project host as a rollback fallback.
  The release uploads with `supabase storage`, so read [supabase/AGENTS.md](../supabase/AGENTS.md) § Keys before changing the project's signing keys.
- **Source:** the public `github.com/8bittts/JPtheCat` repository, whose `main` the Vercel project `jpthecat` (root `web/`) is Git-connected to; the `[deploy]` subject marker gates its builds.
- **Manifest:** the release rewrites `web/public/stable/{version.json,appcast.xml}`, the README markers, and all three cask copies, then commits `release: JPtheCat vX [deploy]` plus a tag from a dedicated worktree (root `AGENTS.md`).

Invariants:

- **The release publishes the download and never touches the installed app.** Existing installs, the operator's included, update themselves through Sparkle; never add an install or relaunch step.
- **No leftovers.** An EXIT trap reverts the `mac/Info.plist` version stamp if the run aborts before its commit, and a final gate asserts a clean tree.
- **Trust recorded evidence, not a wrapper.** Gate each step on the script's own exit code and on artifacts: the app exists, the DMG returns HTTP 200, the appcast is signed.

Post-release proofs:

- `mac/scripts/sparkle-upgrade-smoke.sh` installs the oldest supported public DMG into a temporary bundle, drives Sparkle through the app menu to the live appcast, and confirms App Support and Keychain sentinels survive the relaunch.
- `mac/scripts/release-dmg-qa.sh` downloads the live DMG, verifies its SHA-256 and Finder layout at Retina scale, and copies the app into a temporary Applications folder for codesign and Gatekeeper checks.

## Sparkle vendoring

- Sparkle is vendored at `mac/tools/sparkle/` and SHA-pinned in its `VERSION` file; `build-dmg.sh`'s `verify_sparkle_vendor` preflight aborts on drift.
- Keep the framework's top-level `Updater.app` symlink and `Versions/B/{Updater.app,XPCServices,Autoupdate}`; a missing piece produces "An error occurred while launching the installer" and broke releases 0.014–0.021.
- Sparkle's MIT notice ships in every bundle as `Contents/Resources/Sparkle-LICENSE.txt`, copied from `mac/tools/sparkle/LICENSE` by `build-dmg.sh` (which fails closed without it) and `build_and_run.sh` (guard: `SparkleLicenseNoticeTests`).
- Re-vendor only from the official `Sparkle-<ver>.tar.xz` archive, never SwiftPM artifacts, which ship no helper apps; `.gitignore` keeps explicit `!tools/sparkle/…` lines so the global `*.app` rule cannot drop the helper.
- `Package.swift` links Sparkle with `-F tools/sparkle` unsafe flags, so this leaf package cannot be another package's dependency, and the flag resolves through the tracked root `tools -> mac/tools` symlink (`mac/AGENTS.md`).
- Back up the EdDSA private key (keychain account `jpthecat`, exported to `~/.config/jpthecat/sparkle_ed25519_priv.key`); losing it strands every installed user on their current build.
- The feed sets `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`; an unsandboxed app needs no Sparkle XPC entitlements or mach-lookup exceptions.
- `stage-widget-appintents-metadata.sh` stages native products from `mac/build/appintents/<configuration>/native-build`; never copy that flat resource bundle into swiftbuild's Contents-style bundle.
- `mac/.periphery.yml` configures a Periphery unused-code scan for an AppKit and Sparkle `@objc` app: run `swift build --build-tests && periphery scan` from `mac/`, and delete what it flags.
  The config pins SwiftPM's `.build/out` index store, so the scan reads the last build and never builds for itself.

## Update UI at runtime

- `Updater` is the `SPUStandardUserDriverDelegate`: it activates JP and floats update-session windows before Sparkle shows UI, then restores the activation policy and window levels in `standardUserDriverWillFinishUpdateSession()`.
  `userDriverDelegate: nil` is a regression, because the update alert opens behind other apps.
- `checkForUpdatesInBackground()` calls `checkForUpdateInformation()` with no UI and publishes `updateAvailable`, which drives the right-click row title and the settings status dot.

## Web, DNS, and Email Routing

- `jpthecat.com` (`A 216.150.1.1`), `www.jpthecat.com` (`CNAME *.vercel-dns-016.com`), and `api.jpthecat.com` (Supabase custom domain) stay DNS-only in Cloudflare behind `8lee/jpthecat-web`, with zone settings normalized to `ssl` `strict`, `always_use_https` `on`, `min_tls_version` `1.2`, `email_obfuscation` `off`, and `DNSSEC` `disabled`.
- Outbound mail authenticates through DNS-only Resend records (`mail.jpthecat.com -> send.forge.rmta.net`, `resend._domainkey`, `send.jpthecat.com` MX/SPF, and `_dmarc` `p=none`), and inbound mail uses Cloudflare Email Routing (`route1/2/3.mx.cloudflare.net`, subaddressing on, zero custom rules, and catch-all forwarding to the operator inbox).
