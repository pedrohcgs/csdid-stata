#!/usr/bin/env python3
"""Run deterministic randomized R-vs-Stata differential checks."""

from __future__ import annotations

import csv
import math
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "adversarial-differential"
STATA_CMD = os.environ.get("STATA_CMD", "stata-mp")


@dataclass(frozen=True)
class Scenario:
    name: str
    method: str
    panel: bool
    stata_id: bool
    weights: bool
    covariates: bool
    unbalanced: bool
    cluster: bool = False
    notyet: bool = False
    base_period: str = "varying"
    anticipation: int = 0
    near_overlap: bool = False
    att_tol: float = 1e-6
    se_tol: float = 1e-5
    crit_tol: float = 1e-8
    bootstrap: bool = False
    cband: bool = True
    boot_iters: int = 49
    boot_seed: int = 20260707
    compare_aggte: bool = False
    compare_vcov: bool = False
    min_finite: int = 1
    expect_all_missing: bool = False
    moderate_overlap: bool = False


SCENARIOS = [
    Scenario("balanced_reg_covariates", "reg", True, True, False, True, False, compare_vcov=True),
    Scenario("balanced_dr_weighted_covariates", "dr", True, True, True, True, False, se_tol=5e-5),
    Scenario("repeated_ipw_weighted", "ipw", False, False, True, True, False, se_tol=5e-5),
    Scenario("unbalanced_id_as_rc_dr_weighted", "dr", True, True, True, True, True, se_tol=5e-5),
    Scenario("balanced_reg_near_collinear_weighted", "reg", True, True, True, True, False, se_tol=5e-5),
    Scenario("clustered_reg_covariates", "reg", True, True, False, True, False, cluster=True, se_tol=5e-5, compare_vcov=True),
    Scenario("plain_unbalanced_reg", "reg", True, True, False, False, True, se_tol=5e-5, compare_aggte=True),
    Scenario(
        "notyet_anticipation_universal_dr",
        "dr",
        True,
        True,
        True,
        True,
        False,
        notyet=True,
        base_period="universal",
        anticipation=1,
        se_tol=5e-5,
    ),
    Scenario(
        "rc_near_overlap_dr_weighted",
        "dr",
        False,
        False,
        True,
        True,
        False,
        near_overlap=True,
        se_tol=7.5e-5,
        min_finite=0,
        expect_all_missing=True,
    ),
    Scenario(
        "rc_moderate_overlap_dr_weighted",
        "dr",
        False,
        False,
        True,
        True,
        False,
        moderate_overlap=True,
        se_tol=7.5e-5,
    ),
    Scenario(
        "bootstrap_balanced_reg",
        "reg",
        True,
        True,
        False,
        False,
        False,
        bootstrap=True,
        boot_seed=20260731,
        se_tol=1e-8,
        compare_aggte=True,
    ),
    Scenario(
        "bootstrap_balanced_dr_covariates",
        "dr",
        True,
        True,
        False,
        True,
        False,
        bootstrap=True,
        boot_seed=20260732,
        se_tol=5e-5,
    ),
    Scenario(
        "bootstrap_weighted_ipw_rc",
        "ipw",
        False,
        False,
        True,
        True,
        False,
        bootstrap=True,
        boot_seed=20260733,
        se_tol=5e-5,
    ),
    Scenario(
        "bootstrap_clustered_reg",
        "reg",
        True,
        True,
        False,
        False,
        False,
        cluster=True,
        bootstrap=True,
        boot_seed=20260734,
        se_tol=5e-5,
    ),
]


