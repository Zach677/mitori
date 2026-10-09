# Mitori Spec

This is the living, normative spec for Mitori. Any coding agent (or human) can
pick up a task from it without re-deriving decisions from chat history.

**How to use this document**

- Read this file before implementing anything under `docs/tasks/`.
- **Spec-first rule:** if an implementation need conflicts with this spec,
  stop and update the spec (or ask Zach) before writing code. Never silently
  diverge.
- Every change to this file gets a dated entry in the Decision Log (§8).
- Task cards cite invariants by ID (e.g. "I-3").

---

## 1. Product definition

Mitori is a native macOS menu bar app that watches **Apple ID store credit**
for N accounts. The product is: *login → see balance → refresh when it matters,
without putting the Apple ID at risk*.

- Store credit changes only when the user adds, spends, or redeems credit.
  Freshness is cheap to restore on demand, so background refresh is a bonus,
  not the core promise.
- The **authenticate response** is the balance source at login and on manual
  refresh (`accountInfo.balance` / `creditDisplay`, `source: .authentication`).
- The **probe** (`volumeStoreDownloadProduct` against an owned app) is the only
  background source (`source: .probe`). It uses the stored session and never
  sends a password. A missing probe is never a broken account.
- Each account exposes: a balance snapshot `(value, fetchedAt, source)`, a
  session health state, and an optional last issue. The UI shows staleness
  honestly instead of manufacturing freshness with extra logins.

## 2. Invariants (non-negotiable)

- **I-1** One HTTP stack. All Apple store traffic goes through URLSession with
  a single redirect policy. No AsyncHTTPClient/NIO in the target state.
- **I-2** Every followed redirect is validated: `https`, no credentials in
  URL, port 443, host in an explicit Apple allowlist. A request that carries
  credentials (login POST) never follows a redirect to an unvalidated host.
- **I-3** Protocol errors are typed. UI/state decisions never string-match
  `localizedDescription` or Apple's English messages.
- **I-4** Balance parsing is strict per source. Explicit field paths per
  endpoint; an empty `creditDisplay` means zero only in the **probe**
  response. An authenticate response with no balance field means "no data":
  keep the previous snapshot, never fabricate 0.
- **I-5** Numeric parsing must round-trip real storefront formats:
  `$1,234.56`, `¥1,000`, `1.234,56 €`, `1,50 €`.
- **I-6** Automatic refresh never sends a password. It only runs the probe on
  the stored session. Every password login (add account, manual refresh,
  explicit reauthentication) is started by a user action.
- **I-7** No new 3xx/redirect special case is added without a captured,
  sanitized header dump proving the case exists. Workarounds do not stack.
- **I-8** Secrets (passwords, cookies, passwordToken, device GUID, real Apple
  IDs) never appear in logs, test fixtures, task cards, or commits.
- **I-9** Failures are visible. A probe failure after a user-started
  reauthentication is recorded as an issue, never swallowed.
- **I-10** Errors and state shown to the user belong to a specific account.
  One account's success must not clear another account's error surface.
- **I-11** Repo shape rules in `AGENTS.md` hold: no Tuist/XcodeGen/standalone
  `Package.swift`; app code in `Mitori/`, tests in `MitoriTests/` using Swift
  Testing; verification through `mise run test-macos` / `build-macos` /
  `run-macos`.

## 3. Refresh & session policy

| Trigger | Account | Behavior |
|---------|---------|----------|
| Automatic tick | with probe, no issue or `network` issue | Probe on the stored session. Interval, backoff, screen-lock, and in-flight gates apply. |
| Automatic tick | with probe, any other issue | Skip until a user action clears the issue. |
| Automatic tick | without probe | Skip. Never refreshed automatically. |
| Manual refresh | with probe | Probe; on `sessionExpired`, one silent reauth and one probe retry. A second failure is recorded (I-9). |
| Manual refresh | without probe | One silent reauth; the auth response is the balance. |
| Explicit reauth / 2FA | any | User-supplied code; same recovery as manual refresh. |

- An automatic probe that gets `sessionExpired` records `sessionExpired` and
  stops. It does not reauthenticate.
