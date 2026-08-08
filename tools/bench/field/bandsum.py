#!/usr/bin/env python3
# Run from the bench/ folder of the replication package.
# Usage:  python3 bandsum.py <bands.csv> <ladder.csv>
"""Joint (simultaneous) coverage of the three post-treatment event times.

An event study is a family of estimates, so the question is how often the
whole path is covered at once, not how often one horizon is. This reads two
simulation CSVs and reports, for each interval construction, the fraction of
replications in which ES(0), ES(1) and ES(2) are ALL covered.

  * csdid uniform band: the multiplier-bootstrap band, stored as one row per
    horizon with h = 400 + horizon, the lower endpoint in the est column and
    the upper endpoint in the se column.
  * csdid three pointwise CIs: the same draws, est +/- 1.96*se at each of the
    three horizons, counted jointly.
  * every rival: est +/- 1.96*se at each of the three horizons on the
    balanced-panel rows of the ladder run, counted jointly.

A replication is counted only if all three horizons are present and usable;
the count that entered each rate is printed so a thinned cell cannot pass
itself off as a full one.

Usage:  bandsum.py BANDS.csv LADDER.csv
"""
import csv, math, sys, collections

ES_TRUTH = {0: 2.0, 1: 2.5, 2: 3.0}
BAND_OFFSET = 400                                  # h = 400 + horizon
Z = 1.959964

PKG = {"csdid": "csdid bal(none)", "jwdid": "jwdid", "bjs": "did_imputation",
       "dcdh": "did_multiplegt_dyn", "lpdid": "lpdid", "flexdid": "flexdid",
       "csdidpair": "csdid bal(pair)"}
ORDER = ["csdid", "csdidpair", "jwdid", "bjs", "dcdh", "lpdid", "flexdid"]

def num(x):
    try:
        v = float(x)
        return None if math.isnan(v) else v
    except Exception:
        return None

def load(path):
    return list(csv.DictReader(open(path)))

def joint_band(rows, regime="bands", pkg="csdid_band"):
    """Fraction of reps whose uniform band contains all three truths."""
    got = collections.defaultdict(dict)
    for r in rows:
        if r["regime"] != regime or r["pkg"] != pkg:
            continue
        h = int(r["h"])
        if BAND_OFFSET <= h <= BAND_OFFSET + 2:
            lo, hi = num(r["est"]), num(r["se"])
            if lo is not None and hi is not None:
                got[int(r["rep"])][h - BAND_OFFSET] = (lo, hi)
    full = [v for v in got.values() if len(v) == 3]
    hit = sum(1 for v in full
              if all(v[h][0] <= ES_TRUTH[h] <= v[h][1] for h in (0, 1, 2)))
    return hit, len(full)

def joint_pointwise(rows, regime, pkg):
    """Fraction of reps whose three pointwise 95% CIs all contain the truth."""
    got = collections.defaultdict(dict)
    for r in rows:
        if r["regime"] != regime or r["pkg"] != pkg:
            continue
        h = int(r["h"])
        if h in (0, 1, 2):
            e, s = num(r["est"]), num(r["se"])
            if e is not None and s is not None and s > 0:
                got[int(r["rep"])][h] = (e, s)
    full = [v for v in got.values() if len(v) == 3]
    hit = sum(1 for v in full
              if all(abs(v[h][0] - ES_TRUTH[h]) <= Z * v[h][1] for h in (0, 1, 2)))
    return hit, len(full)

def line(lab, hit, n):
    rate = hit / n if n else float("nan")
    print(f"  {lab:<34}{rate:>8.3f}   ({hit} of {n} reps)")

def main(bands_path, ladder_path):
    bands, ladder = load(bands_path), load(ladder_path)

    print("== joint coverage of ES(0), ES(1), ES(2) ==")
    print(f"  truths: {ES_TRUTH[0]}, {ES_TRUTH[1]}, {ES_TRUTH[2]}\n")

    line("csdid uniform band", *joint_band(bands))
    line("csdid three pointwise CIs", *joint_pointwise(bands, "bands", "csdid_band"))

    seen = {r["pkg"] for r in ladder if r["regime"] == "balanced"}
    for pkg in [p for p in ORDER if p in seen]:
        hit, n = joint_pointwise(ladder, "balanced", pkg)
        if n:
            line(f"{PKG.get(pkg, pkg)} pointwise", hit, n)

    print("\n== per-horizon pointwise coverage, same reps (diagnostic) ==")
    for lab, rows, regime, pkg in (
            [("csdid (bands run)", bands, "bands", "csdid_band")] +
            [(PKG.get(p, p), ladder, "balanced", p) for p in ORDER if p in seen]):
        got = collections.defaultdict(dict)
        for r in rows:
            if r["regime"] != regime or r["pkg"] != pkg:
                continue
            h = int(r["h"])
            if h in (0, 1, 2):
                e, s = num(r["est"]), num(r["se"])
                if e is not None and s is not None and s > 0:
                    got[int(r["rep"])][h] = (e, s)
        full = [v for v in got.values() if len(v) == 3]
        rates = []
        for h in (0, 1, 2):
            c = sum(1 for v in full if abs(v[h][0] - ES_TRUTH[h]) <= Z * v[h][1])
            rates.append(c / len(full) if full else float("nan"))
        print(f"  {lab:<34}" + "".join(f"{x:>8.3f}" for x in rates) +
              f"   (n={len(full)})")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
