#!/usr/bin/env python3
"""Render and verify every statistical table and numerical simulation claim.

The input is website-statistics.json from run-website-simulations.py. Dataset
identities separate covariate and no-covariate draws, and every raw input is
content-verified before a published number is compared or written. Formatting
rounds the measured values to the precision already used in the article.
"""
import argparse
import csv
import gzip
import hashlib
import json
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
ARTICLE = ROOT / "website/articles/csdid-against-the-field.md"
STATISTICS = ROOT / "tools/bench/field/results/website-statistics.json"
HERO = ROOT / "tools/bench/field/figcheck.csv"
BT = chr(96)
NUMBER = r"[-+]?\d+(?:(?:\{,\}|,)\d{3})*(?:\.\d+)?(?:[eE][-+]?\d+)?"

# All eight statistical tables, in article order. The remaining tables contain
# design facts or wall-clock measurements and have their own publication gates.
BIAS_TABLES = {
    "Balanced panel, no covariates: bias and coverage at e=0": ("sampling_main", "balanced", 0),
    "Unequal period sizes: bias and coverage at e=0": ("sampling_main", "varmiss", 0),
    "Linear outcome trend: bias and coverage at e=0": ("covariates_panel", "bal_ok", 0),
    "Misspecified outcome model: bias and coverage at e=1": ("covariates_panel", "bal_owrong", 1),
    "Misspecified propensity score: bias and coverage at e=1": ("covariates_panel", "bal_ps2", 1),
}
MASTER = "One design, every command: bias / coverage by event time"
PRECISION = "Two error processes, standard deviation of the event-study estimate"
JOINT = "Joint coverage of the post-treatment path"
LABELS = {
    "csdid": "csdid", "csdid (any bal() mode)": "csdid", "csdid bal(none)": "csdid",
    "csdid dr": "csdid_dr", "csdid reg": "csdid_reg", "csdid ipw": "csdid_ipw",
    "jwdid": "jwdid", "jwdid uncond": "jwdid_uc", "did_imputation": "bjs",
    "did_imputation wtr": "bjs_wtr", "did_multiplegt_dyn": "dcdh",
    "did_multiplegt_dyn trends_nonparam": "dcdh_tnp", "lpdid": "lpdid",
    "lpdid rw": "lpdid_rw", "lpdid controls()": "lpdid_ctl",
    "lpdid rw controls()": "lpdid_rw_ctl", "eventstudyinteract": "sa",
    "eventstudyinteract additive": "sa", "eventstudyinteract x-by-time": "sa_xt",
}
HERO_LABELS = {"csdid": "csdid", "jwdid": "jwdid", "did_imputation": "bjs",
               "did_multiplegt_dyn": "dcdh", "lpdid": "lpdid", "eventstudyinteract": "sa"}
PUBLISHED_DESIGNS = {name: (1000, 500) for name in
                     ("sampling_main", "covariates_panel", "covariates_rc", "unitroot", "bands", "hero")}
PUBLISHED_DESIGNS["master"] = (2000, 100)
PUBLISHED_DESIGNS["ctvar"] = (1000, 100)
PUBLISHED_DESIGNS.update({name: (1000, 500) for name in ("cohorthet", "breakhunt", "smallnt", "ymiss")})


def plain(value):
    return value.replace(BT, "").replace("**", "").strip()


def finite(value, context):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"missing or non-finite statistic: {context}")
    return value


