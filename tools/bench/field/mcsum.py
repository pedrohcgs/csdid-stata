#!/usr/bin/env python3
# Run from the bench/ folder of the replication package.
# Usage:  python3 mcsum.py <results.csv>
"""Monte Carlo summary: bias/SD/RMSE/coverage against FIXED population
targets. Truth is never re-derived from the draws.

Reads one row per (regime, package, rep, horizon) from a simulation CSV and
prints, for each event-study horizon and for the post-treatment average,
the bias against the population target, the spread across draws, the mean
reported standard error, and the coverage of nominal 95% intervals.

Horizon codes: 0/1/2 are event times, 99 is the post-treatment average, and
any code >= 1000 is a group-time cell packed as 1000*g + t.

Usage:  mcsum.py FILE.csv
"""
import csv, math, sys, collections

ES_TRUTH = {0: 2.0, 1: 2.5, 2: 3.0}
# field designs with their own closed-form targets (base, slope in event time)
REGIME_TRUTH = {"master": (2.516667, 0.633333), "cohorthet": (2.516667, 0.633333),
                "breakC": (2.0945, 0.556)}
def es_truth(regime, h):
    base, slope = REGIME_TRUTH.get(regime, (2.0, 0.5))
    return base + slope * h
POST_AVG_TRUTH = (2.0 + 2.5 + 3.0) / 3.0          # equal-weight window(0 2) overall
def cell_truth(code):                              # code = 1000*g + t
    g, t = divmod(code, 1000)
    return (g - 2) + 0.5 * (t - g)

PKG = {"csdid": "csdid bal(none)", "csdidpair": "csdid bal(pair)",
       "csdid_dr": "csdid dr", "csdid_ipw": "csdid ipw", "csdid_reg": "csdid reg",
       "jwdid": "jwdid", "jwdid_uc": "jwdid uncond", "bjs": "did_imputation", "bjs_wtr": "did_imputation wtr", "dcdh": "did_multiplegt_dyn",
       "lpdid": "lpdid", "sa": "eventstudyinteract", "lpdid_rw": "lpdid rw", "flexdid": "flexdid", "csdid_band": "csdid uniform band"}
ORDER = ["csdid", "csdidpair", "csdid_dr", "csdid_ipw", "csdid_reg",
         "jwdid", "jwdid_uc", "bjs", "bjs_wtr", "sa", "dcdh", "lpdid", "lpdid_rw", "flexdid", "csdid_band"]
REGIMES = ["balanced", "varmiss", "unbalanced", "rcs", "rcsvar",
           "bal_ok", "bal_owrong", "bal_pwrong", "bal_pwrong2", "bal_ps2", "unitroot", "bands"]

def num(x):
    try:
        v = float(x)
        return None if math.isnan(v) else v
    except Exception:
        return None

def order_key(pkg):
    return (ORDER.index(pkg), pkg) if pkg in ORDER else (len(ORDER), pkg)

def label(pkg):
    return PKG.get(pkg, pkg)

def regimes_in(rows):
    seen = {r["regime"] for r in rows}
    out = [g for g in REGIMES if g in seen]
    out += sorted(seen - set(out))
    return out

def pkgs_in(rows):
    return sorted({r["pkg"] for r in rows}, key=order_key)

def table(rows, hsel, truth, lab, regs, pkgs):
    print(f"\n== {lab}   default truth = {truth:.4f} (field designs use their own) ==")
    print(f"  {'regime':<11}{'estimator':<20}{'reps':>5}{'bias':>9}{'sd':>8}"
          f"{'rmse':>8}{'meanSE':>8}{'cover95':>8}")
    for regime in regs:
        for pkg in pkgs:
            v = [(num(r["est"]), num(r["se"])) for r in rows
                 if r["regime"] == regime and r["pkg"] == pkg and int(r["h"]) == hsel]
            ok = [(e, s) for e, s in v if e is not None]
            if not v:
                continue
            if not ok:
                print(f"  {regime:<11}{label(pkg):<20}    - unsupported/empty")
                continue
            n = len(ok)
            rtruth = es_truth(regime, hsel) if hsel in (0, 1, 2) else truth
            est = [e for e, _ in ok]
            m = sum(est) / n
            sd = math.sqrt(sum((e - m) ** 2 for e in est) / (n - 1)) if n > 1 else float("nan")
            rmse = math.sqrt(sum((e - rtruth) ** 2 for e in est) / n)
            ses = [s for _, s in ok if s is not None]
            mse = sum(ses) / len(ses) if ses else float("nan")
            cov = [1 if abs(e - rtruth) <= 1.959964 * s else 0
                   for e, s in ok if s is not None and s > 0]
            cvr = sum(cov) / len(cov) if cov else float("nan")
            print(f"  {regime:<11}{label(pkg):<20}{n:>5}{m-rtruth:>+9.4f}{sd:>8.4f}"
                  f"{rmse:>8.4f}{mse:>8.4f}{cvr:>8.3f}")

