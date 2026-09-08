#!/usr/bin/env bash
# Recorded artifact availability must not masquerade as a completed reproduction.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import csv
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path.cwd()

# F044 is a static inventory and gate requirement, not a current-run receipt.
# These public fixtures must remain checkable without local reports or R.
f044 = root / "tests/fixtures/parity/f044"
with (f044 / "expected/contract/jel-artifact-inventory.csv").open() as stream:
    inventory_reader = csv.DictReader(stream)
    inventory = list(inventory_reader)
    inventory_fields = inventory_reader.fieldnames
with (f044 / "expected/contract/full-reproduction-evidence.csv").open() as stream:
    requirement_reader = csv.DictReader(stream)
    requirements = list(requirement_reader)
    requirement_fields = requirement_reader.fieldnames
manifest = json.loads((f044 / "metadata/manifest.json").read_text())
expected_inventory_fields = {"artifact_id", "artifact_type", "r_artifact",
    "stata_artifact", "r_exists", "stata_exists", "stata_test_file", "smoke_gate",
    "release_status", "release_blocking", "reference_root"}
expected_requirement_fields = {"artifact_id", "artifact_type", "r_artifact",
    "stata_artifact", "smoke_gate", "release_status", "evidence_report",
    "full_gate", "analysis_gate"}
full_gate = "CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh"
report = "reports/jel-full-reproduction-result.md"
if (set(inventory_fields) != expected_inventory_fields or
        len(inventory_fields) != len(expected_inventory_fields) or
        set(requirement_fields) != expected_requirement_fields or
        len(requirement_fields) != len(expected_requirement_fields)):
    raise SystemExit("F044 inventory/requirement schema differs")
ids = [f"JEL{i:03d}" for i in range(1, 19)]
if (sorted(row["artifact_id"] for row in inventory) != ids or
        sorted(row["artifact_id"] for row in requirements) != ids):
    raise SystemExit("F044 must map each of JEL001-JEL018 exactly once")
requirements = {row["artifact_id"]: row for row in requirements}
smoke = {9: "F041-table7-analytical-smoke", 11: "F042-figure2-trends-smoke",
         12: "F042-figure3-dynamic-smoke", 13: "F042-figure4-dynamic-smoke",
         14: "F043-figure5-trends-smoke", 15: "F043-figure6-dynamic-smoke",
         18: "F043-figure9-dynamic-smoke"}
for row in inventory:
    index = int(row["artifact_id"][3:])
    if index == 1:
        kind, r_path, stata_path, test = ("r-master-script",
            "scripts/R/00_master_did_jel.R", "", "test-r-master.do")
    elif index == 2:
        kind, r_path, stata_path, test = ("stata-master-script", "",
            "scripts/Stata/00_stata_master_did_jel.do", "test-stata-master.do")
    else:
        kind, number, suffix = (("table", index - 2, "tex") if index <= 9
                                else ("figure", index - 9, "pdf"))
        r_path = f"{kind}s/{kind}{number}_R.{suffix}"
        stata_path = f"{kind}s/{kind}{number}_stata.{suffix}"
        test = f"test-{kind}{number}.do"
    if (row["artifact_type"], row["r_artifact"], row["stata_artifact"],
            row["stata_test_file"], row["smoke_gate"]) != (
            kind, r_path, stata_path, "tests/stata/jel/" + test,
            smoke.get(index, "none")):
        raise SystemExit(f"F044 {row['artifact_id']}: incorrect artifact/test mapping")
    if (row["r_exists"], row["stata_exists"], row["release_blocking"],
            row["release_status"]) != ("1", "1", "1", "full-reproduction-required"):
        raise SystemExit(f"F044 {row['artifact_id']}: inventory claims a run result or missing artifact")
    requirement = requirements[row["artifact_id"]]
    if (any(requirement[key] != row[key] for key in
            expected_requirement_fields & expected_inventory_fields) or
            requirement["evidence_report"] != report or
            requirement["full_gate"] != full_gate or
            requirement["analysis_gate"] != full_gate + " --analyze-existing"):
        raise SystemExit(f"F044 {row['artifact_id']}: inconsistent full-reproduction requirement")