def make_data(seed: int, scenario: Scenario) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    n_units = 220
    periods = np.arange(1, 7)
    ids = np.arange(1, n_units + 1)
    rows = []
    for i in ids:
        if i <= 60:
            g = 0
        elif i <= 110:
            g = 3
        elif i <= 165:
            g = 4
        else:
            g = 5
        unit_shock = rng.normal(scale=0.4)
        base_weight = 0.7 + (i % 11) / 8
        for t in periods:
            if scenario.unbalanced and ((i % 17 == 0 and t in (2, 5)) or (i % 23 == 0 and t == 4)):
                continue
            if scenario.near_overlap or scenario.moderate_overlap:
                if scenario.near_overlap:
                    overlap_shift = 0 if g == 0 else 1.25 + 0.15 * (g == 4) - 0.10 * (g == 5)
                    overlap_sd = 0.18
                else:
                    overlap_shift = 0 if g == 0 else 0.55 + 0.05 * (g == 4) - 0.03 * (g == 5)
                    overlap_sd = 0.32
                x1 = overlap_shift + 0.05 * math.sin(i / 9) + t / 40 + rng.normal(scale=overlap_sd)
            else:
                x1 = math.sin(i / 9) + t / 8 + rng.normal(scale=0.1)
            if scenario.name == "balanced_reg_near_collinear_weighted":
                x2 = x1 + 1e-3 * math.cos(i + t)
            else:
                x2 = math.cos(i / 13) + (i % 5) / 7 + rng.normal(scale=0.1)
            treated = int(g > 0 and t >= g)
            effect = (0.35 + 0.04 * (g == 4) - 0.02 * (g == 5)) * treated
            y = 1.0 + 0.25 * x1 - 0.15 * x2 + 0.08 * t + unit_shock + effect + rng.normal(scale=0.25)
            w = base_weight * (1 + 0.03 * t)
            if i % 19 == 0:
                w *= 4.5
            rows.append(
                {
                    "id": i,
                    "time": t,
                    "g": g,
                    "state": (i % 9) + 1,
                    "y": y,
                    "x1": x1,
                    "x2": x2,
                    "w": w,
                }
            )
    d = pd.DataFrame(rows)
    return d.sample(frac=1, random_state=seed + 1000).reset_index(drop=True)


