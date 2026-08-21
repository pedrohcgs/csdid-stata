#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Every speed number stated in PROSE must be traceable to a published table.
#
# Tables are generated and checked against the benchmark results, so they
# cannot go stale. The sentences around them can, and that is the likelier
# failure: re-measure, refresh the tables, and leave a paragraph saying jwdid
# takes about three times as long when the new table says ten.
#
# Two kinds of claim are checked, and only inside the speed sections:
#
#   a timing   "1.21 seconds", "0.60s"  -> must appear as a cell in a table
#   a ratio    "about 10 times", "5.3x" -> must equal the ratio of two cells
#              in the same row of one table, at the rounding the prose uses
#
# A number that is neither -- a sample size, a period count, a percentage --
# is not matched. A number that is genuinely not from a table can be listed in
# ALLOWED with the reason, which is a deliberate act rather than a silence.
#
# Usage: python3 tools/release/check-website-speed-prose.py
# ---------------------------------------------------------------------------

import json
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
RESULTS = ROOT / "tools" / "bench" / "field" / "results"
GEN = ROOT / "tools" / "bench" / "make-field-speed-tables.py"

FIELD = ROOT / "website" / "articles" / "csdid-against-the-field.md"
LADDER = ROOT / "website" / "articles" / "speed-vs-182.md"

# Which fragments belong to which article, and where each article's speed
# prose starts and stops. Outside these bounds the article is about estimands,
# coverage and weights, where a number like 2.0 is a treatment effect.
ARTICLES = {
    FIELD: {
        "fragments": ["csdid-only.md", "balanced.md", "unbalanced.md",
                      "rcs.md", "periods.md", "cohorts.md"],
        "start": "## Speed",
        "stop": "## Reliability, part I",
        # csdid is the first timing column; the prose compares rivals to it
        "ratio_rule": "vs-first-column",
        "timing_columns": "all",
    },
    LADDER: {
        "fragments": ["v182-size.md", "v182-periods.md", "v182-cohorts.md",
                      "v182-scheme.md"],
        "start": "# Speed against Version 1.82",
        "stop": None,
        # columns are 1.82, 2.0.0, gain -- the gain IS the ratio, and it is a
        # published cell rather than something a reader computes
        "ratio_rule": "first-over-second",
        "timing_columns": "drop-last",
    },
}

# Numbers in the speed prose that are not table cells. Each needs a reason.
ALLOWED = {
    # (article stem, literal as written): why it is not in a table
    ("csdid-against-the-field", "120.1 seconds"):
        "the warmup call that put xthdidregress past this harness's per-call "
        "cap at T=40; it is recorded in that table's own note, which is why "
        "the cell is empty",
    ("speed-vs-182", "35x"):
        "the top of the seven-trial A/B certification table shipped in the "
        "package README, a different harness at fixed sample size; the page "
        "cites that table's range rather than restating its rows",
    ("csdid-against-the-field", "10x"):
        "the low end of the Version 1.82 page's range, not this article's "
        "tables; that cross-page claim is checked by "
        "tests/meta/test-website-speed-claims.sh",
    ("csdid-against-the-field", "308x"):
        "the high end of the same range, checked by the same gate",
}

TIMING = re.compile(r"(?<![\d.])(\d+\.\d+)\s*(?:seconds|second|s\b)")
RATIO_WORDS = re.compile(r"about (\d+(?:\.\d+)?) times")
RATIO_X = re.compile(r"(?<![\d.])(\d+(?:\.\d+)?)x\b")


def generate(tmp):
    meta = {}
    mp = RESULTS / "metadata.json"
    if mp.exists():
        meta = json.loads(mp.read_text())
    proc = subprocess.run(
        [sys.executable, str(GEN), "--results", str(RESULTS / "scalebench-results.csv"),
         "--outdir", tmp, "--stata", meta.get("stata", "?"),
         "--platform", meta.get("platform", "?"), "--date", meta.get("date", "?"),
         "--trials", str(meta.get("trials", ""))],
        capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"the table generator refused:\n{proc.stderr}")


