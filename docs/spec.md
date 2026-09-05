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
  "no data" — keep the previous snapshot, never fabricate 0.
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
  (a second reauth cannot help) to prevent reauth loops.
- **I-10** Errors and state shown to the user belong to a specific account.
  One account's success must not clear another account's error surface.
- **I-11** Repo shape rules in `AGENTS.md` hold: no Tuist/XcodeGen/standalone
  `Package.swift`; app code in `Mitori/`, tests in `MitoriTests/` using Swift
  Testing; verification through `mise run test-macos` / `build-macos` /
  `run-macos`.

## 3. Refresh & session policy

Current agreed direction (see D-4 for the open live-evidence gate):

- Auto refresh: model-gated by interval and backoff (already implemented in
  `MitoriModel.shouldAutoRefresh`). Unchanged.
- Manual refresh, account **with** probe: probe fetch; on `sessionExpired`,
  one reauth then one probe retry. A second probe failure is recorded (I-9).
- Manual refresh, account **without** probe: silent reauthentication.
  **Open decision (D-4):** whether silent reauth sends stored cookies or
  `cookies: []`. Resolved by the T5 evidence protocol, not by guessing.
- Silent reauth (no 2FA code) that comes back `codeRequired` surfaces as
  `needsVerification` state — it never blocks or loops.

## 4. Error taxonomy (target)

The protocol layer throws a typed error, e.g.:

```
enum StoreAuthError: Error {
  case codeRequired
  case invalid2FACode
  case badLogin(message: String)
  case redirectExhausted(status: Int)
  case untrustedRedirect(host: String)
  case transport(URLError)
  case malformedResponse(String)
}
```

`MitoriError.map` translates typed cases only; the string-matching branches in
`Mitori/Domain/MitoriError.swift` are deleted once the protocol layer is
ported (T6b).

## 5. Architecture: current → target

**Current:** Apple protocol lives in the `Zach677/ApplePackage` fork (branch
`zach/mitori`), pinned by revision in `Mitori.xcodeproj`. Mitori uses ~1,100
of its 3,340 lines; the download machinery and 5 transitive dependencies are
dead weight. Every protocol fix costs a fork commit + pin bump.

**Target:** the protocol layer moves **into this repo** as a source folder —
`Mitori/AppleStore/` — inside the app target (synchronized folder reference;
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
only their live implementations change, so the fake-based tests keep running
unchanged.

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
| B4 | P1 | Fork follows redirect `Location` with no scheme/host validation on a credential-bearing POST | fork `Authenticate.resolvedRedirectURL` | T6b (structural fix) | open |
| B5 | P2 | Global `bannerMessage`: any account's success clears another account's error banner | `MitoriModel.applyPostRefreshState` | T4 | open |
| B6 | P2 | Re-adding an existing email silently wipes snapshot/history (`existing: nil`) with no duplicate warning | `MitoriModel.addAccount` / bridge `login` | T4 | open |
| B7 | P3 | `recordFailure` mutates `accounts[index]` before the generation check | `MitoriModel.recordFailure` | T4 | open |
| B8 | P1 | Refresh of a no-probe account 302s (`failed to retrieve redirect location (HTTP 302)`); fork pin `3b535f1` unverified | policy + fork | T5 | open |

Update the Status column (open / in-progress / fixed @commit) as tasks land.

## 7. Verification gates

- **G1 Unit:** `mise run test-macos` green. Required for every task.
- **G2 Build:** `mise run build-macos` for packaging-affecting changes
  (project file, resources, new folders, bridging header).
- **G3 Live no-probe gate (ship blocker):** on a real account with no probe:
  login → manual refresh → manual refresh again, all three succeed in a row.
  Required before any release and before declaring B8 fixed. Requires Zach at
  the keyboard; agents never run live logins on their own (I-8).
- **G4 Docs:** doc-only changes verify by re-reading the file and checking
  commands/paths against the repo.

## 8. Decision log

- **D-1** (prev. session) Balance comes from the authenticate response; probe
  demoted to optional "Background Refresh". Accounts are Ready without a probe.
- **D-2** (2026-09-05) Abandon the ApplePackage dependency. The protocol layer
  is ported into `Mitori/AppleStore/` as app-target source — no separate
  package, no separate repo. Rationale: Mitori uses ~1/3 of the fork, the
  fork's product direction is download (not session health), and the
  dependency boundary itself caused the pin-bump friction. The fork stays as a
  read-only reference archive.
- **D-3** (2026-09-05) Migration is a port, not a rewrite (§5). Fix order:
  app-side bugs first (T1–T4), refresh policy + live 302 evidence (T5), then
  the port (T6a–c). No porting while B8 is unresolved.
- **D-4** (2026-09-05, **open**) Cookie policy for silent reauth of no-probe
  accounts — stored cookies vs `cookies: []` — decided by T5's instrumented
  live run, per I-7. The fork's `3b535f1` cookie-clear retry is reverted if
  cookie-less becomes the app-level default (no stacked workarounds).
- **D-5** (2026-09-05) Workflow: this spec + `docs/tasks/` cards are the
  hand-off medium. Analysis/orchestration/verification by the reviewing agent;
  implementation by coding agents executing one card at a time; Zach
  dispatches and accepts.
