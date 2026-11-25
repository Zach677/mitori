#!/usr/bin/env bash
# Static guardrails for Mitori's spec invariants (docs/spec.md).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
fail() {
    echo "invariant check failed: $1" >&2
    failures=$((failures + 1))
}

# I-3: Never match on localizedDescription for state decisions.
if grep -rnE --include='*.swift' 'localizedDescription\s*(\.(contains|hasPrefix|hasSuffix|lowercased|uppercased|range\()|==|!=)' Mitori/ >/dev/null 2>&1; then
    grep -rnE --include='*.swift' 'localizedDescription\s*(\.(contains|hasPrefix|hasSuffix|lowercased|uppercased|range\()|==|!=)' Mitori/ >&2
    fail "I-3: localizedDescription must not be matched or inspected for state decisions."
fi

# I-8: No stdout/NSLog printing in app sources; only StoreTrace may emit public unified log lines.
if grep -rnE '\b(print|debugPrint|NSLog)\s*\(' Mitori/ >/dev/null 2>&1; then
    grep -rnE '\b(print|debugPrint|NSLog)\s*\(' Mitori/ >&2
    fail "I-8: print/debugPrint/NSLog is disallowed in Mitori/."
fi
if grep -rn 'privacy: \.public' Mitori/ --exclude='StoreTrace.swift' >/dev/null 2>&1; then
    grep -rn 'privacy: \.public' Mitori/ --exclude='StoreTrace.swift' >&2
    fail "I-8: privacy: .public is allowed only in StoreTrace.swift."
fi

# Sheet lifecycle: all sheets go through NSWindow.presentSheet to prevent retain cycles and stacking.
if grep -rn 'beginSheet(' Mitori/ --exclude='NSWindow+Sheet.swift' >/dev/null 2>&1; then
    grep -rn 'beginSheet(' Mitori/ --exclude='NSWindow+Sheet.swift' >&2
    fail "Use NSWindow.presentSheet instead of calling beginSheet directly."
fi

# Activation policy: only MitoriMain and DockIconPolicyController may set activation policy.
if grep -rn 'setActivationPolicy(' Mitori/ --exclude='MitoriMain.swift' --exclude='DockIconPolicyController.swift' >/dev/null 2>&1; then
    grep -rn 'setActivationPolicy(' Mitori/ --exclude='MitoriMain.swift' --exclude='DockIconPolicyController.swift' >&2
    fail "Route activation policy changes through DockIconPolicyController."
fi

if [[ "$failures" -gt 0 ]]; then
    exit 1
fi

echo "Invariant checks passed."
