#!/usr/bin/env bash
set -euo pipefail

# Every e() result asserted by a release script must actually be posted by the
# package.
#
# Renaming a stored result is a one-line edit in the poster and leaves every
# script that asserts the old name failing on a missing scalar. e(large_store)
# was unified into e(storage) exactly this way, and the opt-in performance
# script went on asserting the old name: it runs from
# run-platform-release-row.sh rather than from preflight, so the whole suite
# stayed green and the break surfaced only when the macOS platform row was
# needed for a release and could not be produced.
#
# Same shape as a shipped binary that lags its own source: an artifact required
# for release, produced by a path no gate exercises.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Where results are posted. e() names live in the ados; a name posted nowhere
# cannot be asserted anywhere.
posted="$(grep -hoE 'ereturn (scalar|local|matrix) [A-Za-z_][A-Za-z0-9_]*' \
            src/ado/*.ado src/legacy/*.ado 2>/dev/null | awk '{print $3}' | sort -u)"
if [ -z "$posted" ]; then
  echo "found no ereturn names in src/ado -- this gate is checking nothing" >&2
  exit 1
fi

# Scripts that assert on e() and are NOT run by preflight's unit tier, which is
# where an orphaned name would otherwise be caught.
SCRIPTS="tools/bench/run-optin-performance.py tools/bench/run-legacy-candidate-ab.py
         tools/release/write-platform-row.do tools/release/verify-handoff-install.do"

fail=0
checked=0
for f in $SCRIPTS; do
  [ -f "$f" ] || continue
  while read -r name; do
    [ -z "$name" ] && continue
    checked=$((checked + 1))
    if ! grep -qx -- "$name" <<<"$posted"; then
      echo "$f asserts e($name), which no ado posts" >&2
      fail=1
    fi
  done < <(grep -oE '\be\([A-Za-z_][A-Za-z0-9_]*\)' "$f" | sed 's/^e(//; s/)$//' | sort -u)
done

if [ "$checked" -eq 0 ]; then
  echo "no e() references found in the release scripts -- this gate is checking nothing" >&2
  exit 1
fi

[ "$fail" -eq 0 ] || exit 1
echo "asserted results exist: $checked e() references across the release scripts, all posted"
