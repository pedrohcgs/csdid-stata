#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 LOG [LOG ...]" >&2
  exit 2
fi

failed=0
for log in "$@"; do
  if [[ ! -f "$log" ]]; then
    echo "missing Stata log: $log" >&2
    failed=1
    continue
  fi
  # Robust detection. Two former weaknesses: (a) `if ... | rg -q ...; then`
  # read a MISSING ripgrep (exit 127) as "no failure", so the gate passed when
  # the tool was absent; (b) only the last 40 lines were scanned, so an
  # uncaught error followed by further output was invisible. Now: grep (POSIX),
  # whole file, and grep's exit status checked explicitly. `capture`d errors do
  # not emit a bare r(rc); line, so a whole-file scan stays correct for tests
  # that deliberately provoke errors.
  grep_status=0
  grep -qE '^r\([0-9]+\);$' "$log" || grep_status=$?
  if [[ "$grep_status" -eq 0 ]]; then
    echo "terminal Stata failure marker found in $log" >&2
    failed=1
  elif [[ "$grep_status" -ne 1 ]]; then
    echo "could not scan $log for failure markers (grep exit $grep_status)" >&2
    failed=1
  fi
done

exit "$failed"
