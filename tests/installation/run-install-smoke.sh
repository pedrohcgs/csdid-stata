#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STATA_CMD="${STATA_CMD:-stata-mp}"
"$STATA_CMD" -b do validation-tests/install-and-smoke.do

echo "install smoke validation passed"