class Evidence:
    def __init__(self, path):
        self.path = pathlib.Path(path).resolve()
        self.data = json.loads(self.path.read_text())
        if self.data.get("status") not in {"complete", "pass"}:
            raise ValueError("simulation campaign is incomplete; refusing to publish partial evidence")
        if not self.data.get("provenance"):
            raise ValueError("simulation campaign has no provenance")
        self.metrics = {}
        self.inputs = 0
        for dataset, group in self.data.get("groups", {}).items():
            if dataset in PUBLISHED_DESIGNS and (group.get("n"), group.get("reps")) != PUBLISHED_DESIGNS[dataset]:
                raise ValueError(f"published sample size or replication count changed: {dataset}")
            self.verify_file(group, dataset, csv_input=True)
            for metric in group.get("metrics", []):
                key = (dataset, metric["regime"], metric["pkg"], int(metric["h"]))
                if key in self.metrics:
                    raise ValueError(f"duplicate statistic: {key}")
                self.metrics[key] = metric
        self.joint = {}
        for metric in self.data.get("joint_metrics", []):
            key = (metric["dataset_id"], metric["pkg"], metric["interval"])
            if key in self.joint:
                raise ValueError(f"duplicate joint statistic: {key}")
            self.joint[key] = metric
        self.diagnostics = self.data.get("diagnostics", {})

    def resolve(self, name):
        path = pathlib.Path(name)
        if path.is_absolute():
            return path
        candidates = (self.path.parent / path, ROOT / path)
        return next((p for p in candidates if p.is_file()), candidates[0])

    def verify_file(self, record, context, csv_input=False):
        name = record.get("raw_file", record.get("source_file"))
        expected = record.get("sha256")
        if not name or not re.fullmatch(r"[0-9a-f]{64}", str(expected)):
            raise ValueError(f"missing input identity: {context}")
        path = self.resolve(name)
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"raw input missing or changed: {context}: {path}")
        if csv_input:
            opener = gzip.open if path.suffix == ".gz" else open
            with opener(path, "rt", newline="") as stream:
                reader = csv.DictReader(stream)
                if not {"regime", "pkg", "rep", "h", "est", "se"} <= set(reader.fieldnames or ()) or next(reader, None) is None:
                    raise ValueError(f"raw simulation input has no estimates: {context}")
        self.inputs += 1

    def metric(self, dataset, regime, pkg, h, field):
        key = (dataset, regime, pkg, h)
        if key not in self.metrics:
            raise ValueError(f"required statistic absent: {key}")
        row = self.metrics[key]
        if row.get("attempted", 0) <= 0 or row.get("finite_estimates", 0) <= 0:
            raise ValueError(f"required statistic has no usable replication: {key}")
        return finite(row.get(field), f"{key}/{field}")

    def joint_value(self, pkg, interval="pointwise", dataset="sampling_main"):
        key = (dataset, pkg, interval)
        if key not in self.joint:
            raise ValueError(f"required joint statistic absent: {key}")
        row = self.joint[key]
        if row.get("n", 0) <= 0 or row.get("attempted", 0) < row["n"]:
            raise ValueError(f"invalid joint denominator: {key}")
        value = finite(row.get("coverage"), f"{key}/coverage")
        if not math.isclose(value, row["hit"] / row["n"], abs_tol=1e-15):
            raise ValueError(f"joint coverage and hit count disagree: {key}")
        return value

    def diagnostic(self, name):
        if name not in self.diagnostics:
            raise ValueError(f"fresh diagnostic evidence absent: {name}")
        record = self.diagnostics[name]
        self.verify_file(record, name)
        value = finite(record.get("value"), name)
        if name.startswith(("missing_", "publication_", "target_check_")):
            path = self.resolve(record["source_file"])
            opener = gzip.open if path.suffix == ".gz" else open
            with opener(path, "rt", newline="") as stream:
                rows = list(csv.DictReader(stream))
            if name.startswith("target_check_"):
                if len(rows) != 3 or {int(row['h']) for row in rows} != {0,1,2}:
                    raise ValueError("target-check source must contain exactly the three horizons")
                if name == "target_check_three_decimal_agreements":
                    observed = sum(f"{float(row['population_target']):.3f}" == f"{float(row['empirical_target']):.3f}" for row in rows)
                else:
                    match = re.fullmatch(r'target_check_e([012])_(population|empirical|difference)',name)
                    if not match:
                        raise ValueError(f"unmapped target-check diagnostic: {name}")
                    column = {'population':'population_target','empirical':'empirical_target','difference':'difference'}[match[2]]
                    observed = float(next(row[column] for row in rows if int(row['h']) == int(match[1])))
            else:
                selected = [row for row in rows if row.get('metric') == name]
                if len(selected) != 1:
                    raise ValueError(f"diagnostic source row absent or duplicated: {name}")
                observed = float(selected[0]['value'])
            if observed != value:
                raise ValueError(f"diagnostic differs from its source CSV: {name}")
        return value

    def paired_gap(self, dataset, regimes, left, right):
        values = []
        rows = self.data.get("paired_metrics", [])
        expected = self.data["groups"][dataset]["reps"]
        for regime in regimes:
            for h in range(3):
                selected = [r for r in rows if (r["dataset_id"],r["regime"],r["left_pkg"],r["right_pkg"],int(r["h"])) == (dataset,regime,left,right,h)]
                if len(selected) != 1:
                    raise ValueError(f"paired point-estimate evidence absent or duplicated: {dataset}/{regime}/{left}/{right}/{h}")
                row = selected[0]
                counts = [row.get(k) for k in ("attempted","matched_estimates","missing_left_only","missing_right_only","missing_both")]
                if any(type(value) is not int or value < 0 for value in counts) or row["attempted"] != expected or row["matched_estimates"] != expected or any(counts[2:]):
                    raise ValueError(f"paired point-estimate comparison has unmatched draws: {dataset}/{regime}/{h}")
                values.append(finite(row.get("max_abs_estimate_difference"), "paired point gap"))
        if min(values) < 0:
            raise ValueError("negative absolute point-estimate difference")
        return max(values)

    def equivalence_gate(self):
        outputs = self.data.get("diagnostic_jobs",{}).get("eqgate",{}).get("outputs",[])
        files = [o for o in outputs if pathlib.Path(o["path"]).name in {"eqgate.csv","eqgate.csv.gz"}]
        if len(files) != 1:
            raise ValueError("literal-command equivalence raw evidence is absent or duplicated")
        output = files[0]
        self.verify_file(dict(source_file=output["path"],sha256=output["sha256"]),"eqgate")
        path = self.resolve(output["path"])
        opener = gzip.open if path.suffix == ".gz" else open
        with opener(path,"rt",newline="") as stream:
            rows = list(csv.DictReader(stream))
        arms = "csdid_reg csdid_dr csdid_reg_nt lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl dcdh_tnp sa_xt".split()
        expected = {(seed,arm,h) for seed in (90001,90002,90003) for arm in arms for h in (0,1,2)}
        if len(rows) != len(expected) or {(int(r["seed"]),r["arm"],int(r["h"])) for r in rows} != expected:
            raise ValueError("literal-command equivalence roster is incomplete")
        for row in rows:
            values = [float(row[k]) for k in ("b_branch","b_inline","se_branch","se_inline")]
            if not all(math.isfinite(x) for x in values) or values[0] != values[1] or values[2] != values[3]:
                raise ValueError("literal-command equivalence has missing or unequal results")
        return len(arms),3,3



def formatted(value, old):
    match = re.search(NUMBER, old)
    if not match:
        raise ValueError(f"published numeric cell cannot be parsed: {old!r}")
    token = match.group()
    digits = len(token.split(".")[1]) if "." in token else 0
    sign = "+" if token.startswith(("+", "-")) else ""
    new = format(value, f"{sign}.{digits}f")
    return old[:match.start()] + new + old[match.end():]


def table_blocks(text):
    pattern = re.compile(r'<p class="table-title" markdown="span">(?P<title>[^<]+)</p>\s*\n(?P<table>(?:\|[^\n]*\n)+)')
    blocks = {m.group("title"): m for m in pattern.finditer(text)}
    expected = set(BIAS_TABLES) | {MASTER, PRECISION, JOINT}
    if not expected <= blocks.keys():
        raise ValueError(f"published statistical tables missing: {sorted(expected - blocks.keys())}")
    return blocks


