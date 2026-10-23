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
import math

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



def expected_results():
    """The published grid: 142 main-tier rows and 30 legacy-ladder rows."""
    result = {}
    def cell(scan, n, t, g, packages, rows=None, scheme="", legacy_trials=None):
        for package in packages.split():
            trials = (legacy_trials if package == "csdid_182" else 7) if scan.startswith("F_") else 10
            result[(scan, n, t, g, package, scheme)] = (rows if rows is not None else n*t, trials)
    for n in (1000, 10000, 100000):
        cell("G_bal",n,10,4,"csdid_analytical jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn xthdid")
        cell("A_unbal",n,10,4,"csdid_balfull csdid_balpair csdid_balnone jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn xthdid",{1000:8496,10000:85219,100000:849905}[n])
        cell("B_rcs",n,10,4,"csdid flexdid jwdid did_imputation hdid csdid_cov flexdid_cov jwdid_cov did_imputation_cov hdid_cov")
    for t in (5,10,20,40):
        cell("C_periods",10000,t,4,"csdid jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn xthdid")
    for g in (3,6,12,18):
        cell("D_cohorts",10000,20,g,"csdid jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn xthdid")
    for n in (100,1000,10000,100000):
        cell("E_default",n,10,4,"csdid_analytical csdid_boot999")
    for n,trials in ((1000,7),(5000,5),(20000,3),(50000,2),(100000,2)):
        cell("F_n",n,10,4,"csdid_200 csdid_182",legacy_trials=trials)
    for t,trials in ((5,7),(10,5),(20,3),(40,2)):
        cell("F_T",5000,t,4,"csdid_200 csdid_182",legacy_trials=trials)
    for g,trials in ((3,3),(6,3),(12,2)):
        cell("F_G",5000,20,g,"csdid_200 csdid_182",legacy_trials=trials)
    for scheme in ("balanced","unbalanced","rcs"):
        cell("F_scheme",10000,10,4,"csdid_200 csdid_182",85219 if scheme=="unbalanced" else 100000,scheme,3)
    return result


def validate_complete_results(path):
    expected, seen = expected_results(), set()
    with open(path, newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != "scan,n_units,T,cohorts,rows,pkg,median_seconds,trials,ok,note".split(","):
            raise SystemExit("invalid published speed-results schema")
        for row in reader:
            scheme = ""
            if row["scan"] == "F_scheme":
                match = re.search(r"scheme=(\w+)", row.get("note", ""))
                scheme = match.group(1) if match else ""
            key = (row["scan"],int(row["n_units"]),int(row["T"]),int(row["cohorts"]),row["pkg"],scheme)
            if key not in expected or key in seen:
                raise SystemExit(f"unexpected or duplicated speed observation: {key}")
            seen.add(key)
            rows, trials = expected[key]
            if int(row["rows"]) != rows or row["ok"] not in ("-1","0","1"):
                raise SystemExit(f"invalid speed design or result status: {key}")
            observed_trials = int(row["trials"])
            if row["ok"] == "1":
                seconds = float(row["median_seconds"])
                if not math.isfinite(seconds) or seconds <= 0 or observed_trials != trials:
                    raise SystemExit(f"invalid timing or trial count: {key}")
            else:
                if row["median_seconds"] != ".":
                    raise SystemExit(f"unsuccessful observation must not carry a timing: {key}")
                if key[4].startswith("csdid") and key[4] != "csdid_182":
                    raise SystemExit(f"current command has no successful timing: {key}")
                if row["ok"] == "-1" and (observed_trials != 0 or "cap" not in row.get("note", "")):
                    raise SystemExit(f"invalid capped speed observation: {key}")
                if observed_trials not in (0,trials) or not row.get("note", "").strip():
                    raise SystemExit(f"untimed observation lacks its prescribed trials or reason: {key}")
    missing = set(expected)-seen
    if missing:
        raise SystemExit(f"incomplete published speed grid: {len(seen)} of {len(expected)} observations; first missing {sorted(missing)[0]}")
    return len(seen)


def all_requested_horizons_dropped(note):
    horizon = re.search(r"(?:^|;\s*)H=(\d+)(?:;|$)", note)
    dropped = re.search(r"(?:^|;\s*)autosample dropped:\s*([^;]*)", note)
    if not horizon or not dropped:
        return False
    requested = {f"tau{h}" for h in range(int(horizon[1]) + 1)}
    return requested <= set(re.findall(r"\btau\d+\b", dropped[1]))


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


def build_gain_table(cells, meta, scan, title, unit_label, candidate_version="2.0.0"):
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
             f"| {head} | rows | 1.82 | {candidate_version} | gain |",
             "| --- | ---: | ---: | ---: | ---: |"]

    skipped = []
    for i, k in enumerate(keys):
        row = cells[k]
        leg = row.get("csdid_182", (None,))[0]
        cand = row.get("csdid_200", (None,))[0]
        if cand is None:
            raise SystemExit(
                f"{scan} {k}: no candidate timing -- the harness always runs the candidate "
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
            vals = []
            for p in pkgs:
                cell = row.get(p + suffix, (None, None, ""))
                marker = "†" if cell[0] is not None and all_requested_horizons_dropped(cell[2]) else ""
                vals.append(fmt(cell[0]) + marker)
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
    if any(cell[0] is not None and all_requested_horizons_dropped(cell[2])
           for k in keys for cell in cells[k].values()):
        full += (" Entries marked † record invocation time only: autosample dropped "
                 "every requested horizon, so no requested effects or inference were returned.")
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
        for p, (secs, _, note) in sorted(row.items(), key=lambda x: (x[1][0] is None, x[1][0] or 0)):
            if secs and not p.startswith(CSDID_FIRST) and not all_requested_horizons_dropped(note):
                out.append((k[1], p, secs, secs / b))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True)
    ap.add_argument("--outdir")
    ap.add_argument("--validate-only", action="store_true")
    ap.add_argument("--candidate-version", default="2.0.0")
    ap.add_argument("--stata")
    ap.add_argument("--platform")
    ap.add_argument("--date")
    ap.add_argument("--trials", default="")
    args = ap.parse_args()

    count = validate_complete_results(args.results)
    if args.validate_only:
        print(f"complete published speed grid: {count} observations")
        return
    if not all((args.outdir,args.stata,args.platform,args.date)) or not re.fullmatch(r"\d+\.\d+\.\d+",args.candidate_version):
        ap.error("rendering requires --outdir, --stata, --platform, --date and a valid --candidate-version")
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
        ("E_default", "csdid-only.md", "`csdid` on a balanced panel, seconds for estimation and event-study aggregation", "n"),
    ]

    shared_note = (
        "Every entry is the median of the timed runs after a discarded warmup. "
        "Commands that deliver the event study in a second call &mdash; `csdid`, "
        "`jwdid`, `xthdidregress` and `hdidregress` &mdash; are charged for that "
        "call as well as the estimation call."
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
        frag = build_gain_table(cells, meta, scan, title, unit, args.candidate_version)
        (outdir / fname).write_text(frag, encoding="utf-8")
        print(f"  wrote {fname}", file=sys.stderr)

    provenance = (
        f"The timing campaign in this section completed on {args.date} with "
        f"{args.stata} on {args.platform}"
        + (f", {args.trials} timed runs per cell in the main tiers" if args.trials else "")
        + ". The main tiers use separate Stata processes; the Version 1.82 "
          "comparisons use a fresh process per cell and implementation."
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
