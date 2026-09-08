#!/usr/bin/env python3

import csv
import platform
from pathlib import Path

from stata_runtime import measure_stata, prepare_build, stata_command, write_driver


ROOT = Path(__file__).resolve().parents[2]
OUTDIR = ROOT / "build" / "memory-gate"
SCENARIOS = {
    "default_cband": 1800.0,
    "seeded_plugin": 1800.0,
    "unbalanced_plugin": 1800.0,
    "aggregation_bootstrap": 900.0,
    "large_panel": 6000.0,
}


def measure(scenario, budget_mb):
    driver = OUTDIR / f"{scenario}-driver.do"
    write_driver(ROOT, driver, "tools/bench/memory-workload.do", (scenario, ROOT))
    elapsed, peak_mb, samples = measure_stata(
        ROOT, stata_command(), driver, OUTDIR / f"{scenario}-batch.log")
    return {
        "scenario": scenario,
        "elapsed_seconds": f"{elapsed:.6f}",
        "peak_rss_mb": f"{peak_mb:.3f}",
        "rss_measure": "ps_rss_kb",
        "rss_samples": str(samples),
        "max_rss_mb": f"{budget_mb:.3f}",
        "passed": str(int(peak_mb <= budget_mb)),
        "system": platform.system(),
        "machine": platform.machine(),
    }


def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    (OUTDIR / "results.csv").unlink(missing_ok=True)
    prepare_build(ROOT)
    rows = [measure(name, budget) for name, budget in SCENARIOS.items()]
    output = OUTDIR / "results.csv"
    with output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    for row in rows:
        print(
            f"{row['scenario']}: peak RSS {row['peak_rss_mb']} MB "
            f"<= {row['max_rss_mb']} MB"
        )
    failed = [row for row in rows if row["passed"] != "1"]
    if failed:
        raise SystemExit("memory gate failed")


if __name__ == "__main__":
    main()
