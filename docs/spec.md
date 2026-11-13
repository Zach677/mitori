# Mitori Spec

This is the normative spec for Mitori: what the product is, the rules that
must hold, and the decisions that are in force now.

- Read it before a change to sign-in, refresh, storage, or the store protocol.
- If a change conflicts with this spec, stop and ask Zach, or change the spec
  in the same commit. Never diverge silently.
- This file holds current rules only. History is in git: the full decision
  log, the closed defects, and the task cards T1-T6c of the 2026-09/10 rework
  were last present at `dc4edad`.

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

- **I-1** One HTTP stack. All Apple store traffic goes through
  `StoreTransport` (URLSession) with a single redirect policy.
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
  IDs) never appear in logs, test fixtures, docs, or commits.
- **I-9** Failures are visible. A probe failure after a user-started
  reauthentication is recorded as an issue, never swallowed.
- **I-10** Errors and state shown to the user belong to a specific account.
  One account's success must not clear another account's error surface.
- **I-11** Repo shape rules in `AGENTS.md` hold: no Tuist/XcodeGen/standalone
  `Package.swift`; app code in `Mitori/`, unit tests in `MitoriTests/` using
  Swift Testing; verification through the `mise` tasks.

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
  Changing or removing the probe clears probe-related issues only. Saving an
  unchanged probe keeps the issue.
- Manual refresh always makes a real request. Repeated clicks reuse the
  in-flight operation guard; there is no cache shortcut.
- The persisted issue kind is the pause signal; there is no extra flag.
- Manual reauth of a no-probe account sends the stored cookies. Login (add
  account) sends none.
- A server failure is a `network` issue and keeps the network backoff. A
  cancelled refresh returns to idle and records no issue.

## 4. Error taxonomy

The protocol layer throws a typed error:

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

`MitoriError.map` and the probe's `parseKnownFailure` classify by typed case,
not by message text. Native transport and storage errors keep their
domain/code mappings; unknown errors stay visible.

## 5. Architecture

- Layers: `App` (lifecycle, `MitoriModel`), `UI` (AppKit), `Services`
  (persistence, session bridge, parsing), `Domain` (models, `MitoriError`),
  `AppleStore` (store protocol, transport, redirect policy, typed errors).
- `Mitori/AppleStore/` is a port of a subset of ApplePackage (MIT, Lakr233),
  which adapts ipatool (MIT, majd). The app has no Swift package dependency.
  `docs/applestore-port.md` records the file map and what the port removed.
- The seams `AppleAuthenticating` and `BalanceRefreshing` keep their
  contracts; tests replace them and `StoreTransport`.
- Credentials are in the Data Protection Keychain (`SecItem`); account
  metadata is in `~/Library/Application Support/Mitori/accounts.json`.
- Not scheduled: collapse the concurrency bookkeeping in `MitoriModel`
  (generations, mutation sets, pending logins, repository locks) into a
  per-account actor. Revisit only if a real bug needs it.

## 6. Defects and backlog

Open defects and known work are GitHub Issues: `gh issue list`. A finding
that a change does not fix gets an issue in the same round. The old defect
numbers that are still open: B10 is #2, B11 is #3, B12 is #4, B21 is #5.

Closed before the move to Issues (fix commit): B1 `c011c00`, B2 `d32a0b0`, B3
`2908d9d`, B4 `c481531` `d91468c`, B5 `930a763`, B6 `6b5498a`, B7 `33dfdc2`,
B8 `720c628`, B9 `2908d9d`, B13 `d80e368`, B14 `74c2d1d`, B15 `544f993`, B16
`544f993`, B17 `502723f`, B18 `544f993`, B19 `4452d8a`, B20 `b43caff`.

## 7. Verification

| Check | Command or condition | When |
|-------|----------------------|------|
| Unit | `mise run test-macos` exits 0; a regression test fails before its fix | Every code change |
| Build | `mise run build-macos` exits 0 | Project, resource, script, or bridging-header changes |
| UI | `mise run test-ui-vm` (tart VM) or `mise run test-ui-macos` (host screen) exits 0 | Changes to visible state or accessibility identifiers |
| Runtime | `mise run run-macos`; confirm the changed state, including the failure state | Changes that the UI fixture does not cover |
| Live | Supervised by Zach: login, manual refresh twice (no-probe), and one owned-probe refresh each make a real request and return new balance data | Every release; every change to sign-in or the probe request |
| Docs | Re-read the changed docs; `git diff --check` passes | Document changes |

