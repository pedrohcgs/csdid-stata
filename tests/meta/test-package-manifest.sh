#!/usr/bin/env bash
# Guards the package manifest against the failure that made csdid uninstallable:
# csdid.pkg named eleven files under build/, .gitignore excluded build/, so every
# path the manifest promised was untracked and
#   net install csdid, from("<repo raw url>")
# -- the only install route a public audience has -- returned 404 on every file,
# on every branch and every tag. A local `net install` from a working tree still
# succeeded, because the ignored files were present on that one machine, so no
# existing test could see the problem.
#
# Each path in the manifest must therefore be BOTH present on disk AND tracked by
# git. "Tracked" is the part that matters: it is what a stranger cloning the
# repository actually gets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

status=0

if [[ ! -f csdid.pkg ]]; then
  echo "csdid.pkg not found at the repository root" >&2
  exit 1
fi

paths="$(awk '$1 == "f" { print $2 }' csdid.pkg)"
if [[ -z "$paths" ]]; then
  echo "csdid.pkg declares no files" >&2
  exit 1
fi

for f in $paths; do
  if [[ ! -f "$f" ]]; then
    echo "manifest names a file that does not exist: $f (run: stata -b do src/build.do)" >&2
    status=1
    continue
  fi
  if git check-ignore -q "$f" 2>/dev/null; then
    echo "manifest names a GITIGNORED file: $f -- net install would 404 for every user" >&2
    status=1
    continue
  fi
  if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    echo "manifest names an UNTRACKED file: $f -- commit it, or net install will 404 for every user" >&2
    status=1
  fi
done

# Metadata that Stata itself consumes. Distribution-Date is what `adoupdate`
# compares to decide whether an installed copy is stale; without it a user who
# installed an older build can never be told a bugfix exists.
for required in "Distribution-Date:" "Requires: Stata version"; do
  if ! grep -qE "^d .*${required}" csdid.pkg; then
    echo "csdid.pkg is missing a '${required}' line" >&2
    status=1
  fi
done

if [[ "$status" -eq 0 ]]; then
  echo "package manifest ok: $(echo "$paths" | wc -w | tr -d ' ') files, all present and tracked"
fi
exit "$status"
