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
# a deliberate, reviewed act -- see docs/merge-protocol.md -- partly because
# some generators overwrite committed inputs as a side effect.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Pinned versions. Changing these means every expected/r/ artifact must be
# regenerated and re-reviewed, and the divergence registry revisited.
PIN_DID="2.5.1"
PIN_DRDID="1.3.0"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript is not on PATH; the R oracle cannot be verified" >&2
  exit 1
fi

read -r GOT_DID GOT_DRDID <<<"$(Rscript -e '
  v <- function(p) tryCatch(as.character(packageVersion(p)), error = function(e) "MISSING")
  cat(v("did"), v("DRDID"))
' 2>/dev/null)"

status=0
if [ "$GOT_DID" != "$PIN_DID" ]; then
  echo "R package 'did' is $GOT_DID but the oracles were generated against $PIN_DID" >&2
  status=1
fi
if [ "$GOT_DRDID" != "$PIN_DRDID" ]; then
  echo "R package 'DRDID' is $GOT_DRDID but the oracles were generated against $PIN_DRDID" >&2
  status=1
fi

# A VERSION STRING IS NOT PROOF OF CONTENT. A locally installed did reported
# version 2.5.1 while its compute.att_gt was built without the 0.5 unit-folding
# factor that real 2.5.1 applies to the repeated-cross-section influence
# function under fix_weights = "varying". Every comparison against that build
# was against 2.5.0 behaviour wearing a 2.5.1 label, and it produced a
# convincing but entirely spurious 2x divergence. So assert a CONTENT
# fingerprint of the loaded code, not just its declared version.
FINGERPRINT=$(Rscript -e '
  src <- deparse(did:::compute.att_gt)
  cat(as.integer(any(grepl("0.5 * (n/n1)", src, fixed = TRUE))))
' 2>/dev/null)
if [ "$FINGERPRINT" != "1" ]; then
  echo "installed did reports $GOT_DID but its compute.att_gt lacks the 0.5" >&2
  echo "unit-folding factor that 2.5.1 applies under fix_weights = \"varying\"." >&2
  echo "This is a STALE BUILD wearing a current version label. Reinstall:" >&2
  echo "    remotes::install_github(\"bcallaway11/did\", force = TRUE)" >&2
  status=1
fi

if [ "$status" -ne 0 ]; then
  echo "" >&2
  echo "Every expected/r/ artifact is frozen against the pinned versions. Install" >&2
  echo "them, or regenerate and re-review every oracle and the divergence registry." >&2
  exit 1
fi

# The oracles must also actually be present; an empty expected/r/ tree would let
# the certification suite pass while comparing against nothing.
count=$(find tests/fixtures -path '*/expected/r/*' -name '*.csv' | wc -l | tr -d ' ')
if [ "$count" -lt 1 ]; then
  echo "no expected/r/*.csv oracles found; the parity suite would compare against nothing" >&2
  exit 1
fi

echo "R oracle environment OK (did $GOT_DID, DRDID $GOT_DRDID, $count frozen oracle files)"
