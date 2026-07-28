#!/usr/bin/env python3

import csv
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "f049"
LOG = ROOT / "test-f049.log"


def run(cmd):
    proc = subprocess.run(cmd, cwd=ROOT)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


def scan_stata_log():
    if not LOG.exists():
        raise SystemExit(f"missing Stata log: {LOG}")
    bad = []
    for i, line in enumerate(LOG.read_text(errors="replace").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("r(") and stripped.endswith(");"):
            bad.append(f"{LOG}:{i}:{stripped}")
    if bad:
        raise SystemExit("Uncaught Stata error:\n" + "\n".join(bad[-20:]))


def read_csv(path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def main():
    run(["bash", "tools/plugin/build-bootstrap-plugin.sh", "auto"])
    run(["stata-mp", "-b", "do", "src/build.do"])
    run(["Rscript", "tools/parity/generators/f049/generate.R"])
    run(["Rscript", "tools/bench/f049-r-reference.R", str(ROOT)])
    run(["stata-mp", "-b", "do", "tests/stata/test-f049.do"])
    scan_stata_log()

    stata = {row["benchmark"]: row for row in read_csv(BUILD / "results.csv")}
    r = {row["benchmark"]: row for row in read_csv(BUILD / "r-results.csv")}
    budget = {
        row["benchmark"]: row
        for row in read_csv(ROOT / "tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv")
    }

    out = []
    failures = []
    for benchmark, b in sorted(budget.items()):
        if benchmark not in stata:
            failures.append(f"{benchmark}: missing Stata result")
            continue
        if benchmark not in r:
            failures.append(f"{benchmark}: missing R result")
            continue
        stata_seconds = float(stata[benchmark]["seconds"])
        r_seconds = float(r[benchmark]["r_seconds"])
        max_ratio = float(b["max_stata_over_r"])
        ratio = stata_seconds / r_seconds if r_seconds > 0 else float("inf")
        passed = int(ratio <= max_ratio)
        out.append(
            {
                "benchmark": benchmark,
                "stata_seconds": f"{stata_seconds:.6g}",
                "r_seconds": f"{r_seconds:.6g}",
                "stata_over_r": f"{ratio:.6g}",
                "max_stata_over_r": f"{max_ratio:.6g}",
                "passed": str(passed),
            }
        )
        if not passed:
            failures.append(
                f"{benchmark}: Stata/R ratio {ratio:.3g} exceeds {max_ratio:.3g} "
                f"(Stata {stata_seconds:.3g}s, R {r_seconds:.3g}s)"
            )

    BUILD.mkdir(parents=True, exist_ok=True)
    with (BUILD / "r-stata-ratio.csv").open("w", newline="") as f:
        fields = ["benchmark", "stata_seconds", "r_seconds", "stata_over_r", "max_stata_over_r", "passed"]
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(out)

    for row in out:
        print(
            "{benchmark}: Stata {stata_seconds}s, R {r_seconds}s, "
            "ratio {stata_over_r} <= {max_stata_over_r}".format(**row)
        )

    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