def render_tables(text, evidence):
    edits = []
    count = 0
    for title, match in table_blocks(text).items():
        if title not in set(BIAS_TABLES) | {MASTER, PRECISION, JOINT}:
            continue
        lines = match.group("table").splitlines(keepends=True)
        seen = set()
        for index, line in enumerate(lines):
            cells = line.rstrip("\n").split("|")[1:-1]
            if index < 2:
                continue
            name = plain(cells[0])
            if name in seen:
                raise ValueError(f"duplicate published row: {title}/{name}")
            seen.add(name)
            if title in BIAS_TABLES:
                dataset, regime, h = BIAS_TABLES[title]
                if name not in LABELS:
                    raise ValueError(f"unmapped published row: {title}/{name}")
                for col, field in ((1, "bias"), (2, "coverage")):
                    value = evidence.metric(dataset, regime, LABELS[name], h, field)
                    cells[col] = formatted(value, cells[col])
            elif title == MASTER:
                if name not in LABELS:
                    raise ValueError(f"unmapped master row: {name}")
                for h in range(3):
                    left, right = cells[h + 1].split("/")
                    left = formatted(evidence.metric("master", "master", LABELS[name], h, "bias"), left)
                    right = formatted(evidence.metric("master", "master", LABELS[name], h, "coverage"), right)
                    cells[h + 1] = left + "/" + right
            elif title == PRECISION:
                dataset, regime = {"iid": ("sampling_main", "balanced"), "unit root": ("unitroot", "unitroot")}[name]
                cs = evidence.metric(dataset, regime, "csdid", 0, "sd")
                pool = evidence.metric(dataset, regime, "jwdid", 0, "sd")
                bjs = evidence.metric(dataset, regime, "bjs", 0, "sd")
                if round(pool, 3) != round(bjs, 3):
                    raise ValueError("jwdid and did_imputation need separate precision rows")
                cells[1] = formatted(cs, cells[1])
                cells[2] = formatted(pool, cells[2])
                percent = 100 * (1 - min(cs, pool) / max(cs, pool))
                winner = "poolers" if pool < cs else BT + "csdid" + BT
                cells[3] = " " + winner + f", by ~{percent:.0f}% "
            else:
                joint = {
                    "csdid uniform band": ("bands", "csdid_band", "uniform_band"),
                    "csdid three pointwise CIs": ("bands", "csdid_band", "pointwise"),
                    "jwdid / did_imputation pointwise": ("sampling_main", "jwdid", "pointwise"),
                    "did_multiplegt_dyn pointwise": ("sampling_main", "dcdh", "pointwise"),
                    "lpdid pointwise": ("sampling_main", "lpdid", "pointwise"),
                }
                dataset, pkg, interval = joint[name]
                value = evidence.joint_value(pkg, interval, dataset)
                if pkg == "jwdid" and round(value, 3) != round(evidence.joint_value("bjs"), 3):
                    raise ValueError("jwdid and did_imputation need separate joint-coverage rows")
                cells[1] = formatted(value, cells[1])
            lines[index] = "|" + "|".join(cells) + "|\n"
            count += 1
        expected_rows = {**dict(zip(BIAS_TABLES, (8, 9, 10, 10, 10))), MASTER: 13, PRECISION: 2, JOINT: 5}[title]
        if len(seen) != expected_rows:
            raise ValueError(f"{title}: expected {expected_rows} rows, found {len(seen)}")
        edits.append((match.start("table"), match.end("table"), "".join(lines)))
    if count != 67:
        raise ValueError(f"expected 67 published statistical rows, found {count}")
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text, count


class Claims:
    def __init__(self, text):
        self.text, self.count = text, 0

    def require(self, name, statement, valid):
        if self.text.count(statement.replace("§", BT)) != 1 or not valid:
            raise ValueError(f"numerical diagnostic claim requires review: {name}")
        self.count += 1

    def rewrite(self, name, previous, template, **values):
        def pattern(value):
            pieces = re.split(r"\{([a-zA-Z_]\w*)\}", value.replace("§", BT))
            return "".join(re.escape(part) if i % 2 == 0 else f"(?:{NUMBER})"
                           for i, part in enumerate(pieces))
        variants = [list(re.finditer(pattern(value), self.text)) for value in (previous, template)]
        matches = [match for variant in variants for match in variant]
        if len(matches) != 1:
            raise ValueError(f"narrative anchor {name!r}: expected once, found {len(matches)}")
        replacement = re.sub(r"\{([a-zA-Z_]\w*)\}", lambda match: str(values[match.group(1)]), template.replace("§", BT))
        match = matches[0]
        self.text = self.text[:match.start()] + replacement + self.text[match.end():]
        self.count += 1

    def render(self, name, template, **values):
        # Section signs stand for Markdown backticks so templates remain easy
        # to distinguish from Python's formatting and the article's LaTeX.
        template = template.replace("§", BT)
        pieces = re.split(r"\{([a-zA-Z_]\w*)\}", template)
        pattern = "".join(re.escape(part) if i % 2 == 0 else f"(?P<{part}>{NUMBER}|zero)"
                          for i, part in enumerate(pieces))
        matches = list(re.finditer(pattern, self.text))
        if len(matches) != 1:
            raise ValueError(f"narrative anchor {name!r}: expected once, found {len(matches)}")
        match = matches[0]
        if set(match.groupdict()) != set(values):
            raise ValueError(f"narrative fields disagree: {name}")
        for field in sorted(values, key=lambda key: match.start(key), reverse=True):
            start, end = match.span(field)
            self.text = self.text[:start] + str(values[field]) + self.text[end:]
        self.count += 1


