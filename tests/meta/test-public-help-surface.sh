#!/usr/bin/env bash
set -euo pipefail

# NOTE: this was missing -r, so `grep PATTERN src/help` hit a directory,
# errored, returned non-zero, and the `if` never fired. The check had never
# inspected a single help file. Recurse explicitly.
if grep -rnE 'F0[0-9][0-9]|fixture|frozen conformance|repository|partially supported|verified' src/help; then
    echo "Public help files must stay user-facing; move fixture and contract details to docs/." >&2
    exit 1
fi

if grep -rnE '28jun2026|22jun2026' src/help src/ado; then
    echo "Stale public ado/help header date found." >&2
    exit 1
fi