- Silent reauth that returns `codeRequired` records `requiresVerification`.
- A successful user action clears the issue; automatic refresh then resumes.
  Changing or removing the probe clears probe-related issues only.
- Manual refresh always makes a real request. Repeated clicks reuse the
  in-flight operation guard; there is no cache shortcut.
- Use the existing persisted issue kind as the pause signal; no extra flag.
- **Open (D-4):** whether manual no-probe reauth sends stored cookies or
  `cookies: []`. Decided by T5 live evidence, not by guessing.

## 4. Error taxonomy (target)

The protocol layer throws a typed error, e.g.:

```
enum StoreAuthError: Error {
  case codeRequired
  case invalid2FACode
  case badLogin(message: String)
  case sessionExpired
  case probeAppNotOwned
  case unsupportedStorefront(String)
  case redirectExhausted(status: Int)
  case untrustedRedirect(host: String)
  case transport(URLError)
  case malformedResponse(String)
}
```

Protocol error mapping uses typed cases. `MitoriError.map` and the probe's
`parseKnownFailure` stop classifying by message text. Native transport and
storage errors keep their domain/code mappings; unknown errors stay visible.

## 5. Architecture: current → target

**Current:** Apple protocol lives in the `Zach677/ApplePackage` fork (branch
`zach/mitori`), pinned by revision in `Mitori.xcodeproj`. Mitori uses about
1.8k lines of it: authenticate, bag, lookup, cookies, storefront table,
configuration, device identifier, app search, and `CommerceKitSigner`.

**Target:** the protocol layer lives in `Mitori/AppleStore/` inside the app
target (synchronized folder reference; no SPM package, per I-11), on one
URLSession transport with the I-2 validator and typed errors (§4).

**Migration rule: port, don't rewrite.** Move the fork subset nearly verbatim
first (behavior identical to the pinned revision), then improve in separate
commits. "Move" and "improve" never share a commit. The seams
`AppleAuthenticating` and `BalanceRefreshing` keep their contracts. No fork
changes after the port starts; the fork becomes a read-only archive.

Attribution: the port derives from ApplePackage (MIT, Lakr233), which adapts
ipatool (MIT, majd). `Mitori/Resources/OpenSourceLicenses.md` keeps both
notices after the SPM dependency is removed.

**Later (not scheduled):** collapse `MitoriModel`'s concurrency bookkeeping
(generations, mutation sets, pending logins, refresh states, repository locks)
into a per-account runtime actor. I-6 reduces background work, so revisit only
if a real bug needs it.

## 6. Defect register

| ID | Sev | Summary | Task | Status |
|----|-----|---------|------|--------|
| B1 | P0 | `¥1,000` parsed as 1 (comma-only amounts read as decimals) | T1 | fixed @c011c00 |
| B2 | P0 | Empty auth `creditDisplay` fabricates a `$0.00` snapshot | T2 | fixed @d32a0b0 |
| B3 | P1 | Probe `sessionExpired` after reauth is swallowed; background refresh becomes login + 2 probes forever | T3 | fixed @2908d9d |
| B4 | P1 | Authenticate follows a redirect `Location` with no scheme/host validation on a credential-bearing POST | T6b | open |
| B5 | P2 | Any account's success clears another account's error banner | T4 | fixed @930a763 |
| B6 | P2 | Re-adding an existing email wipes its snapshot/history | T4 | fixed @6b5498a |
| B7 | P3 | `recordFailure` mutates `accounts[index]` before the generation check | T4 | fixed @33dfdc2 |
| B8 | P1 | Manual refresh of a no-probe account 302s (`failed to retrieve redirect location (HTTP 302)`) | T5 | open |
| B9 | P1 | Automatic refresh sends password logins for no-probe accounts and after probe expiry | T3 | fixed @2908d9d |
| B10 | P1 | Add account with a 2FA code fails: `authentication failed: response body is empty (code: 204)` | T5 | open |
| B11 | P3 | `recordFailure` upserts the meta from the start of the refresh; a probe edit between the generation check and the repository lock can be overwritten on disk | - | open |

Update the Status column (open / in-progress / fixed @commit) as tasks land.

## 7. Verification gates