def render_missing_row_claims(text, e):
    c = Claims(text)
    def d(name):
        return e.diagnostic("missing_" + name)
    def whole(value):
        if value < 0 or value != int(value):
            raise ValueError("missing-row count is not a nonnegative integer")
        return int(value)
    def bound(value):
        if value < 0 or value > 1e-12:
            raise ValueError("missing-row paired-cell agreement requires review")
        if value == 0:
            return "0"
        scale = 10 ** math.floor(math.log10(value))
        return f"{math.ceil(value / scale) * scale:.0e}"
    c.require("missing-row xthdid surgical agreement",
              "estimates at event times 0, 1, and 2 agree within 1e-12.",
              all(0 <= d(f"xthdid_P1_h{h}_abs_gap") <= 1e-12 for h in range(3)))
    c.require("missing-row lpdid later horizons",
              "For §lpdid§, event\ntimes 1 and 2 agree within 1e-12",
              all(0 <= d(f"lpdid_P1_h{h}_abs_gap") <= 1e-12 for h in (1, 2)))
    lp0 = d("lpdid_P1_h0_abs_gap")
    dc = d("dcdh_P1_max_abs_dynamic_gap")
    if lp0 <= 1e-12 or dc <= 1e-12:
        raise ValueError("missing-row surgical counterexamples require review")
    c.render("missing-row lpdid first horizon", "but event time 0 differs by {gap}.", gap=f"{lp0:.3g}")
    c.render("missing-row dcdh surgical difference",
             "For §did_multiplegt_dyn§, the largest difference over those three horizons\nis {gap}.", gap=f"{dc:.3g}")
    supported = whole(d("derived_post_cells"))
    unsupported = whole(d("derived_unavailable_post_cells"))
    if (supported <= 0 or unsupported <= 0 or
        whole(d("derived_total_post_cells")) != supported + unsupported or
        whole(d("derived_xthdid_finite_without_pair")) != unsupported):
        raise ValueError("missing-row derived-cell support requires review")
    err = max(d("derived_pair_max_abs"), d("derived_csdid_max_abs"))
    c.render("missing-row supported derived cells",
             "units, ten periods, and 15% of rows missing at random. For the {cells}\npost-treatment cells with paired base/current observations on its\n*derived* cohort labels, hand-built pairs and §csdid bal(pair)§ reproduce\nits coefficients within {error}.", cells=str(supported), error=bound(err))
    c.render("missing-row unsupported derived cells",
             "This reconstruction has a limit: {cells} additional\npost cells have no paired base observations.", cells=str(unsupported))
    wrong = whole(d("xthdid_relabelled_units"))
    treated = whole(d("xthdid_treated_units"))
    if not 0 < wrong <= treated:
        raise ValueError("missing-row cohort counts require review")
    c.render("missing-row label count", "In this design, {wrong} of {treated} treated units carry a different derived",
             wrong=str(wrong), treated=f"{treated:,}")
    if not d("xthdid_min_signed_dynamic_shift") < 0 < d("xthdid_max_signed_dynamic_shift"):
        raise ValueError("missing-row event shift no longer varies in sign")
    c.render("missing-row event shift", "moves the event study by up to {value}, with a sign that varies across",
             value=f"{d('xthdid_max_abs_dynamic_shift'):.4f}")
    user = whole(d("usercohort_post_cells"))
    if (user <= 0 or whole(d("usercohort_total_post_cells")) != user or
        d("usercohort_unavailable_post_cells") != 0 or d("usercohort_xthdid_finite_without_pair") != 0):
        raise ValueError("missing-row usercohort support requires review")
    usererr = max(d("usercohort_pair_max_abs"), d("usercohort_csdid_max_abs"))
    c.render("usercohort cell count", "time when the gap is present.\" With the true cohorts supplied, all {cells}\npost-treatment cells in this design match both the hand-built true-label\npairs and §csdid, method(reg) nevertreated bal(pair)§ within {error}.",
             cells=str(user), error=bound(usererr))
    code = whole(d("usercohort_never_missing_rc"))
    if code != 3301:
        raise ValueError("missing-coded usercohort no longer reproduces the recorded internal error")
    c.render("missing-coded never-treated usercohort", "an internal error, r({code}), in this probe.", code=str(code))
    excluded = whole(d("jwdid_removed_rows"))
    units = whole(d("jwdid_predicted_removed_units"))
    if excluded <= 0 or units <= 0 or d("jwdid_predicted_removed_rows") != excluded or d("jwdid_data_rows_removed") != 0:
        raise ValueError("missing-row jwdid estimation sample requires review")
    c.render("jwdid excluded observations", "our 15%-missingness panel it excluded {rows} observations from {units} unit\nwithout announcing the exclusion. The dataset itself retained every row.",
             rows=str(excluded), units=str(units))
    return c.text, c.count


