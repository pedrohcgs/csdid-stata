#!/usr/bin/env bash
# Reference selection and restored-code authentication need no empirical jobs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

sys.dont_write_bytecode = True
root = Path.cwd()
runner = Path(os.environ.get("CSDID_JEL_RUNNER", root / "tools/jel/run-full-reproduction.py"))
reference = json.loads((root / "inst/spec/r-oracle-reference.json").read_text())
checks = 0


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def refuses(call):
    try:
        call()
    except RuntimeError:
        return
    raise AssertionError("invalid oracle evidence was accepted")


jel = load(runner, "jel_reference_pin")
assert jel.EXPECTED_DID_VERSION == reference["did_version"], "DID version ignores central pin"
assert jel.EXPECTED_DID_COMMIT == reference["did_commit"], "DID commit ignores central pin"
checks += 2
with tempfile.TemporaryDirectory(prefix="csdid-jel-pin-") as scratch:
    work = Path(scratch)
    pin = work / "reference.json"
    invalid = [None, [], {}, dict(reference, did_version=4),
               dict(reference, did_version="2x5x1"), dict(reference, did_version="2.5.1\n"),
               dict(reference, did_commit="HEAD"), dict(reference, did_commit="a" * 39),
               dict(reference, did_commit=None), dict(reference, DRDID_version="1.3.0")]
    for record in invalid:
        pin.write_text(json.dumps(record))
        refuses(lambda: jel.read_oracle_reference(pin))
        checks += 1
    pin.write_text("{")
    refuses(lambda: jel.read_oracle_reference(pin))
    pin.unlink()
    refuses(lambda: jel.read_oracle_reference(pin))
    checks += 2

    # A later reviewed central pin must control both fields without editing
    # the JEL runner. This also detects literals matching today's pin by chance.
    future = work / "future"
    (future / "tools/jel").mkdir(parents=True)
    (future / "inst/spec").mkdir(parents=True)
    future_pin = dict(reference, did_version="2.5.1.999", did_commit="c" * 40)
    (future / "inst/spec/r-oracle-reference.json").write_text(json.dumps(future_pin))
    shutil.copy2(runner, future / "tools/jel/run-full-reproduction.py")
    future_jel = load(future / "tools/jel/run-full-reproduction.py", "jel_future_pin")
    assert (future_jel.EXPECTED_DID_VERSION, future_jel.EXPECTED_DID_COMMIT) == (
        future_pin["did_version"], future_pin["did_commit"])
    checks += 1

    tree = work / "lock"
    tree.mkdir()
    lockfile = tree / "renv.lock"
    lockfile.write_text(json.dumps({"Packages": {
        "did": {"Version": "2.5.1", "RemoteSha": "a" * 40},
        "DRDID": {"Version": "1.3.0"}, "untouched": {"Version": "1.2"}}}))
    summary = {}
    jel.patch_jel_r_oracle_lock(tree, summary)
    jel.validate_jel_r_oracle(tree, summary)
    packages = json.loads(lockfile.read_text())["Packages"]
    assert packages["did"]["Version"] == reference["did_version"]
    assert packages["did"]["RemoteSha"] == reference["did_commit"]
    assert packages["DRDID"]["Version"] == "1.4.0"
    assert packages["DRDID"]["RemoteSha"] == jel.EXPECTED_DRDID_COMMIT
    assert "BMisc (>= 1.4.8)" in packages["did"]["Imports"]
    assert "DRDID (>= 1.4.0)" in packages["did"]["Imports"]
    assert packages["untouched"] == {"Version": "1.2"}
    checks += 7

    (tree / "scripts/R").mkdir(parents=True)
    master = tree / "scripts/R/00_master_did_jel.R"
    master.write_text('renv::restore(prompt = FALSE)\ncat("ANALYSIS\\n")\n')
    jel.patch_jel_r_oracle_check(tree, root)
    generated = master.read_text()
    gate = str(root / "tools/parity/generators/oracle-check.R")
    assert generated.index("renv::restore") < generated.index(gate) < generated.index('cat("ANALYSIS')
    assert '\n  Sys.unsetenv("CSDID_DID_UPSTREAM")\n  source(' in generated
    assert 'upstream <- Sys.getenv("CSDID_DID_UPSTREAM"' in generated
    assert 'Sys.setenv(CSDID_DID_UPSTREAM = upstream)' in generated
    jel.patch_jel_r_oracle_check(tree, root)
    assert master.read_text() == generated
    checks += 5

    digest = "a" * 64
    (tree / "inst/spec").mkdir(parents=True)
    fingerprint = tree / "inst/spec/r-oracle-full-code-digest.txt"
    fingerprint.write_text(digest + "\n")
    log = tree / "r-master.log"
    correct = (f"oracle gate: did {reference['did_version']} / DRDID 1.4.0 "
               f"content-verified (fixture; all 134 R functions {digest}) at restored-library")
    log.write_text(correct)
    assert jel.validate_restored_r_oracle(log, tree) == digest
    checks += 1
    for invalid_log in ("", correct.replace(reference["did_version"], "2.5.1"),
                        correct.replace(reference["did_version"], reference["did_version"].replace(".", "x")),
                        correct.replace("DRDID 1.4.0", "DRDID 1.3.0"),
                        correct.replace(digest, "b" * 64)):
        log.write_text(invalid_log)
        refuses(lambda: jel.validate_restored_r_oracle(log, tree))
        checks += 1
    fingerprint.write_text("a" * 63)
    log.write_text(correct)
    refuses(lambda: jel.validate_restored_r_oracle(log, tree))
    checks += 1

    # Exercise the real orchestration with modeled R/Stata processes. The
    # genuine failed R log is retained separately; no R or Stata runs here.
    for mode in ("complete", "wrong-restored-version", "missing-loaded-code-proof", "R-error"):
        case = work / mode
        (case / "tools/release").mkdir(parents=True)
        shutil.copy2(root / "tools/release/check-stata-log-tail.sh", case / "tools/release/check-stata-log-tail.sh")
        (case / "inst/spec").mkdir(parents=True)
        (case / "inst/spec/r-oracle-full-code-digest.txt").write_text(digest)
        frozen = case / "reference"
        (frozen / ".git").mkdir(parents=True)
        job = case / "build/jel"
        copied = job / "worktree"
        (copied / "scripts/R").mkdir(parents=True)
        (copied / "scripts/R/00_master_did_jel.R").write_text('renv::restore(prompt = FALSE)\ncat("ANALYSIS\\n")\n')
        (copied / "renv.lock").write_text(json.dumps({"Packages": {}}))
        calls = []

        def fake_run(command, *, cwd, log_path, **kwargs):
            is_r = len(calls) == 0
            calls.append("R" if is_r else "Stata")
            log_path.parent.mkdir(parents=True, exist_ok=True)
            if is_r:
                body = (copied / "scripts/R/00_master_did_jel.R").read_text()
                assert '\n  Sys.unsetenv("CSDID_DID_UPSTREAM")\n  source(' in body
                assert body.index("renv::restore") < body.index("source(") < body.index('cat("ANALYSIS')
                text = correct
                if mode == "wrong-restored-version":
                    text = correct.replace(reference["did_version"], "2.5.1")
                if mode == "missing-loaded-code-proof":
                    text = "R process exited without namespace authentication\n"
                if mode == "R-error":
                    text = "oracle gate: wrong restored did namespace\n"
                log_path.write_text(text)
                if mode == "R-error":
                    raise RuntimeError("modeled restored namespace rejection before analysis")
            else:
                log_path.write_text("complete\n")
                (copied / "run-stata-master.log").write_text("end of do-file\n")
            return subprocess.CompletedProcess(command, 0)

        replacements = dict(repo_root=lambda: case,
            git_output=lambda repo, *args: "" if args == ("status", "--porcelain") else jel.EXPECTED_JEL_COMMIT,
            patch_jel_r_rng_state_exports=lambda *_: None,
            patch_jel_stata_event_label_calls=lambda *_: None,
            configure_r_toolchain_env=lambda *_: None,
            find_jel_rscript=lambda: Path("/modeled/Rscript"),
            prepare_r_home_overlay=lambda *_: None,
            write_r_makevars=lambda *_: None,
            run=fake_run, build_stata_wrapper=lambda path, *_: path.write_text("display 1\n"),
            compare_artifacts=lambda *_: ([], [], []),
            audit_r_stata_figure_labels=lambda *_: ([], []),
            audit_r_stata_table7_display=lambda *_: ([], []),
            render_pdf_side_by_side=lambda *_: {})
        args = [str(runner), "--jel-repo", str(frozen), "--work-dir", str(job),
                "--report", str(case / "reports/result.md"), "--keep-work"]
        with patch.multiple(jel, **replacements), patch.object(sys, "argv", args), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            accepted = jel.main() == 0
        assert accepted == (mode == "complete"), (mode, accepted)
        assert calls == (["R", "Stata"] if mode == "complete" else ["R"]), (mode, calls)
        numeric_artifact = job / "outputs/artifact-manifest.csv"
        assert numeric_artifact.exists() == (mode == "complete")
        checks += 3

print(f"JEL oracle pin: {checks} central-pin, lock, authentication and isolated-process checks pass (no R/Stata jobs)")
PY
