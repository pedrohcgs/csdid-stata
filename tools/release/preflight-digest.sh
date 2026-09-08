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

# Everything whose contents can change a preflight verdict. docs/, website/,
# packaging/ and NEWS.md are in scope because preflight tiers READ them:
# tests/meta/test-gate-qualification.sh reads the gate-qualification register under docs/,
# tools/docs/check-doc-examples.py executes the Stata blocks in
# packaging/README.md (README.md in the public payload) and website/**/*.md,
# test-news-help-agreement.sh reads
# NEWS.md, and the website speed gates read website/ (in-house review, gates
# lens: seeding red into any of them left the release receipt's digest
# byte-identical, so the receipt validated a tree whose gates fail).
# Examples execute in the unit tier; the builder copies LICENSE; prose checks
# read PROVENANCE.md; productization reads .github; .gitignore controls the
# platform runner's discovery of untracked inputs.
PATHS=(src inst/spec tests tools csdid.pkg stata.toc pkg docs website packaging examples README.md NEWS.md LICENSE PROVENANCE.md .github .gitignore)

# --production covers the source, install payload and manifests, including
# their bundled help. It excludes tests, fixtures, external documentation and
# tools. Unchanged production bytes cannot change an estimate; benchmark reuse
# additionally checks runtime and instrumentation in preflight-evidence.py.
# The broader PATHS can change a verdict without changing an estimate, which
# is why the two digests are separate.
if [ "${1:-}" = "--production" ]; then
  PATHS=(src pkg csdid.pkg stata.toc)
fi

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
