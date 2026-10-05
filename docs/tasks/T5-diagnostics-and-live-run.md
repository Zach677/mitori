# T5 - Safe diagnostics and the supervised live run (B8, D-4)

Read `AGENTS.md` and `docs/spec.md` I-2, I-7, I-8, D-4, D-10 first.
Precondition: T6c. Zach is at the keyboard for every live step; agents never
enter credentials. This card is an evidence gate: it may end `blocked`.

## Part 1 - Offline (agent)

Add a sanitized request trace to the `Mitori/AppleStore/` transport, off by
default. It logs only: operation and attempt number, endpoint label, cookie
count, status, header names, body size, and body type. No URLs, query strings,
header values, bodies, or identifiers.

Acceptance: a test feeds sentinel secrets through Cookie, Set-Cookie,
authorization, token, GUID, URL, and body fields; no sentinel appears in the
output, and every safe field does.

## Part 2 - Live (Zach supervises)

1. On the current cookie policy, run G3 with the trace on. Count authenticate
   requests per operation, including redirects.
2. If B8 reproduces, try `cookies: []` for **manual no-probe reauth only**.
   Keep it only if G3 passes without an extra 2FA prompt and the trace shows
   the cause. Probe recovery and interactive 2FA keep their policy.
3. If neither policy passes, record the sanitized evidence, leave B8 and D-4
   open, and stop. Do not add a redirect workaround (I-7).
4. Run one owned-probe refresh.

Record the result and revisions in D-4. A passing run is the release G3.

## Verification

G1, G3, G4.