def cells_of(fragment_text):
    """The TIMING cells of each table row, in column order.

    The first two columns are dropped: they are the design lever and the row
    count, not timings. That matters -- the periods table's first column holds
    5, 10, 20, 40, and treating those as seconds would let prose quote a
    period count as though it were a measurement."""
    rows = []
    for line in fragment_text.splitlines():
        if not line.startswith("|") or set(line) <= set("| -:"):
            continue
        cells = [c.strip().replace("**", "") for c in line.split("|")[1:-1]]
        if len(cells) <= 2:
            continue
        vals = []
        for cell in cells[2:]:
            c = cell.rstrip("sx")
            vals.append(float(c) if re.fullmatch(r"\d+(\.\d+)?", c) else None)
        if any(v is not None for v in vals):
            rows.append(vals)
    return rows


def main():
    if not (RESULTS / "scalebench-results.csv").exists():
        sys.exit(f"no results of record at {RESULTS}; run the benchmark first")

    failures, checked = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        generate(tmp)
        for article, spec in ARTICLES.items():
            rows, values = [], set()
            for name in spec["fragments"]:
                p = pathlib.Path(tmp) / name
                if not p.exists():
                    continue
                text = p.read_text(encoding="utf-8")
                for r in cells_of(text):
                    rows.append(r)
                    # the gain column is a ratio, not a timing: keeping it in
                    # the timing set would let prose quote "35" as seconds
                    timing = r[:-1] if spec["timing_columns"] == "drop-last" else r
                    values.update(v for v in timing if v is not None)
            if not rows:
                continue

            # Ratios against csdid ONLY, within a row.
            #
            # Every pair of cells in every row would be a dense set: with the
            # tables' spread, almost any small number is some pair's ratio to
            # within rounding, and the check would pass whatever the prose
            # said. csdid is the first timing column in every table here, and
            # "N times as long as csdid" is what the prose actually claims.
            ratios = set()
            for r in rows:
                if spec["ratio_rule"] == "first-over-second":
                    if len(r) >= 2 and r[0] and r[1]:
                        ratios.add(r[0] / r[1])
                    # The gain is a PUBLISHED cell, computed from the full
                    # precision timings. Recomputing it from the rounded
                    # neighbours the page prints gives 336 where the cell says
                    # 334, so the cell itself has to count.
                    if len(r) >= 3 and r[2]:
                        ratios.add(r[2])
                else:
                    base = r[0]
                    if not base:
                        continue
                    for v in r[1:]:
                        if v:
                            ratios.add(v / base)

            body = article.read_text(encoding="utf-8")
            i = body.find(spec["start"])
            if i < 0:
                failures.append(f"{article.name}: no section {spec['start']!r}")
                continue
            j = body.find(spec["stop"], i) if spec["stop"] else len(body)
            prose = body[i:j if j > 0 else len(body)]
            # the tables themselves live inside the section; drop table lines
            prose = "\n".join(ln for ln in prose.splitlines()
                              if not ln.startswith("|") and "table-note" not in ln)

            def ok_value(x):
                return any(abs(x - v) < 5e-3 for v in values)

            def ok_ratio(x):
                # "about 10 times" is satisfied by anything that rounds to 10
                # at the precision written; "5.3x" needs a tighter match.
                tol = 0.5 if float(x).is_integer() else 0.05
                return any(abs(x - r) <= tol for r in ratios)

            for m in TIMING.finditer(prose):
                checked += 1
                x = float(m.group(1))
                if (article.stem, m.group(0)) in ALLOWED or ok_value(x):
                    continue
                failures.append(f"{article.name}: prose says {m.group(0)!r}, "
                                "which is not a cell in any of its tables")
            for pat in (RATIO_WORDS, RATIO_X):
                for m in pat.finditer(prose):
                    checked += 1
                    x = float(m.group(1))
                    if (article.stem, m.group(0)) in ALLOWED or ok_ratio(x):
                        continue
                    failures.append(f"{article.name}: prose says {m.group(0)!r}, "
                                    "which is not the ratio of two cells in any "
                                    "row of its tables")

    if failures:
        print(f"{len(failures)} of {checked} prose numbers are not supported by "
              "the published tables:\n", file=sys.stderr)
        for f in sorted(set(failures)):
            print(f"  {f}", file=sys.stderr)
        sys.exit(1)
    if checked == 0:
        sys.exit("no prose numbers were checked -- this gate is checking nothing")
    print(f"website speed prose OK: {checked} stated numbers all trace to a table")


if __name__ == "__main__":
    main()
