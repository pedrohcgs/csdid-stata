#!/usr/bin/env python3

import csv
import platform
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTDIR = ROOT / "build" / "memory-gate"
SCENARIOS = {
    "default_cband": 1800.0,
    "seeded_plugin": 1800.0,
    "unbalanced_plugin": 1800.0,
    "aggregation_bootstrap": 900.0,
    "large_panel": 6000.0,
}


def run_checked(command):
    subprocess.run(command, cwd=ROOT, check=True)


def rss_kb(pid):
    result = subprocess.run(
        ["ps", "-o", "rss=", "-p", str(pid)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return 0
    return int(result.stdout.strip().splitlines()[0])


def scan_log(scenario, log_path):
    if not log_path.exists():
        raise RuntimeError(f"{scenario}: Stata did not create {log_path}")
    failures = []
    for line_number, line in enumerate(log_path.read_text(errors="replace").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("r(") and stripped.endswith(");"):
            failures.append(f"line {line_number}: {stripped}")
    if failures:
        raise RuntimeError(f"{scenario}: uncaught Stata error: {failures[-1]}")


def measure(scenario, budget_mb):
    log_path = OUTDIR / f"{scenario}.log"
    if log_path.exists():
        log_path.unlink()
    process = subprocess.Popen(
        [
            "stata-mp",
            "-b",
            "do",
            "tools/bench/memory-workload.do",
            scenario,
            str(ROOT),
        ],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    peak_kb = 0
    started = time.perf_counter()
    while process.poll() is None:
        peak_kb = max(peak_kb, rss_kb(process.pid))
        time.sleep(0.002)
    peak_kb = max(peak_kb, rss_kb(process.pid))
    elapsed = time.perf_counter() - started
    if process.returncode != 0:
        raise RuntimeError(f"{scenario}: Stata process exited {process.returncode}")
    scan_log(scenario, log_path)
    peak_mb = peak_kb / 1024.0
    return {
        "scenario": scenario,
        "elapsed_seconds": f"{elapsed:.6f}",
        "peak_rss_mb": f"{peak_mb:.3f}",
        "max_rss_mb": f"{budget_mb:.3f}",
        "passed": str(int(peak_mb <= budget_mb)),
        "system": platform.system(),
        "machine": platform.machine(),
    }


def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    run_checked(["bash", "tools/plugin/build-bootstrap-plugin.sh", "auto"])
    run_checked(["stata-mp", "-b", "do", "src/build.do"])
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
