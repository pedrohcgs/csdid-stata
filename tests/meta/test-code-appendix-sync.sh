#!/usr/bin/env bash
set -euo pipefail

# The code appendix opens by promising that every number in the comparison
# article comes from one of the scripts reproduced on that page. That promise
# holds only while the two copies agree, and a fenced code block gives no sign
# that the script it shows has moved on.
#
# The drift is ordinary: the benchmark gains a column -- Stata's native
# xthdidregress and hdidregress, say -- and the published copy does not follow.
# A script that exists ONLY inside the markdown page is worse still, because
# nothing can run or diff it at all.
#
# The file in the tree is what runs, so the file wins.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/tools/release/sync-code-appendix.py"
