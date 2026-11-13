#!/usr/bin/env bash
# Run the UI tests in a local tart VM, so they do not take the host screen.
# Needs tart and a VM that has Xcode, mise, and xcbeautify
# (the cirruslabs macos-*-xcode images do). Set TART_HOME if the VM is not in ~/.tart.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM="${VM:-mitori-ui}"
# The public default account of the cirruslabs images; the VM is reachable from this Mac only.
VM_USER="${VM_USER:-admin}"
VM_PASSWORD="${VM_PASSWORD:-admin}"
SSH_OPTIONS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o PubkeyAuthentication=no
    -o PreferredAuthentications=password
    -o ServerAliveInterval=30
)

for tool in tart rsync; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 69; }
done

# ssh gets the password from this helper. sshpass is not used: about one login in ten failed with it.
ASKPASS="$(mktemp)"
printf '#!/bin/sh\necho "$VM_PASSWORD"\n' > "$ASKPASS"
chmod 700 "$ASKPASS"
export VM_PASSWORD SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force

STARTED_VM=0
cleanup() {
    rm -f "$ASKPASS"
    if [[ "$STARTED_VM" == 1 ]]; then
        tart stop "$VM" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

vm_state() { tart list | awk -v vm="$VM" '$1 == "local" && $2 == vm { print $NF }'; }
in_vm() { ssh "${SSH_OPTIONS[@]}" "$VM_USER@$VM_IP" "$@"; }

case "$(vm_state)" in
    running) ;;
    "") echo "No tart VM named $VM. Clone one first, or set VM and TART_HOME." >&2; exit 66 ;;
    *)
        tart run --no-graphics "$VM" >/dev/null 2>&1 &
        STARTED_VM=1
        ;;
esac

VM_IP="$(tart ip "$VM" --wait 180)"
for _ in $(seq 1 30); do
    in_vm true 2>/dev/null && break
    sleep 5
done

cd "$ROOT_DIR"
rsync -a --delete \
    --exclude .git --exclude .xcodebuild --exclude .app-build --exclude .artifacts \
    --exclude node_modules --exclude .build --exclude dist --exclude .cache \
    -e "ssh ${SSH_OPTIONS[*]}" ./ "$VM_USER@$VM_IP:mitori/"

# The VM is not in the development profile, so it runs the build that has no entitlements.
status=0
in_vm 'zsh -lc "cd ~/mitori && mise trust -q && CI=1 mise run test-ui-macos"' || status=$?

mkdir -p .artifacts/ui-screens
rsync -a --delete -e "ssh ${SSH_OPTIONS[*]}" \
    "$VM_USER@$VM_IP:mitori/.artifacts/ui-screens/" .artifacts/ui-screens/ || true
echo "Screens: $(find .artifacts/ui-screens -name '*.png' | wc -l | tr -d ' ') in .artifacts/ui-screens"
exit "$status"
