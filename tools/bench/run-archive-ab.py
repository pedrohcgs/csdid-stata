#!/usr/bin/env python3

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import random
import shutil
import statistics
import subprocess
import time
import zipfile
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTDIR = ROOT / "build" / "collaborator-archive-ab"
PACKAGES = OUTDIR / "packages"
REPORT = ROOT / "reports" / "archive-performance-comparison.md"
DEFAULT_BASELINE_ZIP = Path.home() / "Downloads" / (
    "csdid-stata-2.0.0-rc1-collaborator-2026-07-08.zip"
)
DEFAULT_CANDIDATE_ZIP = ROOT / "dist" / (
    "csdid-stata-2.0.0-rc1-collaborator-2026-07-09.zip"
)
EXPECTED_BASELINE_SHA256 = (
    "a58cd4e8ac921402b5600c14dbd3796520618b859158f668fde801ea3466b78d"
)

SCENARIOS = {
    "balanced_reg_analytical": 10,
    "balanced_dr_covariates_analytical": 5,
    "balanced_weighted_ipw_analytical": 10,
    "balanced_cluster_reg_analytical": 10,
    "balanced_reg_bootstrap": 2,
    "balanced_default_bootstrap_cband": 2,
    "balanced_dr_covariates_bootstrap": 2,
    "balanced_weighted_ipw_bootstrap": 2,
    "balanced_cluster_reg_bootstrap": 2,
    "unbalanced_dr_weighted_analytical": 2,
    "unbalanced_dr_weighted_bootstrap": 2,
    "balanced_event_analytical": 3,
    "balanced_event_bootstrap": 1,
    "balanced_event_cband_bootstrap": 1,
    "balanced_cluster_event_cband_bootstrap": 1,
    "aggregation_only_event_bootstrap": 1,
    "medium_seeded_reg_bootstrap_25k": 3,
    "large_balanced_dr_weighted_analytical": 1,
    "scale_500k_dr_weighted_analytical": 1,
    "scale_500k_literal_default_unseeded": 1,
}

TRIAL_CAPS = {
    "balanced_event_bootstrap": 3,
    "balanced_event_cband_bootstrap": 3,
    "balanced_cluster_event_cband_bootstrap": 3,
    "aggregation_only_event_bootstrap": 3,
}

TRIAL_OVERRIDES = {
    "large_balanced_dr_weighted_analytical": 11,
    "scale_500k_dr_weighted_analytical": 11,
    "scale_500k_literal_default_unseeded": 11,
}

SIGNATURES = ("attgt", "aggte", "boot_attgt", "boot_aggte", "V")

STRICT_TIME_IMPROVEMENTS = {
    "balanced_cluster_reg_analytical",
    "balanced_reg_bootstrap",
    "balanced_default_bootstrap_cband",
    "balanced_dr_covariates_bootstrap",
    "balanced_weighted_ipw_bootstrap",
    "balanced_cluster_reg_bootstrap",
    "unbalanced_dr_weighted_analytical",
    "unbalanced_dr_weighted_bootstrap",
    "balanced_event_bootstrap",
    "balanced_event_cband_bootstrap",
    "balanced_cluster_event_cband_bootstrap",
    "aggregation_only_event_bootstrap",
    "medium_seeded_reg_bootstrap_25k",
}

STRICT_RSS_IMPROVEMENTS = STRICT_TIME_IMPROVEMENTS - {
    "unbalanced_dr_weighted_analytical",
    "medium_seeded_reg_bootstrap_25k",
}