def render_claims(text, e):
    c = Claims(text)
    def m(group, regime, pkg, h, field="bias"):
        return e.metric(group, regime, pkg, h, field)
    def b(pkg, h=0, regime="balanced", field="bias"):
        return m("sampling_main", regime, pkg, h, field)
    def cov(pkg, h=0, regime="bal_ok", field="bias"):
        return m("covariates_panel", regime, pkg, h, field)
    def master(pkg, h, field="bias"):
        return m("master", "master", pkg, h, field)
    c.rewrite("balanced imputation point agreement",
              "On a balanced panel, §jwdid§ and §did_imputation§ give identical point estimates, with and without covariates. They don't agree on standard errors as they consider different types of uncertainty, but we will discuss this more later.",
              "In the balanced-panel simulations below, the largest absolute point-estimate gaps between §jwdid§ and §did_imputation§ are {nox} without covariates and {cov} in the linear-outcome covariate design. Their standard errors reflect different sources of uncertainty, as we discuss below.",
              nox=f"{e.paired_gap('sampling_main',('balanced',),'jwdid','bjs'):.3g}",
              cov=f"{e.paired_gap('covariates_panel',('bal_ok',),'jwdid','bjs'):.3g}")
    c.rewrite("balanced csdid dcdh point agreement",
              "In fact, with balanced panel data and no covariates, §csdid§'s event study point estimates coincide with §did_multiplegt_dyn§, as both use not-yet-treated units as the comparison group and anchor the baseline period to the last untreated period available, g-1.",
              "In the balanced-panel simulations without covariates, the largest absolute point-estimate gap between §csdid§ and §did_multiplegt_dyn§ is {gap}. Both use not-yet-treated comparison units and anchor the baseline at g-1.",
              gap=f"{e.paired_gap('sampling_main',('balanced',),'csdid','dcdh'):.3g}")
    c.rewrite("heterogeneity point agreement",
              "Take §jwdid§ and §did_imputation§,\nwhich agree to six decimal places in the exercise above.",
              "In the separate 50,000-unit heterogeneous-effects draw, the largest absolute\npoint-estimate gap between §jwdid§ and §did_imputation§ is {gap}.",
              gap=f"{e.diagnostic('publication_hetx_max_abs_point_difference'):.3g}")
    c.rewrite("dcdh point inference diagnostic",
              "In designs\nwhere their point estimates coincide, their standard errors still differ by",
              "In the separate 20,000-unit balanced-panel diagnostic, the maximum absolute\npoint-estimate gap is {gap}, while the standard errors differ by",
              gap=f"{e.diagnostic('publication_dcdh_max_abs_point_difference'):.3g}")
    c.render("lpdid relative bias", "The §lpdid§ bias is {pct}% of the true effect.", pct=f"{100 * abs(b('lpdid')) / 2:.1f}")
    c.render("lpdid rw remedy", "e=0 falls from {old} to {new} and coverage returns to {cover}.",
             old=f"{b('lpdid'):+.2f}", new=f"{b('lpdid_rw'):+.3f}", cover=f"{b('lpdid_rw', field='coverage'):.2f}")
    ratios = [100 * (b("jwdid_uc", h, reg, "mean_se") / b("jwdid", h, reg, "mean_se") - 1)
              for reg in ("balanced", "varmiss", "unbalanced") for h in range(3)]
    c.rewrite("unconditional widening",
              "Point estimates do not change along this\nroute; the standard errors widen by {lo} to {hi}% in our designs, and this is",
              "Across the three sampling designs, the maximum absolute point-estimate gap\nbetween the default and unconditional routes is {gap}. The standard errors\nwiden by {lo} to {hi}% in these designs, and this is",
              gap=f"{e.paired_gap('sampling_main',('balanced','varmiss','unbalanced'),'jwdid','jwdid_uc'):.3g}",
              lo=f"{min(ratios):.0f}",hi=f"{max(ratios):.0f}")
    competitor_cover = [b(pkg, regime="varmiss", field="coverage") for pkg in ("jwdid", "bjs", "dcdh", "lpdid")]
    c.render("unequal sampling coverage range", "effect only {lo}% to {hi}% of the time.",
             lo=f"{100 * min(competitor_cover):.0f}", hi=f"{100 * max(competitor_cover):.0f}")
    c.render("unequal sampling rw", "improves from {old} to {new} and coverage from {clo} to {chi}, which is still",
             old=f"{b('lpdid', regime='varmiss'):+.2f}", new=f"{b('lpdid_rw', regime='varmiss'):+.2f}",
             clo=f"{b('lpdid', regime='varmiss', field='coverage'):.2f}", chi=f"{b('lpdid_rw', regime='varmiss', field='coverage'):.2f}")
    c.rewrite("RCS sampling bias",
              "When period sizes differ, however, the bias of the observation-weighted\ncommands is {first} at e=0 and {last} at e=2.",
              "When period sizes differ, the bias for §jwdid§ is {first} at e=0 and\n{last} at e=2.",
              first=f"{m('sampling_main','rcsvar','jwdid',0):+.2f}",last=f"{m('sampling_main','rcsvar','jwdid',2):+.2f}")
    c.require("RCS bias sign change", "Hence, the bias changes sign over\nthe event-study horizon.",m('sampling_main','rcsvar','jwdid',0)*m('sampling_main','rcsvar','jwdid',2) < 0)
    covers = [m('sampling_main','rcsvar','csdid',h,'coverage') for h in (0,2)]
    c.rewrite("RCS csdid bias",
              "At the same event times, the biases for §csdid§ are {first}\nand {last}, with nominal coverage.",
              "At the same event times, the biases for §csdid§ are {first}\nand {last}, with coverage {clo} to {chi}.",
              first=f"{m('sampling_main','rcsvar','csdid',0):.3f}",last=f"{m('sampling_main','rcsvar','csdid',2):.3f}",clo=f"{min(covers):.2f}",chi=f"{max(covers):.2f}")
    cell_bias = [abs(row['bias']) for (group, reg, pkg, h), row in e.metrics.items()
                 if group == 'sampling_main' and pkg in ('csdid', 'csdidpair') and h >= 1000 and row.get('bias') is not None]
    if not cell_bias:
        raise ValueError("sampling cell-bias evidence is absent")
    c.rewrite("worst cell bias",
              "Across all the settings in this part\nof the guide, its individual ATT(g,t) estimates are within {value} of their\npopulation values.",
              "Across the settings in this part of the guide, the largest absolute\nMonte Carlo bias among the reported ATT(g,t) cells is {value}.", value=f"{max(cell_bias):.3f}")
    c.render("covariate dcdh horizon bias", "§did_multiplegt_dyn§, the bias is {first} at e=0 and increases to {last} at\ne=2.",
             first=f"{cov('dcdh'):+.3f}", last=f"{cov('dcdh', 2):+.2f}")
    c.render("intro interaction bias", "the bias of §eventstudyinteract§ estimates grows from {first} at e=0 to {last} at e=2",
             first=f"{cov('sa'):+.2f}", last=f"{cov('sa', 2):+.2f}")
    c.render("intro interaction coverage", "with coverage of {cover}, while §csdid§ remains unbiased",
             cover="zero" if round(cov("sa", 2, field="coverage"), 2) == 0 else f"{cov('sa', 2, field='coverage'):.2f}")
    c.render("calendar-time design", "principle. Over {reps} replications, §csdid dr§ has a bias of {first} at e=0 and\n{last} at e=2. The §controls()§ route starts at {ctl_first} and reaches {ctl_last},",
             reps=str(e.data['groups']['ctvar']['reps']), first=f"{m('ctvar','ctvar','csdid_dr',0):+.3f}",
             last=f"{m('ctvar','ctvar','csdid_dr',2):+.3f}", ctl_first=f"{m('ctvar','ctvar','dcdh',0):+.3f}", ctl_last=f"{m('ctvar','ctvar','dcdh',2):+.3f}")
    c.render("tnp diagnostic", "e=2 from {old} to {new} over {reps} replications, but does not eliminate it,",
             old=f"{cov('dcdh',2):+.2f}", new=f"{e.diagnostic('tnp_x1_e2_bias'):+.2f}", reps="100")
    rc_biases = [m('covariates_rc',reg,'csdid',h) for reg in ('rcs','rcsvar') for h in range(3)]
    rc_covers = [m('covariates_rc',reg,'csdid',h,'coverage') for reg in ('rcs','rcsvar') for h in range(3)]
    c.rewrite("covariate RCS results",
              "In\nthe repeated-cross-section experiment, §csdid dr§ remains centered around\nthe population target under both sampling schemes.",
              "In the covariate repeated-cross-section runs, §csdid§ biases range from\n{lo} to {hi} across the three horizons and both period-size designs, with\ncoverage {clo} to {chi}.",lo=f"{min(rc_biases):+.3f}",hi=f"{max(rc_biases):+.3f}",clo=f"{min(rc_covers):.2f}",chi=f"{max(rc_covers):.2f}")
    c.render("outcome misspecification tail", "bias also increases with the horizon: for §jwdid§, it reaches {bias} at e=2,\nwith coverage of {cover}.",
             bias=f"{cov('jwdid',2,'bal_owrong'):+.2f}", cover=f"{cov('jwdid',2,'bal_owrong','coverage'):.2f}")
    c.rewrite("nonlinear outcome observed robustness",
              "§csdid ipw§ remains consistent because the\ntreatment-probability model is correct. §csdid dr§ remains consistent for the\nsame reason: one of its two working models is correctly specified.",
              "The observed §csdid dr§ biases at e=0,1,2 are {d0}, {d1}, and {d2};\nthe §ipw§ biases are {i0}, {i1}, and {i2}. These results describe the\napproximate working models in this design, rather than proving a clean\none-model-correct consistency case.",
              **{f"d{h}":f"{cov('csdid_dr',h,'bal_owrong'):+.3f}" for h in range(3)},
              **{f"i{h}":f"{cov('csdid_ipw',h,'bal_owrong'):+.3f}" for h in range(3)})
    c.rewrite("variance-shift propensity experiment",
              "We then misspecify the propensity score. Our first simulation design for\nthis exercise did not work, and it is useful to explain why. We allowed the\nspread of the continuous covariate to differ across cohorts, a feature that\na logit linear in X cannot represent. Nevertheless, even §ipw§ remained\nwell behaved. The fitted logit projects cohort selection onto the included\ncovariates. In this design, the remaining approximation error was nearly\northogonal to functions that were linear in those covariates. Because the\nuntreated trend was also linear in them, the propensity-score error had\nlittle effect on the target. This example also highlights that one should be\ncareful when designing misspecification exercises: the misspecification\nmatters here only if its remaining error is related to the untreated trend.",
              "An additional variance-shift design lets the spread of the continuous\ncovariate differ across cohorts, creating selection that a linear logit\ncannot represent. The observed §ipw§ biases at e=0,1,2 are {p0}, {p1},\nand {p2}. Nonlinearity in the score alone does not determine the size of\nthe bias: its interaction with the untreated outcome trend matters.",
              **{f"p{h}":f"{cov('csdid_ipw',h,'bal_pwrong'):+.3f}" for h in range(3)})
    c.render("propensity bias path", "horizon: {b0}, {b1}, and {b2}. One cell-level illustration is",
             **{f"b{h}":f"{cov('csdid_ipw',h,'bal_ps2'):+.2f}" for h in range(3)})
    c.render("propensity cell bias and SE", "bias of {bias} and a standard error of {ipw_se}. The standard error for §dr§ is\n{dr_se}.",
             bias=f"{cov('csdid_ipw',5006,'bal_ps2'):+.2f}", ipw_se=f"{cov('csdid_ipw',5006,'bal_ps2','mean_se'):.2f}", dr_se=f"{cov('csdid_dr',5006,'bal_ps2','mean_se'):.2f}")
    missing_sets = {}
    for pkg in ('csdid_ipw','csdid_dr'):
        selected = [row for row in e.data.get('decline_sets',[]) if (row['dataset_id'],row['regime'],row['pkg'],int(row['h'])) == ('covariates_panel','bal_ps2',pkg,1)]
        if len(selected) != 1:
            raise ValueError("propensity-score decline-set evidence absent or duplicated")
        row = selected[0]
        attempted = int(row['attempted'])
        observed = row['finite_estimate_reps']
        missing = row['missing_estimate_reps']
        if (attempted != e.metrics[('covariates_panel','bal_ps2',pkg,1)]['attempted'] or
            len(observed) != e.metrics[('covariates_panel','bal_ps2',pkg,1)]['finite_estimates'] or
            len(set(observed)) != len(observed) or len(set(missing)) != len(missing) or
            set(observed)&set(missing) or set(observed)|set(missing) != set(range(1,attempted+1))):
            raise ValueError("propensity-score decline sets do not partition the prescribed draws")
        missing_sets[pkg] = set(missing)
    c.rewrite("overlap denominator",
              "There is also an overlap issue in this design. In {declined} of the {attempted} draws,\n§csdid§ does not estimate the cell with the worst overlap and reports the\nviolation. The §ipw§ and §dr§ results in the table are therefore conditional\non draws that pass this check. If anything, this makes the reported §ipw§\nresults look better because the excluded draws have the most extreme\nweights. None of the other commands in the comparison performs this check.",
              "For the event study at e=1, §ipw§ has missing estimates in {declined} of\n{attempted} draws, and §dr§ in {dr_declined}. The missing-draw sets differ in\n{different} draws. Each arm's table entries condition on its finite estimates;\ncoverage additionally requires a finite positive standard error. These\ndenominators are retained with the simulation outputs.",
              declined=str(len(missing_sets['csdid_ipw'])),attempted=str(attempted),dr_declined=str(len(missing_sets['csdid_dr'])),different=str(len(missing_sets['csdid_ipw']^missing_sets['csdid_dr'])))
    agreement = e.diagnostic("target_check_three_decimal_agreements")
    expected_agreement = sum(f"{e.diagnostic(f'target_check_e{h}_population'):.3f}" == f"{e.diagnostic(f'target_check_e{h}_empirical'):.3f}" for h in range(3))
    if agreement != expected_agreement:
        raise ValueError("target-check rounding count differs from its measured targets")
    c.rewrite("large-draw closed-form check",
              "Before any Monte Carlo runs, the scripts verify this closed form against a\nsingle draw with 200,000 units; the simulated averages agree to three\ndecimal places.",
              "A separate draw with 200,000 units gives empirical-minus-closed-form\ndifferences of {d0}, {d1}, and {d2} at event times 0, 1, and 2. Rounding the\ntargets and empirical averages to three decimals gives equal values for\n{matches} of the three horizons.",
              **{f"d{h}":f"{e.diagnostic(f'target_check_e{h}_difference'):+.6f}" for h in range(3)},matches=str(int(agreement)))
    arms,seeds,horizons = e.equivalence_gate()
    c.render("literal-command gate scope", "§eqgate.do§ checks {arms} refactored arms against their literal commands on\n{seeds} seeds, at all {horizons} reported horizons.", arms=str(arms),seeds=str(seeds),horizons=str(horizons))
    c.render("master draw count", "Bias and coverage of nominal 95% intervals at each event time, over {reps}\nreplications with $$n={n}$$:",
             reps=str(e.data['groups']['master']['reps']), n=f"{e.data['groups']['master']['n']:,}".replace(",", "{,}"))
    mean0 = master('lpdid_ctl',0)+master('lpdid_ctl',0,'truth')
    mean2 = master('lpdid_ctl',2)+master('lpdid_ctl',2,'truth')
    c.require("master bias sign change", "First, the bias changes sign.",master('lpdid_ctl',0)>0>master('lpdid_ctl',2))
    if min(mean0,mean2) <= 0:
        raise ValueError("master mean effects no longer remain positive at both endpoints")
    c.rewrite("master bias and effect path",
              "§lpdid controls()§ moves from $${first}$$ at $$e=0$$\nto $${last}$$ at $$e=2$$. In an application this would be read as a positive\neffect that decays and then reverses &mdash; dynamics that are simply not\nthere. We find this the most sobering row of the table: not because the bias\nis large, but because its shape imitates a finding.",
              "The bias of §lpdid controls()§ moves from $${first}$$ at $$e=0$$ to\n$${last}$$ at $$e=2$$. Its mean estimated effects are $${mean0}$$ and\n$${mean2}$$, while the true effects are $${truth0}$$ and $${truth2}$$.\nThe estimated dynamics are distorted, although the mean estimated effect\nremains positive at both endpoints. A sign change in bias is not itself a\nsign change in the treatment effect.",
              first=f"{master('lpdid_ctl',0):+.2f}",last=f"{master('lpdid_ctl',2):+.2f}",mean0=f"{mean0:.2f}",mean2=f"{mean2:.2f}",truth0=f"{master('lpdid_ctl',0,'truth'):.2f}",truth2=f"{master('lpdid_ctl',2,'truth'):.2f}")
    c.rewrite("master interaction mechanism comparison",
              "interactions is biased by $${b0}$$, $${b1}$$, $${b2}$$ &mdash;\nmatching, digit for digit, its bias in a companion design that carries\nMechanism 2 alone.",
              "interactions is biased by $${b0}$$, $${b1}$$, $${b2}$$.\nRelative to the separately simulated Mechanism 2 design, the bias differences\nare $${d0}$$, $${d1}$$, and $${d2}$$.",
              **{f"b{h}": f"{master('sa_xt',h):+.3f}" for h in range(3)},
              **{f"d{h}": f"{master('sa_xt',h)-m('cohorthet','cohorthet','sa_xt',h):+.3f}" for h in range(3)})
    c.rewrite("master pooling mechanism comparison",
              "Likewise §lpdid rw§ and §did_multiplegt_dyn§ match their values in the\ndesign that carries Mechanism 1 alone: their failure is entirely the\ncalendar-time pooling. The two mechanisms neither mask nor amplify each\nother. Each command fails for exactly the reason its structure predicts,\nwhich is what gives us confidence that the table is measuring design, not\naccident.",
              "For §lpdid rw§, the bias differences from the separately simulated\nMechanism 1 design are $${l0}$$, $${l1}$$, and $${l2}$$. For\n§did_multiplegt_dyn§ they are $${d0}$$, $${d1}$$, and $${d2}$$.\nThese Monte Carlo comparisons use different sample sizes and draw counts,\nso exact agreement of the simulated means is not expected. The single-mechanism\ndesigns isolate the two channels; the combined design shows their joint effect.",
              **{f"l{h}": f"{master('lpdid_rw',h)-m('ctvar','ctvar','lpdid_rw',h):+.3f}" for h in range(3)},
              **{f"d{h}": f"{master('dcdh',h)-m('ctvar','ctvar','dcdh',h):+.3f}" for h in range(3)})
    c.render("master csdid coverage", "carries the estimation and composition pieces jointly: coverage {lo} to\n  {hi} in the table, with no options required.",
             lo=f"{min(master('csdid_dr',h,'coverage') for h in range(3)):.2f}", hi=f"{max(master('csdid_dr',h,'coverage') for h in range(3)):.2f}")
    c.render("master imputation coverage", "conservative inference under heterogeneity: coverage {lo} to {hi} here.",
             lo=f"{min(master('bjs',h,'coverage') for h in range(3)):.2f}", hi=f"{max(master('bjs',h,'coverage') for h in range(3)):.2f}")
    c.render("master fixed-composition coverage", "realized composition: coverage falls to {cover} at $$e=2$$.", cover=f"{master('jwdid',2,'coverage'):.2f}")
    c.render("master unconditional coverage", "reports coverage {cover} &mdash; at standard errors {pct}% wider.",
             cover=f"{master('jwdid_uc',2,'coverage'):.2f}", pct=f"{100 * (master('jwdid_uc',2,'mean_se') / master('jwdid',2,'mean_se') - 1):.0f}")
    ratios = [100 * (m(group,reg,'jwdid_uc',h,'mean_se') / m(group,reg,'jwdid_uc',h,'sd') - 1)
              for group, regs in [('sampling_main',('balanced',)), ('covariates_panel',('bal_ok',))]
              for reg in regs for h in range(3)]
    covers = [m(group,reg,'jwdid_uc',h,'coverage')
              for group, regs in [('sampling_main',('balanced',)), ('covariates_panel',('bal_ok',))]
              for reg in regs for h in range(3)]
    c.render("unconditional realized-SD range", "this guide its mean standard errors run {lo} to {hi}% above the Monte Carlo\n  standard deviation (coverage {clo}&ndash;{chi}),",
             lo=f"{min(ratios):.0f}", hi=f"{max(ratios):.0f}", clo=f"{min(covers):.2f}", chi=f"{max(covers):.2f}")
    se_ratio = master('jwdid_uc',2,'mean_se')/master('jwdid',2,'mean_se')
    c.rewrite("master unconditional uncertainty share",
              "Under heterogeneity\n  this rich, treating the realized cohorts as fixed is not a technicality;\n  it is a third of the reported uncertainty.",
              "The difference between the default and unconditional standard errors\n  is {share}% of the unconditional standard error at e=2.",share=f"{100*(1-1/se_ratio):.0f}")
    c.rewrite("master unconditional SE and SD",
              "and land almost exactly on\n  it here at $$e=2$$, where the heterogeneity is strongest.",
              "while its mean standard error is\n  {ratio} times its Monte Carlo standard deviation here at $$e=2$$.",
              ratio=f"{e.diagnostic('master_jwdid_uc_e2_mean_se_sd_ratio'):.3f}")
    cs, pool = b('csdid',field='sd'), b('jwdid',field='sd')
    if not 0 < pool < cs:
        raise ValueError("iid standard-deviation ordering requires review")
    c.rewrite("iid precision prose",
              "standard deviation of {pool}, compared with {cs} for §csdid§, and are about\n{pct}% more precise.",
              "standard deviation of {pool}, compared with {cs} for §csdid§: a\n{pct}% smaller standard deviation.",pool=f"{pool:.3f}",cs=f"{cs:.3f}",pct=f"{100*(1-pool/cs):.0f}")
    cs = m('unitroot','unitroot','csdid',0,'sd'); pool = m('unitroot','unitroot','jwdid',0,'sd')
    if not 0 < cs < pool:
        raise ValueError("unit-root standard-deviation ordering requires review")
    c.render("unit-root precision prose", "a unit and the ranking reverses: the standard deviation is {cs} for\n§csdid§ and {pool} for §jwdid§ and §did_imputation§, a difference of about\n{pct}%.",
             cs=f"{cs:.3f}", pool=f"{pool:.3f}", pct=f"{100*(1-cs/pool):.0f}")
    uniform = e.joint_value('csdid_band','uniform_band','bands')
    points = [e.joint_value(pkg) for pkg in ('jwdid','bjs','dcdh')]
    points.append(e.joint_value('csdid_band','pointwise','bands'))
    c.render("joint precision prose", "The uniform band has joint coverage of {band}. Using three pointwise 95%\nintervals as if they covered the entire path gives joint coverage between\n{lo} and {hi} among the unbiased estimators, a loss of roughly {loss_lo} to {loss_hi}\npercentage points. The {lpdid} coverage for §lpdid§ mainly reflects its bias,",
             band=f"{uniform:.3f}", lo=f"{min(points):.3f}", hi=f"{max(points):.3f}",
             loss_lo=f"{100*(.95-max(points)):.0f}", loss_hi=f"{100*(.95-min(points)):.0f}", lpdid=f"{e.joint_value('lpdid'):.3f}")
    hero = [m('hero','varmiss',pkg,0,'coverage') for pkg in HERO_LABELS.values() if pkg != 'csdid']
    c.render("hero alternative text", "csdid is centered on the truth with {cs}% coverage, while the other five commands are biased with coverage between {lo}% and {hi}%]",
             cs=f"{100*m('hero','varmiss','csdid',0,'coverage'):.0f}", lo=f"{100*min(hero):.0f}", hi=f"{100*max(hero):.0f}")
    # Deterministic diagnostics are authenticated just like raw MC files. Their
    # producers use different output schemas, so their named scalars are explicit.
    if e.diagnostic("publication_hetx_verified_horizons") != 3 or e.diagnostic("publication_dcdh_verified_horizons") != 3:
        raise ValueError("point/inference diagnostic horizon labels require review")
    c.render("heterogeneity SE diagnostic", "the difference between them grew from {first}% at event time 0 to {last}% at event time 2.",
             first=f"{e.diagnostic('publication_hetx_e0_se_gap_percent'):.0f}", last=f"{e.diagnostic('publication_hetx_e2_se_gap_percent'):.0f}")
    c.render("dcdh SE diagnostic", "about {lo}&ndash;{hi}% in the example we report in the code appendix.",
             lo=f"{e.diagnostic('publication_dcdh_min_se_gap_percent'):.0f}", hi=f"{e.diagnostic('publication_dcdh_max_se_gap_percent'):.0f}")
    c.require("eight-decimal point agreement", "the two returned identical point estimates to eight decimal places.",
              round(e.diagnostic("sa_balanced_max_abs_point_difference"), 8) == 0)
    if e.diagnostic('lpdid_n1000_bias_mcse') < 0 or e.diagnostic('lpdid_n4000_bias_mcse') < 0:
        raise ValueError("negative Monte Carlo standard error")
    if e.diagnostic('master_jwdid_uc_e2_mean_se_sd_ratio') <= 0:
        raise ValueError("invalid unconditional standard-error/SD ratio")
    c.rewrite("larger-sample lpdid check",
              "We obtain essentially the same\nbias when n is increased to 4,000, so this is not Monte Carlo noise.",
              "At n=1,000 the estimated bias is {b1} (Monte Carlo standard error {s1});\nat n=4,000 it is {b4} (Monte Carlo standard error {s4}).",
              b1=f"{e.diagnostic('lpdid_n1000_bias'):+.4f}",s1=f"{e.diagnostic('lpdid_n1000_bias_mcse'):.4f}",
              b4=f"{e.diagnostic('lpdid_n4000_bias'):+.4f}",s4=f"{e.diagnostic('lpdid_n4000_bias_mcse'):.4f}")
    rendered, missing_claims = render_missing_row_claims(c.text, e)
    return rendered, c.count + missing_claims


