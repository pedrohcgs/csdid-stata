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
  3. The comparison covers cell estimates and standard errors, aggregation
     estimates and standard errors, the overall pointwise quantile, the
     pre-test, panel unit counts, and failure/refusal behaviour.

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
import base64
import hashlib
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
# On a near-singular design matrix, floating-point differences in the nuisance
# solves can be amplified. This is the established unweighted whole-cell
# diagnostic bound, not proof of exact equality, nor a condition estimate for
# each weighted treatment/comparison subgroup's nuisance fit.
#
# Measured on the two divergent trials of seed 31415, varying only the
# collinearity of x2 on x1 and holding everything else fixed:
#     cond(X) 1.4e5 -> max|dATT| 3.2e-5
#     cond(X) 1.4e4 -> max|dATT| 3.5e-7
#     cond(X) 4.8e3 -> max|dATT| 2.4e-9
#     independent  -> max|dATT| 2.0e-10
# i.e. the gap tracks cond^2 * machine epsilon. Panel mode does not matter.
# A numeric difference below this bound is classified "ill_conditioned" and
# reported separately; anything above it stays a divergence. The design comes
# from the actual reference fitter. Aggregations and the Wald test use the
# maximum over contributing cells observed in the reference helpers; neither
# raw pooled covariates nor reconstructed cell membership are a fallback.
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
            if oracle_lib else "")
    lines = [
        load,
        f'source("{ROOT}/tools/parity/generators/oracle-check.R")',
        'cat("authenticated oracle did:", as.character(packageVersion("did")), find.package("did"), "\n")',
        f'source("{ROOT}/tools/parity/capture-differential-designs.R")',
        f'build <- "{BUILD}"',
        "ok <- function(expr) tryCatch(expr, error = function(e) e)",
        "sf <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else as.numeric(x)[1]",
        "",
    ]
    for t in trials:
        n = t.name
        # A kept build may contain an older refusal or partial result. Each
        # rerun owns fresh reference evidence for this exact input and spec.
        for previous in BUILD.glob(f"{n}-r-*"):
            previous.unlink()
        spec_json = json.dumps(json.dumps(asdict(t), separators=(",", ":")))
        wt = '"w"' if t.weighted else "NULL"
        cl = 'c("cl")' if t.clustered else "NULL"
        lines += [
            f'csdid_design_begin("{n}", file.path(build, "{n}-data.csv"), jsonlite::fromJSON({spec_json}))',
            f'd <- read.csv(file.path(build, "{n}-data.csv"))',
            # csdid's rcs mode takes no ivar(), so R must not be handed an
            # idname either: under panel = FALSE a repeated id is a legitimate
            # refusal in did >= 2.5.1.901, and passing one here would compare a
            # Stata run that has no unit identifier against an R run that does.
            (f'res <- ok(did::att_gt(yname="y", tname="time", gname="g",'
             if t.panel_mode == "rcs" else
             f'res <- ok(did::att_gt(yname="y", tname="time", idname="id", gname="g",'),
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
            '    csdid_design_agg_begin("dynwin")',
            "    aw <- ok(do.call(aggte, c(list(res, type='dynamic', bstrap=FALSE, cband=FALSE, na.rm=TRUE), aggopts)))",
            "    csdid_design_agg_end(aw)",
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
            "    csdid_design_agg_begin(ty)",
            "    a <- ok(aggte(res, type=ty, bstrap=FALSE, cband=FALSE, na.rm=TRUE))",
            "    csdid_design_agg_end(a)",
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
            f'csdid_design_write(file.path(build, "{n}-r-designs.json"))',
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


CELL_COND = {}
SUPPORT_COND = {}
COUNTS = {"r_unestimable_only": 0, "agg_option_rows": 0, "ill_conditioned": 0, "trials_compared": 0, "attgt_cells": 0, "agg_rows": 0, "both_refused": 0, "meta_rows": 0}


def numeric_gap(t: Trial, kind: str, value: float, cell: tuple | None = None,
                support: str | None = None) -> bool:
    """Use the unweighted fitted design, or the maximum over actual support.

    Aggregation and Wald supports are observed inside the reference, after its
    missing-cell, calendar and event-window selections. No raw-data proxy is
    used. Structural normalizations have no fitted design and retain the base
    tolerance; missing required observations are refused before comparison.

    This unweighted whole-cell condition is the established diagnostic bound,
    not proof of equality or a condition estimate for weighted subgroup fits.
    """
    base = TOL[kind]
    cache = CELL_COND if cell is not None else SUPPORT_COND
    key = (t.name, cell if cell is not None else support)
    if key not in cache:
        raise DesignCaptureError(f"no verified conditioning input for {key}")
    cond = cache[key]
    bound = conditioning_bound(base, cond)
    if value <= base:
        return False
    if value <= bound:
        COUNTS["ill_conditioned"] += 1
        return False
    return True


class DesignCaptureError(ValueError):
    pass


def load_design_capture(t: Trial) -> dict:
    """Read exact reference inputs; never reconstruct a more permissive design."""
    path = BUILD / f"{t.name}-r-designs.json"
    try:
        record = json.loads(path.read_text())
        digest = hashlib.sha256((BUILD / f"{t.name}-data.csv").read_bytes()).hexdigest()
        if (record["schema"] != 1 or record["trial"] != t.name
                or record["input_sha256"] != digest or record["spec"] != asdict(t)):
            raise ValueError("capture identity differs from the requested trial/input")
        if record["errors"] != []:
            raise ValueError(f"reference capture failed: {record['errors']}")
        cells = {}
        for entry in record["cells"]:
            group, time = entry["group"], entry["time"]
            if (not isinstance(group, (int, float)) or not isinstance(time, (int, float))
                    or not math.isfinite(group) or not math.isfinite(time)
                    or int(group) != group or int(time) != time):
                raise ValueError("noninteger cell key")
            key = (int(group), int(time))
            if key in cells or entry["status"] not in ("fitted", "missing", "structural_zero"):
                raise ValueError("duplicate cell key or unknown fit status")
            entry["condition"] = None
            if "X_f64le" in entry:
                rows, columns = entry["rows"], entry["columns"]
                if (type(rows) is not int or rows < 0 or type(columns) is not int
                        or columns != t.n_covars + 1):
                    raise ValueError("captured design dimensions disagree with fitted covariates")
                raw = base64.b64decode(entry["X_f64le"], validate=True)
                if len(raw) != 8 * rows * columns:
                    raise ValueError("truncated or oversized binary64 design")
                x = np.frombuffer(raw, dtype="<f8").reshape((rows, columns), order="F")
                if not np.isfinite(x).all():
                    raise ValueError("nonfinite design entry")
                vectors = {name: np.atleast_1d(np.asarray(entry[name], dtype=float))
                           for name in ("ids", "periods", "D", "weights")}
                if any(v.ndim != 1 or len(v) != rows or not np.isfinite(v).all()
                       for v in vectors.values()):
                    raise ValueError("design row identity/vector length is invalid")
                if (len(set(zip(vectors["ids"], vectors["periods"]))) != rows
                        or not np.isin(vectors["D"], [0, 1]).all()
                        or (vectors["weights"] < 0).any()):
                    raise ValueError("duplicate design row or invalid treatment/weight")
                # pre_process_did2.R:331-346 turns allow_unbalanced_panel off
                # when the observed panel is balanced. The fitted matrix stays
                # authoritative on either route; the option only permits gaps.
                routes = {"balanced": ("panel",),
                          "unbalanced_allowed": ("unbalanced", "panel"),
                          "rcs": ("rcs",)}[t.panel_mode]
                if entry["route"] not in routes:
                    raise ValueError("captured route differs from the trial")
                if entry["status"] == "fitted":
                    condition = float(np.linalg.cond(x))
                    if not math.isfinite(condition) or condition < 1:
                        raise ValueError("finite fit has no finite design condition")
                    entry["condition"] = condition
            elif entry["status"] == "fitted":
                raise ValueError("finite fitted cell has no design capture")
            cells[key] = entry
        record["cells_by_key"] = cells
        return record
    except (OSError, KeyError, TypeError, ValueError, OverflowError, np.linalg.LinAlgError) as error:
        raise DesignCaptureError(f"{path.name}: {error}") from error


def install_design_conditions(t: Trial, record: dict, r: pd.DataFrame) -> None:
    """Bind the unchanged bound to captured cell and actual aggregate supports."""
    for cache in (CELL_COND, SUPPORT_COND):
        for key in [key for key in cache if key[0] == t.name]:
            del cache[key]
    entries = record["cells_by_key"]
    keys = set(zip(r["group"].astype(int), r["time"].astype(int)))
    if len(keys) != len(r) or set(entries) != keys:
        raise DesignCaptureError("captured cell keys differ from reference results")
    for row in r.itertuples():
        key = (int(row.group), int(row.time))
        entry = entries[key]
        if (entry["status"] == "missing") != math.isnan(num(row.att)):
            raise DesignCaptureError(f"capture fit status disagrees with ATT: {key}")
        if entry["status"] == "structural_zero" and num(row.att) != 0:
            raise DesignCaptureError(f"structural normalization has a nonzero ATT: {key}")
        CELL_COND[(t.name, key)] = entry["condition"]

    def support_condition(support):
        if not isinstance(support, list) or len(set(support)) != len(support):
            raise DesignCaptureError("support is not a list of unique cell keys")
        values = []
        by_label = {f"{g}:{tt}": e for (g, tt), e in entries.items()}
        for key in support:
            if key not in by_label or by_label[key]["status"] == "missing":
                raise DesignCaptureError(f"support names an absent or failed cell: {key}")
            condition = by_label[key]["condition"]
            if condition is not None:
                values.append(condition)
        return max(values) if values else None

    wald = record.get("wald")
    if not isinstance(wald, dict) or wald.get("status") not in ("missing", "complete"):
        raise DesignCaptureError("Wald support capture is absent")
    meta = pd.read_csv(BUILD / f"{t.name}-r-meta.csv")
    if len(meta) != 1 or (wald["status"] == "complete") != math.isfinite(num(meta["wpval"].iloc[0])):
        raise DesignCaptureError("Wald support status disagrees with the reported pre-test")
    if wald["status"] == "complete" and not wald["support"]:
        raise DesignCaptureError("finite Wald statistic has no contributing cells")
    SUPPORT_COND[(t.name, "wald")] = support_condition(wald["support"])
    aggregates = record.get("aggregations")
    if not isinstance(aggregates, dict):
        raise DesignCaptureError("aggregation support capture is absent")
    required = ["simple", "dynamic", "group", "calendar"]
    if t.agg_opt != "none":
        required.append("dynwin")
    if set(aggregates) != set(required):
        raise DesignCaptureError("aggregation capture keys differ from requested aggregations")
    for label, aggregate in aggregates.items():
        if not isinstance(aggregate, dict) or aggregate.get("status") not in ("refused", "complete"):
            raise DesignCaptureError(f"unknown aggregation capture status: {label}")
        expected_refusal = (BUILD / f"{t.name}-r-aggerr-{label}.txt").exists()
        if expected_refusal != (aggregate["status"] == "refused"):
            raise DesignCaptureError(f"aggregation refusal/capture mismatch: {label}")
        if expected_refusal:
            if (BUILD / f"{t.name}-r-agg-{label}.csv").exists():
                raise DesignCaptureError(f"refused aggregation also has returned estimates: {label}")
            continue
        if aggregate.get("errors", []):
            raise DesignCaptureError(f"returned aggregation has trace errors: {label}")
        path = BUILD / f"{t.name}-r-agg-{label}.csv"
        try:
            results = pd.read_csv(path)
        except (OSError, ValueError) as error:
            raise DesignCaptureError(f"missing aggregation result: {path.name}") from error
        if results.empty or (label != "simple" and results["egt"].duplicated().any()):
            raise DesignCaptureError(f"empty or duplicate aggregation rows: {label}")
        supports = aggregate["supports"]
        labels = {"overall"}
        if label != "simple":
            labels |= {f"egt:{v:g}" for v in results["egt"]}
        if not isinstance(supports, dict) or set(supports) != labels:
            raise DesignCaptureError(f"aggregation support rows differ from results: {label}")
        for effect, support in supports.items():
            finite = (math.isfinite(num(results["overall_att"].iloc[0])) if effect == "overall"
                      else np.isfinite(results.loc[results["egt"] == float(effect[4:]), "att"]).any())
            if finite and not support:
                raise DesignCaptureError(f"finite aggregation has no contributing cells: {label}/{effect}")
            SUPPORT_COND[(t.name, f"{label}/{effect}")] = support_condition(support)


def compare_trial(t: Trial) -> list[dict]:
    """Return a list of divergence records; empty means this trial agreed."""
    out = []
    n = t.name
    r_err = (BUILD / f"{n}-r-error.txt").exists()
    rc_path = BUILD / f"{n}-stata-rc.txt"
    st_rc = int(rc_path.read_text().strip()) if rc_path.exists() else -1

    try:
        capture = load_design_capture(t)
    except DesignCaptureError as error:
        return [{"trial": n, "channel": "conditioning_unverified", "detail": str(error)}]

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
    try:
        install_design_conditions(t, capture, r)
    except (DesignCaptureError, OSError, KeyError, TypeError, ValueError) as error:
        return [{"trial": n, "channel": "conditioning_unverified", "detail": str(error)}]
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
        if numeric_gap(t, "pval", wd, support="wald"):
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
        if numeric_gap(t, "att", o_att, support=f"{ty}/overall") or numeric_gap(t, "se", o_se, support=f"{ty}/overall"):
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
                if numeric_gap(t, "att", da, support=f"{ty}/egt:{row['egt']:g}") or numeric_gap(t, "se", ds, support=f"{ty}/egt:{row['egt']:g}"):
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
                    help="R library holding a content-authenticated did 2.5.1 installation; "
                         "CSDID_DID_UPSTREAM takes precedence. Newer did builds require a "
                         "separately qualified design observer and are not supported here.")
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
    # A missing observation is a harness failure, not estimator disagreement.
    return 2 if "conditioning_unverified" in by_channel else 0


if __name__ == "__main__":
    sys.exit(main())
