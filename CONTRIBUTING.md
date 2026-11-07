# Contributing to JP the Cat

Contributions are welcome: bug reports, provider log fixtures, pricing corrections, and pull requests.

## Before you start

- Read [`AGENTS.md`](AGENTS.md).
  It is the enforceable contract, and every rule there names the test that guards it.
- For a new provider, read [`_docs/11-adding-a-provider.md`](_docs/11-adding-a-provider.md) first.
- For any visual change, read [`_docs/02-design-system.md`](_docs/02-design-system.md) and use the existing design.
  Do not invent new colors, spacing, or components.
- Open an issue before a large change, so the approach can be agreed before you write it.

## Hard rules

- Prompts, code, transcripts, credentials, and local usage databases never leave the user's Mac.
- Never invent a quota, tier, or plan ceiling; show only what a provider reports, or nothing.
- The app makes no Keychain access of its own and needs no Full Disk Access or Accessibility grant.
- Never commit secrets, tokens, signing keys, or local credential state.

## Run the gates

Run each line from the repository root:

```sh
(cd mac && swift build && swift test --parallel)   # native gates
(cd web && bun install && bun run quality)         # full web gate
```

Use Bun for all JavaScript package work.
Add or update tests for the behavior you change, and keep both gates green.

## Pull requests

- Keep each pull request to one topic.
- Describe what changed and how you verified it, including a screenshot for visible UI work.
- Write commit subjects in plain user language; customer-facing release notes are built from them.

Releases, signing, notarization, and deploys need owner credentials, so the maintainer runs them.

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
The JP the Cat name, logo, and mascot art are not covered by that license; see the README.
