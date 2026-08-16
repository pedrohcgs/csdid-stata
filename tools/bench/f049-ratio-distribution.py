#!/usr/bin/env python3
"""Repeat the f049 Stata/R ratio measurement and report its distribution.

tools/bench/run-f049-ratio.py answers one question -- is every cell inside its
budget right now -- and a budget cannot be set from one answer. This driver
takes the same two measurements the gate takes, N times in a row, and writes
every round so the budget can be read off the observed spread rather than off
the last run that happened to be quiet.

The one-time steps of the gate (plugin build, src/build.do, fixture generation)
are NOT repeated: they produce the inputs, not the timings. The two steps that
ARE repeated are exactly the gate's, in the gate's order, one Stata process and
one R process per round.

    python3 tools/bench/f049-ratio-distribution.py --rounds 8 --tag <t>

Output: tools/bench/perfscale/f049-ratio-<tag>.csv, one row per cell per round.
"""

import argparse
import csv
import statistics
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# parameters
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "f049"
OUTDIR = ROOT / "tools" / "bench" / "perfscale"
STATA_LOG = ROOT / "test-f049.log"
BUDGETS = ROOT / "tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv"


# ---------------------------------------------------------------------------
# the workhorse: one round is one R reference and one Stata benchmark
# ---------------------------------------------------------------------------
def run_round(round_index):
    for cmd in (
        ["Rscript", "tools/bench/f049-r-reference.R", str(ROOT)],
        ["stata-mp", "-b", "do", "tests/stata/test-f049.do"],
    ):
        proc = subprocess.run(cmd, cwd=ROOT)
        if proc.returncode != 0:
            raise SystemExit(f"round {round_index}: {cmd[0]} exited {proc.returncode}")

    # stata-mp -b exits 0 even when the do-file aborts
    bad = [
        f"{STATA_LOG}:{i}:{line.strip()}"
        for i, line in enumerate(STATA_LOG.read_text(errors="replace").splitlines(), 1)
        if line.strip().startswith("r(") and line.strip().endswith(");")
    ]
    if bad:
        raise SystemExit(f"round {round_index}: uncaught Stata error\n" + "\n".join(bad[-20:]))

    def read(path):
        with path.open(newline="") as f:
            return {row["benchmark"]: row for row in csv.DictReader(f)}

    stata = read(BUILD / "results.csv")
    r = read(BUILD / "r-results.csv")
    budget = read(BUDGETS)

    rows = []
    for benchmark in sorted(budget):
        if benchmark not in stata or benchmark not in r:
            raise SystemExit(f"round {round_index}: {benchmark} missing a measurement")
        stata_seconds = float(stata[benchmark]["seconds"])
        r_seconds = float(r[benchmark]["r_seconds"])
        rows.append(
            {
                "round": round_index,
                "benchmark": benchmark,
                "stata_seconds": f"{stata_seconds:.6g}",
                "r_seconds": f"{r_seconds:.6g}",
                "stata_over_r": f"{stata_seconds / r_seconds:.6g}",
                "max_stata_over_r": budget[benchmark]["max_stata_over_r"],
            }
        )
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=8)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()

    rows = []
    for i in range(1, args.rounds + 1):
        print(f"[f049-ratio-distribution] round {i}/{args.rounds}", flush=True)
        rows.extend(run_round(i))

    OUTDIR.mkdir(parents=True, exist_ok=True)
    out = OUTDIR / f"f049-ratio-{args.tag}.csv"
    with out.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    by_cell = {}
    for row in rows:
        by_cell.setdefault(row["benchmark"], []).append(float(row["stata_over_r"]))
    print(f"\n{out}\n")
    print(f"{'benchmark':<42} {'min':>7} {'median':>7} {'max':>7} {'budget':>7} {'max/budget':>11}")
    for benchmark in sorted(by_cell):
        v = by_cell[benchmark]
        budget = float(next(r["max_stata_over_r"] for r in rows if r["benchmark"] == benchmark))
        print(
            f"{benchmark:<42} {min(v):>7.3f} {statistics.median(v):>7.3f} "
            f"{max(v):>7.3f} {budget:>7.3f} {max(v) / budget:>10.1%}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