| Gate | Pass condition | Required for |
|------|----------------|--------------|
| G1 Unit | `mise run test-macos` exits 0; regressions fail before the fix | Every code card |
| G2 Build | `mise run build-macos` exits 0 | Project, dependency, resource, or bridging-header changes |
| G3 Live | Supervised: login, manual refresh, second manual refresh (no-probe), and one owned-probe refresh each make a real request and return new balance data | T5; every release |
| G4 Docs | Re-read changed docs; `git diff --check` passes | Document changes |
| G5 Runtime | `mise run run-macos`; confirm the changed UI/state, including the failure state | Cards that change visible state |
| G6 Community | `mise run test-community`, `mise run package-community`, `bash scripts/smoke-community-dmg.sh <dmg-path>` exit 0 | Every release |

G3 is supervised by Zach. Agents never start real credential entry or live
logins. Record build revision, signing mode, request counts, and response
sources; never record identifiers or header values. A cached, skipped, or
UI-only success does not pass.

A completion report lists: changed files, each acceptance item mapped to a test
or observed result, commands with exit codes, and open blockers. Rollback must
preserve stored accounts and Keychain items and must never remove redirect
validation or log redaction. A card does not authorize commit, push, or release.

## 8. Decision log

- **D-1** (prev. session) Balance comes from the authenticate response; probe
  demoted to optional "Background Refresh". Accounts are Ready without a probe.
- **D-2** (2026-09-05) Abandon the ApplePackage dependency. The protocol layer
  is ported into `Mitori/AppleStore/` as app-target source - no separate
  package, no separate repo. Rationale: Mitori uses ~1/3 of the fork, the
  fork's product direction is download (not session health), and the
  dependency boundary itself caused the pin-bump friction. The fork stays as a
  reference archive after T6c. T5 may still require scoped safety or policy fixes
  in the fork before migration.
- **D-3** (2026-09-05) Migration is a port, not a rewrite (§5). Fix order:
  app-side bugs first (T1-T4), refresh policy + live 302 evidence (T5), then
  the port (T6a-c). No porting while B8 is unresolved.
- **D-4** (2026-09-05, **open**) Cookie policy for silent reauth of no-probe
  accounts - stored cookies vs `cookies: []` - decided by T5's instrumented
  live run, per I-7. The fork's `3b535f1` cookie-clear retry is reverted if
  cookie-less becomes the verified no-probe refresh default, only after tests
  show probe recovery and interactive login do not need that fallback. Otherwise
  retain it with a documented, distinct scope; do not layer retries on one path.
- **D-5** (2026-09-05) Workflow: this spec + `docs/tasks/` cards are the
  hand-off medium. Analysis/orchestration/verification by the reviewing agent;
  implementation by coding agents executing one card at a time; Zach
  dispatches and accepts.
- **D-6** (2026-09-17) Tighten execution and acceptance: T2 owns strict
  source-specific parsing; T3 pauses automatic probe recovery after
  `balanceUnavailable`; T5 uses sanitized evidence and real requests, with no
  cache shortcut. Validate credential-bearing redirects before T5 live runs.
  Cookie changes stay within the proven path. Migration acceptance includes
  test-type wiring, account persistence, owned-probe behavior, and community
  builds. D-4 remains open until the supervised evidence gate passes.
- **D-7** (2026-10-01) Accept T1 at `c011c00`. The separator cases in
  `BalanceParserTests.parsesAmountSeparators` and the JPY display regression in
  `formatsParsedYenWithThousandsSeparator` passed with `mise run test-macos`
  (exit 0). Before the fix, the same command exited 65 with five numeric
  failures and one JPY display failure. T2-T6 remain pending; D-4 stays open.
- **D-8** (2026-10-05) T2 removes the authentication zero fallback. Before T2,
  that fabricated zero set `lastRefreshAt` and gated automatic refresh by
  accident. Without it, a no-probe account whose authentication returns no
  balance would do a full password login on every 60 s scheduler tick (I-6).
  T2 therefore owns one model gate: a successful result without new balance
  data sets the existing `nextEligibleRefreshAt` to now + auto refresh interval.
  `lastRefreshAt` and the snapshot stay unchanged, so the UI still shows honest
  staleness. Manual refresh is not gated. No new persisted field.
  Accepted at `d32a0b0` (parser) and `9191bac` (gate); `mise run test-macos`
  exit 0, with eight new tests failing before the fix.