def write_r_script(path: Path, scenarios: list[Scenario]) -> None:
    lines = [
        "suppressPackageStartupMessages(library(did))",
        "args <- commandArgs(trailingOnly = TRUE)",
        "build <- args[[1]]",
        "as_num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)[1]",
        "write_vcov <- function(out, name) {",
        "  keep <- which(!is.na(out$att) & abs((out$t - out$group) + 1) > 1e-8)",
        "  V <- as.matrix(out$V_analytical) / out$n",
        "  rows <- list()",
        "  ix <- 1L",
        "  if (length(keep) > 1) {",
        "    for (rr in seq_along(keep)) {",
        "      for (cc in seq_along(keep)) {",
        "        rows[[ix]] <- data.frame(",
        "          row_group=out$group[keep[rr]], row_time=out$t[keep[rr]],",
        "          col_group=out$group[keep[cc]], col_time=out$t[keep[cc]],",
        "          cov=V[keep[rr], keep[cc]])",
        "        ix <- ix + 1L",
        "      }",
        "    }",
        "  }",
        "  ans <- if (length(rows)) do.call(rbind, rows) else data.frame(row_group=numeric(), row_time=numeric(), col_group=numeric(), col_time=numeric(), cov=numeric())",
        "  write.csv(ans, file.path(build, paste0(name, '-r-vcov.csv')), row.names=FALSE)",
        "}",
        "write_aggte <- function(out, name, type, bootstrap, biters, cband) {",
        "  ag <- aggte(out, type=type, bstrap=bootstrap, biters=if (bootstrap) biters else NULL, cband=if (bootstrap) cband else NULL, na.rm=TRUE)",
        "  if (is.null(ag$att.egt)) {",
        "    ans <- data.frame(type=type, egt=NA_real_, att=ag$overall.att, se=ag$overall.se, overall_att=ag$overall.att, overall_se=ag$overall.se, crit_val=NA_real_)",
        "  } else {",
        "    crit <- ag$crit.val.egt",
        "    if (is.null(crit)) crit <- rep(NA_real_, length(ag$att.egt))",
        "    ans <- data.frame(type=type, egt=ag$egt, att=ag$att.egt, se=ag$se.egt, overall_att=as_num(ag$overall.att), overall_se=as_num(ag$overall.se), crit_val=crit)",
        "  }",
        "  write.csv(ans, file.path(build, paste0(name, '-r-aggte-', type, '.csv')), row.names=FALSE)",
        "}",
        "run_one <- function(name, method, panel, weights, covariates, cluster, notyet, base_period, anticipation, bootstrap, cband, biters, seed, compare_aggte, compare_vcov) {",
        "  d <- read.csv(file.path(build, paste0(name, '.csv')))",
        "  xf <- if (covariates) ~ x1 + x2 else ~ 1",
        "  if (bootstrap) set.seed(seed)",
        "  out <- att_gt(",
        "    yname='y', tname='time', idname=if (panel) 'id' else NULL,",
        "    gname='g', xformla=xf, data=d, panel=panel,",
        "    weightsname=if (weights) 'w' else NULL,",
        "    clustervars=if (cluster) 'state' else NULL,",
        "    control_group=if (notyet) 'notyettreated' else 'nevertreated',",
        "    base_period=base_period, anticipation=anticipation,",
        "    est_method=method, bstrap=bootstrap, cband=bootstrap && cband, biters=biters,",
        "    allow_unbalanced_panel=TRUE,",
        "    print_details=FALSE)",
        "  ans <- data.frame(group=out$group, time=out$t, att=out$att, se=out$se, crit_val=as_num(out$c))",
        "  write.csv(ans, file.path(build, paste0(name, '-r.csv')), row.names=FALSE)",
        "  if (compare_vcov) write_vcov(out, name)",
        "  if (compare_aggte) {",
        "    rng_after_attgt <- if (exists('.Random.seed', envir=.GlobalEnv)) .Random.seed else NULL",
        "    for (type in c('simple', 'group', 'dynamic', 'calendar')) {",
        "      if (!is.null(rng_after_attgt)) .Random.seed <<- rng_after_attgt",
        "      write_aggte(out, name, type, bootstrap, biters, cband)",
        "    }",
        "  }",
        "}",
    ]
    for s in scenarios:
        panel = "TRUE" if s.panel else "FALSE"
        weights = "TRUE" if s.weights else "FALSE"
        covariates = "TRUE" if s.covariates else "FALSE"
        cluster = "TRUE" if s.cluster else "FALSE"
        notyet = "TRUE" if s.notyet else "FALSE"
        bootstrap = "TRUE" if s.bootstrap else "FALSE"
        cband = "TRUE" if s.cband else "FALSE"
        compare_aggte = "TRUE" if s.compare_aggte else "FALSE"
        compare_vcov = "TRUE" if s.compare_vcov else "FALSE"
        lines.append(
            f"run_one('{s.name}', '{s.method}', {panel}, {weights}, {covariates}, "
            f"{cluster}, {notyet}, '{s.base_period}', {s.anticipation}, "
            f"{bootstrap}, {cband}, {s.boot_iters}, {s.boot_seed}, {compare_aggte}, {compare_vcov})"
        )
    path.write_text("\n".join(lines) + "\n")


