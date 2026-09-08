#!/usr/bin/env python3
"""Six complete paired F049 rounds; every workload keeps its original ceiling."""

import csv
import hashlib
import json
import math
import shutil
import statistics
import subprocess
import time
from pathlib import Path

from stata_runtime import prepare_build, run_stata, stata_command


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "f049"
LOG = ROOT / "test-f049.log"
ROUNDS = 6


def run(cmd, log=None):
    if log is None:
        proc = subprocess.run(cmd, cwd=ROOT)
    else:
        with log.open("w") as stream:
            proc = subprocess.run(cmd, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


def read_csv(path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def indexed(path):
    rows = read_csv(path)
    values = {row["benchmark"]: row for row in rows}
    if len(rows) != 24 or len(values) != len(rows):
        raise SystemExit(f"{path} must contain each of the 24 F049 benchmarks exactly once")
    return values


def positive(value):
    value = float(value)
    if not math.isfinite(value) or value <= 0:
        raise SystemExit("F049 timings and budgets must be finite and positive")
    return value


def write_csv(path, rows):
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def summarize(rows, budget):
    expected = {(i, name) for i in range(1, ROUNDS + 1) for name in budget}
    keys = [(int(row["round"]), row["benchmark"]) for row in rows]
    if len(keys) != len(expected) or set(keys) != expected:
        raise SystemExit("F049 needs all 24 benchmarks exactly once in each of six rounds")
    for row in rows:
        order = "r,stata" if int(row["round"]) % 2 else "stata,r"
        if row["process_order"] != order:
            raise SystemExit("F049 process order must alternate across the six rounds")
        ratio = positive(row["stata_seconds"]) / positive(row["r_seconds"])
        if positive(row["stata_over_r"]) != ratio:
            raise SystemExit("F049 raw ratio does not match its recorded timings")
        if positive(row["max_stata_over_r"]) != positive(budget[row["benchmark"]]["max_stata_over_r"]):
            raise SystemExit("F049 raw ratio changed the contracted ceiling")
    out = []
    for name in sorted(budget):
        cell = [row for row in rows if row["benchmark"] == name]
        ratio = statistics.median(positive(row["stata_over_r"]) for row in cell)
        limit = positive(budget[name]["max_stata_over_r"])
        out.append(dict(
            benchmark=name,
            stata_seconds=f"{statistics.median(positive(row['stata_seconds']) for row in cell):.6g}",
            r_seconds=f"{statistics.median(positive(row['r_seconds']) for row in cell):.6g}",
            stata_over_r=f"{ratio:.6g}", max_stata_over_r=f"{limit:.6g}",
            passed=str(int(ratio <= limit)), ratio_statistic="median_paired_ratio", rounds=str(ROUNDS)))
    return out


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    raw = BUILD / "r-ratio-rounds"
    if raw.exists():
        raw.rename(BUILD / f"r-ratio-rounds.previous-{time.time_ns()}")
    raw.mkdir()
    execution = dict(rounds=ROUNDS, started_ns=time.time_ns(),
                     stata_command=stata_command(),
                     stata_resolved=shutil.which(stata_command()), runs=[])
    source = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True)
    execution["source_commit"] = source.stdout.strip() if source.returncode == 0 else None
    execution["instrument_sha256"] = {
        path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
        for path in ("tools/bench/run-f049-ratio.py", "tools/bench/f049-r-reference.R", "tests/stata/test-f049.do")}
    def save_execution():
        (raw / "run.json").write_text(json.dumps(execution, indent=2) + "\n")
    save_execution()
    paths = (LOG, BUILD / "results.csv", BUILD / "r-results.csv", BUILD / "relative-results.csv")
    for path in (*paths, BUILD / "r-stata-ratio.csv", BUILD / "r-ratio-rounds.csv"):
        path.unlink(missing_ok=True)
    prepare_build(ROOT)
    run(["Rscript", "tools/parity/generators/f049/generate.R"])
    budget = indexed(ROOT / "tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv")
    rows = []
    for round_index in range(1, ROUNDS + 1):
        directory = raw / f"round-{round_index:02d}"
        directory.mkdir()
        for path in paths:
            path.unlink(missing_ok=True)
        order = ("r", "stata") if round_index % 2 else ("stata", "r")
        print(f"F049 complete paired round {round_index}/{ROUNDS}: {','.join(order)}", flush=True)
        # Preserve partial outputs and logs even when a process or assertion fails.
        try:
            for language in order:
                entry = dict(round=round_index, position=order.index(language) + 1,
                             language=language, started_ns=time.time_ns(), status="running")
                execution["runs"].append(entry)
                save_execution()
                try:
                    if language == "r":
                        run(["Rscript", "tools/bench/f049-r-reference.R", str(ROOT)], directory / "R.log")
                    else:
                        run_stata(ROOT, ROOT / "tests/stata/test-f049.do")
                    entry["status"] = "complete"
                except BaseException as error:
                    entry.update(status="failed", error=str(error))
                    raise
                finally:
                    entry["finished_ns"] = time.time_ns()
                    save_execution()
        finally:
            for path in paths:
                if path.is_file():
                    shutil.copy2(path, directory / path.name)
        stata = indexed(directory / "results.csv")
        reference = indexed(directory / "r-results.csv")
        if set(stata) != set(budget) or set(reference) != set(budget):
            raise SystemExit("F049 timing outputs do not match the contracted benchmark inventory")
        for name in sorted(budget):
            st = positive(stata[name]["seconds"])
            rt = positive(reference[name]["r_seconds"])
            rows.append(dict(round=round_index, process_order=','.join(order), benchmark=name,
                             stata_seconds=st, r_seconds=rt, stata_over_r=st / rt,
                             max_stata_over_r=positive(budget[name]["max_stata_over_r"])))
        write_csv(BUILD / "r-ratio-rounds.csv", rows)
    out = summarize(rows, budget)
    write_csv(BUILD / "r-stata-ratio.csv", out)
    execution.update(status="complete", finished_ns=time.time_ns())
    save_execution()
    for row in out:
        verdict = "PASS" if row["passed"] == "1" else "FAIL"
        print(("{benchmark}: " + verdict + " median paired Stata/R ratio {stata_over_r}; ceiling {max_stata_over_r} "
               "(six rounds; marginal medians Stata {stata_seconds}s, R {r_seconds}s)").format(**row))
    failures = [row["benchmark"] for row in out if row["passed"] != "1"]
    if failures:
        raise SystemExit("F049 median paired ratio exceeds the unchanged ceiling: " + ", ".join(failures))


if __name__ == "__main__":
    main()
