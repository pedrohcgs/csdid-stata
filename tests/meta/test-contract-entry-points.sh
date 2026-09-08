#!/usr/bin/env bash
# Public test entry points must run without a schema tool excluded from their
# distribution. A missing required checker or a failed check still refuses.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path.cwd()
runners = ["tests/run-smoke.sh", "tests/run-jel-smoke.sh",
           "tests/run-jel-full-reproduction.sh", "tools/release/run-local-release-gates.sh"]
checks = 0
with tempfile.TemporaryDirectory(prefix="csdid-contract-entry-") as scratch:
    work = Path(scratch)
    for rel in [*runners, "tools/release/check-contract.sh"]:
        target = work / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / rel, target)
    for rel, content in {
        "bin/Rscript": '#!/usr/bin/env bash\necho DOWNSTREAM-REACHED\nexit 23\n',
        "tools/plugin/build-bootstrap-plugin.sh": '#!/usr/bin/env bash\nexit 0\n',
        "tools/release/lint-website.sh": '#!/usr/bin/env bash\necho DOWNSTREAM-REACHED\nexit 23\n',
        "tools/jel/run-full-reproduction.py": 'print("DOWNSTREAM-REACHED")\nraise SystemExit(23)\n',
    }.items():
        target = work / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        target.chmod(0o755)
    checker = work / "tools/validate-contract.py"
    builder = work / "tools/release/build-release-payload.sh"
    env = dict(os.environ, PATH=str(work / "bin") + os.pathsep + os.environ["PATH"],
               CSDID_RUN_JEL_FULL="1")
    for mode in ("public", "missing-required", "pass", "fail"):
        checker.unlink(missing_ok=True)
        builder.unlink(missing_ok=True)
        if mode != "public":
            builder.write_text("# schema required in this source layout\n")
        if mode in ("pass", "fail"):
            checker.write_text('print("SCHEMA-RAN")\nraise SystemExit(' +
                               ("9" if mode == "fail" else "0") + ')\n')
        for runner in runners:
            proc = subprocess.run(["bash", str(work / runner)], cwd=work, env=env,
                                  capture_output=True, text=True)
            expected = 1 if mode == "missing-required" else 9 if mode == "fail" else 23
            reached = "DOWNSTREAM-REACHED" in proc.stdout
            if proc.returncode != expected or reached != (mode in ("public", "pass")):
                raise SystemExit(f"{runner} mishandled {mode}: rc={proc.returncode}\n"
                                 f"{proc.stdout}{proc.stderr}")
            if mode in ("pass", "fail") and "SCHEMA-RAN" not in proc.stdout:
                raise SystemExit(f"{runner} did not execute its present schema checker")
            checks += 1
print(f"contract entry points: {checks} distribution/refusal cases pass")
PY
