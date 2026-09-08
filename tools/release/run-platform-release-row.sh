#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

STATA_CMD="${STATA_CMD:-stata-mp}"
OUTFILE="${1:-reports/platform-matrix-local.csv}"
logfile="csdid-platform-probe.log"
ARCHIVE="$(mktemp -d "${TMPDIR:-/tmp}/csdid-platform-row.XXXXXX")"
if [[ -e "$logfile" ]]; then mv "$logfile" "$ARCHIVE/batch.log" || exit $?; fi
if [[ -e "$OUTFILE" ]]; then mv "$OUTFILE" "$ARCHIVE/platform.csv" || exit $?; fi

: "${CSDID_RUN_OPTIN_PERF:=1}"
: "${CSDID_RUN_JEL_FULL:=1}"
: "${CSDID_RUN_LEGACY_AB:=1}"
export CSDID_RUN_OPTIN_PERF CSDID_RUN_JEL_FULL CSDID_RUN_LEGACY_AB
for flag in CSDID_RUN_OPTIN_PERF CSDID_RUN_JEL_FULL CSDID_RUN_LEGACY_AB; do
  if [[ "${!flag}" != "1" ]]; then
    echo "platform certification requires $flag=1; use run-local-release-gates.sh for a partial run" >&2
    exit 1
  fi
done

# Generated binaries can differ by platform; the source and checks must belong
# to the named commit. Recheck after the suite so edits cannot inherit its pass.
INPUTS=(src inst/spec tests tools docs website packaging examples README.md NEWS.md LICENSE PROVENANCE.md .github .gitignore csdid.pkg stata.toc ':!src/ado/*.plugin')
check_inputs() {
  git diff --quiet HEAD -- "${INPUTS[@]}" || {
    echo "commit the release source and checks before platform certification" >&2
    return 1
  }
  if [[ -n "$(git ls-files --others --exclude-standard -- "${INPUTS[@]}")" ]]; then
    echo "untracked release inputs cannot be attributed to a repository commit" >&2
    return 1
  fi
}
check_inputs
REPOSITORY_COMMIT="$(git rev-parse HEAD)"

bash tools/release/run-local-release-gates.sh
check_inputs
if [[ "$(git rev-parse HEAD)" != "$REPOSITORY_COMMIT" ]]; then
  echo "repository commit changed during the release gates; no platform row is certified" >&2
  exit 1
fi
PRODUCTION_DIGEST="$(bash tools/release/preflight-digest.sh --production)"
# Stata derives the batch log name from its command-line arguments. Put the
# writer's arguments inside a driver so the CLI has only one do-file name.
python3 - "$ARCHIVE/csdid-platform-probe.do" "$ROOT" "$ARCHIVE/candidate.csv" "$REPOSITORY_COMMIT" "$PRODUCTION_DIGEST" <<'PY'
from pathlib import Path
import sys
driver, root, output, commit, digest = sys.argv[1:]
if any(any(c in part for c in '\"\r\n') for part in (root, output)):
    raise SystemExit("platform probe paths cannot contain quotes or line breaks")
Path(driver).write_text(f'version 15\ndo "{root}/tools/release/write-platform-row.do" "{output}" pass "{commit}" "{digest}"\n')
PY
"$STATA_CMD" -b do "$ARCHIVE/csdid-platform-probe.do"
bash tools/release/check-stata-log-tail.sh "$logfile"
python3 - "$ARCHIVE/candidate.csv" "$REPOSITORY_COMMIT" "$PRODUCTION_DIGEST" <<'PY'
import csv, sys
from pathlib import Path
path = Path(sys.argv[1])
with path.open(newline="") as fh:
    reader = csv.DictReader(fh)
    rows = list(reader)
columns = ["date", "stata_version", "edition", "os", "machine_type", "byteorder",
           "release_gates_status", "repository_commit", "production_digest"]
if reader.fieldnames != columns or len(rows) != 1 or None in rows[0] or any(not value for value in rows[0].values()):
    raise SystemExit("platform probe must write one complete row")
row = rows[0]
if (row.get("release_gates_status"), row.get("repository_commit"), row.get("production_digest")) != ("pass", *sys.argv[2:]):
    raise SystemExit("platform probe does not identify the tested release")
PY
check_inputs
if [[ "$(git rev-parse HEAD)" != "$REPOSITORY_COMMIT" || \
      "$(bash tools/release/preflight-digest.sh --production)" != "$PRODUCTION_DIGEST" ]]; then
  echo "release identity changed during the platform probe; no row is certified" >&2
  exit 1
fi
mv "$ARCHIVE/candidate.csv" "$OUTFILE"

echo "platform release row written to $OUTFILE"
