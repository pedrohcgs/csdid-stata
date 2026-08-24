#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

STATA_CMD="${STATA_CMD:-stata-mp}"

run_stata_do() {
  local dofile="$1"
  "$STATA_CMD" -b do "$dofile"
  local log
  log="$(basename "$dofile" .do).log"
  if [[ -f "$log" ]]; then
    bash tools/release/check-stata-log-tail.sh "$log"
  fi
}

python3 tools/validate-contract.py
bash tools/release/lint-website.sh
for f in tests/meta/*.sh; do
  bash "$f"
done

bash tools/plugin/build-bootstrap-plugin.sh auto
run_stata_do src/build.do
# The release-critical do-files are no longer listed here one by one:
# run-smoke.sh derives its list from the tree and covers every one of them,
# so a second explicit pass ran each twice on the release path for nothing.
python3 tools/release/run-adversarial-differential.py

bash tests/run-smoke.sh
bash tests/run-jel-smoke.sh

if [[ "${CSDID_RUN_OPTIN_PERF:-0}" == "1" ]]; then
  CSDID_RUN_OPTIN_PERF=1 bash tests/run-optin-performance.sh
else
  echo "Skipping opt-in performance gate; set CSDID_RUN_OPTIN_PERF=1 to run it."
fi

if [[ "${CSDID_RUN_LEGACY_AB:-0}" == "1" ]]; then
  bash tests/run-legacy-candidate-ab.sh
else
  echo "Skipping legacy-to-candidate A/B gate; set CSDID_RUN_LEGACY_AB=1 to run it."
fi

if [[ "${CSDID_RUN_JEL_FULL:-0}" == "1" ]]; then
  CSDID_RUN_JEL_FULL=1 bash tests/run-jel-full-reproduction.sh
else
  echo "Skipping full JEL gate; set CSDID_RUN_JEL_FULL=1 to run it."
fi

git diff --check
