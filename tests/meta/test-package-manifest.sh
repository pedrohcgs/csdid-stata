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

# And the reverse direction: a file built into pkg/ that no `f' line names is
# committed, looks shipped, and is delivered to nobody. The plugin was outside
# the build for exactly this reason and it took a stale binary in production to
# notice, so the manifest and the directory are now compared both ways.
for f in pkg/*; do
  [[ -e "$f" ]] || continue
  if ! grep -qxF "f $f" csdid.pkg; then
    echo "pkg/ carries $f, which no 'f' line in csdid.pkg delivers -- add it, or stop building it" >&2
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

# Existing is not enough: the date has to be at least as new as the payload it
# describes. `adoupdate' compares this line and nothing else, so a date left
# behind while pkg/ moves is not a cosmetic staleness -- it is every installed
# copy being told it is current. It sat at 20260730 through twenty-five
# further commits to pkg/, one of them a bootstrap crash fix, and every gate
# was green.
declared="$(sed -n 's/^d Distribution-Date: \([0-9]\{8\}\).*/\1/p' csdid.pkg | head -1)"
if [[ -z "$declared" ]]; then
  echo "csdid.pkg's Distribution-Date is not an 8-digit YYYYMMDD date" >&2
  status=1
else
  payload_date="$(git log -1 --format=%ad --date=format:%Y%m%d -- pkg csdid.pkg 2>/dev/null || true)"
  if [[ -z "$payload_date" ]]; then
    echo "no commit history for pkg/ or csdid.pkg, so the Distribution-Date cannot be checked against the payload -- refusing to report this as a pass" >&2
    status=1
  elif [[ "$declared" -lt "$payload_date" ]]; then
    echo "csdid.pkg says Distribution-Date: $declared, but the payload last moved on $payload_date" >&2
    echo "  adoupdate reads this line alone, so every installed copy would be told it is current" >&2
    echo "  fix: set it to the release date (tools/release/stamp-version.py --version rewrites it)" >&2
    status=1
  fi
fi

if [[ "$status" -eq 0 ]]; then
  echo "package manifest ok: $(echo "$paths" | wc -w | tr -d ' ') files, all present and tracked;"
  echo "  pkg/ names nothing the manifest does not deliver; Distribution-Date $declared is not older than the payload ($payload_date)"
fi
exit "$status"