def usable(rows, regs, pkgs):
    """Replications that produced a usable estimate, per regime and package.

    A replication is attempted if any row exists for it and usable if the
    event-study estimate is non-missing. The difference is the count of
    draws the command declined to estimate (for csdid under a broken
    propensity score, the overlap check that refuses the cell)."""
    print("\n== usable replications (attempted / usable / declined) ==")
    print(f"  {'regime':<11}{'estimator':<20}{'attempt':>8}{'usable':>8}{'declined':>9}")
    att = collections.defaultdict(set)
    use = collections.defaultdict(set)
    for r in rows:
        if int(r["h"]) not in (0, 1, 2):
            continue
        key = (r["regime"], r["pkg"])
        att[key].add(int(r["rep"]))
        if num(r["est"]) is not None:
            use[key].add(int(r["rep"]))
    for regime in regs:
        for pkg in pkgs:
            key = (regime, pkg)
            if key not in att:
                continue
            a, u = len(att[key]), len(use[key])
            print(f"  {regime:<11}{label(pkg):<20}{a:>8}{u:>8}{a-u:>9}")

def cells(rows, regs, pkgs):
    """Cell-level block: every ATT(g,t) cell with its mean reported SE.

    The mean SE column is what makes two estimators on the same cell
    comparable in spread, not only in location."""
    print("\n== ATT(g,t) cells: bias and mean reported SE ==")
    print(f"  {'regime':<11}{'estimator':<20}{'cell':>12}{'reps':>6}"
          f"{'truth':>8}{'bias':>9}{'sd':>8}{'meanSE':>8}{'cover95':>8}")
    acc = collections.defaultdict(list)
    for r in rows:
        h = int(r["h"])
        if h >= 1000:
            e, s = num(r["est"]), num(r["se"])
            if e is not None:
                acc[(r["regime"], r["pkg"], h)].append((e, s))
    for regime in regs:
        for pkg in pkgs:
            codes = sorted(c for (g, p, c) in acc if g == regime and p == pkg)
            for code in codes:
                v = acc[(regime, pkg, code)]
                g, t = divmod(code, 1000)
                truth = cell_truth(code)
                n = len(v)
                est = [e for e, _ in v]
                m = sum(est) / n
                sd = math.sqrt(sum((e - m) ** 2 for e in est) / (n - 1)) if n > 1 else float("nan")
                ses = [s for _, s in v if s is not None]
                mse = sum(ses) / len(ses) if ses else float("nan")
                cov = [1 if abs(e - rtruth) <= 1.959964 * s else 0
                       for e, s in v if s is not None and s > 0]
                cvr = sum(cov) / len(cov) if cov else float("nan")
                print(f"  {regime:<11}{label(pkg):<20}{f'ATT({g},{t})':>12}{n:>6}"
                      f"{truth:>8.3f}{m-rtruth:>+9.4f}{sd:>8.4f}{mse:>8.4f}{cvr:>8.3f}")

def worst_cells(rows, regs, pkgs):
    print("\n== ATT(g,t) cells: worst |bias| over the post grid ==")
    acc = collections.defaultdict(list)
    for r in rows:
        h = int(r["h"])
        if h >= 1000 and num(r["est"]) is not None:
            acc[(r["regime"], r["pkg"], h)].append(float(r["est"]))
    worst = collections.defaultdict(lambda: (0.0, None))
    for (regime, pkg, code), v in acc.items():
        b = abs(sum(v) / len(v) - cell_truth(code))
        if b > worst[(regime, pkg)][0]:
            worst[(regime, pkg)] = (b, code)
    for regime in regs:
        for pkg in pkgs:
            if (regime, pkg) in worst:
                b, code = worst[(regime, pkg)]
                g, t = divmod(code, 1000)
                print(f"  {regime:<11}{label(pkg):<20}max|bias|={b:.4f} at ATT({g},{t})")

def main(path):
    rows = list(csv.DictReader(open(path)))
    print(f"rows: {len(rows)}   reps: {max(int(r['rep']) for r in rows)}")
    regs, pkgs = regimes_in(rows), pkgs_in(rows)
    for h in (0, 1, 2):
        table(rows, h, ES_TRUTH[h], f"event study ES({h})", regs, pkgs)
    table(rows, 99, POST_AVG_TRUTH, "post-treatment average (window 0-2)", regs, pkgs)
    usable(rows, regs, pkgs)
    cells(rows, regs, pkgs)
    worst_cells(rows, regs, pkgs)

if __name__ == "__main__":
    main(sys.argv[1])