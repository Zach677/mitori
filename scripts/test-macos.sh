#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        *=*) export "$arg" ;;
        *) echo "Unexpected argument: $arg" >&2; exit 64 ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift test
