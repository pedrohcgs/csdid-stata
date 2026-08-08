#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Build the speed tables for the "How csdid compares with other DiD Stata
# commands" article from the benchmark results file, so that no number in the
# article is typed by hand.
#
# The article's tables used to be transcribed. Transcription is how a table
# ends up disagreeing with the run that produced it, and how a provenance line
# ends up naming a Stata release the numbers were not measured on. Everything
# below -- the cells, the column set, the ordering, the ratios quoted in the
# prose, and the provenance line -- is derived from the CSV.
#
# Input:  a scalebench-results.csv written by tools/bench/field/scalebench.do
# Output: one markdown fragment per table, written to a directory
#
# Usage:
#   python3 tools/bench/make-field-speed-tables.py \
#       --results <path to scalebench-results.csv> \
#       --outdir  <directory for the fragments> \
#       --stata "StataNow/MP 19.5" --platform "macOS, 10-core Apple M1 Max" \
#       --date 2026-08-07
# ---------------------------------------------------------------------------

import argparse
import csv
import collections
import re
import pathlib
import sys

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

# How each internal package label is written in the article. A label absent
# from this map is a label the article has no column for, and is a hard error
# rather than a silent omission -- a rival quietly dropped from a speed table
# is the worst failure this script could have.
DISPLAY = {
    "csdid": "`csdid`",
    "csdid_cov": "`csdid`",
    "csdid_analytical": "`csdid`",
    "csdid_boot999": "`csdid` default",
    "csdid_balnone": "`csdid bal(none)`",
    "csdid_balpair": "`csdid bal(pair)`",
    "csdid_balfull": "`csdid bal(full)`",
    "jwdid": "`jwdid`",
    "jwdid_cov": "`jwdid`",
    "lpdid": "`lpdid`",
    "did_imputation": "`did_imputation`",
    "did_imputation_cov": "`did_imputation`",
    "eventstudyinteract": "`eventstudyinteract`",
    "did_multiplegt_dyn": "`did_multiplegt_dyn`",
    "flexdid": "`flexdid`",
    "flexdid_cov": "`flexdid`",
    "xthdid": "`xthdidregress`",
    "hdid": "`hdidregress`",
    "hdid_cov": "`hdidregress`",
}

# Column order within each table: csdid variants first, then rivals by their
# speed at the LARGEST size in that table, so the ordering is a property of
# the measurements rather than of the author's preference.
CSDID_FIRST = ("csdid", "csdid_")


def fmt(seconds):
    """Two significant-looking decimals below 10s, one above, matching the
    article's existing convention. A missing cell prints an em dash rather
    than a blank, so a gap is visibly a gap."""
    if seconds is None:
        return "&mdash;"
    if seconds < 10:
        return f"{seconds:.2f}"
    return f"{seconds:.1f}"


# Which lever each scan moves, and therefore what its first column shows.
SCAN_LEVER = {
    "F_n": "n", "F_T": "T", "F_G": "G", "F_scheme": "scheme",
    "C_periods": "T", "D_cohorts": "G",
}


def lever_of(scan):
    return SCAN_LEVER.get(scan, "n")