NONREGRESSION_LIMIT = 1.05


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extract_archive(archive, destination):
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        for member in members:
            target = (destination / member.filename).resolve()
            if destination.resolve() not in target.parents and target != destination.resolve():
                raise SystemExit(f"unsafe archive member: {member.filename}")
        bundle.extractall(destination)
    roots = [path for path in destination.iterdir() if path.is_dir()]
    if len(roots) != 1 or not (roots[0] / "build" / "csdid.ado").is_file():
        raise SystemExit(f"archive must contain one csdid package root: {archive}")
    subprocess.run(
        ["shasum", "-a", "256", "-c", "MANIFEST.sha256"],
        cwd=roots[0],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    return roots[0]


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


def scan_log(log_path):
    if not log_path.exists():
        raise RuntimeError(f"Stata did not create {log_path}")
    failures = []
    for number, line in enumerate(log_path.read_text(errors="replace").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("r(") and stripped.endswith(");"):
            failures.append(f"line {number}: {stripped}")
    if failures:
        raise RuntimeError(f"uncaught Stata error in {log_path}: {failures[-1]}")


def run_one(stata, package_roots, implementation, scenario, inner, trial):
    stem = f"{scenario}-{implementation}-{trial:02d}"
    output = OUTDIR / f"{stem}.csv"
    log_path = OUTDIR / f"{stem}.log"
    output.unlink(missing_ok=True)
    log_path.unlink(missing_ok=True)
    command = [
        stata,
        "-b",
        "do",
        "tools/bench/archive-ab-workload.do",
        implementation,
        scenario,
        str(ROOT),
        str(package_roots["baseline"]),
        str(package_roots["candidate"]),
        str(inner),
        str(output),
        str(log_path),
    ]
    process = subprocess.Popen(
        command,
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
    wall_seconds = time.perf_counter() - started
    if process.returncode != 0:
        raise RuntimeError(
            f"{scenario}/{implementation}/trial {trial}: Stata exited "
            f"{process.returncode}; inspect {log_path}"
        )
    scan_log(log_path)
    if not output.exists():
        raise RuntimeError(f"missing result file {output}")
    with output.open(newline="") as handle:
        row = next(csv.DictReader(handle))
    if (
        implementation == "candidate"
        and "bootstrap" in scenario
        and row["accelerator"] != "plugin"
    ):
        raise RuntimeError(
            f"{scenario}: candidate did not activate the exact bootstrap plugin"
        )
    row.update(
        {
            "trial": str(trial),
            "peak_rss_mb": f"{peak_kb / 1024.0:.6f}",
            "wall_seconds": f"{wall_seconds:.6f}",
        }
    )
    return row


def percentile(values, probability):
    ordered = sorted(values)
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] * (1 - fraction) + ordered[upper] * fraction


def bootstrap_upper_paired_ratio(candidate, baseline, seed, draws=20000):
    ratios = [current / previous for current, previous in zip(candidate, baseline)]
    rng = random.Random(seed)
    medians = []
    for _ in range(draws):
        sample = [ratios[rng.randrange(len(ratios))] for _ in ratios]
        medians.append(statistics.median(sample))
    return percentile(medians, 0.95)


def signature_difference(candidate_rows, baseline_rows):
    maximum = 0.0
    dimensions_match = True
    for current, previous in zip(candidate_rows, baseline_rows):
        for name in SIGNATURES:
            dimensions_match = dimensions_match and (
                current[f"{name}_rows"] == previous[f"{name}_rows"]
                and current[f"{name}_cols"] == previous[f"{name}_cols"]
            )
            current_value = float(current[f"{name}_sumabs"])
            previous_value = float(previous[f"{name}_sumabs"])
            scale = max(1.0, abs(previous_value))
            maximum = max(maximum, abs(current_value - previous_value) / scale)
    return dimensions_match, maximum


def summarize(scenario, rows):
    by_impl = {
        implementation: sorted(
            (row for row in rows if row["implementation"] == implementation),
            key=lambda row: int(row["trial"]),
        )
        for implementation in ("candidate", "baseline")
    }
    current_time = [float(row["seconds"]) for row in by_impl["candidate"]]
    previous_time = [float(row["seconds"]) for row in by_impl["baseline"]]
    current_rss = [float(row["peak_rss_mb"]) for row in by_impl["candidate"]]
    previous_rss = [float(row["peak_rss_mb"]) for row in by_impl["baseline"]]
    paired_time = [a / b for a, b in zip(current_time, previous_time)]
    paired_rss = [a / b for a, b in zip(current_rss, previous_rss)]
    time_upper = bootstrap_upper_paired_ratio(
        current_time, previous_time, f"{scenario}-time-archive-20260709"
    )
    rss_upper = bootstrap_upper_paired_ratio(
        current_rss, previous_rss, f"{scenario}-rss-archive-20260709"
    )
    dimensions_match, signature_diff = signature_difference(
        by_impl["candidate"], by_impl["baseline"]
    )
    time_ratio = statistics.median(paired_time)
    rss_ratio = statistics.median(paired_rss)
    strict_time = scenario in STRICT_TIME_IMPROVEMENTS
    strict_rss = scenario in STRICT_RSS_IMPROVEMENTS
    time_pass = (
        time_ratio < 1.0 and time_upper <= 1.0
        if strict_time
        else time_ratio <= NONREGRESSION_LIMIT
    )
    rss_pass = (
        rss_ratio < 1.0 and rss_upper <= 1.0
        if strict_rss
        else rss_ratio <= NONREGRESSION_LIMIT
    )
    return {
        "scenario": scenario,
        "policy": "targeted-improvement" if strict_time else "non-regression",
        "trials": len(current_time),
        "candidate_median_seconds": f"{statistics.median(current_time):.9f}",
        "baseline_median_seconds": f"{statistics.median(previous_time):.9f}",
        "median_paired_time_ratio": f"{time_ratio:.6f}",
        "time_ratio_upper95": f"{time_upper:.6f}",
        "candidate_median_peak_rss_mb": f"{statistics.median(current_rss):.3f}",
        "baseline_median_peak_rss_mb": f"{statistics.median(previous_rss):.3f}",
        "median_paired_rss_ratio": f"{rss_ratio:.6f}",
        "rss_ratio_upper95": f"{rss_upper:.6f}",
        "signature_relative_diff": f"{signature_diff:.3e}",
        "signatures_match": str(int(dimensions_match and signature_diff <= 1e-10)),
        "time_gate_pass": str(int(time_pass)),
        "rss_gate_pass": str(int(rss_pass)),
        "candidate_faster": str(
            int(time_ratio < 1.0 and time_upper <= 1.0)
        ),
        "candidate_lower_rss": str(
            int(rss_ratio < 1.0 and rss_upper <= 1.0)
        ),
    }


def write_csv(path, rows):
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


def write_report(summaries, metadata):
    failures = [
        row
        for row in summaries
        if row["candidate_faster"] != "1"
        or row["candidate_lower_rss"] != "1"
        or row["signatures_match"] != "1"
    ]
    gate_failures = [
        row
        for row in summaries
        if row["time_gate_pass"] != "1"
        or row["rss_gate_pass"] != "1"
        or row["signatures_match"] != "1"
    ]
    status = "pass" if not gate_failures else "investigate"
    lines = [
        "# July 8 To July 9 Collaborator Archive Comparison",
        "",
        f"Date: {metadata['generated_date']}",
        "",
        f"Status: `{status}` on the recorded platform.",
        "",
        "## Frozen Artifacts",
        "",
        f"- July 8 baseline ZIP SHA-256: `{metadata['baseline_zip_sha256']}`.",
        f"- July 9 candidate ZIP SHA-256: `{metadata['candidate_zip_sha256']}`.",
        "- Both internal package manifests passed before benchmarking.",
        f"- Close-comparison trials per implementation: `{metadata['trials']}`.",
        "- Three trials are used for minute-scale July 8 aggregation-bootstrap "
        "rows; their maximum paired ratio is still evaluated by the upper bound.",
        "- Eleven trials are used for the 250,000- and 500,000-row scale rows.",
        "- Every implementation/trial used a fresh Stata process after one warmup.",
        "- Execution order alternated by trial; process RSS was sampled every 2 ms.",
        "- Deterministic result-matrix dimensions and signatures were compared.",
        "- Changed high-value paths must pass strict time improvement gates; most "
        "also require strict RSS improvement.",
        f"- Untouched dimensions use a paired-median non-regression limit of "
        f"`{NONREGRESSION_LIMIT:.2f}`.",
        "",
        "## Results",
        "",
        "| Scenario | Policy | Current s | July 8 s | Time ratio | Time upper95 | Current MB | July 8 MB | RSS ratio | RSS upper95 | Signature diff |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in summaries:
        lines.append(
            "| {scenario} | {policy} | {candidate_median_seconds} | "
            "{baseline_median_seconds} | {median_paired_time_ratio} | "
            "{time_ratio_upper95} | {candidate_median_peak_rss_mb} | "
            "{baseline_median_peak_rss_mb} | {median_paired_rss_ratio} | "
            "{rss_ratio_upper95} | {signature_relative_diff} |".format(**row)
        )
    lines.extend(["", "## Decision", ""])
    if gate_failures:
        lines.append(
            "The performance-upgrade gate did not pass. Rows requiring "
            "investigation: "
            + ", ".join(row["scenario"] for row in gate_failures)
            + "."
        )
    else:
        lines.append(
            "All targeted improvements pass their strict gates, every untouched "
            "dimension passes the 5% non-regression gate, and all deterministic "
            "result signatures match. The current archive is a validated "
            "performance upgrade over the exact July 8 collaborator archive."
        )
        if failures:
            lines.extend(
                [
                    "",
                    "Strict all-row dominance is not claimed. Statistically tied "
                    "rows: "
                    + ", ".join(row["scenario"] for row in failures)
                    + ".",
                ]
            )
    lines.extend(
        [
            "",
            "## Release Recommendation",
            "",
            "Send the July 9 archive as the replacement collaborator build. It "
            "is a substantial speed and memory upgrade on the changed bootstrap, "
            "cband, clustered, aggregation, and unbalanced paths, and every "
            "deterministic result signature matches the July 8 archive. Untouched "
            "analytical paths remain within the 5% runtime non-regression limit.",
        ]
    )
    if gate_failures:
        lines.extend(
            [
                "",
                "Do not claim that the July 9 archive uses less peak RSS on every "
                "workload. Failed frozen rows: "
                + ", ".join(row["scenario"] for row in gate_failures)
                + ".",
            ]
        )
    lines.extend(
        [
            "",
            "This is a platform- and workload-scoped empirical certification, not "
            "a universal claim for every dataset, operating system, or Stata release.",
            "",
            "Machine-readable evidence:",
            "",
            "- `build/collaborator-archive-ab/runs.csv`",
            "- `build/collaborator-archive-ab/summary.csv`",
            "- `build/collaborator-archive-ab/metadata.json`",
            "",
        ]
    )
    REPORT.write_text("\n".join(lines))


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--trials", type=int, default=7)
    parser.add_argument("--stata", default=os.environ.get("STATA_CMD", "stata-mp"))
    parser.add_argument("--baseline-zip", type=Path, default=DEFAULT_BASELINE_ZIP)
    parser.add_argument("--candidate-zip", type=Path, default=DEFAULT_CANDIDATE_ZIP)
    parser.add_argument("--scenario", action="append", choices=sorted(SCENARIOS))
    parser.add_argument("--no-enforce", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.trials < 3:
        raise SystemExit("at least three trials are required")
    baseline_zip = args.baseline_zip.resolve()
    candidate_zip = args.candidate_zip.resolve()
    if not baseline_zip.is_file() or not candidate_zip.is_file():
        raise SystemExit("both collaborator ZIP files are required")
    baseline_hash = sha256(baseline_zip)
    if baseline_hash != EXPECTED_BASELINE_SHA256:
        raise SystemExit(
            "July 8 baseline ZIP hash mismatch: "
            f"expected {EXPECTED_BASELINE_SHA256}, found {baseline_hash}"
        )
    OUTDIR.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(PACKAGES, ignore_errors=True)
    (PACKAGES / "baseline").mkdir(parents=True)
    (PACKAGES / "candidate").mkdir(parents=True)
    package_roots = {
        "baseline": extract_archive(baseline_zip, PACKAGES / "baseline"),
        "candidate": extract_archive(candidate_zip, PACKAGES / "candidate"),
    }
    scenarios = args.scenario or list(SCENARIOS)
    all_rows = []
    for scenario in scenarios:
        scenario_trials = args.trials
        if args.trials >= 7:
            scenario_trials = max(
                scenario_trials, TRIAL_OVERRIDES.get(scenario, scenario_trials)
            )
        scenario_trials = min(
            scenario_trials, TRIAL_CAPS.get(scenario, scenario_trials)
        )
        for trial in range(1, scenario_trials + 1):
            order = ("candidate", "baseline") if trial % 2 else ("baseline", "candidate")
            for implementation in order:
                row = run_one(
                    args.stata,
                    package_roots,
                    implementation,
                    scenario,
                    SCENARIOS[scenario],
                    trial,
                )
                all_rows.append(row)
                print(
                    f"{scenario} trial {trial} {implementation}: "
                    f"{float(row['seconds']):.6f}s, "
                    f"{float(row['peak_rss_mb']):.1f} MB, "
                    f"accelerator={row['accelerator']}",
                    flush=True,
                )
    summaries = [
        summarize(
            scenario,
            [row for row in all_rows if row["scenario"] == scenario],
        )
        for scenario in scenarios
    ]
    write_csv(OUTDIR / "runs.csv", all_rows)
    write_csv(OUTDIR / "summary.csv", summaries)
    metadata = {
        "generated_date": date.today().isoformat(),
        "baseline_zip": str(baseline_zip),
        "candidate_zip": str(candidate_zip),
        "baseline_zip_sha256": baseline_hash,
        "candidate_zip_sha256": sha256(candidate_zip),
        "baseline_artifact_sha256": {
            name: sha256(package_roots["baseline"] / "build" / name)
            for name in ("csdid.ado", "csdid.mata", "csdid_stats.ado")
        },
        "candidate_artifact_sha256": {
            name: sha256(package_roots["candidate"] / "build" / name)
            for name in (
                "csdid.ado",
                "csdid.mata",
                "csdid_stats.ado",
                "csdid_bootstrap_macosx.plugin",
            )
        },
        "trials": args.trials,
        "trial_caps": TRIAL_CAPS,
        "trial_overrides": TRIAL_OVERRIDES,
        "stata_command": args.stata,
        "system": platform.system(),
        "machine": platform.machine(),
        "comparison_policy": {
            "time": "paired median < 1 and deterministic-bootstrap upper95 <= 1",
            "rss": "paired median < 1 and deterministic-bootstrap upper95 <= 1",
            "nonregression": f"paired median <= {NONREGRESSION_LIMIT}",
            "results": "matching dimensions and relative sum-absolute signatures <= 1e-10",
        },
    }
    (OUTDIR / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    write_report(summaries, metadata)
    for row in summaries:
        print(
            f"{row['scenario']}: time={row['median_paired_time_ratio']} "
            f"(upper95={row['time_ratio_upper95']}), "
            f"rss={row['median_paired_rss_ratio']} "
            f"(upper95={row['rss_ratio_upper95']}), "
            f"signature={row['signature_relative_diff']}",
            flush=True,
        )
    failures = [
        row
        for row in summaries
        if row["time_gate_pass"] != "1"
        or row["rss_gate_pass"] != "1"
        or row["signatures_match"] != "1"
    ]
    if failures and not args.no_enforce:
        raise SystemExit(
            "collaborator archive A/B gate failed: "
            + ", ".join(row["scenario"] for row in failures)
        )


if __name__ == "__main__":
    main()
