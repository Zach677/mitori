#!/usr/bin/env bash
# Copy the named screen captures from the newest UI test result into
# .artifacts/ui-screens/<screen>.png, replacing the previous set.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT="$(ls -td "$ROOT_DIR"/.xcodebuild/community/Logs/Test/*.xcresult 2>/dev/null | head -1)"
[[ -n "$RESULT" ]] || { echo "No xcresult found" >&2; exit 1; }

EXPORT_DIR="$(mktemp -d)"
OUTPUT_DIR="$ROOT_DIR/.artifacts/ui-screens"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EXPORT_DIR" >/dev/null
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

python3 - "$EXPORT_DIR" "$OUTPUT_DIR" <<'PY'
import json, re, shutil, sys
export_dir, output_dir = sys.argv[1:]
count = 0
for test in json.load(open(f"{export_dir}/manifest.json")):
    for attachment in test.get("attachments", []):
        match = re.match(r"screen-(.+?)_\d+_", attachment.get("suggestedHumanReadableName", ""))
        if match:
            shutil.copy(f"{export_dir}/{attachment['exportedFileName']}", f"{output_dir}/{match.group(1)}.png")
            count += 1
print(f"Exported {count} screens to {output_dir}")
PY
rm -rf "$EXPORT_DIR"
