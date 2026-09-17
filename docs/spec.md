# Mitori Spec

This is the living, normative spec for Mitori. It exists so that any coding
agent (or human) can pick up a task and move in the same direction without
re-deriving decisions from chat history.

**How to use this document**

- Read this file before implementing anything under `docs/tasks/`.
- **Spec-first rule:** if an implementation need conflicts with this spec,
  stop and update the spec (or ask Zach) before writing code. Never silently
  diverge.
- Every change to this file gets a dated entry in the Decision Log (§8).
- Task cards in `docs/tasks/` cite invariants by ID (e.g. "I-3"). A review
  that finds a violated invariant cites it the same way.

---

## 1. Product definition

Mitori is a native macOS menu bar app that watches **Apple ID store credit**
for N accounts. The product is: *login → see balance → balance stays fresh
without babysitting*.

- The **authenticate response** is the primary balance source
  (`accountInfo.balance` / `creditDisplay`, `source: .authentication`).
- The **probe** (`volumeStoreDownloadProduct` against an owned app) is an
  optional, secondary verifier (`source: .probe`). A missing probe is never a
  broken account.
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
  `localizedDescription`.
- **I-4** Balance parsing is strict per source. Explicit field paths per
  endpoint; the empty-`creditDisplay`-means-zero rule applies to the **probe**
  response only. An authenticate response that yields no balance field means
  "no data" - keep the previous snapshot, never fabricate 0.
- **I-5** Numeric parsing must round-trip real storefront formats:
  `$1,234.56`, `¥1,000` (JPY, no decimals), `1.234,56 €`, `1,50 €`. A parsed
  value that changes the order of magnitude of the display string is a bug.
- **I-6** Refresh discipline: auto refresh is interval-gated
  (`RefreshSettingsStore.minimumInterval` = 15 min floor). A refresh of a
  no-probe account must not silently degrade into an unbounded loop of full
  password logins.
- **I-7** No new 3xx/redirect special case is added without a captured header
  dump (status, header names, body length/type) proving the case exists.
  Workarounds do not stack; the previous one is removed or justified.
- **I-8** Secrets (passwords, cookies, passwordToken, device GUID, real Apple
  IDs) never appear in logs, test fixtures, task cards, or commits.
- **I-9** Probe failures after a successful (re)authentication are recorded as
  a visible issue, never swallowed. A `sessionExpired` from the probe
  immediately after a fresh reauth is recorded as `balanceUnavailable`
  and retains the authentication snapshot. T3 must also stop scheduled refresh
  for probe accounts with `balanceUnavailable`; renaming the issue alone does
  not stop the next scheduled password login. Manual recovery remains available.
- **I-10** Errors and state shown to the user belong to a specific account.
  One account's success must not clear another account's error surface.
- **I-11** Repo shape rules in `AGENTS.md` hold: no Tuist/XcodeGen/standalone
  `Package.swift`; app code in `Mitori/`, tests in `MitoriTests/` using Swift
  Testing; verification through `mise run test-macos` / `build-macos` /
  `run-macos`.

## 3. Refresh & session policy

Current agreed direction (see D-4 for the open live-evidence gate):

- Auto refresh: model-gated by interval, screen lock, in-flight work, and backoff.
  Skip accounts that require verification and probe accounts with a
  `balanceUnavailable` issue. Other accounts continue on their own schedule.
  Use the existing persisted issue kind; do not add a second suspension flag.
- Recovery: the user can retry through manual refresh or explicit reauthentication,
  or change/remove the probe. A successful retry clears the issue; another
  rejected fresh session keeps automatic refresh paused. A failed recovery
  must not clear an existing pause until the probe succeeds or its configuration
  changes. Preserve the pause while showing the latest recovery error. If recovery
  requires 2FA, use `requiresVerification`, which also suspends automatic refresh.
- Manual refresh never reports a cached snapshot as a successful network refresh.
  Reuse the existing in-flight operation guard for repeated clicks; do not add
  the previously proposed 60-second cache shortcut.
- Manual refresh, account **with** probe: probe fetch; on `sessionExpired`,
  one reauth then one probe retry. A second probe failure is recorded (I-9).
- Manual refresh, account **without** probe: silent reauthentication.
  **Open decision (D-4):** whether silent reauth sends stored cookies or
  `cookies: []`. Resolved by the T5 evidence protocol, not by guessing.
  Limit a changed cookie policy to this no-probe refresh path. Shared
  reauthentication, probe recovery, and interactive 2FA keep their policy unless
  separate evidence and regression tests justify a change.
- Silent reauth (no 2FA code) that comes back `codeRequired` surfaces as
  `needsVerification` state - it never blocks or loops.

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

Protocol error mapping uses typed cases. T6b removes protocol-message matching
from `MitoriError.map`. RefreshIssue-to-UI mappings also use `kind`, not message
text. Native transport and storage errors retain their domain/code mappings;
unknown errors remain visible without being classified from English text.

## 5. Architecture: current → target

**Current:** Apple protocol lives in the `Zach677/ApplePackage` fork (branch
`zach/mitori`), pinned by revision in `Mitori.xcodeproj`. Mitori uses a subset
of its authentication and lookup code. Confirm the source subset and resolved
dependencies at the chosen revision before the port. Each protocol fix currently
requires a fork change and a pin update.

**Target:** the protocol layer moves **into this repo** as a source folder -
`Mitori/AppleStore/` - inside the app target (synchronized folder reference;
no SPM package, per I-11). Scope of the module:

