#!/usr/bin/env bash
# Static entry coverage needs no R installation. The parity environment gate
# executes the companion R test for loaded-code and tracing behavior.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PYCODE'
from pathlib import Path
import re

files = sorted(Path("tools/parity/generators").glob("*/generate.R"))
if len(files) < 100:
    raise SystemExit("too few R generators: refusing an incomplete scan")
entry = re.compile(r'^source\((?:file\.path\(dirname\(script_path\), "\.\./oracle-check\.R"\)|"tools/parity/generators/oracle-check\.R")\)\s*$', re.M)
work = re.compile(r'\b(?:read\.csv|write\.csv|readRDS|saveRDS|system2|dir\.create|write_json|att_gt|aggte)\s*\(|library\(\s*(?:did|DRDID)\s*\)')
for path in files:
    source = "\n".join(line for line in path.read_text().splitlines()
                       if not line.lstrip().startswith("#"))
    match = entry.search(source)
    if match is None:
        raise SystemExit(f"{path} has no executable oracle authentication entry")
    if work.search(source[:match.start()]):
        raise SystemExit(f"{path} works with fixtures or its oracle before authentication")
runtime = Path("tools/parity/test-oracle-authentication.R")
if not runtime.is_file():
    raise SystemExit("runtime oracle authentication check is missing")
child_check = Path("tools/parity/test-generator-child-status.R")
if not child_check.is_file() or 'source("tools/parity/test-generator-child-status.R")' not in runtime.read_text():
    raise SystemExit("runtime generator child-status qualification is missing")
runner = Path("tools/release/check-r-oracles.sh").read_text()
if "Rscript --vanilla tools/parity/test-oracle-authentication.R || exit $?" not in runner:
    raise SystemExit("the parity environment gate does not require the runtime authentication check")
for name, length in (("r-oracle-code-digest.txt", 16), ("r-oracle-full-code-digest.txt", 64)):
    path = Path("inst/spec") / name
    if not path.is_file() or re.fullmatch(rf"[0-9a-f]{{{length}}}", path.read_text().strip()) is None:
        raise SystemExit(f"missing or malformed oracle fingerprint: {path}")
print(f"Oracle authentication: {len(files)} static entries checked; loaded-code checks run in the parity tier")
PYCODE
