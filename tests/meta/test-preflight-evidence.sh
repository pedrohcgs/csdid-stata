#!/usr/bin/env bash
# Receipt lifecycle and A/B attribution without numerical or timing jobs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

root = Path.cwd()
# These files affect examples, build output, static gates or input discovery.
# None belongs to the estimator's production digest.
with tempfile.TemporaryDirectory(prefix="csdid-readme-digest-") as temporary:
    work = Path(temporary)
    (work / "tools/release").mkdir(parents=True)
    (work / "src").mkdir()
    (work / "src/payload.txt").write_text("fixed production\n")
    digest = work / "tools/release/preflight-digest.sh"
    shutil.copy2(root / "tools/release/preflight-digest.sh", digest)
    def digest_value(*args):
        return subprocess.check_output(["bash", str(digest), *args], cwd=work, text=True).strip()
    for relative in ("README.md", "packaging/README.md", "examples/demo.do",
                     "LICENSE", "PROVENANCE.md", ".github/workflows/static-release-gates.yml",
                     ".gitignore"):
        document = work / relative
        document.parent.mkdir(parents=True, exist_ok=True)
        document.write_text("```stata\ndisplay 1\n```\n")
        before = digest_value()
        production = digest_value("--production")
        document.write_text("```stata\nassert 0\n```\n")
        assert digest_value() != before, f"{relative} changes tested inputs but not the receipt digest"
        assert digest_value("--production") == production, f"{relative} changed the production digest"
print("Input digests: 7 consumed documentation/build/discovery inputs invalidate receipts only")

