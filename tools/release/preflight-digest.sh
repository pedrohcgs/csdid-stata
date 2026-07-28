#!/usr/bin/env bash
# Print a digest of everything preflight actually exercises.
#
# A preflight receipt has to be pinned to WHAT WAS TESTED, not merely to a
# commit. Pinning to HEAD alone would accept a receipt produced before an
# uncommitted edit to the engine; requiring a globally clean tree is not usable
# here, because this repository legitimately carries unrelated work in progress.
# So the receipt records a digest over the paths preflight covers, and any edit
# to those paths invalidates it while unrelated edits do not.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Everything whose contents can change a preflight verdict.
PATHS=(src inst/spec tests tools csdid.pkg stata.toc pkg)

{
  for p in "${PATHS[@]}"; do
    [ -e "$p" ] || continue
    if [ -d "$p" ]; then
      find "$p" -type f ! -name '*.log' -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null
    else
      shasum -a 256 "$p" 2>/dev/null
    fi
  done
} | shasum -a 256 | awk '{print $1}'