- bag fetch + endpoint normalization, authenticate (with CommerceKit
  signing), probe (`volumeStoreDownloadProduct`), iTunes lookup, cookie jar,
  storefront table, device GUID.
- `CommerceKitSigner` (~140 lines Obj-C) joins the app target via bridging
  header.
- One URLSession transport with the I-2 redirect validator, typed errors (§4).

**Migration rule: port, don't rewrite.** Move code and its tests from the
fork nearly verbatim first (behavior identical to the last live-verified fork
state), then refactor in separate commits. "Move" and "improve" never share a
commit. The existing seams `AppleAuthenticating` and `BalanceRefreshing` stay;
their behavior contracts stay stable. Port package-owned types used by these
seams, then update imports and type references in production code and test
doubles together. Preserve test assertions; a new local type is not the same
Swift type as its former package type.

Attribution: the port derives from ApplePackage (MIT, Lakr233) which adapts
ipatool (MIT, majd). `Mitori/Resources/OpenSourceLicenses.md` keeps both
notices after the SPM dependency is removed.

**Later (not scheduled):** collapse `MitoriModel`'s five concurrency
bookkeeping mechanisms (generations, mutation sets, pending logins, refresh
states, repository locks) into a per-account runtime actor. Out of scope for
every current task card; do not start it opportunistically.

## 6. Defect register

| ID | Sev | Summary | Where | Task | Status |
|----|-----|---------|-------|------|--------|
| B1 | P0 | Comma-only amounts parsed as decimals: `¥1,000` → 1 (JPY & no-cent USD balances off by 1000×) | `BalanceParser.numericValue` | T1 | open |
| B2 | P0 | Empty `creditDisplay` in authenticate response fabricates a `$0.00` snapshot | `BalanceParser.parse` zero fallback + `emptyCreditDisplayPath` | T2 | open |
| B3 | P1 | Probe `sessionExpired` after successful reauth swallowed; refresh silently becomes login+2 probes forever | `AppleSessionBridge.authenticate` catch | T3 | open |
| B4 | P1 | Fork follows redirect `Location` with no scheme/host validation on a credential-bearing POST | fork `Authenticate.resolvedRedirectURL` | T5 safety prerequisite; T6b consolidation | open |
| B5 | P2 | Global `bannerMessage`: any account's success clears another account's error banner | `MitoriModel.applyPostRefreshState` | T4 | open |
| B6 | P2 | Re-adding an existing email silently wipes snapshot/history (`existing: nil`) with no duplicate warning | `MitoriModel.addAccount` / bridge `login` | T4 | open |
| B7 | P3 | `recordFailure` mutates `accounts[index]` before the generation check | `MitoriModel.recordFailure` | T4 | open |
| B8 | P1 | Refresh of a no-probe account 302s (`failed to retrieve redirect location (HTTP 302)`); fork pin `3b535f1` unverified | policy + fork | T5 | open |

Update the Status column (open / in-progress / fixed @commit) as tasks land.

## 7. Verification gates

Use this section with each card's acceptance criteria. A missing required gate
means `blocked`, not `done`. Document-only edits require G4, not an app build.

| Gate | Pass condition | Required for |
|------|----------------|--------------|
| G1 Unit | `mise run test-macos` exits 0; bug-fix regressions fail before the fix and pass after it | Every code card |
| G2 Build | `mise run build-macos` exits 0 and produces the expected app bundle | Project, dependency, resource, or bridging-header changes |
| G3 Live no-probe | Supervised login, manual refresh, then another manual refresh each sends an authenticate request and returns a fresh auth response | T5, T6a, T6b, T6c; any release |
| G4 Docs | Re-read changed cards and spec; check task dependencies, paths, commands, and invariant ownership; `git diff --check` passes | Document changes |
| G5 Runtime | `mise run run-macos`; confirm the changed UI/state behavior in the running app, including the failure state | T3, T4, T6a, T6b, T6c |
| G6 Community | `mise run test-community`, `mise run package-community`, then `bash scripts/smoke-community-dmg.sh <dmg-path>` all exit 0 | T6a, T6b, T6c; any release |

G3 is supervised by Zach. Agents never initiate real credential entry or live
logins on their own. Record build revision, build/signing mode, macOS version,
anonymous account label, operation sequence, request counts, and response/source
and snapshot timestamps. Never record account identifiers or header values.
A cache hit, retained old snapshot, skipped request, or UI-only success does not
pass. Each successful no-probe operation must yield new balance data from that
operation, even when the amount is unchanged. A missing balance is still a valid
no-data application result, but does not pass this live balance-retrieval gate.

For T6, also run a supervised owned-probe refresh on the new build. Cover expired
session, invalid 2FA, rejected fresh session, network failure, screen lock, and
per-account isolation with deterministic tests. Do not force real Apple failures
to satisfy a test. Missing credentials or hardware is an explicit validation gap.
G3 must pass on the final community build before a release is declared ready.

Every card completion report includes:

- Base revision, final revision or uncommitted diff, and exact changed files.
- Each acceptance criterion mapped to a named test or observed manual result.
- Exact commands, exit codes, required live evidence, and remaining blockers.
- Recovery/rollback steps. Preserve stored account and Keychain formats; code
  rollback must not delete user data. Reverting a cookie change restores the
  last verified policy. Never remove redirect validation or log redaction to
  recover connectivity. No commit, push, tag, or release is implied by a card.

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