- **D-9** (2026-10-05) Automatic refresh never sends a password (new I-6).
  Store credit changes only on user action, so frequent password logins buy
  little freshness and look like credential stuffing to Apple. No-probe
  accounts refresh only on user action; probe accounts refresh in the
  background on the stored session and pause on any non-network issue.
  Supersedes the background part of D-1 and makes the D-8 gate unnecessary;
  T3 removes it. A low-frequency automatic login is a possible later option,
  not scheduled.
- **D-10** (2026-10-05) Port before the live investigation; supersedes the
  ordering in D-3. A verbatim port does not change behavior, so B8 no longer
  blocks it, and fixing B8 in-repo avoids the fork pin friction that D-2
  wanted to remove. New order: T3 → T4 → T6a → T6b → T6c → T5. No more fork
  changes. B4 moves to T6b. T5 runs once, on the final transport, and doubles
  as the release G3. D-4 stays open until T5.
- **D-11** (2026-10-05) Lighter process. Cards state goal, files, 3-6
  acceptance items, and verification. G3 and G6 are release gates (plus T5),
  not per-card gates. The invariant ownership table is removed; cards cite
  invariants directly.
- **D-12** (2026-10-05) Register B10, seen during the T3 G5 run on the pinned
  fork revision. The first login returns `codeRequired`; the submit with the
  code gets three 204 responses with an empty body (the fork retries 204 as
  transient). T3 does not touch this path. No request trace exists, so the
  cause is not known. Hypotheses: the second submit drops the cookies from the
  first response (`login` always sends `cookies: []`); the transient retry
  reuses a one-time code; Apple changed the 2FA response on the native auth
  endpoint. Per I-7 and D-10, no fork change and no workaround without
  sanitized evidence. T5 captures the trace for an interactive 2FA login.
- **D-13** (2026-10-08) Accept T3 at `2908d9d`. Acceptance 1-5 map to tests in
  `AppleSessionBridgeTests`, `MitoriModelAutoRefreshTests`, and
  `MitoriModelTests`; `mise run test-macos` exit 0, checked again by an
  independent verifier. Saving an unchanged probe keeps the issue, so it does
  not resume a paused account. G5: `mise run run-macos` exit 0, and Zach
  confirmed the Settings auto-refresh help text. The paused-account UI and a
  manual refresh from it were waived: no paused account was available.
  Red-before-green was not shown, because the new bridge signature does not
  compile against the old code.
- **D-14** (2026-10-08) Accept T4 at `33dfdc2` (B7), `930a763` (B5), and
  `6b5498a` (B6). `mise run test-macos` exit 0 after each fix; the B7 test
  failed before its fix. Fix 3 deviates from the card: removing the eager write
  alone broke the in-memory backoff after a failed metadata write, so that
  failure path applies the backoff in memory behind the generation check.
  Fix 1 adds no dismissal, because the UI has none; a banner set from outside
  the model is unowned. G5: `mise run run-macos` exit 0; banner and re-add
  checks with controlled failures need a live account and were not run.
  B11 (found during T4) is registered without a task: the window is a single
  main actor hop, and the fix is to merge failure fields under the repository
  lock.
- **D-15** (2026-10-09) Accept T6a at `ac31c60`. The ApplePackage subset from
  fork revision `3b535f1` lives in `Mitori/AppleStore/`; the file map and the
  four required edits are in `docs/applestore-port.md`. `rg 'import
  ApplePackage' Mitori MitoriTests` has no matches. `mise run build-macos` and
  `mise run test-macos` exit 0 (120 passed, 0 failed, 1 skipped: the
  CommerceKit signer test needs `APPLEPACKAGE_TEST_SAP=1`). The local signer
  symbols carry a `Mitori` prefix, because the still-linked package exports
  `_APCommerceKitSign`; a 6 s direct launch printed nothing to stderr. Stored
  accounts and secrets decode the same (`StoredAccountCompatibilityTests`).
  G5: Zach confirmed an existing account renders. The ApplePackage product
  stays linked until T6c.