spec = importlib.util.spec_from_file_location("evidence", root / "tools/release/preflight-evidence.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = (root / "tools/release/preflight.sh").read_text()
# Keep the real receipt, probe, reuse and verdict code. Only numerical/static
# gate bodies and executable availability are stubbed in this isolated copy.
source, count = re.subn(r'^have\(\) \{.*?\}$', 'have() { return 0; }', source, flags=re.M)
assert count == 1
needle = 'if "$@" >"$log" 2>&1; then'
assert source.count(needle) == 1
source = source.replace(needle, 'if test_gate "$name" >"$log" 2>&1; then')
source = source.replace('# run <tier>', '''test_gate() {
  if [ "${CSDID_PREFLIGHT_FAKE_MODE:-}" = "interrupted" ]; then exit 130; fi
  [ "${CSDID_PREFLIGHT_FAKE_MODE:-}" != "gate-failure" ]
}
# run <tier>''', 1)
fake_stata = '''#!/usr/bin/env python3
import os
from pathlib import Path
import re
import sys
root = Path.cwd()
counter = root / "probe-count"
n = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(n))
mode = os.environ.get("CSDID_PREFLIGHT_FAKE_MODE", "complete")
driver = Path(sys.argv[3])
match = re.search(r'file open ph using "([^"\\n]+)"', driver.read_text())
output = Path(sys.argv[4]) if len(sys.argv) > 4 else Path(match[1])
version = os.environ.get("CSDID_PREFLIGHT_FAKE_VERSION", "17")
if mode == "changed-runtime" and n == 2: version = "19.5"
identity = "stata_version=" + version + "\\nedition=MP\\nos=MacOSX\\nmachine_type=Mac Apple Silicon\\n"
if mode == "incomplete-identity": identity = identity.replace("edition=MP\\n", "")
if mode == "duplicate-identity": identity += "edition=SE\\n"
if mode == "empty-identity": identity = ""
if mode == "invalid-identity": identity = identity.replace("stata_version=" + version, "stata_version=pending")
if mode != "missing-identity": output.write_text(identity)
if mode == "changed-binary" and n == 2:
    path = Path(__file__); path.write_text(path.read_text() + "# changed\\n")
if mode == "changed-inputs" and n == 2:
    path = root / "tools/bench/legacy-candidate-ab-workload.do"
    path.write_text(path.read_text() + "* changed\\n")
if mode == "changed-production" and n == 2:
    (root / "src/payload.txt").write_text("changed\\n")
if mode != "missing-log":
    log = ". file close ph\\n"
    if mode == "error-log": log += "r(9);\\n"
    if mode != "partial-log" and not (mode == "partial-final" and n == 2):
        log += "end of do-file\\n"
    (root / (driver.stem + ".log")).write_text(log)
if mode == "nonzero": sys.exit(42)
'''

checks = 0
with tempfile.TemporaryDirectory(prefix="csdid-preflight-evidence-") as temporary:
    base = Path(temporary)
    def tree(name):
        work = base / name
        work.mkdir()
        paths = set(module.AB_FILES) | {"tools/release/preflight-digest.sh"}
        for relative in paths:
            destination = work / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / relative, destination)
        (work / "tools/release/preflight.sh").write_text(source)
        for relative in ("tests/stata/test-bootstrap-plugin.do", "tests/stata/test-f049.do",
                         "tests/stata/test-unit.do", "src/payload.txt", "legacy/codes/csdid.ado"):
            path = work / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
        for relative in ("site/.git", "did", "jel", "bin", "tests/meta"):
            (work / relative).mkdir(parents=True, exist_ok=True)
        stata = work / "bin/stata-stub"
        stata.write_text(fake_stata)
        stata.chmod(0o755)
        git = work / "bin/git"
        git.write_text('''#!/usr/bin/env bash
case "$*" in
  *status*) [ "${CSDID_PREFLIGHT_FAKE_MODE:-}" != "dirty-legacy" ] || echo ' M codes/csdid.ado' ;;
  *) if [ "${CSDID_PREFLIGHT_FAKE_MODE:-}" = "wrong-legacy" ]; then
       echo 1111111111111111111111111111111111111111
     else echo fdbae25521a941314af8d84ec0c93fb0596daa8e; fi ;;
esac
''')
        git.chmod(0o755)
        return work

    def run(work, mode="complete", args=(), version="17", stata=None):
        (work / "probe-count").unlink(missing_ok=True)
        env = dict(os.environ, PATH=str(work / "bin") + os.pathsep + os.environ["PATH"],
                   STATA_CMD=str(stata or work / "bin/stata-stub"),
                   PREFLIGHT_LOGDIR=str(work / "logs"), CSDID_SITE_ROOT=str(work / "site"),
                   CSDID_DID_UPSTREAM=str(work / "did"), JEL_DID_REFERENCE=str(work / "jel"),
                   CSDID_LEGACY_ROOT=str(work / "legacy"), PREFLIGHT_SKIP_DEEP="0",
                   CSDID_PREFLIGHT_FAKE_MODE=mode, CSDID_PREFLIGHT_FAKE_VERSION=version)
        return subprocess.run(["bash", "tools/release/preflight.sh", *args], cwd=work,
                              env=env, capture_output=True, text=True)

    def require(work, mode="complete", args=(), expected=True, **kwargs):
        global checks
        result = run(work, mode, args, **kwargs)
        assert (result.returncode == 0) == expected, (mode, args, result.returncode, result.stdout, result.stderr)
        checks += 1
        return result

    clean = tree("clean")
    require(clean)
    receipt = clean / "logs/receipt.json"
    record = json.loads(receipt.read_text())
    assert record["ab_unchanged"] == 0 and record["ab_runtime"]["stata_version"] == "17"
    original = receipt.read_bytes()
    require(clean)
    assert json.loads(receipt.read_text())["ab_unchanged"] == 1
    assert original in [path.read_bytes() for path in (clean / "logs/receipts").iterdir()]
    for args in (("--fast",), ("--list",)):
        previous = receipt.read_bytes()
        archives = sorted((clean / "logs/receipts").iterdir())
        require(clean, args=args)
        assert receipt.read_bytes() == previous
        assert sorted((clean / "logs/receipts").iterdir()) == archives
        assert not (clean / "probe-count").exists()
    for args in (("--release",), ("--ab",)):
        require(clean, args=args)
        assert json.loads(receipt.read_text())["ab_unchanged"] == 0

    for mode in ("partial-log", "partial-final", "error-log", "missing-log", "nonzero",
                 "missing-identity", "empty-identity", "incomplete-identity", "duplicate-identity",
                 "invalid-identity", "changed-runtime", "changed-binary", "changed-inputs",
                 "changed-production", "dirty-legacy", "wrong-legacy", "gate-failure", "interrupted"):
        work = tree(mode)
        require(work)
        receipt = work / "logs/receipt.json"
        previous = receipt.read_bytes()
        # An older complete log must not vouch for a failed fresh probe.
        (work / "_preflight-platform.log").write_text("end of do-file\n")
        require(work, mode=mode, expected=False)
        assert not receipt.exists(), mode + " left a current receipt"
        assert previous in [path.read_bytes() for path in (work / "logs/receipts").iterdir()]
        if mode in ("gate-failure", "interrupted"):
            require(work)
            assert json.loads(receipt.read_text())["ab_unchanged"] == 1

    mutations = ["missing-runtime", "missing-inputs", "failed-receipt", "blocked-receipt",
                 "fast-receipt", "runtime-version", "runtime-executable", "runtime-host",
                 "runtime-system", "binary", "legacy-path", "production", *module.AB_FILES]
    bad_counters = {f"counter-{field}-{label}": (field, value)
                    for field in ("fail", "blocked")
                    for label, value in (("boolean", False), ("float", 0.0),
                                         ("string", "0"), ("null", None))}
    mutations.extend(bad_counters)
    for mutation in mutations:
        work = tree("reuse-" + mutation.replace("/", "_"))
        require(work)
        receipt = work / "logs/receipt.json"
        record = json.loads(receipt.read_text())
        version = "17"
        if mutation == "missing-runtime": del record["ab_runtime"]
        elif mutation == "missing-inputs": del record["ab_inputs"]
        elif mutation == "failed-receipt": record["fail"] = 1
        elif mutation == "blocked-receipt": record["blocked"] = 1
        elif mutation == "fast-receipt": record["mode"] = "fast"
        elif mutation in bad_counters:
            field, value = bad_counters[mutation]
            record[field] = value
        elif mutation == "runtime-version": version = "19.5"
        elif mutation.startswith("runtime-"): record["ab_runtime"][mutation.removeprefix("runtime-")] = "different"
        elif mutation == "legacy-path": record["ab_inputs"]["legacy_root"] = "different"
        elif mutation == "binary":
            path = work / "bin/stata-stub"; path.write_text(path.read_text() + "# different\n")
        elif mutation == "production": (work / "src/payload.txt").write_text("different\n")
        else:
            path = work / mutation
            path.write_text(path.read_text() + "\n# different instrumentation\n")
        receipt.write_text(json.dumps(record))
        require(work, version=version)
        assert json.loads(receipt.read_text())["ab_unchanged"] == 0, mutation
print(f"Preflight evidence: {checks} lightweight receipt/probe/attribution cases passed")
PY