def write_stata_script(path: Path, scenarios: list[Scenario]) -> None:
    lines = [
        "version 15",
        "clear all",
        "set more off",
        f'adopath ++ "{ROOT / "src" / "ado"}"',
        f'adopath ++ "{ROOT / "src" / "mata"}"',
        f'local build "{BUILD}"',
    ]
    for s in scenarios:
        cmd_parts = ["csdid y"]
        if s.covariates:
            cmd_parts.append("x1 x2")
        if s.weights:
            cmd_parts.append("[iw=w]")
        cmd_parts.append(f", time(time) gvar(g) method({s.method})")
        if s.stata_id:
            cmd_parts.append("id(id)")
        if s.cluster:
            cmd_parts.append("cluster(state)")
        if s.notyet:
            cmd_parts.append("notyettreated")
        if s.base_period == "universal":
            cmd_parts.append("universal")
        if s.anticipation:
            cmd_parts.append(f"anticipation({s.anticipation})")
        if s.bootstrap:
            boot = f"wboot(reps({s.boot_iters}) rseed({s.boot_seed}))"
            if not s.cband:
                boot = f"{boot} pointwise"
            cmd_parts.append(boot)
        else:
            cmd_parts.append("analytical")
        cmd = " ".join(cmd_parts)
        lines.extend(
            [
                f"import delimited using \"`build'/{s.name}.csv\", clear asdouble",
                f"quietly {cmd}",
                "matrix A = e(attgt)",
                "clear",
                "svmat double A, names(col)",
                "generate double crit_val = e(crit_val)",
                f"export delimited using \"`build'/{s.name}-stata.csv\", replace",
            ]
        )
        if s.compare_vcov:
            lines.extend(
                [
                    "matrix A = e(attgt)",
                    "matrix V = e(V)",
                    "tempname P",
                    "local post_k = 0",
                    "forvalues i = 1/`=rowsof(A)' {",
                    "    if missing(A[`i', 4]) continue",
                    "    if abs(A[`i', 3] + 1) < 1e-8 continue",
                    "    local ++post_k",
                    "    if `post_k' == 1 matrix `P' = (A[`i', 1], A[`i', 2])",
                    "    else matrix `P' = (`P' \\ (A[`i', 1], A[`i', 2]))",
                    "}",
                    "clear",
                    "if `post_k' > 0 {",
                    "    set obs `=`post_k' * `post_k''",
                    "    generate double row_group = .",
                    "    generate double row_time = .",
                    "    generate double col_group = .",
                    "    generate double col_time = .",
                    "    generate double cov = .",
                    "    local outrow = 0",
                    "    forvalues rr = 1/`post_k' {",
                    "        forvalues cc = 1/`post_k' {",
                    "            local ++outrow",
                    "            replace row_group = `P'[`rr', 1] in `outrow'",
                    "            replace row_time = `P'[`rr', 2] in `outrow'",
                    "            replace col_group = `P'[`cc', 1] in `outrow'",
                    "            replace col_time = `P'[`cc', 2] in `outrow'",
                    "            replace cov = V[`rr', `cc'] in `outrow'",
                    "        }",
                    "    }",
                    "}",
                    f"export delimited using \"`build'/{s.name}-stata-vcov.csv\", replace",
                ]
            )
        if s.compare_aggte:
            for agg_type in ("simple", "group", "dynamic", "calendar"):
                lines.extend(
                    [
                        f"import delimited using \"`build'/{s.name}.csv\", clear asdouble",
                        f"quietly {cmd}",
                        f"quietly csdid_stats, type({agg_type}) na_rm",
                        "matrix G = e(aggte)",
                        "clear",
                        "svmat double G, names(col)",
                        f'generate str12 type = "{agg_type}"',
                        "capture generate double crit_val = e(crit_val)",
                        "capture confirm variable crit_val",
                        "if _rc generate double crit_val = .",
                        f"export delimited using \"`build'/{s.name}-stata-aggte-{agg_type}.csv\", replace",
                    ]
                )
    path.write_text("\n".join(lines) + "\n")


def run(cmd: list[str], cwd: Path = ROOT) -> None:
    proc = subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        print(proc.stdout)
        raise SystemExit(proc.returncode)


def finite_number(value: object) -> bool:
    try:
        x = float(value)
    except (TypeError, ValueError):
        return False
    return math.isfinite(x)


def missing_or_nan(value: object) -> bool:
    try:
        return pd.isna(value) or not math.isfinite(float(value))
    except (TypeError, ValueError):
        return True


def abs_diff_or_zero(left: object, right: object) -> float:
    if missing_or_nan(left) and missing_or_nan(right):
        return 0.0
    return abs(float(left) - float(right))