Agents never start real credential entry or live logins. A live run records
the build revision, signing mode, request counts, and response sources; never
identifiers or header values. A cached, skipped, or UI-only success does not
pass. A rollback must preserve stored accounts and Keychain items and must
never remove redirect validation or log redaction.

## 8. Decisions in force

The numbers are the original log numbers, so references in code stay valid.

- **D-2, D-10** The protocol layer lives in this repo as app-target source, not
  as a package. The ApplePackage fork is a read-only archive.
- **D-16** `URLSessionStoreTransport` is an ephemeral session that refuses
  redirects and stores no cookies; callers follow redirects through
  `StoreRedirectPolicy`. Bag, lookup, and search follow no redirect. A probe
  3xx without `Location`, or a pod with an invalid host, is a malformed
  response and pauses automatic refresh; no retry rule without live evidence
  (I-7).
- **D-17, D-18** `MitoriUITests` is the one XCTest exception to I-11. A
  DEBUG-only fixture (`MITORI_UI_FIXTURE=1`) runs the app on temporary
  accounts, in-memory secrets, and an offline session bridge. The
  accessibility identifiers (`menu.*`, `account-row.*`, `add-account.*`,
  `account-detail.*`, `settings.*`, `document.*`) are the contract for a UI
  rewrite. UI tests do not toggle Open at login, open the privacy policy, or
  write to the pasteboard.
- **D-19** The ApplePackage and ipatool MIT notices live in
  `Resources/AdditionalLicenses/ApplePackage/` at the repository root, not in
  the synchronized `Mitori/Resources/` folder, where two `LICENSE` files would
  collide. `scripts/scan.license.sh` passes with zero packages and fails when
  a required notice is missing.
- **D-20** Authenticate posts to the bag's MZFinance `authenticate` URL with a
  trailing slash and keeps the bag host. The bare path answers 301 without
  `Location`. Verified live 2026-10-15 at `720c628`.
- **D-21** The cookie-less sign-in retry is scoped to a 3xx with no usable
  `Location`, at most once per sign-in. It did not fire in any passing live
  run. Transient sign-in statuses are retried after 10 s and 20 s, and
  `Retry-After` is honored, because each retry sends the password again (B14).
  A 429 or 5xx that is still there after the retries is a transport error
  (B20).
- **D-22** A new or re-added account uses the permanent hardware MAC of the
  primary network interface as its device identifier (IOKit). When none is
  readable, one random identifier is kept in user defaults. Stored accounts
  keep their identifier. Not verified live: the first sign-in of a re-added
  account with the hardware identifier.
- **D-23** The unit test host does not create the status item, the model on
  real accounts, or the refresh timer. Showing a window that is already
  visible does not rebuild its content.
- **D-24** (2026-11-13) There is one build variant. The ad hoc "community"
  build, its compile flag, and its packaging scripts are removed (last present
  at `dcec201`). Builds sign with team `2R495YX57L` and the
  `keychain-access-groups` entitlement. Credentials use the Data Protection
  Keychain; an item from an older build in the login Keychain moves on its
  first read. CI runs the unit tests signed to run locally without the
  entitlement, and the tests that need the Keychain skip there. The UI tests
  do not run in CI; they run with the same signing in a local tart VM
  (`mise run test-ui-vm`), which is not in the development profile. Releases are
  made on Zach's Mac with Developer ID signing and notarization; that script
  does not exist yet, so the repo has no release path until it does. A stored
  secret that cannot be read no longer blocks deleting its account (B19).
- **D-25** (2026-11-13) Task cards and per-card acceptance records are
  retired. This spec holds current rules; a commit message holds the evidence
  for its change. Open defects and backlog are GitHub Issues. Write a task
  card again only for work that must be handed across sessions.