evidence = manifest.get("full_reproduction_evidence", {})
if (manifest.get("matrix_id") != "F044" or
        evidence.get("status") != "not-assessed" or
        evidence.get("report") != report or
        evidence.get("required_gate") != full_gate):
    raise SystemExit("F044 metadata must require full reproduction without certifying it")
with tempfile.TemporaryDirectory(prefix="csdid-jel-evidence-") as scratch:
    work = Path(scratch)
    project = work / "project"
    generator = project / "tools/parity/generators/jel/generate.py"
    generator.parent.mkdir(parents=True)
    shutil.copy2(root / "tools/parity/generators/jel/generate.py", generator)
    reference = work / "reference"
    artifacts = ["scripts/R/00_master_did_jel.R", "scripts/Stata/00_stata_master_did_jel.do"]
    artifacts += [f"tables/table{i}_{lang}.tex" for i in range(1, 8) for lang in ("R", "stata")]
    artifacts += [f"figures/figure{i}_{lang}.pdf" for i in range(1, 10) for lang in ("R", "stata")]
    for relative in artifacts:
        path = reference / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("%PDF-1.4\n" if path.suffix == ".pdf" else "1 2 3\n")
    summary = project / "build/jel-full-reproduction/outputs/summary.json"
    summary.parent.mkdir(parents=True)
    valid = dict(status="pass", oracle_parity_status="pass", failure_markers=[],
                 r_exit_code=0, stata_exit_code=0)
    cases = [
        ("missing", None, "not-run"),
        ("pass", valid, "pass"),
        ("failed", dict(valid, status="failed"), "failed"),
        ("needs-review", dict(valid, status="needs-review"), "needs-review"),
        ("running", dict(valid, status="running"), "running"),
        ("oracle-failed", dict(valid, oracle_parity_status="failed"), "inconsistent"),
        ("error-marker", dict(valid, failure_markers=["r(9);"]), "inconsistent"),
        ("r-failed", dict(valid, r_exit_code=1), "inconsistent"),
        ("stata-failed", dict(valid, stata_exit_code=1), "inconsistent"),
        ("null-exit", dict(valid, r_exit_code=None), "inconsistent"),
        ("boolean-exit", dict(valid, stata_exit_code=False), "inconsistent"),
        ("string-markers", dict(valid, failure_markers=""), "inconsistent"),
        ("empty-object", {}, "invalid"),
        ("array", [], "invalid"),
        ("claimed-not-run", dict(valid, status="not-run"), "invalid"),
        ("malformed", "{", "invalid"),
    ]
    for key in valid:
        incomplete = {k: v for k, v in valid.items() if k != key}
        cases.append((f"missing-{key}", incomplete,
                      "invalid" if key == "status" else "inconsistent"))
    generator_env = dict(os.environ, JEL_DID_REFERENCE=str(reference))
    generator_env.pop("CSDID_JEL_FIXTURE_ROOT", None)
    for name, payload, expected in cases:
        if payload is None:
            summary.unlink(missing_ok=True)
        else:
            summary.write_text(payload if isinstance(payload, str) else json.dumps(payload))
        result = subprocess.run([sys.executable, str(generator)], cwd=project,
                                env=generator_env,
                                capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(f"generator did not record {name}: {result.stdout}{result.stderr}")
        fixture = project / "tests/fixtures/jel"
        with (fixture / "expected/contract/jel-artifact-rollup.csv").open() as stream:
            rows = list(csv.DictReader(stream))
        if len(rows) != 18:
            raise SystemExit(f"{name}: expected 18 artifact records, got {len(rows)}")
        for row in rows:
            aid = row["artifact_id"]
            flag = "1" if expected == "pass" else "0"
            if row["parity_verified"] != flag:
                raise SystemExit(f"{name}: {aid} claims parity_verified={row['parity_verified']}, expected {flag}")
            artifact = fixture / aid.lower()
            with (artifact / "expected/contract/full-reproduction-evidence.csv").open() as stream:
                evidence = list(csv.DictReader(stream))
            json_evidence = json.loads((artifact / "expected/contract/full-reproduction-evidence.json").read_text())
            metadata = json.loads((artifact / "metadata/manifest.json").read_text())
            states = [evidence[0]["status"], json_evidence[0]["status"],
                      metadata["full_reproduction_evidence"]["status"]]
            if len(evidence) != 1 or len(json_evidence) != 1 or states != [expected] * 3:
                raise SystemExit(f"{name}: {aid} inconsistent evidence states: {states}")

    # Local observations cannot mutate the committed historical snapshot.
    summary.write_text(json.dumps(valid))
    subprocess.run([sys.executable, str(generator)], cwd=project,
                   env=generator_env, check=True, capture_output=True)
    frozen = {p.relative_to(fixture): p.read_bytes() for p in fixture.rglob("*") if p.is_file()}
    for state in ("not-run", "failed"):
        if state == "not-run":
            summary.unlink()
        else:
            summary.write_text(json.dumps(dict(valid, status="failed")))
        observed = project / "build" / ("observed-" + state)
        subprocess.run([sys.executable, str(generator)], cwd=project,
                       env=dict(generator_env, CSDID_JEL_FIXTURE_ROOT=str(observed)),
                       check=True, capture_output=True)
        current = {p.relative_to(fixture): p.read_bytes() for p in fixture.rglob("*") if p.is_file()}
        if current != frozen:
            raise SystemExit(f"local {state} observation rewrote the frozen JEL snapshot")
        for aid in range(1, 19):
            path = observed / f"jel{aid:03d}/expected/contract/full-reproduction-evidence.csv"
            with path.open() as stream:
                evidence = list(csv.DictReader(stream))
            if len(evidence) != 1 or evidence[0]["status"] != state:
                raise SystemExit(f"local {state}: missing or false observed status for JEL{aid:03d}")

    # Execute each real caller through its JEL generator, stopping before any
    # Stata work. Only unrelated build/schema/R prerequisites are stubbed.
    # A child process verifies that subsequent readers inherit the new path.
    binary = project / "bin"
    binary.mkdir()
    stubs = [binary / "Rscript", project / "tools/plugin/build-bootstrap-plugin.sh",
             project / "tools/release/check-contract.sh"]
    for stub in stubs:
        stub.parent.mkdir(parents=True, exist_ok=True)
        stub.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$0 $*" >> dependency-stubs.log\n')
        stub.chmod(0o755)
    boundary = "python3 tools/parity/generators/jel/generate.py\n"
    observed_roots = set()
    caller_prefixes = {}
    caller_checks = 0
    for caller in ("tests/run-smoke.sh", "tests/run-jel-smoke.sh"):
        source = (root / caller).read_text()
        if source.count(boundary) != 1:
            raise SystemExit(f"{caller}: cannot locate the unique JEL generator boundary")
        prefix = source.split(boundary, 1)[0] + boundary
        prefix += '''python3 - <<'CSDID_JEL_CALLER'
import os
from pathlib import Path
Path("caller-observed-root.txt").write_text(os.environ.get("CSDID_JEL_FIXTURE_ROOT", ""))
CSDID_JEL_CALLER
'''
        caller_prefixes[caller] = prefix
        driver = project / Path(caller).name
        driver.write_text(prefix)
        for state in ("not-run", "pass", "failed"):
            if state == "not-run":
                summary.unlink(missing_ok=True)
            else:
                summary.write_text(json.dumps(dict(valid, status=state)))
            result = subprocess.run(["bash", str(driver)], cwd=project,
                env=dict(generator_env, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                         CSDID_JEL_FIXTURE_ROOT=str(fixture)),
                capture_output=True, text=True, timeout=30)
            if result.returncode:
                raise SystemExit(f"{caller} {state}: prefix failed: {result.stdout}{result.stderr}")
            current = {p.relative_to(fixture): p.read_bytes() for p in fixture.rglob("*") if p.is_file()}
            if current != frozen:
                raise SystemExit(f"{caller} {state}: caller rewrote the frozen JEL snapshot")
            observed = Path((project / "caller-observed-root.txt").read_text()).resolve()
            if (observed.parent != (project / "build").resolve() or
                    not observed.name.startswith("jel-artifact-contract.") or
                    observed in observed_roots):
                raise SystemExit(f"{caller} {state}: readers did not inherit a fresh build observation")
            observed_roots.add(observed)
            for aid in range(1, 19):
                path = observed / f"jel{aid:03d}/expected/contract/full-reproduction-evidence.csv"
                with path.open() as stream:
                    evidence = list(csv.DictReader(stream))
                if len(evidence) != 1 or evidence[0]["status"] != state:
                    raise SystemExit(f"{caller} {state}: wrong observed status for JEL{aid:03d}")
            caller_checks += 1
    if not (project / "dependency-stubs.log").is_file():
        raise SystemExit("smoke caller prerequisites were not exercised")
    print(f"JEL smoke callers: {caller_checks} real-prefix observations preserve frozen fixtures and reader paths")
    # export VAR=$(command) masks command failure. A failed allocation must
    # stop before a blank output path makes the generator write into cwd.
    mktemp = binary / "mktemp"
    mktemp.write_text("#!/usr/bin/env bash\nexit 73\n")
    mktemp.chmod(0o755)
    for caller, prefix in caller_prefixes.items():
        driver.write_text(prefix)
        marker = project / "caller-observed-root.txt"
        marker.unlink(missing_ok=True)
        result = subprocess.run(["bash", str(driver)], cwd=project,
            env=dict(generator_env, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                     CSDID_JEL_FIXTURE_ROOT=str(fixture)),
            capture_output=True, text=True, timeout=30)
        if result.returncode != 73 or marker.exists() or (project / "expected").exists():
            raise SystemExit(f"{caller}: failed observation allocation did not stop before generation")
        current = {p.relative_to(fixture): p.read_bytes() for p in fixture.rglob("*") if p.is_file()}
        if current != frozen:
            raise SystemExit(f"{caller}: allocation failure changed frozen JEL evidence")
    print("JEL smoke callers: both allocation failures stop before generation")
# A standalone public run has no reports/ directory. Exercise the real report
# writer without launching either empirical master or substituting a writer stub.
spec = importlib.util.spec_from_file_location("jel_report_writer", root / "tools/jel/run-full-reproduction.py")
writer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(writer)
writer_summary = dict(status="pass", oracle_parity_status="pass",
    historical_artifact_status="pass", finished_at="2026-09-08T00:00:00+0000",
    jel_commit="reference-commit", csdid_commit="candidate-commit",
    r_exit_code=0, stata_exit_code=0, summary_json="build/summary.json",
    artifact_manifest_csv="build/manifest.csv", artifact_comparison_csv="build/comparison.csv",
    logs_dir="build/logs")
expected_report = """# Full JEL Reproduction Result

Status: pass
R 2.5.1 oracle parity status: `pass`
Historical artifact status: `pass`

Date: 2026-09-08T00:00:00+0000
JEL-DiD commit: `reference-commit`
Local csdid commit: `candidate-commit`
R master exit code: `0`
Stata master exit code: `0`
Failure markers: `0`

## Artifact Comparison Counts

| Status | Count |
| --- | ---: |
| `hash-match` | 1 |

## Non-Matching Or Missing Artifacts

| Artifact | Status | Detail |
| --- | --- | --- |
| _none_ |  |  |

## Generated Evidence

- JSON summary: `build/summary.json`
- Artifact manifest: `build/manifest.csv`
- Artifact comparison: `build/comparison.csv`
- Figure label audit: ``
- Table 7 display audit: ``
- Stata figure semantic audit: ``
- Logs directory: `build/logs`
- Stata batch log: ``

Full reproduction is established only when both masters exit 0, failure
markers are absent, Stata outputs pass the explicit R `did` 2.5.1
oracle audits, and all historical table/figure artifact drift is either
hash matched, semantically matched, or dispositioned by a release owner.
"""
with tempfile.TemporaryDirectory(prefix="csdid-jel-report-parent-") as scratch:
    for existing in (True, False):
        path = Path(scratch) / str(existing) / "reports/result.md"
        if existing:
            path.parent.mkdir(parents=True)
            path.write_text("previous report\n")
        else:
            assert not path.parent.exists()
        writer.write_markdown_report(path, summary=writer_summary,
            comparison_rows=[dict(status="hash-match", artifact="tables/table1.tex", detail="")],
            failure_markers=[])
        assert path.read_text() == expected_report, (existing, path.read_text())
        assert writer_summary["status"] == "pass"
print("JEL report writer: existing and absent parent directories preserve exact successful content")
print("F044: 18 static inventory mappings and full-reproduction requirements pass; runtime NOT VERIFIED")
print(f"JEL evidence status: {len(cases)} summary states and 2 isolated observations across 18 artifacts pass")
PY
