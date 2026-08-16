#!/usr/bin/env python3
"""What a csdid session pays once, gated.

Builds the package, runs tools/bench/session-warmup.do in fresh processes
against the compiled library, and compares the first run of a command with the
steady-state run of the SAME command in the SAME session.

The figure is a ratio inside one session, so it does not depend on how fast the
machine is; only on how much of the engine that session had to go and find. A
budget breach means a fresh session pays materially more than a warmed one --
which is what a user running csdid once in a do-file experiences, and what no
other instrument here can see.

    python3 tools/bench/run-session-warmup.py [--reps N]
"""

import argparse
import csv
import statistics
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "session-warmup.csv"
RIF = ROOT / "build" / "session-warmup-rif.dta"

# Budgets, and what four trees read against them on a 50,000-row panel:
#
#                                   cold    agg     rif
#   this tree                       1.12    1.01    1.03
#   the cell driver before it       1.62    1.16    1.17   <- the regressions
#   the same, one stage earlier     1.62    1.15           this gate exists
#   the engine before the refactor  1.48    1.04           to catch
#
# (the rif column is the aggregation route, which the two trees on the middle
# rows reach through their own loader; the row above them is this tree)
#
# Repeated runs of this tree scatter within 1.12-1.14, 1.01-1.03 and
# 1.03-1.04, so every budget sits several times the scatter above it and well
# below every tree that has to go and find the engine. The cold budget is
# deliberately tighter than the pre-refactor engine could meet: it is met only
# because the library is searched first, and it is set where it is so that
# arrangement cannot be undone without this saying so.
#
# `rif' is `csdid_stats using <riffile>' in a session where csdid never runs,
# which is the only workflow that reaches the engine on its own. Its ratio is
# damped by the file it reads -- 0.46s of the 0.48s is loading the artifact --
# so the figure to read beside it is the first run in seconds: 0.477s here
# against 0.539s when that route had its own loader and did not move the
# library it accepted. Six readings on this tree: 1.030, 1.032, 1.035, 1.035,
# 1.041, 1.055, the highest of them taken while the rest of the suite was
# running. The route it exists to catch reads 1.167-1.174. The budget sits
# between the two rather than just above this tree, because a gate that goes
# red on a busy machine stops the suite before its end for a reason that has
# nothing to do with the engine.
BUDGETS = {"cold": 1.35, "agg": 1.07, "rif": 1.10}


def run(cmd):
    proc = subprocess.run(cmd, cwd=ROOT)
    if proc.returncode != 0:
        raise SystemExit(f"command failed: {' '.join(str(c) for c in cmd)}")


def phase(name, *args):
    """One phase, one process, and the log that process actually wrote.

    stata-mp -b names its batch log after the LAST argument it is handed, not
    after the do-file, so the name is derived the same way and the file is
    removed first: a scan that reads a log some earlier run left behind is a
    scan that cannot fail.
    """
    argv = [str(ROOT / "build"), str(OUT), name, *args]
    log = ROOT / (Path(argv[-1]).stem + ".log")
    if log.exists():
        log.unlink()
    run(["stata-mp", "-b", "do", "tools/bench/session-warmup.do", *argv])
    scan_log(log)


def scan_log(log):
    """stata-mp -b exits 0 even when the do-file aborts; the log is the truth."""
    if not log.exists():
        raise SystemExit(f"missing Stata log: {log}")
    # Batch Stata exits 0 on an aborted do-file, so the log IS the verdict --
    # and `r(NNN);' is not the only way a run fails. A failed assert prints
    # "assertion is false" and stops; scanning only for r() called that a pass.
    # Same marker set as run-perf-campaign.py, deliberately.
    bad = [
        f"{log}:{i}:{line.strip()}"
        for i, line in enumerate(log.read_text(errors="replace").splitlines(), 1)
        if (line.strip().startswith("r(") and line.strip().endswith(");"))
        or line.strip() == "assertion is false"
    ]
    if bad:
        raise SystemExit("Uncaught Stata error:\n" + "\n".join(bad[-20:]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reps", type=int, default=3)
    args = parser.parse_args()

    # The compiled library this instrument benchmarks is built here. `stata-mp
    # -b' exits 0 even when the do-file aborts, and an aborted build leaves the
    # PREVIOUS lcsdid_v2.mlib in place -- so without removing the artifact and
    # reading the log, every phase below would time a stale library and the
    # compiled-library gate would pass while the current source failed to build.
    stale_mlib = ROOT / "build" / "lcsdid_v2.mlib"
    if stale_mlib.exists():
        stale_mlib.unlink()
    build_log = ROOT / "build.log"
    if build_log.exists():
        build_log.unlink()
    run(["stata-mp", "-b", "do", "src/build.do"])
    scan_log(build_log)
    if not stale_mlib.exists():
        raise SystemExit("src/build.do produced no build/lcsdid_v2.mlib")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        OUT.unlink()

    # The RIF the `rif' phase aggregates is written here, in a process of its
    # own: a file written by the session that reads it would be read by a
    # session that had already found the engine, which is the one thing that
    # phase is measuring.
    phase("rifbuild", str(RIF))

    # One phase per process, and the phases rotate, so a machine that drifts
    # during the campaign drifts across all of them rather than into one.
    for _ in range(args.reps):
        for name in ("cold", "agg", "rif"):
            phase(name, str(RIF))

    seconds = {}
    with OUT.open(newline="") as f:
        for name, label, value in csv.reader(f):
            seconds.setdefault((name, label), []).append(float(value))

    failures = []
    for name, budget in BUDGETS.items():
        first = seconds.get((name, "first"))
        steady = seconds.get((name, "steady"))
        if not first or not steady:
            failures.append(f"{name}: no timings recorded")
            continue
        # Median of the first runs over the median of every steady run: the
        # steady runs are the same command in the same session, so their
        # median is what this session costs once it holds the engine.
        ratio = statistics.median(first) / statistics.median(steady)
        verdict = "ok" if ratio <= budget else "OVER BUDGET"
        print(
            f"{name}: first {statistics.median(first):.4g}s, "
            f"steady {statistics.median(steady):.4g}s, "
            f"ratio {ratio:.3f} <= {budget:.2f} [{verdict}]"
        )
        if ratio > budget:
            failures.append(
                f"{name}: first-run/steady-run ratio {ratio:.3f} exceeds {budget:.2f} "
                f"(first {statistics.median(first):.3g}s, steady {statistics.median(steady):.3g}s); "
                "a fresh session is paying to go and find the engine"
            )

    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
