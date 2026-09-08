#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
if [[ ! -f "$ROOT/csdid.pkg" && -f "$ROOT/../csdid.pkg" ]]; then
  ROOT="$(cd "$ROOT/.." && pwd)"
fi
if [[ ! -f "$ROOT/csdid.pkg" ]]; then
  echo "cannot find csdid.pkg above $HERE; run from a complete checkout or extracted bundle" >&2
  exit 1
fi
cd "$ROOT"

SMOKE="$HERE/install-and-smoke.do"
if [ ! -f "$SMOKE" ]; then
  echo "cannot find install-and-smoke.do beside $0" >&2
  exit 1
fi
CHECKER="$HERE/check-stata-log-tail.sh"
if [[ ! -f "$CHECKER" ]]; then
  CHECKER="$ROOT/tools/release/check-stata-log-tail.sh"
fi
if [[ ! -f "$CHECKER" ]]; then
  echo "cannot find the Stata log validator; restore the complete checkout or bundle" >&2
  exit 1
fi

STATA_CMD="${STATA_CMD:-stata-mp}"
# A stale successful batch log must not certify a launch that writes nothing.
LOG="$ROOT/install-and-smoke.log"
if [[ -e "$LOG" ]]; then
  ARCHIVE="$(mktemp -d "${TMPDIR:-/tmp}/csdid-install-log.XXXXXX")"
  mv "$LOG" "$ARCHIVE/install-and-smoke.log" || exit $?
fi
"$STATA_CMD" -b do "$SMOKE" || exit $?
bash "$CHECKER" "$LOG" || exit $?

echo "install smoke validation passed"
