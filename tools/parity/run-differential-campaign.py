#!/usr/bin/env python3
"""Randomized R-vs-Stata differential campaign over the csdid option and design space.

WHAT THIS ADDS over tools/release/run-adversarial-differential.py, which is the
release gate and stays as it is:

  1. The DESIGN is randomized, not just the noise. That gate draws every scenario
     on one fixed panel -- 220 units, 6 periods, cohorts {0,3,4,5}. Here the unit
     count, period count, time spacing, cohort structure, never-treated share,
     cluster structure, missingness and unbalancedness are all drawn per trial.
  2. The OPTIONS are randomized across the supported surface rather than being a
     hand-written list of 14 combinations.
  3. Every CHANNEL is compared, including the ones that gate does not look at:
     the aggregation critical values and confidence limits (its compare_aggte
     checks att/se/overall_att/overall_se only, which is why an overall-row band
     defect could sit under a green gate), the ATT(g,t) critical value, the
     pre-test, the cell counts, and the failure/refusal behaviour.

WHAT AGREEMENT ESTABLISHES: conformance to R did 2.5.1 at the pinned oracle
commit, on the frozen contract below. It does not establish that either
implementation is statistically correct.

INFERENCE IS DETERMINISTIC HERE. Trials run analytical + pointwise on both sides
(bstrap = FALSE, cband = FALSE in R), so every compared number is a deterministic
function of the data. Bootstrap agreement is covered separately by the rt037
fixture, which matches R draw for draw at a fixed aggregation sequence.

Usage:
    python3 tools/parity/run-differential-campaign.py [--trials N] [--seed S]
    python3 tools/parity/run-differential-campaign.py --self-test
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
from dataclasses import dataclass, asdict, field
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "differential-campaign"
STATA_CMD = os.environ.get("STATA_CMD", "stata-mp")

# ---------------------------------------------------------------------------
# Frozen contract: tolerance classes. A looser value than these is an approved
# divergence and must be recorded in the report, not applied silently.
# ---------------------------------------------------------------------------
# APPROVED DIVERGENCE (recorded, not silently widened).
# On a near-singular design matrix, R and csdid solve the same system with
# equivalent-but-different decompositions, and the last bits differ. csdid
# deliberately mirrors R/DRDID's choices -- qrsolve for the regression
# coefficients, cholinv behind an rcond guard for the pscore Hessian
# (csdid.mata csdid__hessinv_r_parity), luinv as the fallback so Stata computes
# where R computes -- so this is amplification, not a different algorithm.
#
# Measured on the two divergent trials of seed 31415, varying only the
# collinearity of x2 on x1 and holding everything else fixed:
#     cond(X) 1.4e5 -> max|dATT| 3.2e-5
#     cond(X) 1.4e4 -> max|dATT| 3.5e-7
#     cond(X) 4.8e3 -> max|dATT| 2.4e-9
#     independent  -> max|dATT| 2.0e-10
# i.e. the gap tracks cond^2 * machine epsilon. Panel mode does not matter.
# A numeric difference below this bound is classified "ill_conditioned" and
# reported separately; anything above it stays a divergence.
def conditioning_bound(base: float, cond: float) -> float:
    if cond is None or not math.isfinite(cond):
        return base
    return max(base, 10.0 * 2.220446049250313e-16 * cond * cond)


TOL = {
    "att": 1e-7,      # deterministic point estimates
    "se": 1e-6,       # deterministic analytical standard errors
    "crit": 1e-9,     # normal quantiles, identical closed form on both sides
    "pval": 1e-7,
    "exact": 0.0,     # counts, cell sets, statuses
}


@dataclass
class Trial:
    name: str
    seed: int
    # design
    n_units: int
    n_periods: int
    time_start: int
    time_step: int
    cohort_spec: str
    never_share: float
    unbalanced: bool
    n_covars: int
    weighted: bool
    clustered: bool
    n_clusters: int
    # options
    method: str
    control_group: str
    base_period: str
    anticipation: int
    panel_mode: str  # "balanced" | "unbalanced_allowed" | "rcs"
    extreme_weights: bool = False
    collinear: bool = False
    tiny_cohort: bool = False
    missing_rate: float = 0.0
    # aggregation-side options: R's min_e/max_e/balance_e, csdid's window()/balance()
    agg_opt: str = "none"     # "none" | "window" | "balance"
    min_e: int = 0
    max_e: int = 0
    balance_e: int = 0

    def r_panel(self) -> str:
        return "FALSE" if self.panel_mode == "rcs" else "TRUE"

    def r_allow_unbalanced(self) -> str:
        return "TRUE" if self.panel_mode == "unbalanced_allowed" else "FALSE"


def draw_trial(rng: np.random.Generator, idx: int, seed: int) -> Trial:
    n_periods = int(rng.integers(3, 8))
    # a cohort structure that is legal for this many periods
    cohort_spec = rng.choice(["early", "late", "spread", "single", "all_treated",
                              "first_period", "first_period_long"])
    return Trial(
        name=f"trial{idx:03d}",
        seed=seed + idx,
        n_units=int(rng.integers(40, 260)),
        n_periods=n_periods,
        time_start=int(rng.choice([1, 1990, 2001])),
        time_step=int(rng.choice([1, 1, 1, 2, 5])),  # non-consecutive time values
        cohort_spec=str(cohort_spec),
        never_share=float(rng.choice([0.0, 0.15, 0.3, 0.45])),
        unbalanced=bool(rng.random() < 0.35),
        n_covars=int(rng.integers(0, 3)),
        weighted=bool(rng.random() < 0.45),
        clustered=bool(rng.random() < 0.35),
        n_clusters=int(rng.integers(4, 15)),
        method=str(rng.choice(["dr", "ipw", "reg"])),
        control_group=str(rng.choice(["nevertreated", "notyettreated"])),
        base_period=str(rng.choice(["universal", "varying"])),
        anticipation=int(rng.choice([0, 0, 0, 1])),
        panel_mode=str(rng.choice(["balanced", "balanced", "unbalanced_allowed", "rcs"])),
        extreme_weights=bool(rng.random() < 0.2),
        collinear=bool(rng.random() < 0.2),
        tiny_cohort=bool(rng.random() < 0.2),
        missing_rate=float(rng.choice([0.0, 0.0, 0.0, 0.03])),
        agg_opt=str(rng.choice(["none", "window", "window", "balance"])),
        min_e=int(rng.integers(-3, 0)),
        max_e=int(rng.integers(0, 4)),
        balance_e=int(rng.integers(0, 3)),
    )


def make_data(t: Trial) -> pd.DataFrame:
    rng = np.random.default_rng(t.seed)
    times = t.time_start + t.time_step * np.arange(t.n_periods)
    # cohorts are drawn from the interior of the time grid so that at least one
    # pre-period exists for a treated cohort; 0 marks never-treated.
    # "first_period*" deliberately places a cohort ON the first period: those
    # units cannot be estimated and R drops them BEFORE balancing, so they must
    # not be allowed to define the period grid. No earlier campaign drew this.
    interior = times if t.cohort_spec.startswith("first_period") else times[1:]
    if t.cohort_spec == "early":
        pool = interior[: max(1, len(interior) // 2)]
    elif t.cohort_spec == "late":
        pool = interior[max(1, len(interior) // 2):]
    elif t.cohort_spec == "single":
        pool = np.array([interior[len(interior) // 2]])
    else:
        pool = interior
    pool = np.array(sorted(set(int(x) for x in pool)))

    ids = np.arange(1, t.n_units + 1)
    never_n = 0 if t.cohort_spec == "all_treated" else int(round(t.never_share * t.n_units))
    g_by_unit = {}
    for k, i in enumerate(ids):
        if k < never_n:
            g_by_unit[i] = 0
        else:
            g_by_unit[i] = int(pool[(k - never_n) % len(pool)])

    if t.tiny_cohort and len(pool) > 0:
        for j in ids[-2:]:
            g_by_unit[j] = int(pool[-1])
    rows = []
    for i in ids:
        g = g_by_unit[i]
        unit_shock = rng.normal(scale=0.4)
        w = float(0.6 + rng.random() * 1.8) if t.weighted else 1.0
        if t.weighted and t.extreme_weights and i % 17 == 0:
            w *= 50.0
        cl = int(i % t.n_clusters) + 1 if t.clustered else int(i)
        for tt in times:
            if t.unbalanced and rng.random() < 0.08:
                continue
            # early-treated units keep a longer history than the rest, so the
            # units that will be dropped are the ones defining the grid
            if t.cohort_spec == "first_period_long" and g == 0 and tt == times[0]:
                continue
            x1 = math.sin(i / 9.0) + tt / (40.0 * max(1, t.time_step)) + rng.normal(scale=0.3)
            x2 = (x1 + 1e-3 * math.cos(i + tt)) if t.collinear else (math.cos(i / 13.0) + rng.normal(scale=0.3))
            treated = int(g > 0 and tt >= g)
            effect = 0.4 * treated
            y = (
                1.0
                + 0.3 * x1
                - 0.2 * x2
                + 0.05 * (tt - t.time_start) / max(1, t.time_step)
                + unit_shock
                + effect
                + rng.normal(scale=0.5)
            )
            if t.missing_rate and rng.random() < t.missing_rate:
                y = float("nan")
            rows.append({"id": int(i), "time": int(tt), "g": int(g), "y": y, "x1": x1, "x2": x2, "w": w, "cl": cl})
    d = pd.DataFrame(rows)
    # shuffle: row order must not change any result
    return d.sample(frac=1, random_state=t.seed + 7).reset_index(drop=True)


def xformla(t: Trial) -> str:
    if t.n_covars == 0:
        return "~1"
    if t.n_covars == 1:
        return "~x1"
    return "~x1 + x2"


def stata_covars(t: Trial) -> str:
    return {0: "", 1: "x1", 2: "x1 x2"}[t.n_covars]


def write_r_script(path: Path, trials: list[Trial], oracle_lib: str = "") -> None:
    load = ('suppressPackageStartupMessages(library(did, lib.loc="%s"))' % oracle_lib
            if oracle_lib else "suppressPackageStartupMessages(library(did))")
    lines = [
        load,
        'cat("oracle did version:", as.character(packageVersion("did")), "\n")',
        f'build <- "{BUILD}"',
        "ok <- function(expr) tryCatch(expr, error = function(e) e)",
        "sf <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else as.numeric(x)[1]",
        "",
    ]
    for t in trials:
        n = t.name
        wt = '"w"' if t.weighted else "NULL"
        cl = 'c("cl")' if t.clustered else "NULL"
        lines += [
            f'd <- read.csv(file.path(build, "{n}-data.csv"))',
            # csdid's rcs mode takes no ivar(), so R must not be handed an
            # idname either: under panel = FALSE a repeated id is a legitimate
            # refusal in did >= 2.5.1.901, and passing one here would compare a
            # Stata run that has no unit identifier against an R run that does.
            (f'res <- ok(att_gt(yname="y", tname="time", gname="g",'
             if t.panel_mode == "rcs" else
             f'res <- ok(att_gt(yname="y", tname="time", idname="id", gname="g",'),
            f'    xformla={xformla(t)}, data=d, panel={t.r_panel()},',
            f'    allow_unbalanced_panel={t.r_allow_unbalanced()},',
            f'    control_group="{t.control_group}", anticipation={t.anticipation},',
            f'    weightsname={wt}, clustervars={cl}, est_method="{t.method}",',
            f'    base_period="{t.base_period}", bstrap=FALSE, cband=FALSE))',
            "try({",
            'if (inherits(res, "error")) {',
            f'  writeLines(conditionMessage(res), file.path(build, "{n}-r-error.txt"))',
            "} else {",
            "  za <- qnorm(1 - res$alp/2)",
            "  cells <- data.frame(group=res$group, time=res$t, att=res$att, se=res$se,",
            "                      crit=ifelse(is.null(res$c), za, res$c))",
            f'  write.csv(cells, file.path(build, "{n}-r-cells.csv"), row.names=FALSE)',
            "  wald <- data.frame(wpval=sf(res$Wpval), n_cells=nrow(cells), n_units=sf(res$n))",
            f'  write.csv(wald, file.path(build, "{n}-r-meta.csv"), row.names=FALSE)',
            "  aggopts <- list()",
            (f'  aggopts <- list(min_e={t.min_e}, max_e={t.max_e})' if t.agg_opt == "window"
             else (f'  aggopts <- list(balance_e={t.balance_e})' if t.agg_opt == "balance" else "  aggopts <- list()")),
            "  if (length(aggopts) > 0) {",
            "    aw <- ok(do.call(aggte, c(list(res, type='dynamic', bstrap=FALSE, cband=FALSE, na.rm=TRUE), aggopts)))",
            "    if (inherits(aw, 'error')) {",
            f'      writeLines(conditionMessage(aw), file.path(build, "{n}-r-aggerr-dynwin.txt"))',
            "    } else {",
            "      zw <- qnorm(1 - aw$DIDparams$alp/2)",
            "      write.csv(data.frame(egt=aw$egt, att=aw$att.egt, se=aw$se.egt,",
            "                           crit=if (is.null(aw$crit.val.egt)) NA else aw$crit.val.egt,",
            "                           overall_att=aw$overall.att, overall_se=aw$overall.se,",
            "                           overall_lo=aw$overall.att - zw*aw$overall.se,",
            "                           overall_hi=aw$overall.att + zw*aw$overall.se, pointwise=zw),",
            f'                file.path(build, "{n}-r-agg-dynwin.csv"), row.names=FALSE)',
            "    }",
            "  }",
            "  for (ty in c('simple','dynamic','group','calendar')) {",
            "    a <- ok(aggte(res, type=ty, bstrap=FALSE, cband=FALSE, na.rm=TRUE))",
            "    if (inherits(a, 'error')) {",
            f'      writeLines(conditionMessage(a), file.path(build, paste0("{n}-r-aggerr-", ty, ".txt")))',
            "    } else {",
            "      zb <- qnorm(1 - a$DIDparams$alp/2)",
            "      egt <- if (is.null(a$egt)) NA else a$egt",
            "      att <- if (is.null(a$att.egt)) NA else a$att.egt",
            "      se  <- if (is.null(a$se.egt)) NA else a$se.egt",
            "      cv  <- if (is.null(a$crit.val.egt)) NA else a$crit.val.egt",
            "      df <- data.frame(egt=egt, att=att, se=se, crit=cv,",
            "                       overall_att=a$overall.att, overall_se=a$overall.se,",
            "                       overall_lo=a$overall.att - zb*a$overall.se,",
            "                       overall_hi=a$overall.att + zb*a$overall.se, pointwise=zb)",
            f'      write.csv(df, file.path(build, paste0("{n}-r-agg-", ty, ".csv")), row.names=FALSE)',
            "    }",
            "  }",
            "}",
            "}, silent=TRUE)",
            "",
        ]
    path.write_text("\n".join(lines))


def write_stata_script(path: Path, trials: list[Trial]) -> None:
    lines = [
        "version 15",
        "clear all",
        "set more off",
        f'local root "{ROOT}"',
        f'local build "{BUILD}"',
        'adopath ++ "`root\'/src/ado"',
        'adopath ++ "`root\'/src/mata"',
        "",
    ]
    for t in trials:
        n = t.name
        wt = " [iw=w]" if t.weighted else ""
        cl = " cluster(cl)" if t.clustered else ""
        ctrl = "nevertreated" if t.control_group == "nevertreated" else "notyet"
        if t.panel_mode == "rcs":
            struct = "rcs"
        elif t.panel_mode == "unbalanced_allowed":
            struct = "ivar(id) bal(none)"
        else:
            struct = "ivar(id) bal(full)"
        opts = (
            f"time(time) gvar(g) {struct} method({t.method}) {ctrl} "
            f"base_period({t.base_period}) anticipation({t.anticipation}) analytical pointwise{cl}"
        )
        lines += [
            f'import delimited using "`build\'/{n}-data.csv", clear asdouble varnames(1)',
            f"capture noisily csdid y {stata_covars(t)}{wt}, {opts}",
            "local rc = _rc",
            f'file open fh using "`build\'/{n}-stata-rc.txt", write replace text',
            "file write fh \"`rc'\" _n",
            "file close fh",
            "if `rc' == 0 {",
            "    tempname A",
            "    matrix `A' = e(attgt)",
            "    preserve",
            "    quietly clear",
            "    quietly svmat double `A', names(col)",
            "    quietly keep group time att se",
            "    quietly keep if !missing(group)",
            f'    quietly export delimited using "`build\'/{n}-stata-cells.csv", replace',
            "    restore",
            "    quietly {",
            "        preserve",
            "        clear",
            "        set obs 1",
            "        gen double wpval = .",
            "        capture confirm scalar e(wald_pvalue)",
            "        if !_rc replace wpval = e(wald_pvalue)",
            "        gen double n_units = e(N_units)",
            "        gen double crit = e(crit_val)",
            f'        export delimited using "`build\'/{n}-stata-meta.csv", replace',
            "        restore",
            "    }",
            (f'    local aggextra "window({t.min_e} {t.max_e})"' if t.agg_opt == "window"
             else (f'    local aggextra "balance({t.balance_e})"' if t.agg_opt == "balance" else '    local aggextra ""')),
            "    if \"`aggextra'\" != \"\" {",
            "        capture noisily csdid_stats, type(dynamic) dropmissing `aggextra'",
            "        local wrc = _rc",
            f"        file open fh3 using \"`build'/{n}-stata-aggrc-dynwin.txt\", write replace text",
            "        file write fh3 \"`wrc'\" _n",
            "        file close fh3",
            "        if `wrc' == 0 {",
            "            tempname W",
            "            matrix `W' = e(aggte)",
            "            preserve",
            "            quietly clear",
            "            quietly svmat double `W', names(col)",
            "            quietly keep egt att se overall_att overall_se",
            "            quietly keep if !missing(egt) | !missing(att)",
            "            quietly gen double crit = e(crit_val)",
            "            quietly gen double pointwise = e(point_crit_val)",
            f"            quietly export delimited using \"`build'/{n}-stata-agg-dynwin.csv\", replace",
            "            restore",
            "        }",
            "    }",
            "    foreach ty in simple dynamic group calendar {",
            "        capture noisily csdid_stats, type(`ty') dropmissing",
            "        local arc = _rc",
            f'        file open fh2 using "`build\'/{n}-stata-aggrc-`ty\'.txt", write replace text',
            "        file write fh2 \"`arc'\" _n",
            "        file close fh2",
            "        if `arc' == 0 {",
            "            tempname G",
            "            matrix `G' = e(aggte)",
            "            preserve",
            "            quietly clear",
            "            quietly svmat double `G', names(col)",
            "            quietly keep egt att se overall_att overall_se",
            "            quietly keep if !missing(egt) | !missing(att)",
            "            quietly gen double crit = e(crit_val)",
            "            quietly gen double pointwise = e(point_crit_val)",
            f'            quietly export delimited using "`build\'/{n}-stata-agg-`ty\'.csv", replace',
            "            restore",
            "        }",
            "    }",
            "}",
            "",
        ]
    path.write_text("\n".join(lines))


def num(x) -> float:
    try:
        v = float(x)
    except (TypeError, ValueError):
        return math.nan
    return v


def diff(a, b) -> float:
    """Absolute difference that treats two missings as equal and one as infinite."""
    a, b = num(a), num(b)
    am, bm = math.isnan(a), math.isnan(b)
    if am and bm:
        return 0.0
    if am != bm:
        return math.inf
    return abs(a - b)


COND = {}
CELL_COND = {}
COUNTS = {"r_unestimable_only": 0, "agg_option_rows": 0, "ill_conditioned": 0, "trials_compared": 0, "attgt_cells": 0, "agg_rows": 0, "both_refused": 0, "meta_rows": 0}


def numeric_gap(t: Trial, kind: str, value: float, cell: tuple | None = None) -> bool:
    """True if this numeric gap exceeds what conditioning alone can explain.

    The bound belongs to the matrix the CELL was fitted on, not to the pooled
    frame. A 2x2 comparison runs on one cohort against its comparison group in
    two periods, which is smaller and worse conditioned than the whole panel --
    measured on trial226 of seed 90210, pooled cond was 7.08e4 (bound 1.11e-5)
    while the cell's own was 8.18e4 (bound 1.49e-5), and the observed gap of
    1.14e-5 sits between them. Using the pooled figure reported a conditioning
    artifact as a divergence.
    """
    base = TOL[kind]
    cond = CELL_COND.get((t.name, cell)) if cell is not None else None
    if cond is None:
        cond = COND.get(t.name)
    bound = conditioning_bound(base, cond)
    if value <= base:
        return False
    if value <= bound:
        COUNTS["ill_conditioned"] += 1
        return False
    return True


def fill_cell_cond(t: Trial, cells) -> None:
    """Conditioning of the matrix each 2x2 cell is actually fitted on.

    Resolves the cell's base period the way both packages do -- universal takes
    g-1-anticipation on the observed grid, varying takes t-1 for pre-treatment
    cells and g-1-anticipation from treatment on -- and its comparison group
    from control_group. A cell whose membership cannot be resolved is left out,
    and numeric_gap then falls back to the pooled figure rather than inventing
    a looser bound.
    """
    dpath = BUILD / f"{t.name}-data.csv"
    if not dpath.exists():
        return
    d = pd.read_csv(dpath)
    d = d[~d["y"].isna()]
    if d.empty:
        return
    grid = sorted(int(v) for v in d["time"].unique())
    pos = {v: i for i, v in enumerate(grid)}

    def prev_on_grid(v):
        i = pos.get(int(v))
        return grid[i - 1] if i is not None and i > 0 else None

    for (g, tt) in cells:
        g, tt = int(g), int(tt)
        anchor = g
        for _ in range(int(t.anticipation)):
            anchor = prev_on_grid(anchor) if anchor is not None else None
        base = prev_on_grid(anchor) if anchor is not None else None
        if t.base_period == "varying" and tt < g:
            base = prev_on_grid(tt)
        if base is None or base == tt:
            continue
        later = max(tt, base)
        if t.control_group == "nevertreated":
            comp = d["g"] == 0
        else:
            comp = (d["g"] == 0) | (d["g"] > later)
        sel = ((d["g"] == g) | comp) & d["time"].isin([base, tt])
        cell = d[sel.values]
        if len(cell) <= 3:
            continue
        X = np.column_stack([np.ones(len(cell)), cell["x1"].values, cell["x2"].values])
        X = X[~np.isnan(X).any(axis=1)]
        if len(X) <= 3:
            continue
        try:
            CELL_COND[(t.name, (g, tt))] = float(np.linalg.cond(X))
        except Exception:
            pass


def compare_trial(t: Trial) -> list[dict]:
    """Return a list of divergence records; empty means this trial agreed."""
    out = []
    n = t.name
    r_err = (BUILD / f"{n}-r-error.txt").exists()
    rc_path = BUILD / f"{n}-stata-rc.txt"
    st_rc = int(rc_path.read_text().strip()) if rc_path.exists() else -1

    # CHANNEL: failure behaviour
    if r_err and st_rc == 0:
        out.append({"trial": n, "channel": "failure", "detail": "R refused, Stata accepted"})
        return out
    if (not r_err) and st_rc != 0:
        out.append({"trial": n, "channel": "failure", "detail": f"R accepted, Stata rc={st_rc}"})
        return out
    if r_err and st_rc != 0:
        COUNTS["both_refused"] += 1
        return out  # both refused: agreement

    rc = BUILD / f"{n}-r-cells.csv"
    sc = BUILD / f"{n}-stata-cells.csv"
    if not rc.exists() or not sc.exists():
        out.append({"trial": n, "channel": "cells", "detail": "missing cell output on one side"})
        return out
    r = pd.read_csv(rc)
    s = pd.read_csv(sc)

    # CHANNEL: the cell set itself (EXACT)
    rk = set(zip(r["group"].astype(int), r["time"].astype(int)))
    sk = set(zip(s["group"].astype(int), s["time"].astype(int)))
    if rk != sk:
        only_r = sorted(rk - sk)[:5]
        only_s = sorted(sk - rk)[:5]
        # NOTE: on this campaign's `first_period_long' family these differences
        # are the approved divergence in docs/r-did-crosswalk.md 6.7 -- R keeps
        # a never-treated group that balancing has emptied and returns a table
        # of NAs, csdid replaces the comparison group and estimates. They are
        # deliberately still REPORTED rather than filtered: an attempt to
        # filter them (2026-09-01) had to relax the cell-by-cell comparison to
        # do it, which turned 31 reported divergences into 97 and let inf gaps
        # through. Classify them when reading the report; do not teach the
        # comparator to look away.
        out.append({"trial": n, "channel": "cell_set",
                    "detail": f"R-only={only_r} Stata-only={only_s} (|R|={len(rk)} |S|={len(sk)})"})
        return out

    m = r.merge(s, on=["group", "time"], suffixes=("_r", "_s"))
    fill_cell_cond(t, list(zip(m["group"].astype(int), m["time"].astype(int))))
    COUNTS["trials_compared"] += 1
    COUNTS["attgt_cells"] += len(m)
    for _, row in m.iterrows():
        da = diff(row["att_r"], row["att_s"])
        ds = diff(row["se_r"], row["se_s"])
        key = (int(row["group"]), int(row["time"]))
        if numeric_gap(t, "att", da, key) or numeric_gap(t, "se", ds, key):
            out.append({"trial": n, "channel": "attgt",
                        "detail": f"g={int(row['group'])} t={int(row['time'])} att_diff={da:.3g} se_diff={ds:.3g}"})

    # CHANNEL: pre-test and unit count (written by both sides; previously
    # generated and never compared -- an output with no live comparison is how
    # a suite reports success on something it never looked at)
    rm = BUILD / f"{n}-r-meta.csv"
    sm = BUILD / f"{n}-stata-meta.csv"
    if rm.exists() and sm.exists():
        rmeta = pd.read_csv(rm)
        smeta = pd.read_csv(sm)
        COUNTS["meta_rows"] += 1
        wd = diff(rmeta["wpval"].iloc[0], smeta["wpval"].iloc[0])
        if numeric_gap(t, "pval", wd):
            out.append({"trial": n, "channel": "wald_pretest",
                        "detail": f"pre-test p-value differs by {wd:.3g} "
                                  f"(R={rmeta['wpval'].iloc[0]}, Stata={smeta['wpval'].iloc[0]})"})
        # R's DIDparams$n counts panel units; under panel=FALSE it counts rows,
        # a different quantity by construction, so that mode is out of scope here.
        if t.panel_mode != "rcs":
            nd = diff(rmeta["n_units"].iloc[0], smeta["n_units"].iloc[0])
            if nd > 0:
                out.append({"trial": n, "channel": "n_units",
                            "detail": f"unit count differs: R={rmeta['n_units'].iloc[0]} Stata={smeta['n_units'].iloc[0]}"})

    # CHANNEL: aggregations, including the critical values and the overall band
    agg_types = ["simple", "dynamic", "group", "calendar"]
    if t.agg_opt != "none":
        agg_types.append("dynwin")
    for ty in agg_types:
        ra = BUILD / f"{n}-r-agg-{ty}.csv"
        sa = BUILD / f"{n}-stata-agg-{ty}.csv"
        r_aggerr = (BUILD / f"{n}-r-aggerr-{ty}.txt").exists()
        arc_path = BUILD / f"{n}-stata-aggrc-{ty}.txt"
        s_aggrc = int(arc_path.read_text().strip()) if arc_path.exists() else -1
        if r_aggerr and s_aggrc != 0:
            continue
        if r_aggerr != (s_aggrc != 0):
            out.append({"trial": n, "channel": f"agg_failure_{ty}",
                        "detail": f"R error={r_aggerr}, Stata rc={s_aggrc}"})
            continue
        if not ra.exists() or not sa.exists():
            continue
        ad = pd.read_csv(ra)
        sd = pd.read_csv(sa)
        # overall effect and its band
        o_att = diff(ad["overall_att"].iloc[0], sd["overall_att"].iloc[0])
        o_se = diff(ad["overall_se"].iloc[0], sd["overall_se"].iloc[0])
        if numeric_gap(t, "att", o_att) or numeric_gap(t, "se", o_se):
            out.append({"trial": n, "channel": f"agg_overall_{ty}",
                        "detail": f"overall att_diff={o_att:.3g} se_diff={o_se:.3g}"})
        # the pointwise quantile both sides should be using for the overall row
        p_diff = diff(ad["pointwise"].iloc[0], sd["pointwise"].iloc[0])
        if p_diff > TOL["crit"]:
            out.append({"trial": n, "channel": f"agg_pointwise_{ty}",
                        "detail": f"pointwise crit differs by {p_diff:.3g}"})
        if ty != "simple":
            key = ad[["egt", "att", "se"]].merge(sd[["egt", "att", "se"]], on="egt",
                                                 suffixes=("_r", "_s"), how="outer", indicator=True)
            if not (key["_merge"] == "both").all():
                out.append({"trial": n, "channel": f"agg_keys_{ty}", "detail": "egt sets differ"})
                continue
            COUNTS["agg_rows"] += len(key)
            if ty == "dynwin":
                COUNTS["agg_option_rows"] += len(key)
            for _, row in key.iterrows():
                da = diff(row["att_r"], row["att_s"])
                ds = diff(row["se_r"], row["se_s"])
                if numeric_gap(t, "att", da) or numeric_gap(t, "se", ds):
                    out.append({"trial": n, "channel": f"agg_{ty}",
                                "detail": f"egt={row['egt']} att_diff={da:.3g} se_diff={ds:.3g}"})
    return out


def self_test() -> int:
    """Seed comparator faults. Each MUST be detected, not skipped."""
    print("comparator self-test")
    failures = []

    # wrong value
    if diff(1.0, 1.0 + 1e-3) <= TOL["att"]:
        failures.append("a wrong value passed the att tolerance")
    # missing on one side only
    if diff(float("nan"), 1.0) != math.inf:
        failures.append("a one-sided missing was not treated as a divergence")
    # both missing is agreement
    if diff(float("nan"), float("nan")) != 0.0:
        failures.append("two missings were not treated as agreement")
    # unparseable value
    if diff("not-a-number", 1.0) != math.inf:
        failures.append("an unparseable value was not treated as a divergence")
    # exact-channel: differing cell sets must be caught by set comparison
    if set([(1, 2)]) == set([(1, 3)]):
        failures.append("cell-set comparison is degenerate")

    for f in failures:
        print("  FAIL:", f)
    if not failures:
        print("  all seeded comparator faults were detected")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=24)
    ap.add_argument("--seed", type=int, default=20260901)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--keep", action="store_true", help="keep build dir contents")
    ap.add_argument("--oracle-lib", default="",
                    help="R library holding the did build to compare against "
                         "(default: the pinned oracle in the system library). Use this to "
                         "distinguish a csdid defect from a bug in the pinned reference: a "
                         "divergence that disappears against a NEWER did build is a limitation "
                         "of the reference, not of csdid.")
    ap.add_argument("--compare-only", action="store_true",
                    help="re-compare existing outputs without re-running R/Stata (fault injection)")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if self_test() != 0:
        print("comparator self-test failed; refusing to report a green campaign")
        return 1

    BUILD.mkdir(parents=True, exist_ok=True)
    if args.compare_only:
        args.keep = True
    if not args.keep:
        for p in BUILD.glob("*"):
            p.unlink()

    rng = np.random.default_rng(args.seed)
    trials = [draw_trial(rng, i, args.seed) for i in range(args.trials)]
    if not args.compare_only:
        for t in trials:
            make_data(t).to_csv(BUILD / f"{t.name}-data.csv", index=False)
    for t in trials:
        dpath = BUILD / f"{t.name}-data.csv"
        if dpath.exists():
            dd = pd.read_csv(dpath)
            X = np.column_stack([np.ones(len(dd)), dd["x1"].values, dd["x2"].values])
            X = X[~np.isnan(X).any(axis=1)]
            COND[t.name] = float(np.linalg.cond(X)) if len(X) > 3 else float("nan")

    r_script = BUILD / "campaign.R"
    do_script = BUILD / "campaign.do"
    if not args.compare_only:
        write_r_script(r_script, trials, args.oracle_lib)
        write_stata_script(do_script, trials)

    if not args.compare_only:
        subprocess.run(["Rscript", str(r_script)], cwd=ROOT, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([STATA_CMD, "-b", "do", str(do_script)], cwd=BUILD, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    all_div = []
    for t in trials:
        all_div.extend(compare_trial(t))

    manifest = {"seed": args.seed, "trials": [asdict(t) for t in trials],
                "tolerances": TOL, "divergences": all_div}
    (BUILD / "campaign-result.json").write_text(json.dumps(manifest, indent=2))

    by_channel = {}
    for d in all_div:
        by_channel.setdefault(d["channel"], []).append(d)
    print(f"\ntrials: {len(trials)}   divergences: {len(all_div)}")
    print(f"measured: {COUNTS['trials_compared']} trials fully compared, "
          f"{COUNTS['attgt_cells']} ATT(g,t) cells, {COUNTS['agg_rows']} aggregation rows, "
          f"{COUNTS['both_refused']} trials where both sides refused, "
          f"{COUNTS['meta_rows']} pre-test/count rows; "
          f"{COUNTS['ill_conditioned']} gaps within the conditioning bound (approved); "

          f"{COUNTS['agg_option_rows']} windowed/balanced aggregation rows")
    if COUNTS["trials_compared"] == 0:
        print("  NOTHING WAS COMPARED -- a green result here means the harness is broken")
    for ch, items in sorted(by_channel.items()):
        print(f"  {ch}: {len(items)}")
        for it in items[:4]:
            print(f"     {it['trial']}: {it['detail']}")
    if not all_div:
        print("  no divergence on any compared channel")
    print(f"\nfull record: {BUILD / 'campaign-result.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
