#!/usr/bin/env bash
set -euo pipefail

# The shipped help must read stand-alone and say only true things.
#
# The greps below must RECURSE. `grep PATTERN src/help' without -r hits a
# directory, errors, returns non-zero, and the `if' never fires: the check then
# inspects no help file at all and reports success for it.
#
# What these greps can prove is narrow -- fifteen lines of patterns over six
# words. Text that reads as a reference to another package, as development
# history, or as a factual claim inverted to its opposite passes them all.
# check-help-surface.py is what guards the rest of the surface.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if grep -rnE 'F0[0-9][0-9]|fixture|frozen conformance|repository|partially supported|verified' src/help; then
    echo "Public help files must stay user-facing; move fixture and contract details to docs/." >&2
    exit 1
fi

if grep -rnE '28jun2026|22jun2026' src/help src/ado; then
    echo "Stale public ado/help header date found." >&2
    exit 1
fi

exec python3 tools/release/check-help-surface.py