def compare_vcov(s: Scenario, rows: list[dict[str, object]], failures: list[str]) -> None:
    r = pd.read_csv(BUILD / f"{s.name}-r-vcov.csv")
    st = pd.read_csv(BUILD / f"{s.name}-stata-vcov.csv")
    st = st.rename(columns={c: c.lower() for c in st.columns})
    keys = ["row_group", "row_time", "col_group", "col_time"]
    merged = r.merge(st, on=keys, suffixes=("_r", "_stata"), how="outer", indicator=True)
    if not (merged["_merge"] == "both").all():
        failures.append(f"{s.name}: R/Stata e(V) keys differ")
    for _, row in merged[merged["_merge"] == "both"].iterrows():
        cov_diff = abs_diff_or_zero(row["cov_r"], row["cov_stata"])
        passed = cov_diff <= s.se_tol
        if not passed:
            failures.append(
                f"{s.name} V row=({row['row_group']},{row['row_time']}) "
                f"col=({row['col_group']},{row['col_time']}): cov_diff={cov_diff}"
            )
        rows.append(
            {
                "scenario": s.name,
                "metric": "vcov",
                "group": row["row_group"],
                "time": row["row_time"],
                "target": f"{row['col_group']}:{row['col_time']}",
                "att_diff": "",
                "se_diff": "",
                "crit_diff": "",
                "cov_diff": cov_diff,
                "att_tol": s.att_tol,
                "se_tol": s.se_tol,
                "crit_tol": s.crit_tol,
                "passed": int(passed),
            }
        )


def compare_aggte(s: Scenario, rows: list[dict[str, object]], failures: list[str]) -> None:
    for agg_type in ("simple", "group", "dynamic", "calendar"):
        r = pd.read_csv(BUILD / f"{s.name}-r-aggte-{agg_type}.csv")
        st = pd.read_csv(BUILD / f"{s.name}-stata-aggte-{agg_type}.csv")
        st = st.rename(columns={c: c.lower() for c in st.columns})
        if agg_type == "simple":
            merged = r.head(1).copy()
            if st.empty:
                failures.append(f"{s.name}: Stata simple aggte output is empty")
                continue
            merged["att_stata"] = st.iloc[0]["att"]
            merged["se_stata"] = st.iloc[0]["se"]
            merged["overall_att_stata"] = st.iloc[0].get("overall_att", math.nan)
            merged["overall_se_stata"] = st.iloc[0].get("overall_se", math.nan)
        else:
            keep = ["egt", "att", "se", "overall_att", "overall_se"]
            merged = r[keep].merge(st[keep], on=["egt"], suffixes=("_r", "_stata"), how="outer", indicator=True)
            if not (merged["_merge"] == "both").all():
                failures.append(f"{s.name}: R/Stata {agg_type} aggte keys differ")
        for _, row in merged.iterrows():
            att_r = row.get("att_r", row.get("att"))
            se_r = row.get("se_r", row.get("se"))
            overall_att_r = row.get("overall_att_r", row.get("overall_att"))
            overall_se_r = row.get("overall_se_r", row.get("overall_se"))
            att_st = row.get("att_stata")
            se_st = row.get("se_stata")
            overall_att_st = row.get("overall_att_stata")
            overall_se_st = row.get("overall_se_stata")
            att_diff = abs_diff_or_zero(att_r, att_st)
            se_diff = abs_diff_or_zero(se_r, se_st)
            overall_att_diff = abs_diff_or_zero(overall_att_r, overall_att_st)
            overall_se_diff = abs_diff_or_zero(overall_se_r, overall_se_st)
            passed = (
                att_diff <= s.att_tol
                and se_diff <= s.se_tol
                and overall_att_diff <= s.att_tol
                and overall_se_diff <= s.se_tol
            )
            if not passed:
                failures.append(
                    f"{s.name} aggte({agg_type}) egt={row.get('egt', '')}: "
                    f"att_diff={att_diff}, se_diff={se_diff}, "
                    f"overall_att_diff={overall_att_diff}, overall_se_diff={overall_se_diff}"
                )
            rows.append(
                {
                    "scenario": s.name,
                    "metric": f"aggte_{agg_type}",
                    "group": "",
                    "time": row.get("egt", ""),
                    "target": "",
                    "att_diff": max(att_diff, overall_att_diff),
                    "se_diff": max(se_diff, overall_se_diff),
                    "crit_diff": "",
                    "cov_diff": "",
                    "att_tol": s.att_tol,
                    "se_tol": s.se_tol,
                    "crit_tol": s.crit_tol,
                    "passed": int(passed),
                }
            )


