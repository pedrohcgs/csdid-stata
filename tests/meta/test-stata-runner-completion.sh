#!/usr/bin/env bash
# Batch launch failures and unfinished logs cannot certify a Stata test.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import os
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import sys
from unittest.mock import patch
sys.dont_write_bytecode = True

root = Path.cwd()
checker = root / "tools/release/check-stata-log-tail.sh"
checks = 0
with tempfile.TemporaryDirectory(prefix="csdid-runner-check-") as scratch:
    work = Path(scratch)
    (work / "tools/release").mkdir(parents=True)
    shutil.copy2(checker, work / "tools/release/check-stata-log-tail.sh")
    log = work / "probe.log"
    cases = {
        "complete": (". assert 1\n\nend of do-file\n", True),
        "complete-with-prompt": (". assert 1\nend of do-file\n. \n\n", True),
        "empty": ("", False),
        "truncated": (". assert 1\n", False),
        "inner-completion": ("end of do-file\n. more work\n1\n2\n3\n", False),
        "inner-completion-one-line": ("end of do-file\n. do more-work.do\n", False),
        "inner-completion-two-lines": ("end of do-file\n\n. assert 0\n", False),
        "error-before-tail": ("r(9);\n" + "continued\n" * 60 + "end of do-file\n", False),
    }
    for name, (content, expected) in cases.items():
        log.write_text(content)
        result = subprocess.run(["bash", str(checker), str(log)], capture_output=True)
        if (result.returncode == 0) != expected:
            raise SystemExit(f"log validator misclassified {name}: rc={result.returncode}")
        checks += 1
    log.unlink()
    if subprocess.run(["bash", str(checker), str(log)], capture_output=True).returncode == 0:
        raise SystemExit("log validator accepted a missing log")
    checks += 1

    fake = work / "stata-stub"
    fake.write_text('''#!/usr/bin/env bash
case "$CSDID_TEST_MODE" in
  launch-failure) exit 42 ;;
  missing|remove-failure) exit 0 ;;
esac
name="$(basename "${3%.do}").log"
case "$CSDID_TEST_MODE" in
  truncated|archive-failure) printf 'VARABBREV-OFF-HELD\\n. assert 1\\n' > "$name" ;;
  error) printf 'r(9);\\nVARABBREV-OFF-HELD\\nend of do-file\\n' > "$name" ;;
  complete) printf 'VARABBREV-OFF-HELD\\n\\nend of do-file\\n' > "$name" ;;
esac
''')
    fake.chmod(0o755)
    (work / "bin").mkdir()
    for command, failure_mode in (("mv", "archive-failure"), ("rm", "remove-failure")):
        tool = work / "bin" / command
        tool.write_text('#!/usr/bin/env bash\n'
                        f'if [[ "$CSDID_TEST_MODE" == "{failure_mode}" ]]; then exit 42; fi\n'
                        f'exec {shlex.quote(shutil.which(command))} "$@"\n')
        tool.chmod(0o755)
    (work / "logs").mkdir()
    runners = [
        ("tests/run-smoke.sh", "run_stata"),
        ("tests/run-jel-smoke.sh", "run_stata"),
        ("tools/release/run-local-release-gates.sh", "run_stata_do"),
        ("tools/release/preflight.sh", "stata_do"),
        ("tools/release/preflight.sh", "stata_do_varabbrev_off"),
    ]
    for source, name in runners:
        text = (root / source).read_text()
        match = re.search(r"^" + name + r"\(\) \{\n.*?^\}", text, re.M | re.S)
        if match is None:
            raise SystemExit(f"cannot locate runner {name} in {source}; nothing tested")
        for mode in ("complete", "truncated", "missing", "launch-failure", "error",
                     "archive-failure", "remove-failure"):
            # A successful log from a previous invocation must not vouch for
            # a command that never writes a new one.
            for stale in ("probe.log", "varabbrev-off-probe.log"):
                (work / stale).write_text("VARABBREV-OFF-HELD\n\nend of do-file\n")
                (work / "logs" / stale).write_text("VARABBREV-OFF-HELD\n\nend of do-file\n")
            invocation = f"{name} probe.do"
            if source == "tools/release/preflight.sh":
                # preflight's run() invokes the function as an if condition,
                # which disables Bash errexit inside the function body.
                invocation = f"if {invocation}; then exit 0; else exit $?; fi"
            script = (
                "set -euo pipefail\n"
                f"STATA={shlex.quote(str(fake))}\nSTATA_CMD=\"$STATA\"\nLOGDIR=logs\n"
                + match.group() + "\n" + invocation + "\n"
            )
            env = dict(os.environ, CSDID_TEST_MODE=mode,
                       PATH=str(work / "bin") + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["bash", "-c", script], cwd=work, env=env,
                                    capture_output=True, text=True)
            if (result.returncode == 0) != (mode == "complete"):
                raise SystemExit(f"{source}:{name} misclassified {mode}: "
                                 f"rc={result.returncode}\n{result.stdout}{result.stderr}")
            checks += 1
    # Installation ships in two layouts and must validate the outer batch log.
    for layout, relative in (("checkout", "tests/installation"),
                             ("bundle", "validation-tests")):
        install_root = work / layout
        here = install_root / relative
        here.mkdir(parents=True)
        (install_root / "csdid.pkg").write_text("v 3\n")
        (here / "install-and-smoke.do").write_text("display 1\n")
        shutil.copy2(root / "tests/installation/run-install-smoke.sh", here)
        destination = (here if layout == "bundle" else
                       install_root / "tools/release")
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(checker, destination)
        for mode in ("complete", "truncated", "missing", "launch-failure", "error",
                     "archive-failure", "remove-failure"):
            (install_root / "install-and-smoke.log").write_text("end of do-file\n")
            env = dict(os.environ, STATA_CMD=str(fake), CSDID_TEST_MODE=mode,
                       PATH=str(work / "bin") + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["bash", str(here / "run-install-smoke.sh")],
                                    cwd=work, env=env, capture_output=True, text=True)
            if (result.returncode == 0) != (mode == "complete"):
                raise SystemExit(f"installation {layout} misclassified {mode}: "
                                 f"rc={result.returncode}\n{result.stdout}{result.stderr}")
            checks += 1
        (destination / checker.name).unlink()
        env["CSDID_TEST_MODE"] = "complete"
        result = subprocess.run(["bash", str(here / "run-install-smoke.sh")],
                                cwd=work, env=env, capture_output=True)
        if result.returncode == 0:
            raise SystemExit(f"installation {layout} accepted a missing validator")
        checks += 1
    # Exercise the actual Python entrypoint control paths. Only numerical data,
    # package restoration and artifact comparisons are replaced by fixtures.
    # External commands are real shell/Python stubs; log validation stays real.
    def load(name, relative):
        spec = importlib.util.spec_from_file_location(name, root / relative)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        return module

    jel = load("jel_transport", "tools/jel/run-full-reproduction.py")
    adv = load("adversarial_transport", "tools/release/run-adversarial-differential.py")
    adversarial_run = adv.run
    failures = []
    for runner in ("jel", "adversarial"):
        modes = ["complete", "missing", "truncated", "inner-completion", "error", "nonzero"]
        if runner == "jel":
            modes += ["missing-reference", "wrong-reference", "dirty-reference", "interrupted",
                      "analyze-existing", "r-auth-failure", "r-nonzero", "unauthenticated-existing", "invalid-existing-exit"]
            modes += ["invalid-existing-commit", "missing-existing-runtime", "wrong-existing-reference"]
        for mode in modes:
            case = work / f"{runner}-{mode}"
            (case / "tools/release").mkdir(parents=True)
            shutil.copy2(checker, case / "tools/release" / checker.name)
            bin_ = case / "bin"
            bin_.mkdir()
            rscript = bin_ / "Rscript"
            rscript.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$0" >> "$CSDID_TRANSPORT_COMMANDS"\n'
                '[ "$CSDID_TRANSPORT_MODE" != r-nonzero ] || exit 42\n'
                '[ "$CSDID_TRANSPORT_MODE" = r-auth-failure ] || printf "%s\\n" "$CSDID_TRANSPORT_ORACLE"\n')
            rscript.chmod(0o755)
            alternate = bin_ / "R"
            shutil.copy2(rscript, alternate)
            stata = bin_ / "chosen-stata"
            stata.write_text('''#!/usr/bin/env python3
import os, sys
from pathlib import Path
mode = os.environ['CSDID_TRANSPORT_MODE']
if mode == 'nonzero': sys.exit(42)
if mode == 'missing': sys.exit(0)
text = {'truncated': '. assert 1\\n',
        'inner-completion': 'end of do-file\\n. do unfinished.do\\n',
        'error': 'r(9);\\nend of do-file\\n'}.get(mode, 'end of do-file\\n')
Path(Path(sys.argv[3]).stem + '.log').write_text(text)
''')
            stata.chmod(0o755)
            commands = case / "commands.txt"
            oracle_digest = "a" * 64
            oracle_message = f"oracle gate: did 2.5.1 / DRDID 1.3.0 content-verified (fixture; all 118 R functions {oracle_digest}) at fixture"
            (case / "inst/spec").mkdir(parents=True)
            (case / "inst/spec/r-oracle-full-code-digest.txt").write_text(oracle_digest + "\n")
            env = dict(os.environ, STATA_CMD=str(stata), CSDID_JEL_RSCRIPT=str(rscript),
                       CSDID_TRANSPORT_MODE=mode, CSDID_TRANSPORT_COMMANDS=str(commands),
                       CSDID_TRANSPORT_ORACLE=oracle_message,
                       PATH=str(bin_) + os.pathsep + os.environ["PATH"])
            accepted = False
            archived = True
            try:
                with patch.dict(os.environ, env, clear=True), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    if runner == "adversarial":
                        (case / "run-stata.log").write_text("end of do-file\n")
                        with patch.multiple(adv, ROOT=case, BUILD=case / "build/adversarial", STATA_CMD=str(stata), SCENARIOS=[]), \
                             patch.object(adv, "run", side_effect=lambda command: adversarial_run(command, cwd=case)), \
                             patch.object(adv, "compare_outputs", return_value=None):
                            accepted = adv.main() == 0
                    else:
                        reference = case / "reference"
                        if mode != "missing-reference":
                            (reference / ".git").mkdir(parents=True)
                        job = case / "build/jel"
                        tree = job / "worktree"
                        (tree / "scripts/R").mkdir(parents=True)
                        master = tree / "scripts/R/00_master_did_jel.R"
                        master.write_text('renv::restore(prompt = FALSE)\ncat("ANALYSIS\\n")\n')
                        (tree / "renv.lock").write_text(json.dumps({"Packages": {"did": {"Version": "2.5.1"}, "DRDID": {"Version": "1.3.0"}}}))
                        (tree / "run-stata-master.log").write_text("end of do-file\n")
                        summary = job / "outputs/summary.json"
                        summary.parent.mkdir()
                        prior_identity = {"csdid_commit": "b" * 40, "csdid_repo": "/prior/source",
                                          "jel_commit": jel.EXPECTED_JEL_COMMIT,
                                          "r_command": "/prior/Rscript", "stata_command": "/prior/stata"}
                        if mode == "invalid-existing-commit": prior_identity["csdid_commit"] = "invalid"
                        if mode == "missing-existing-runtime": del prior_identity["stata_command"]
                        if mode == "wrong-existing-reference": prior_identity["jel_commit"] = "c" * 40
                        prior_summary = json.dumps(dict(prior_identity, status="pass", r_exit_code=False if mode == "invalid-existing-exit" else 0, stata_exit_code=0)).encode()
                        summary.write_bytes(prior_summary)
                        report = case / "reports/result.md"
                        report.parent.mkdir()
                        prior_report = b"Prior passing report\n"
                        report.write_bytes(prior_report)
                        (job / "logs").mkdir()
                        (job / "logs/r-master.log").write_text("" if mode == "unauthenticated-existing" else oracle_message)
                        def git(repo, *args):
                            if args == ("status", "--porcelain"):
                                return " M changed" if mode == "dirty-reference" else ""
                            return "wrong" if mode == "wrong-reference" else jel.EXPECTED_JEL_COMMIT
                        replacements = dict(repo_root=lambda: case, git_output=git,
                            patch_jel_r_rng_state_exports=lambda *_: None,
                            patch_jel_stata_event_label_calls=lambda *_: None,
                            patch_jel_r_oracle_lock=lambda *_: None,
                            configure_r_toolchain_env=lambda *_: None,
                            prepare_r_home_overlay=lambda *_: case,
                            write_r_makevars=lambda *_: None,
                            build_stata_wrapper=lambda path, *_: path.write_text('display 1\n'),
                            compare_artifacts=lambda *_: ([], [], []),
                            audit_r_stata_figure_labels=lambda *_: ([], []),
                            audit_r_stata_table7_display=lambda *_: ([], []),
                            render_pdf_side_by_side=lambda *_: {})
                        if mode == "interrupted":
                            replacements["run"] = lambda *args, **kwargs: (_ for _ in ()).throw(KeyboardInterrupt())
                        args = ["run-full-reproduction.py", "--jel-repo", str(reference), "--work-dir", str(job), "--report", str(report), "--keep-work"]
                        if mode == "analyze-existing" or "existing" in mode:
                            args.append("--analyze-existing")
                        with patch.multiple(jel, **replacements), patch.object(sys, "argv", args):
                            accepted = jel.main() == 0
            except (SystemExit, RuntimeError, OSError, subprocess.CalledProcessError, KeyboardInterrupt):
                accepted = False
            expected = mode in {"complete", "analyze-existing"}
            if accepted != expected:
                failures.append(f"{runner}/{mode}: completion verdict {accepted}, expected {expected}")
            if runner == "adversarial" and mode == "complete":
                generated = (case / "build/adversarial/run-r.R").read_text().splitlines()
                if generated[0] != 'source(' + json.dumps(str(case / 'tools/parity/generators/oracle-check.R')) + ')':
                    failures.append("adversarial: the actual R process does not authenticate its oracle first")
            if runner == "jel":
                archived = (any(p != summary and p.read_bytes() == prior_summary for p in summary.parent.rglob('summary.json'))
                            and any(p != report and p.read_bytes() == prior_report for p in report.parent.rglob('result.md')))
                if not archived:
                    failures.append(f"jel/{mode}: prior canonical evidence was not archived")
                if mode == "complete" and (not commands.exists() or commands.read_text().splitlines() != [str(rscript)]):
                    failures.append("jel/complete: explicit R executable was ignored")
                if mode == "analyze-existing" and accepted:
                    observed = json.loads(summary.read_text())
                    if any(observed.get(key) != value for key, value in prior_identity.items()) or observed.get("analysis_commit") != jel.EXPECTED_JEL_COMMIT:
                        failures.append("jel/analyze-existing: prior execution was relabeled as the current source/runtime")
                if mode == "complete":
                    generated = master.read_text()
                    gate = str(case / "tools/parity/generators/oracle-check.R")
                    if gate not in generated or not generated.index('renv::restore') < generated.index(gate) < generated.index('cat("ANALYSIS'):
                        failures.append("jel: actual-process authentication does not follow restoration before analysis")
                    # A retained worktree must use the current source's gate.
                    if hasattr(jel, "patch_jel_r_oracle_check"):
                        jel.patch_jel_r_oracle_check(tree, case / "new source")
                        updated = master.read_text()
                        jel.patch_jel_r_oracle_check(tree, case / "new source")
                        if updated != master.read_text() or gate in updated or str(case / "new source/tools/parity/generators/oracle-check.R") not in updated:
                            failures.append("jel: retained worktree keeps stale oracle-check plumbing")
                if mode in {"missing-reference", "wrong-reference", "dirty-reference", "interrupted"} and (summary.exists() or report.exists()):
                    failures.append(f"jel/{mode}: prior success remains current")
            checks += 1
    if failures:
        raise SystemExit("\n".join(failures))
print(f"Stata runner completion: {checks} log/launch cases pass")
PY
