#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Compare the reliability figures published in the comparison article against a
# fresh Monte Carlo summary.
#
# The speed numbers are generated from a committed results file and gated. The
# reliability numbers -- bias and coverage, 67 table rows -- are not: they were
# computed on 2026-08-02 and the estimation engine changed on 08-06 and again
# on 08-07. Nothing proved they still held.
#
# This does not rewrite anything. It reports, per cell, what the article says
# and what the simulation now produces, so a number that moved is a decision
# rather than a silent edit.
#
# Usage:
#   python3 tools/release/check-reliability-tables.py <mcsum-output.txt>
#   python3 tools/release/check-reliability-tables.py <summary> --tolerance 0.02
# ---------------------------------------------------------------------------

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
ARTICLE = ROOT / "website" / "articles" / "csdid-against-the-field.md"

# Published table -> the simulation regime that produces it.
TABLES = {
    "Balanced panel, no covariates: bias and coverage at e=0": "balanced",
    "Unequal period sizes: bias and coverage at e=0": "varmiss",
}

# Article label -> the estimator label mcsum.py prints.
LABELS = {
    # mcsum labels csdid by its bal() mode; the article names the command
    "csdid": "csdid bal(none)",
    "csdid (any bal() mode)": "csdid bal(none)",
    "jwdid": "jwdid",
    "jwdid uncond": "jwdid uncond",
    "did_imputation": "did_imputation",
    "did_imputation wtr": "did_imputation wtr",
    "did_multiplegt_dyn": "did_multiplegt_dyn",
    "lpdid": "lpdid",
    "lpdid rw": "lpdid rw",
    "eventstudyinteract": "eventstudyinteract",
}


def published():
    """Every (table, estimator) -> (bias, coverage) the article prints."""
    text = ARTICLE.read_text(encoding="utf-8")
    out = {}
    for title, regime in TABLES.items():
        i = text.find(title)
        if i < 0:
            sys.exit(f"published table not found in the article: {title!r}")
        for line in text[i:i + 2000].splitlines():
            if not line.startswith("|"):
                continue
            cells = [c.strip() for c in line.split("|")[1:-1]]
            if len(cells) < 3 or set(cells[0]) <= set("- "):
                continue
            name = cells[0].replace("`", "").replace("**", "").strip()
            if name in ("estimator",):
                continue
            def num(x):
                x = x.replace("**", "").replace("+", "").strip()
                try:
                    return float(x)
                except ValueError:
                    return None
            bias, cover = num(cells[1]), num(cells[2])
            if bias is None and cover is None:
                continue
            out[(regime, name)] = (bias, cover)
    return out


def measured(summary_path):
    """Parse the ES(0) block of an mcsum.py summary into
    (regime, estimator) -> (bias, coverage)."""
    text = pathlib.Path(summary_path).read_text(encoding="utf-8")
    i = text.find("event study ES(0)")
    if i < 0:
        sys.exit("no 'event study ES(0)' block in the summary -- wrong file?")
    block = text[i:]
    nxt = block.find("event study ES(1)")
    if nxt > 0:
        block = block[:nxt]
    out = {}
    for line in block.splitlines():
        # The bias column carries an explicit sign, so it must accept '+'.
        # Without it only negative-bias rows parsed -- which silently reduced
        # the comparison to the five worst cells and still reported success.
        m = re.match(r"\s+(\S+)\s+(.+?)\s+(\d+)\s+([-+\d.]+)\s+([-+\d.]+)\s+"
                     r"([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*$", line)
        if not m:
            continue
        # columns: reps bias sd rmse meanSE cover95
        # Reading group(5) here took `sd` for `bias`, which produced five
        # false "moved" reports whose COVERAGE matched the article exactly --
        # that mismatch is what gave the error away.
        regime, est = m.group(1), m.group(2).strip()
        bias, cover = float(m.group(4)), float(m.group(8))
        out[(regime, est)] = (bias, cover)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("summary")
    ap.add_argument("--bias-tolerance", type=float, default=0.01,
                    help="how far a published bias may sit from the re-run")
    ap.add_argument("--coverage-tolerance", type=float, default=0.03,
                    help="how far a published coverage may sit from the re-run")
    args = ap.parse_args()

    pub, meas = published(), measured(args.summary)
    if not pub:
        sys.exit("parsed no published reliability cells -- refusing to report agreement")
    if not meas:
        sys.exit("parsed no measured cells from the summary -- refusing to report agreement")

    moved, checked, unmatched = [], 0, []
    for (regime, name), (pb, pc) in sorted(pub.items()):
        key = (regime, LABELS.get(name, name))
        if key not in meas:
            unmatched.append(f"{regime}/{name}")
            continue
        mb, mc = meas[key]
        checked += 1
        db = None if pb is None else abs(pb - mb)
        dc = None if pc is None else abs(pc - mc)
        if (db is not None and db > args.bias_tolerance) or \
           (dc is not None and dc > args.coverage_tolerance):
            moved.append((regime, name, pb, mb, pc, mc))

    print(f"reliability cells checked: {checked} of {len(pub)} published")
    if unmatched:
        print(f"  no measured counterpart for {len(unmatched)}: {', '.join(unmatched)}")
    # Reporting agreement while most cells went unchecked is the failure this
    # tool exists to prevent, one level up. A run that matched only a minority
    # is not evidence about the article.
    if checked < len(pub) / 2:
        print(f"\nonly {checked} of {len(pub)} cells had a counterpart -- that is not "
              "a verification. Either the summary lacks these arms (run the option-arm "
              "scripts too) or the label map is wrong.", file=sys.stderr)
        sys.exit(1)
    if moved:
        print(f"\n{len(moved)} published cell(s) disagree with the re-run:\n")
        print(f"  {'regime':<10}{'estimator':<22}{'bias pub':>10}{'bias new':>10}"
              f"{'cov pub':>9}{'cov new':>9}")
        for regime, name, pb, mb, pc, mc in moved:
            print(f"  {regime:<10}{name:<22}{pb if pb is not None else float('nan'):>10.4f}"
                  f"{mb:>10.4f}{pc if pc is not None else float('nan'):>9.3f}{mc:>9.3f}")
        print("\nNothing was rewritten. Decide each one before editing the article.")
        sys.exit(1)
    print("every published reliability cell agrees with the re-run, within tolerance")


if __name__ == "__main__":
    main()
