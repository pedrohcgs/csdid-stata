#!/usr/bin/env bash
# The upstream-sync tool must itself be sound, and must never run from a test.
#
# Two failure modes this guards against.
#
# First, shipping a maintenance script nobody has ever executed. This
# repository has already found four legacy ado files and four meta gates that
# were shipped or wired without ever running; a script you first invoke in
# anger, two years later, when the reference implementation has moved and you
# need it, is the same defect with a longer fuse.
#
# Second, someone wiring the mutating path into the suite. `--upgrade`
# reinstalls an R package over the network and rewrites every oracle. A test
# that mutates what it is testing is not a test, and the project's dependency
# policy is explicit that default offline tests must not install packages.
set -euo pipefail

TOOL="tools/maint/sync-upstream-did.sh"

[ -f "$TOOL" ] || { echo "$TOOL is missing" >&2; exit 1; }
[ -x "$TOOL" ] || { echo "$TOOL is not executable" >&2; exit 1; }

# It must parse.
bash -n "$TOOL" || { echo "$TOOL has a syntax error" >&2; exit 1; }

# It must reject a mode it does not understand rather than doing something.
set +e
out="$(bash "$TOOL" --nonsense-mode 2>&1)"; rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "$TOOL accepted an unknown mode instead of refusing" >&2
  exit 1
fi

# The mutating path must not be reachable from the test suite or from preflight.
if grep -rn -- "--upgrade" tests/ tools/release/preflight.sh 2>/dev/null \
     | grep -v "test-upstream-sync-tool.sh" | grep -q "sync-upstream-did"; then
  echo "sync-upstream-did.sh --upgrade is invoked from the test path; it" >&2
  echo "reinstalls packages and rewrites oracles and must stay manual." >&2
  exit 1
fi

# The pinned inventory must record which release it came from, or a later
# reader cannot tell what the oracles were generated against.
INV="inst/spec/upstream-did-tests.csv"
[ -f "$INV" ] || { echo "$INV is missing" >&2; exit 1; }
head -1 "$INV" | grep -qE '^# did [0-9]+\.[0-9]+\.[0-9]+ @ [0-9a-f]+' || {
  echo "$INV does not record the did version and commit it was pinned from" >&2
  exit 1
}

echo "upstream sync tool ok (parses, refuses unknown modes, stays out of the test path)"
