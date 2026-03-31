#!/usr/bin/env bash
set -euo pipefail

readonly REAL_CLANG="${MITORI_REAL_CLANG:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang}"

is_deadlock_prone_probe() {
  local saw_v=0
  local saw_E=0
  local saw_dM=0
  local saw_x_probe_language=0
  local saw_dev_null=0
  local expect_x_value=0
  local arg

  for arg in "$@"; do
    if [ "$expect_x_value" -eq 1 ]; then
      saw_x_probe_language=1
      expect_x_value=0
      continue
    fi

    case "$arg" in
      -v) saw_v=1 ;;
      -E) saw_E=1 ;;
      -dM) saw_dM=1 ;;
      -x) expect_x_value=1 ;;
      /dev/null) saw_dev_null=1 ;;
    esac
  done

  [ "$saw_v" -eq 1 ] &&
    [ "$saw_E" -eq 1 ] &&
    [ "$saw_dM" -eq 1 ] &&
    [ "$saw_x_probe_language" -eq 1 ] &&
    [ "$saw_dev_null" -eq 1 ]
}

if ! is_deadlock_prone_probe "$@"; then
  exec "$REAL_CLANG" "$@"
fi

stdout_path="$(mktemp "${TMPDIR:-/tmp}/mitori-clang-probe-stdout.XXXXXX")"
stderr_path="$(mktemp "${TMPDIR:-/tmp}/mitori-clang-probe-stderr.XXXXXX")"

cleanup() {
  rm -f "$stdout_path" "$stderr_path"
}

trap cleanup EXIT

if "$REAL_CLANG" "$@" >"$stdout_path" 2>"$stderr_path"; then
  cat "$stdout_path"
  exit 0
fi

status=$?
cat "$stdout_path"
cat "$stderr_path" >&2
exit "$status"