def load(results_path):
    """Read the results file into {(scan, n, T, G, rows): {pkg: (secs, ...)}}.

    The key carries all four design levers, not just n. The Version 1.82
    scans hold n fixed and move T, or G, or the sampling scheme, so keying on
    n alone would collapse three or four distinct cells into one and silently
    report whichever happened to be read last.

    The sampling scheme is not a column, but the harness writes `scheme=...`
    into every note, so it is read from there. It cannot be inferred from the
    row count: a repeated cross section sampling n per period over T periods
    has exactly as many rows as a balanced panel of n units over T periods.
    Keying on the row count silently collapsed those two cells into one and
    published the repeated-cross-section timings under the balanced label.

    Rows that did not succeed are kept with seconds = None. They must be
    visible: a command that failed or blew the time cap is a finding about
    that command, and dropping it would silently flatter it."""
    cells = collections.defaultdict(dict)
    meta = {}
    with open(results_path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            # The scheme belongs in the key ONLY for the scan that varies it.
            # Elsewhere it is noise: a cell the harness skipped is recorded by
            # the launcher, whose note carries no scheme=, so including it
            # would give the skip row a different key from the cell it belongs
            # to and split one cell into two half-empty ones.
            sch = ""
            if lever_of(row["scan"]) == "scheme":
                m = re.search(r"scheme=(\w+)", row.get("note", "") or "")
                sch = m.group(1) if m else ""
            key = (row["scan"], int(row["n_units"]), int(row["T"]),
                   int(row["cohorts"]), int(row["rows"]), sch)
            secs = float(row["median_seconds"]) if row["ok"] == "1" else None
            cells[key][row["pkg"]] = (secs, int(row["rows"]), row["note"])
            meta.setdefault(key, {}).update(
                {"n": key[1], "T": key[2], "G": key[3], "rows": key[4],
                 "trials": row.get("trials", "")})
    return cells, meta


SCHEME_LABELS = {
    "balanced": "balanced panel",
    "unbalanced": "unbalanced panel (15% of rows deleted)",
    "rcs": "repeated cross sections",
}
SCHEME_ORDER = {"balanced": 0, "unbalanced": 1, "rcs": 2}


def sort_keys(scan, keys):
    """Order a scan's cells by the lever it moves."""
    lever = lever_of(scan)
    if lever == "T":
        return sorted(keys, key=lambda k: k[2])
    if lever == "G":
        return sorted(keys, key=lambda k: k[3])
    if lever == "scheme":
        return sorted(keys, key=lambda k: SCHEME_ORDER.get(k[5], 99))
    return sorted(keys, key=lambda k: k[1])


def row_label(scan, key, position):
    lever = lever_of(scan)
    if lever == "T":
        return f"{key[2]}"
    if lever == "G":
        return f"{key[3]}"
    if lever == "scheme":
        if key[5] not in SCHEME_LABELS:
            raise SystemExit(
                f"{scan}: a cell has no recognised scheme= in its note "
                f"(saw {key[5]!r}); refusing to label it by position, which "
                "is how the wrong timings get the wrong label")
        return SCHEME_LABELS[key[5]]
    return f"{key[1]:,}"


def build_gain_table(cells, meta, scan, title, unit_label):
    """The Version 1.82 page's shape: 1.82, 2.0.0, and the ratio between them.

    A cell the legacy version could not run inside the time cap prints an em
    dash with its reason kept in the note, never a blank that reads as though
    the comparison simply was not attempted."""
    keys = sort_keys(scan, [k for k in cells if k[0] == scan])
    if not keys:
        raise SystemExit(f"no cells for scan {scan!r} -- refusing to write an empty table")

    fixed = []
    if lever_of(scan) != "n":
        fixed.append(f"n={keys[0][1]:,}")
    if lever_of(scan) != "T":
        fixed.append(f"T={keys[0][2]}")
    if lever_of(scan) != "G":
        fixed.append(f"G={keys[0][3]}")
    head = unit_label + (" (" + ", ".join(fixed) + ")" if fixed else "")

    lines = [f'<p class="table-title" markdown="span">{title}</p>', "",
             f"| {head} | rows | 1.82 | 2.0.0 | gain |",
             "| --- | ---: | ---: | ---: | ---: |"]

    skipped = []
    for i, k in enumerate(keys):
        row = cells[k]
        leg = row.get("csdid_182", (None,))[0]
        cand = row.get("csdid_200", (None,))[0]
        if cand is None:
            raise SystemExit(
                f"{scan} {k}: no 2.0.0 timing -- the harness always runs 2.0.0 "
                "first, so a missing one means the cell did not run at all")
        if "csdid_182" not in row:
            # A row that is ABSENT is not a row that was skipped. The harness
            # writes a row for every cell it decides not to time, carrying the
            # reason, so a missing one means the run did not get this far.
            # Publishing it as "not run" would present an interrupted
            # benchmark as a completed one with a deliberate omission.
            raise SystemExit(
                f"{scan} {row_label(scan, k, i)}: no Version 1.82 row at all. "
                "The harness records a row even when it skips a cell, so this "
                "results file is from an incomplete run -- refusing to build a "
                "table that would show it as a deliberate skip.")
        if leg is None:
            note = row.get("csdid_182", (None, None, ""))[2].strip()
            skipped.append((row_label(scan, k, i),
                            note or "recorded as not timed, with no reason given"))
            gain = "&mdash;"
            legs = "not run"
        else:
            gain = f"**{leg / cand:.0f}x**" if leg / cand == max(
                (cells[j].get("csdid_182", (0,))[0] or 0) /
                (cells[j].get("csdid_200", (1,))[0] or 1) for j in keys
            ) else f"{leg / cand:.0f}x"
            legs = f"{leg:.2f}s" if leg < 10 else f"{leg:.1f}s"
        cands = f"{cand:.2f}s" if cand < 10 else f"{cand:.1f}s"
        lines.append(f"| {row_label(scan, k, i)} | {k[4]:,} | {legs} | {cands} | {gain} |")

    if skipped:
        why = "; ".join(f"{lab}: {note}" for lab, note in skipped)
        lines += ["", f'<p class="table-note" markdown="span">Version 1.82 was '
                      f'not timed in every cell &mdash; {why}.</p>']
    return "\n".join(lines) + "\n"


F_SPECS = [
    ("F_n", "v182-size.md", "By sample size, seconds per run", "n"),
    ("F_T", "v182-periods.md", "By number of periods, seconds per run", "T"),
    ("F_G", "v182-cohorts.md", "By number of cohorts, seconds per run", "G"),
    ("F_scheme", "v182-scheme.md", "By sampling scheme, seconds per run", "scheme"),
]


def order_columns(pkgs, cells_at_largest):
    """csdid variants first (in the order given), then rivals ascending by
    their time at the largest size. A rival that failed at the largest size
    sorts last rather than first, which a None would otherwise do."""
    mine = [p for p in pkgs if p.startswith(CSDID_FIRST)]
    rivals = [p for p in pkgs if not p.startswith(CSDID_FIRST)]

    def key(p):
        v = cells_at_largest.get(p, (None,))[0]
        return (v is None, v if v is not None else 0.0)

    return mine + sorted(rivals, key=key)


def build_table(cells, meta, scan, title, unit_label, note, pkg_filter=None):
    keys = sort_keys(scan, [k for k in cells if k[0] == scan])
    if not keys:
        raise SystemExit(f"no cells for scan {scan!r} -- refusing to write an empty table")
    largest = keys[-1]

    seen = []
    for k in keys:
        for p in cells[k]:
            if pkg_filter and p not in pkg_filter:
                continue
            if p not in seen:
                seen.append(p)
    unknown = [p for p in seen if p not in DISPLAY]
    if unknown:
        raise SystemExit(f"no article column defined for: {unknown}")

    # A `_cov' package is the SAME command run with the design's covariate, not
    # a different command, so it must not become a second column with the same
    # header. It becomes a second block of rows under a separator, which is how
    # the published table reads.
    pkgs = order_columns([p for p in seen if not p.endswith("_cov")],
                         cells[largest])
    has_cov = any(p.endswith("_cov") for p in seen)

    # The header names the levers that are HELD FIXED; the first column shows
    # the one that moves. Naming a fixed n in a scan that moves n, or omitting
    # the fixed n from one that does not, is how a reader mis-reads the design.
    lever = lever_of(scan)
    fixed = []
    if lever != "n":
        fixed.append(f"n={keys[0][1]:,}")
    if lever != "T":
        fixed.append(f"T={keys[0][2]}")
    if lever != "G":
        fixed.append(f"G={keys[0][3]}")
    head = unit_label + (" (" + ", ".join(fixed) + ")" if fixed else "")
    header = f"| {head} | rows | " + " | ".join(DISPLAY[p] for p in pkgs) + " |"
    rule = "| --- | ---: | " + " | ".join("---:" for _ in pkgs) + " |"

    lines = [f'<p class="table-title" markdown="span">{title}</p>', "", header, rule]

    def emit(suffix):
        for i, k in enumerate(keys):
            row = cells[k]
            vals = [fmt(row.get(p + suffix, (None,))[0]) for p in pkgs]
            lines.append(f"| {row_label(scan, k, i)} | {meta[k]['rows']:,} | "
                         + " | ".join(vals) + " |")

    emit("")
    if has_cov:
        lines.append("| with a covariate: | | " + " | ".join("" for _ in pkgs) + " |")
        emit("_cov")

    # A cell that was not timed must say WHY, in the table that shows the gap.
    # An em dash on its own reads as "this command cannot do this", when the
    # measured reason may be the opposite -- that it was too slow to trial
    # inside the harness's cap.
    gaps = []
    for i, k in enumerate(keys):
        for p_ in pkgs:
            for suffix in ("", "_cov") if has_cov else ("",):
                cell = cells[k].get(p_ + suffix)
                if cell is not None and cell[0] is not None:
                    continue
                where = row_label(scan, k, i) + (" with a covariate" if suffix else "")
                if cell is None:
                    # No row at all: this arm was never part of the scan. Say
                    # so. An em dash with no note reads as a command that
                    # failed, when it was simply not asked to run.
                    gaps.append(f"{DISPLAY[p_]} at {where}: not run in this scan")
                    continue
                m = re.search(r"not timed: ([^;]+)", cell[2])
                gaps.append(f"{DISPLAY[p_]} at {where}: "
                            + (m.group(1) if m else cell[2].strip() or "not recorded"))
    full = note
    if gaps:
        full = (note + " Cells with no entry were not timed &mdash; "
                + "; ".join(gaps) + ".")
    if full:
        lines += ["", f'<p class="table-note" markdown="span">{full}</p>']
    return "\n".join(lines) + "\n"


def ratio_facts(cells, scan, base="csdid"):
    """The ratios the prose quotes, computed rather than remembered."""
    keys = sort_keys(scan, [k for k in cells if k[0] == scan])
    out = []
    for k in keys:
        row = cells[k]
        b = None
        for cand in (base, "csdid_analytical", "csdid_balfull", "csdid"):
            if cand in row and row[cand][0]:
                b = row[cand][0]
                break
        if not b:
            continue
        for p, (secs, _, _) in sorted(row.items(), key=lambda x: (x[1][0] is None, x[1][0] or 0)):
            if secs and not p.startswith(CSDID_FIRST):
                out.append((k[1], p, secs, secs / b))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--stata", required=True)
    ap.add_argument("--platform", required=True)
    ap.add_argument("--date", required=True)
    ap.add_argument("--trials", default="")
    args = ap.parse_args()

    cells, meta = load(args.results)
    outdir = pathlib.Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    scans = sorted({k[0] for k in cells})
    print(f"scans present: {scans}", file=sys.stderr)

    specs = [
        ("G_bal", "balanced.md", "Balanced panel, seconds per run", "n"),
        ("A_unbal", "unbalanced.md", "Unbalanced panel, 15% of rows deleted, seconds per run", "n"),
        ("B_rcs", "rcs.md", "Repeated cross sections, seconds per run", "n per period"),
        ("C_periods", "periods.md", "Growing the number of periods, seconds per run", "T"),
        ("D_cohorts", "cohorts.md", "Growing the number of cohorts, seconds per run", "G"),
        ("E_default", "csdid-only.md", "`csdid` on a balanced panel, seconds to estimate all ATT(g,t)", "n"),
    ]

    shared_note = (
        "Every entry is the median of the timed runs after a discarded warmup. "
        "Commands that deliver the event study in a second call &mdash; `csdid`, "
        "`jwdid`, `xthdidregress` and `hdidregress` &mdash; are charged for that "
        "call as well as the estimation call, so that every column buys the same "
        "deliverable."
    )

    for scan, fname, title, unit in specs:
        if scan not in scans:
            print(f"  SKIP {scan}: not in this results file", file=sys.stderr)
            continue
        frag = build_table(cells, meta, scan, title, unit, shared_note)
        (outdir / fname).write_text(frag, encoding="utf-8")
        print(f"  wrote {fname}", file=sys.stderr)

    # ---- the Version 1.82 page's four tables, if this file carries tier F
    for scan, fname, title, unit in F_SPECS:
        if scan not in scans:
            continue
        frag = build_gain_table(cells, meta, scan, title, unit)
        (outdir / fname).write_text(frag, encoding="utf-8")
        print(f"  wrote {fname}", file=sys.stderr)

    provenance = (
        f"All timings in this section were measured on {args.date} with "
        f"{args.stata} on {args.platform}"
        + (f", {args.trials} timed runs per cell" if args.trials else "")
        + ", in a single session, so entries are comparable across tables."
    )
    (outdir / "provenance.md").write_text(provenance + "\n", encoding="utf-8")

    facts = []
    for scan in scans:
        for n, pkg, secs, ratio in ratio_facts(cells, scan):
            facts.append(f"{scan:<11} n={n:<7} {pkg:<20} {secs:8.3f}s  {ratio:6.1f}x csdid")
    (outdir / "ratios.txt").write_text("\n".join(facts) + "\n", encoding="utf-8")
    print(f"  wrote provenance.md and ratios.txt", file=sys.stderr)


if __name__ == "__main__":
    main()
