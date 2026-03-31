#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/tuist-common.sh"

ensure_dependencies_installed
ensure_xcode_cache_setup
ensure_external_cache_warmed
ensure_generated_workspace
