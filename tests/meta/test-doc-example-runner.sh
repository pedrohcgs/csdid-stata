#!/usr/bin/env bash
# A documentation example passes only after its complete batch run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path.cwd()
checks = 0
with tempfile.TemporaryDirectory(prefix="csdid-doc-runner-") as scratch:
    work = Path(scratch)
    (work / "tools/docs").mkdir(parents=True)
    (work / "packaging").mkdir()
    (work / "website").mkdir()
    checker = work / "tools/docs/check-doc-examples.py"
    shutil.copy2(root / "tools/docs/check-doc-examples.py", checker)
    document = work / "packaging/README.md"
    document.write_text("# Example\n\n```stata\nassert 1\n```\n")
    fake = work / "stata-stub"
    fake.write_text(f"#!{sys.executable}\n" + '''
import os
from pathlib import Path
import sys
import time
mode = os.environ["CSDID_TEST_MODE"]
required = os.environ.get("CSDID_EXPECT_DOC_SNIPPET", "")
if required and required not in Path("doc_example.do").read_text():
    sys.exit(43)
logs = {
    "complete": ". assert 1\\n\\nend of do-file\\n",
    "prompt": "end of do-file\\n. \\n\\n",
    "captured": ". capture noisily assert 0\\nassertion is false\\nend of do-file\\n",
    "empty": "",
    "truncated": ". assert 1\\n",
    "inner": "end of do-file\\n. do another.do\\n",
    "error": "r(9);\\n" + "more output\\n" * 30 + "end of do-file\\n",
    "nonzero": "end of do-file\\n",
}
if mode == "timeout":
    time.sleep(5)
if mode in logs:
    Path("doc_example.log").write_text(logs[mode])
if mode == "nonzero":
    sys.exit(42)
''')
    fake.chmod(0o755)

    def check(mode, expected, diagnostic, *args, required_snippet=""):
        global checks
        result = subprocess.run(
            [sys.executable, str(checker), "--stata", str(fake), *args],
            env=dict(os.environ, CSDID_TEST_MODE=mode,
                     CSDID_EXPECT_DOC_SNIPPET=required_snippet),
            capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        if (result.returncode == 0) != expected or diagnostic not in output:
            raise SystemExit(f"documentation runner misclassified {mode}: "
                             f"rc={result.returncode}\n{output}")
        checks += 1
        return output

    for mode in ("complete", "prompt", "captured"):
        check(mode, True, "1 document(s) passed")
    for mode in ("empty", "truncated", "inner"):
        check(mode, False, "incomplete Stata batch log")
    check("error", False, "r(9);")
    check("nonzero", False, "Stata process exited 42")
    check("missing", False, "no log produced")
    check("timeout", False, "Stata exceeded", "--timeout", "0.05")
    check("complete", False, "no documents match", "--only", "absent-page")
    for value in ("0", "-1", "nan", "inf"):
        check("complete", False, "--timeout must be a positive finite", "--timeout", value)

    document.write_text("# No runnable blocks\n")
    check("complete", False, "no runnable documentation blocks")
    document.write_text("<!-- norun -->\n```stata\nassert 1\n```\n")
    output = check("complete", False, "no runnable documentation blocks")
    if "1 norun block(s), unverified" not in output:
        raise SystemExit("skipped-only document is not explicitly unverified")
    document.write_text("<!-- norun -->\n```stata\nassert 0\n```\n"
                        "\n```stata\nassert 1\n```\n")
    check("complete", True, "1 norun block(s) remain unverified")
    document.unlink()
    check("complete", False, "cannot read document")

    # The development README is editorial; the public root README contains
    # the runnable package guide after packaging/ is removed by the builder.
    public_readme = work / "README.md"
    public_readme.write_text("# Package guide\n\n```stata\nassert 99\n```\n")
    document.write_text("# Development package guide\n\n```stata\nassert 17\n```\n")
    check("complete", True, "PASS    packaging/README.md", required_snippet="assert 17")
    check("complete", True, "1 document(s) passed", "--only", "README.md",
          required_snippet="assert 17")
    document.unlink()
    check("complete", False, "FAIL    packaging/README.md")
    document.parent.rmdir()
    check("complete", True, "PASS    README.md", required_snippet="assert 99")
    check("complete", True, "1 document(s) passed", "--only", "README.md",
          required_snippet="assert 99")
    check("complete", False, "no documents match", "--only", "packaging/README.md")
    guide = work / "website/guide.md"
    guide.write_text("# Website guide\n\n```stata\nassert 99\n```\n")
    check("complete", True, "2 document(s) passed", required_snippet="assert 99")
    public_readme.unlink()
    check("complete", False, "FAIL    README.md")
    public_readme.write_text("# Package guide\n\n```stata\nassert 99\n```\n")
    guide.unlink()
    guide.mkdir()
    check("complete", False, "FAIL    website/guide.md")

print(f"documentation runner completion: {checks} seeded cases pass")
PY
