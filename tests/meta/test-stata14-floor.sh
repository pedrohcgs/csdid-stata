#!/usr/bin/env bash
# csdid.pkg declares "Requires: Stata version 14", and Stata 14-16 load the
# engine from csdid.mata because the library is built by Stata 17. Two
# features newer than the floor reached shipped code before this gate existed,
# and each failed only on a Stata nobody here runs:
#
#   - Mata now() is Stata 17. Mata links every function a routine calls the
#     first time that routine runs, so a version test beside the call does not
#     help: the call must sit alone in csdid__profile_now(), which only a
#     Stata 17+ branch enters.
#   - c(max_matdim) is Stata 16. On Stata 14/15 any expression naming it is
#     r(133), so it may only be read on a line of the form
#       if c(stata_version) >= 16 local <name> = c(max_matdim)
set -euo pipefail
cd "$(dirname "$0")/../.."

fail=0
mata="src/mata/csdid.mata"

# now() and today() outside csdid__profile_now(), comments excluded.
bad_now="$(awk '
  /^real scalar csdid__profile_now\(\)/ { inside = 1 }
  inside && /^}/ { inside = 0; next }
  {
    line = $0
    sub(/\/\/.*/, "", line)
    if (!inside && line ~ /(^|[^A-Za-z0-9_])(now|today)\(/) print FILENAME ":" NR ": " $0
  }' "$mata")"
if [ -n "$bad_now" ]; then
  echo "FAIL: Stata 17 date functions reached outside csdid__profile_now():" >&2
  echo "$bad_now" >&2
  fail=1
fi

# c(max_matdim) outside the guarded assignment, comments excluded.
bad_dim="$(grep -nH 'c(max_matdim)' src/ado/*.ado src/legacy/*.ado \
  | grep -vE ':[0-9]+:[[:space:]]*\*' \
  | grep -vE ':[0-9]+:[[:space:]]*if c\(stata_version\) >= 16 local [A-Za-z_][A-Za-z0-9_]* = c\(max_matdim\)[[:space:]]*$' \
  || true)"
if [ -n "$bad_dim" ]; then
  echo "FAIL: c(max_matdim) read without the Stata 16 guard:" >&2
  echo "$bad_dim" >&2
  fail=1
fi

[ "$fail" = 0 ] && echo "test-stata14-floor: PASS"
exit "$fail"