def check_hero(path, evidence):
    rows = list(csv.DictReader(pathlib.Path(path).open()))
    observed = {row['label']: row for row in rows}
    if len(rows) != 6 or set(observed) != set(HERO_LABELS):
        raise ValueError("hero labels must name exactly the six plotted commands")
    for label, pkg in HERO_LABELS.items():
        expected = evidence.metrics.get(('hero','varmiss',pkg,0))
        if expected is None:
            raise ValueError(f"hero metric absent: {pkg}")
        row = observed[label]
        for field in ('bias','coverage'):
            if not math.isclose(float(row[field]), expected[field], abs_tol=1e-12, rel_tol=1e-12):
                raise ValueError(f"hero figure label differs from raw simulations: {label}/{field}")
        if int(row['reps']) != expected['finite_se']:
            raise ValueError(f"hero replication count differs: {label}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('statistics', nargs='?', default=STATISTICS, type=pathlib.Path)
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--article', type=pathlib.Path, default=ARTICLE)
    ap.add_argument('--hero-check', type=pathlib.Path, default=HERO)
    args = ap.parse_args()
    try:
        evidence = Evidence(args.statistics)
        original = args.article.read_text()
        rendered, rows = render_tables(original, evidence)
        rendered, claims = render_claims(rendered, evidence)
        check_hero(args.hero_check, evidence)
        if rendered != original:
            if args.write:
                args.article.write_text(rendered)
                print(f'rendered all {rows} statistical rows and {claims} numerical narrative claims')
            else:
                raise ValueError('published statistical tables or narrative differ from the fresh campaign; run with --write')
        print(f'reliability verified: all {rows} statistical rows, {claims} narrative claims, six hero labels; {evidence.inputs} authenticated inputs')
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit(str(error))


if __name__ == '__main__':
    main()
