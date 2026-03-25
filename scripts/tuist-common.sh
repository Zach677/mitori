#!/usr/bin/env bash
set -euo pipefail

readonly MITORI_REPO_ROOT="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
readonly MITORI_CONFIGURATION="${MITORI_CONFIGURATION:-Debug}"
export TUIST_XDG_CACHE_HOME="${TUIST_XDG_CACHE_HOME:-$MITORI_REPO_ROOT/.cache/tuist}"
readonly MITORI_TUIST_STATE_DIR="$MITORI_REPO_ROOT/.xcodebuild/tuist"
readonly MITORI_INSTALL_STAMP="$MITORI_TUIST_STATE_DIR/install.stamp"
readonly MITORI_GENERATE_STAMP="$MITORI_TUIST_STATE_DIR/generate-${MITORI_CONFIGURATION}.stamp"
readonly MITORI_EXTERNAL_CACHE_STAMP="$MITORI_TUIST_STATE_DIR/external-cache-${MITORI_CONFIGURATION}.stamp"
readonly MITORI_TUIST_DIR="$MITORI_REPO_ROOT/Tuist"
readonly MITORI_PACKAGE_SWIFT_PATH="$MITORI_TUIST_DIR/Package.swift"
readonly MITORI_PACKAGE_RESOLVED_PATH="$MITORI_TUIST_DIR/Package.resolved"
readonly MITORI_WORKSPACE_PATH="$MITORI_REPO_ROOT/Mitori.xcworkspace"
readonly MITORI_PROJECT_PATH="$MITORI_REPO_ROOT/Mitori.xcodeproj"

resolve_tuist_bin() {
  if command -v mise >/dev/null 2>&1; then
    (
      cd "$MITORI_REPO_ROOT"
      mise which tuist
    )
    return
  fi

  command -v tuist
}

readonly MITORI_TUIST_BIN="$(resolve_tuist_bin)"

mkdir -p "$TUIST_XDG_CACHE_HOME"

run_tuist() {
  (
    cd "$MITORI_REPO_ROOT"
    "$MITORI_TUIST_BIN" "$@"
  )
}

touch_stamp() {
  mkdir -p "$MITORI_TUIST_STATE_DIR"
  touch "$1"
}

inputs_newer_than_stamp() {
  local stamp_path="$1"
  shift

  if [ ! -f "$stamp_path" ]; then
    return 0
  fi

  while IFS= read -r path; do
    if [ "$path" -nt "$stamp_path" ]; then
      return 0
    fi
  done < <("$@" | sort -u)

  return 1
}

list_dependency_inputs() {
  local path

  for path in "$MITORI_PACKAGE_SWIFT_PATH" "$MITORI_PACKAGE_RESOLVED_PATH"; do
    if [ -e "$path" ]; then
      printf '%s\n' "$path"
    fi
  done
}

list_generation_inputs() {
  local path

  for path in \
    "$MITORI_REPO_ROOT/Project.swift" \
    "$MITORI_REPO_ROOT/Tuist.swift" \
    "$MITORI_PACKAGE_SWIFT_PATH" \
    "$MITORI_PACKAGE_RESOLVED_PATH"; do
    if [ -e "$path" ]; then
      printf '%s\n' "$path"
    fi
  done
}

needs_dependency_install() {
  if [ ! -d "$MITORI_TUIST_DIR/.build/checkouts" ]; then
    return 0
  fi

  inputs_newer_than_stamp "$MITORI_INSTALL_STAMP" list_dependency_inputs
}

ensure_dependencies_installed() {
  if needs_dependency_install; then
    echo "Resolving Swift package dependencies with pinned Tuist..."
    run_tuist install
    touch_stamp "$MITORI_INSTALL_STAMP"
  else
    echo "Skipping tuist install; package graph is unchanged."
  fi
}

external_cache_warming_enabled() {
  case "${MITORI_SKIP_EXTERNAL_CACHE_WARM:-0}" in
    1|true|TRUE|yes|YES)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

needs_external_cache_warm() {
  if [ "${MITORI_FORCE_EXTERNAL_CACHE_WARM:-0}" = "1" ]; then
    return 0
  fi

  inputs_newer_than_stamp "$MITORI_EXTERNAL_CACHE_STAMP" list_dependency_inputs
}

ensure_external_cache_warmed() {
  if ! external_cache_warming_enabled; then
    echo "Skipping external cache warm because MITORI_SKIP_EXTERNAL_CACHE_WARM is set."
    return
  fi

  if needs_external_cache_warm; then
    echo "Warming Tuist binary cache for external dependencies..."
    run_tuist cache warm \
      --path "$MITORI_REPO_ROOT" \
      --configuration "$MITORI_CONFIGURATION" \
      --external-only
    touch_stamp "$MITORI_EXTERNAL_CACHE_STAMP"
  else
    echo "Skipping external cache warm; dependency graph is unchanged."
  fi
}

needs_generation() {
  if [ ! -d "$MITORI_WORKSPACE_PATH" ] || [ ! -d "$MITORI_PROJECT_PATH" ]; then
    return 0
  fi

  inputs_newer_than_stamp "$MITORI_GENERATE_STAMP" list_generation_inputs
}

ensure_generated_workspace() {
  if needs_generation; then
    echo "Generating workspace with binary-cache-enabled externals..."
    run_tuist generate \
      --path "$MITORI_REPO_ROOT" \
      --configuration "$MITORI_CONFIGURATION" \
      --cache-profile only-external \
      --no-open
    touch_stamp "$MITORI_GENERATE_STAMP"
  else
    echo "Skipping generate; manifests are unchanged."
  fi
}
