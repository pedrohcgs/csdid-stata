#!/usr/bin/env bash
# The R oracle environment must be the one the committed expectations were
# generated against.
#
# Every expected/r/*.csv in this repository is a frozen output of a specific R
# package version. If someone upgrades `did` or `DRDID`, those files silently
# stop describing what R does now: the Stata tests keep passing against a stale
# oracle, and a real divergence introduced by the upgrade is invisible. Nothing
# previously checked this.
#
# This is a cheap environment gate, not a regeneration. Regenerating fixtures is
# a deliberate, reviewed act, partly because
# some generators overwrite committed inputs as a side effect.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript is not on PATH; the R oracle cannot be verified" >&2
  exit 1
fi

# Authenticate the same loaded package and explicit checkout as every
# generator. An installed package's version cannot authenticate another tree.
Rscript --vanilla tools/parity/test-oracle-authentication.R || exit $?
Rscript --vanilla tools/parity/test-differential-design-capture.R "$ROOT" || exit $?

# The oracles must also actually be present; an empty expected/r/ tree would let
# the certification suite pass while comparing against nothing.
count=$(find tests/fixtures -path '*/expected/r/*' -name '*.csv' | wc -l | tr -d ' ')
if [ "$count" -lt 1 ]; then
  echo "no expected/r/*.csv oracles found; the parity suite would compare against nothing" >&2
  exit 1
fi

echo "R oracle environment OK ($count frozen oracle files)"