def compare_outputs(scenarios: list[Scenario]) -> None:
    rows = []
    failures = []
    for s in scenarios:
        r = pd.read_csv(BUILD / f"{s.name}-r.csv")
        st = pd.read_csv(BUILD / f"{s.name}-stata.csv")
        st = st.rename(columns={c: c.lower() for c in st.columns})
        if "group" not in st.columns and "c1" in st.columns:
            st = st.rename(columns={"c1": "group", "c2": "time", "c4": "att", "c5": "se"})
        keep = ["group", "time", "att", "se", "crit_val"]
        merged = r[keep].merge(st[keep], on=["group", "time"], suffixes=("_r", "_stata"), how="outer", indicator=True)
        if not (merged["_merge"] == "both").all():
            failures.append(f"{s.name}: R/Stata ATT(g,t) keys differ")
        finite_matches = 0
        for _, row in merged[merged["_merge"] == "both"].iterrows():
            att_diff = abs_diff_or_zero(row["att_r"], row["att_stata"])
            se_diff = abs_diff_or_zero(row["se_r"], row["se_stata"])
            crit_diff = ""
            if s.bootstrap:
                crit_diff = abs_diff_or_zero(row.get("crit_val_r"), row.get("crit_val_stata"))
            if finite_number(row["att_r"]) and finite_number(row["att_stata"]) and finite_number(row["se_r"]) and finite_number(row["se_stata"]):
                finite_matches += 1
            passed = att_diff <= s.att_tol and se_diff <= s.se_tol
            if s.bootstrap:
                passed = passed and float(crit_diff) <= s.crit_tol
            if not passed:
                failures.append(f"{s.name} g={row['group']} t={row['time']}: att_diff={att_diff}, se_diff={se_diff}, crit_diff={crit_diff}")
            rows.append(
                {
                    "scenario": s.name,
                    "metric": "attgt",
                    "group": row["group"],
                    "time": row["time"],
                    "target": "",
                    "att_diff": att_diff,
                    "se_diff": se_diff,
                    "crit_diff": crit_diff,
                    "cov_diff": "",
                    "att_tol": s.att_tol,
                    "se_tol": s.se_tol,
                    "crit_tol": s.crit_tol,
                    "passed": int(passed),
                }
            )
        if s.expect_all_missing:
            if finite_matches != 0:
                failures.append(f"{s.name}: expected all-missing parity but found {finite_matches} finite matched cells")
        elif finite_matches < s.min_finite:
            failures.append(f"{s.name}: only {finite_matches} finite matched cells; required at least {s.min_finite}")
        if s.compare_vcov:
            compare_vcov(s, rows, failures)
        if s.compare_aggte:
            compare_aggte(s, rows, failures)
    with (BUILD / "comparison.csv").open("w", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "scenario",
                "metric",
                "group",
                "time",
                "target",
                "att_diff",
                "se_diff",
                "crit_diff",
                "cov_diff",
                "att_tol",
                "se_tol",
                "crit_tol",
                "passed",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)
    if failures:
        for failure in failures:
            print(f"adversarial differential failure: {failure}", file=sys.stderr)
        raise SystemExit(1)


def main() -> int:
    BUILD.mkdir(parents=True, exist_ok=True)
    for idx, scenario in enumerate(SCENARIOS):
        make_data(20260707 + idx, scenario).to_csv(BUILD / f"{scenario.name}.csv", index=False)
    r_script = BUILD / "run-r.R"
    stata_script = BUILD / "run-stata.do"
    write_r_script(r_script, SCENARIOS)
    write_stata_script(stata_script, SCENARIOS)
    run(["Rscript", str(r_script), str(BUILD)])
    run([STATA_CMD, "-b", "do", str(stata_script)])
    compare_outputs(SCENARIOS)
    print(f"adversarial differential gate passed; see {BUILD / 'comparison.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
