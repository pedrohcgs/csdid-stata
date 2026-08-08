#!/usr/bin/env bash
set -euo pipefail

# The code appendix opens by promising that every number in the comparison
# article comes from one of the scripts reproduced on that page. That promise
# holds only while the two copies agree, and a fenced code block gives no sign
# that the script it shows has moved on.
#
# When this was first run, two blocks had drifted: the benchmark had gained
# Stata's native xthdidregress and hdidregress columns and the published copies
# had not. Twenty-three more scripts existed ONLY inside the markdown page,
# where nothing can run or diff them.
#
# The file in the tree is what runs, so the file wins.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/tools/release/sync-code-appendix.py"
