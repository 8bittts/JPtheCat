# Growth

What JP the Cat can measure, and where growth happens now that the website is retired.

## 1. Measurement

JP the Cat is free and app usage stays local, so there is no product analytics and no website analytics.
`jpthecat.com` is only Cloudflare redirects to GitHub; it runs no analytics and records nothing.
Never add a download counter, a growth database, or an owner report without an explicit operator request and a `PRIVACY.md` update in the same change.

- **Repository traffic** is GitHub's Insights → Traffic view (views, unique visitors, referrers, clones), kept for 14 days; read it with `gh api repos/8bittts/JPtheCat/traffic/views` and `.../traffic/popular/referrers`.
- **Stars, forks, issues, and pull requests** are the public engagement signal.
- **Release downloads** show per-asset counts on the GitHub Releases page (`gh api repos/8bittts/JPtheCat/releases`); a count is a byte fetch, not an install, and Sparkle delta downloads count separately from DMGs.
- **Homebrew installs** are not reported for a third-party tap.

## 2. Discovery

The GitHub README is the public home page: its first screen carries the pitch, the overview image (`brand/homepage.jpg`), the stable version, the download link, and the Homebrew install path.
Keep it honest to shipped scope under the same rules as the app: only `live` providers are called supported, non-Claude dollars are notional, and quota percentages appear only where a provider reports them.
The retired `/library` programmatic SEO pages are gone, and their URLs redirect to the repository; do not rebuild them.
Launch copy and positioning are owned by [10-gtm.md](10-gtm.md).
