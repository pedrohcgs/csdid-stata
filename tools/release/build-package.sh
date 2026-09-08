#!/usr/bin/env bash
# Build with the release compiler while callers may test another Stata runtime.
set -euo pipefail

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [SUCCESS_MARKER]" >&2
  exit 2
fi
marker="${1:-}"
if [[ -n "$marker" ]]; then
  [[ "$marker" = /* ]] || marker="$PWD/$marker"
  if [[ -e "$marker" || -L "$marker" ]]; then
    echo "build success marker already exists: $marker" >&2
    exit 2
  fi
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
build_stata="${CSDID_BUILD_STATA_CMD:-${STATA_CMD:-stata-mp}}"

if [[ -e build.log || -L build.log ]]; then
  mkdir -p build/build-logs
  previous="$(mktemp "$ROOT/build/build-logs/build.XXXXXXXX")"
  if ! mv build.log "$previous"; then
    echo "cannot archive the previous build.log; refusing a potentially stale build" >&2
    exit 1
  fi
fi

# Do-file arguments can alter Stata's batch-log basename. This invocation has
# none, so the fresh log is always build.log, independent of the caller.
status=0
"$build_stata" -b do src/build.do || status=$?
if [[ "$status" -ne 0 ]]; then
  echo "package builder failed (exit $status): $build_stata" >&2
  exit 1
fi
bash tools/release/check-stata-log-tail.sh build.log

if [[ -n "$marker" ]]; then
  # noclobber also prevents a file created during the build being overwritten.
  (set -o noclobber; printf '%s\n' 'CSDID-PACKAGE-BUILD-COMPLETE' > "$marker")
fi
printf '%s\n' "package build complete: $build_stata"
