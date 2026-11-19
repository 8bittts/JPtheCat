# JP the Cat — Privacy and Terms

Last updated November 19, 2026.
Questions go to support@JPtheCat.com or a GitHub issue on this repository.

## Privacy policy

### Local usage records

JP the Cat reads local session logs and usage files written by supported AI coding tools.
The app uses that local data to calculate usage, cost, and official or estimated plan-window percentages on your Mac.
It never reads Claude Code's stored credentials or asks for your macOS password to label a plan.

### No JP cloud for your work

There is no JP the Cat cloud sync account for usage data.
Prompts, code, transcripts, token history, computed costs, local usage database contents, and provider credentials are not uploaded to JP.

### No website tracking

JP the Cat has no marketing website.
JPtheCat.com only serves the app's update feed and sends every other visit to this GitHub repository.
It runs no analytics, sets no cookies, and records no download events.

### Downloads and updates

The public DMG and update files are GitHub Release assets on this open-source repository, and GitHub serves them under its own privacy terms.
JP keeps no download database, collects no email address on download, and sends no newsletter or owner notification.
Sparkle update checks request the update feed and release files, and the app fetches its public pricing table from the same feed.
The app makes no license, trial, or purchase calls: it is free and does not identify your Mac to JP's servers.
No raw hardware identifiers (serial number or platform UUID) ever leave your Mac.
Update checks do not include prompts, code, transcripts, token history, computed costs, provider credentials, or local usage database contents.

If you turn on Grok plan usage in Live data (off by default), the app uses the sign-in Cursor or Grok Bot already saved on your Mac and sends only that bearer token to `api2.cursor.sh` to fetch official weekly and billing-cycle percentages.
It never uses refresh tokens and never sends prompts, code, transcripts, local usage, or paths.
One shared five-minute cadence covers the unified Grok view.
Turning it off stops the calls and deletes unified and legacy saved plan readings.
Local Grok Build and optional Cursor stop-hook activity stay on your Mac.

### Support

Support is plain email.
The app's optional redacted support report opens your own mail app addressed to support@JPtheCat.com; nothing is sent unless you send that message.
Support records may include the email address you write from, the app and macOS versions you share, and the messages you send.
JP does not sell anything, so there is no checkout and no payment data.

### AI providers are separate

JP the Cat is not affiliated with Anthropic, OpenAI, Google, GitHub, Cursor, or other listed AI providers.
Their products, APIs, invoices, websites, and privacy policies are separate from JP.

### Your choices

You can stop using the app, delete local app data, remove the app, or contact us about any records we hold.
Mac app product analytics are off by default.
If opt-in diagnostics or crash reporting ship later, the control will be clearly labeled and will not include prompts, code, transcripts, or token history.

### Children

JP the Cat is a developer tool and is not directed to children under 13.
We do not knowingly collect children's personal information.

### Who may process what

| Service | Role |
|---|---|
| Vercel | Hosts the update feed at JPtheCat.com and the redirect to GitHub. |
| GitHub | The open-source repository and the release downloads, including the update files Sparkle fetches. |
| Sparkle | The macOS update framework that checks the public update feed and downloads app updates. |

## Terms of service

### Free to use

JP the Cat is free.
You may download it and run it on as many of your own Macs as you like, including updates.
There is no account, license key, trial, or payment.

### Earlier purchases

Before JP the Cat became free it was sold as a paid license.
The app no longer checks licenses, so every feature is available to everyone, including earlier buyers.
Questions about an earlier purchase go to support@JPtheCat.com.

### What JP provides

JP the Cat estimates AI usage and cost from logs on your machine.
We work hard to be accurate, but figures are estimates for your convenience and may differ from a provider's official billing.
Always treat your provider's invoice as the source of truth.

### Fair use

Do not resell, rent, or host the app as a paid service, tamper with the update system, or use the app in a way that violates the rules of your AI provider or applicable law.
The source code is MIT licensed; the JP the Cat name, logo, app icon, and mascot assets are not (see [README.md](README.md#license)).

### Third-party providers

JP the Cat is independent from Anthropic, OpenAI, Google, GitHub, Cursor, and every other listed AI provider.
Provider names are used only to identify the local usage data the app can interpret or plans to interpret.
You are responsible for your provider accounts, invoices, API usage, and provider terms.

### Updates and availability

We may change features, provider support, or download availability.

### No warranty

The app is provided as-is.
We do not promise that every provider file will be parseable, that estimates will match invoices exactly, or that the app will be free of bugs or interruptions.

### Liability limit

To the maximum extent allowed by law, JP the Cat's liability is limited to the amount you paid for the app, which is nothing for the free app.
We are not liable for lost profits, lost data, business interruption, provider charges, or indirect damages.

### Changes

If these terms change materially, we will update this file.
Continuing to use the app after an update means you accept the revised terms.
