#!/usr/bin/env bash
set -euo pipefail

# Resolve both paths BEFORE changing directory: a relative dirname does not
# survive the cd, which is how the first version of this fix broke.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

# The do-file sits beside this script. In the release bundle that directory is
# named validation-tests/; in the development tree it is tests/installation/.
# Resolve it from this script's own location so the runner works in both, and
# say which layout it found rather than failing on a path that is correct in
# the other one.
SMOKE="$HERE/install-and-smoke.do"
if [ ! -f "$SMOKE" ]; then
  echo "cannot find install-and-smoke.do beside $0" >&2
  exit 1
fi

STATA_CMD="${STATA_CMD:-stata-mp}"
"$STATA_CMD" -b do "$SMOKE"

echo "install smoke validation passed"

