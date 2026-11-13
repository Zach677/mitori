# Contributing to Mitori

Mitori is a personal project that I maintain in my free time. Bug reports and small, focused pull requests are welcome.

## Report a bug

Open an [issue](https://github.com/Zach677/mitori/issues/new/choose). Include the Mitori version, the macOS version, and the steps to reproduce the problem.

Issues are public. Remove passwords, verification codes, cookies, Apple ID email addresses, and device identifiers from text, logs, and screenshots before you post.

Report a security problem privately. See [SECURITY.md](SECURITY.md).

## Change the code

- [README.md](README.md#build-from-source) lists the tools that you need.
- `CI=1 mise run test-macos` runs the unit tests without a developer team. Run it before you open a pull request.
- To build and run the app, set your own `DEVELOPMENT_TEAM` in `Mitori.xcodeproj`. Do not commit that change.
- Read [docs/spec.md](docs/spec.md) before a change to sign-in, refresh, storage, or the Apple Store protocol. A change must keep its invariants.
- Add a test for a bug fix or a behavior change. Tests and fixtures must not contain real account data.
- For a larger change, open an issue first, so that we agree on the direction before you write the code.
- If you used AI tools, say so in the pull request. You must understand the change and test it yourself.
