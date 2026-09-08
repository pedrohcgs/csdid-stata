#!/usr/bin/env bash
# A platform certificate requires fresh output from all gates on one commit.
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
checks = 0
with tempfile.TemporaryDirectory(prefix="csdid-platform-check-") as directory:
    work = Path(directory)
    (work / "tools/release").mkdir(parents=True)
    (work / "src/ado").mkdir(parents=True)
    (work / "examples").mkdir()
    (work / "examples/probe.do").write_text("* fixed example\n")
    (work / "README.md").write_text("```stata\ndisplay 1\n```\n")
    (work / "reports").mkdir()
    for name in ("run-platform-release-row.sh", "check-stata-log-tail.sh"):
        shutil.copy2(root / "tools/release" / name, work / "tools/release" / name)
    (work / ".gitignore").write_text("*.log\nreports/\n")
    extra_inputs = {"license": "LICENSE", "provenance": "PROVENANCE.md",
                    "workflow": ".github/workflows/static-release-gates.yml",
                    "ignore": ".gitignore"}
    original_inputs = {".gitignore": "*.log\nreports/\n"}
    for relative in extra_inputs.values():
        path = work / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        original_inputs.setdefault(relative, "fixed input\n")
        path.write_text(original_inputs[relative])
    (work / "src/ado/probe.ado").write_text("* fixed source\n")
    (work / "tools/release/preflight-digest.sh").write_text(
        "#!/usr/bin/env bash\nprintf '%064d\\n' 0\n")
    (work / "tools/release/run-local-release-gates.sh").write_text('''#!/usr/bin/env bash
case "$CSDID_TEST_MODE" in
  gate-failure) exit 42 ;;
  changed-source) printf '* changed\\n' >> src/ado/probe.ado ;;
  changed-readme) printf 'changed example\\n' >> README.md ;;
  input-gate-*) printf 'changed input\\n' >> "$CSDID_TEST_INPUT" ;;
  changed-commit) git -c user.name=Test -c user.email=test@example.invalid commit -qm changed --allow-empty ;;
esac
''')
    fake = work / "stata-stub"
    fake.write_text('''#!/usr/bin/env python3
import os, shlex, sys
from pathlib import Path
mode = os.environ["CSDID_TEST_MODE"]
if mode == "launch-failure": sys.exit(42)
if mode == "missing-log": sys.exit(0)
if len(sys.argv) == 4:
    args = shlex.split(Path(sys.argv[3]).read_text().splitlines()[-1])[2:]
    log = Path(Path(sys.argv[3]).stem + ".log")
else:
    args = sys.argv[4:] + ["", ""]
    log = Path(Path(args[0]).stem + ".log")
output, _, commit, digest = args
log.write_text("end of do-file\\n. do unfinished.do\\n" if mode == "truncated" else
               "r(9);\\nend of do-file\\n" if mode == "error" else "end of do-file\\n")
if mode == "missing-row": sys.exit(0)
if mode == "empty-row": Path(output).write_text(""); sys.exit(0)
if mode == "short-row":
    Path(output).write_text(f"release_gates_status,repository_commit,production_digest\\npass,{commit},{digest}\\n")
    sys.exit(0)
if mode == "wrong-identity": commit = "invalid"
Path(output).write_text("date,stata_version,edition,os,machine_type,byteorder,release_gates_status,repository_commit,production_digest\\n"
                       f"8 Sep 2026,17,MP,Unix,Macintosh (Intel 64-bit),lohi,pass,{commit},{digest}\\n")
if mode == "probe-changed-source": Path("src/ado/probe.ado").write_text("* changed\\n")
if mode == "probe-changed-readme": Path("README.md").write_text("changed example\\n")
if mode.startswith("input-probe-"): Path(os.environ["CSDID_TEST_INPUT"]).write_text("changed input\\n")
''')
    fake.chmod(0o755)
    subprocess.run(["git", "init", "-q"], cwd=work, check=True)
    subprocess.run(["git", "add", "."], cwd=work, check=True)
    subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                    "commit", "-qm", "Fixture"], cwd=work, check=True)
    input_cases = {f"input-{phase}-{label}": relative
                   for label, relative in extra_inputs.items()
                   for phase in ("dirty", "gate", "probe")}
    for mode in ("complete", "missing-log", "launch-failure", "truncated", "error",
                 "missing-row", "empty-row", "short-row", "wrong-identity", "gate-failure",
                 "changed-source", "probe-changed-source", "changed-commit",
                 "changed-readme", "probe-changed-readme", "dirty-readme",
                 "untracked-source", "dirty-source", "dirty-example", "skip-perf", "skip-jel", "skip-legacy",
                 *input_cases):
        source = work / "src/ado/probe.ado"
        source.write_text("* fixed source\n")
        example = work / "examples/probe.do"
        example.write_text("* fixed example\n")
        readme = work / "README.md"
        readme.write_text("```stata\ndisplay 1\n```\n")
        for relative, content in original_inputs.items():
            (work / relative).write_text(content)
        extra = work / "src/ado/untracked.ado"
        if extra.exists():
            extra.unlink()
        if mode == "untracked-source":
            extra.write_text("* untracked\n")
        if mode == "dirty-source":
            source.write_text("* changed\n")
        if mode == "dirty-example":
            example.write_text("* changed\n")
        if mode == "dirty-readme":
            readme.write_text("changed example\n")
        if mode.startswith("input-dirty-"):
            (work / input_cases[mode]).write_text("changed input\n")
        # The old runner accepts its correctly named but stale log as current.
        (work / "platform.log").write_text("end of do-file\n")
        (work / "csdid-platform-probe.log").write_text("end of do-file\n")
        output = work / "reports/platform.csv"
        output.write_text("release_gates_status\npass\n")
        env = dict(os.environ, STATA_CMD=str(fake), CSDID_TEST_MODE=mode,
                   CSDID_TEST_INPUT=input_cases.get(mode, ""),
                   CSDID_RUN_OPTIN_PERF="1", CSDID_RUN_JEL_FULL="1", CSDID_RUN_LEGACY_AB="1")
        disabled = {"skip-perf": "CSDID_RUN_OPTIN_PERF", "skip-jel": "CSDID_RUN_JEL_FULL",
                    "skip-legacy": "CSDID_RUN_LEGACY_AB"}
        if mode in disabled:
            env[disabled[mode]] = "0"
        result = subprocess.run(["bash", "tools/release/run-platform-release-row.sh",
                                 "reports/platform.csv"], cwd=work, env=env,
                                text=True, capture_output=True)
        if (result.returncode == 0) != (mode == "complete"):
            raise SystemExit(f"platform runner misclassified {mode}: rc={result.returncode}\n"
                             f"{result.stdout}{result.stderr}")
        if mode != "complete" and output.exists():
            raise SystemExit(f"failed {mode} left a passing platform row")
        checks += 1
print(f"platform row runner: {checks} attributed completion/refusal cases pass")
PY
