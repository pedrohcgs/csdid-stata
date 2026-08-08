#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Verify that every speed table published on the website is exactly what the
# committed benchmark results produce.
#
# The failure this prevents: a table is edited, or a benchmark is re-run and
# only some tables are refreshed, and the site then reports numbers no run ever
# produced. Nothing about a markdown table announces that it has gone stale.
#
# How it works: the generator writes each table as a fragment beginning with a
# unique `<p class="table-title">` line. That title is located in the target
# article and the block that follows is compared line for line. Locating by
# title means the public pages need no markers, comments, or anything else a
# reader would see.
#
# Usage:
#   python3 tools/release/check-website-speed-tables.py
#   python3 tools/release/check-website-speed-tables.py --write   # refresh them
# ---------------------------------------------------------------------------

import argparse
import pathlib
import subprocess
import sys
import tempfile
import json

ROOT = pathlib.Path(__file__).resolve().parents[2]
RESULTS = ROOT / "tools" / "bench" / "field" / "results"
GEN = ROOT / "tools" / "bench" / "make-field-speed-tables.py"

FIELD = ROOT / "website" / "articles" / "csdid-against-the-field.md"
LADDER = ROOT / "website" / "articles" / "speed-vs-182.md"

# fragment file -> (article, how to find its block in that article)
#
# Two anchor styles, because the two pages are written differently. The
# comparison article labels each table with a <p class="table-title">; the
# Version 1.82 page uses a section heading and no label. Assuming one style
# would have left four tables permanently "not found", which reads as a
# missing table rather than as a checker that cannot see it.
PLACEMENT = {
    "csdid-only.md": (FIELD, "title", None),
    "balanced.md": (FIELD, "title", None),
    "unbalanced.md": (FIELD, "title", None),
    "rcs.md": (FIELD, "title", None),
    "periods.md": (FIELD, "title", None),
    "cohorts.md": (FIELD, "title", None),
    "v182-size.md": (LADDER, "heading", "## By sample size"),
    "v182-periods.md": (LADDER, "heading", "## By number of periods"),
    "v182-cohorts.md": (LADDER, "heading", "## By number of cohorts"),
    "v182-scheme.md": (LADDER, "heading", "## By sampling scheme"),
}


def block_of(fragment):
    """Return (title, full_lines) for a generated fragment.

    full_lines KEEPS the blank lines. They are not padding: a markdown table
    needs a blank line before it, and stripping them produced a page where the
    title, the table and the note ran together and the table stopped rendering
    as a table. Comparison is done on the non-blank lines (see `content`), but
    what gets written back is the fragment as generated."""
    lines = fragment.splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    body = [ln for ln in lines if ln.strip()]
    if not body or not body[0].startswith('<p class="table-title"'):
        raise SystemExit("generated fragment does not start with a table title")
    return body[0], lines


def content(lines):
    """The lines that carry meaning, for comparison. Blank-line placement is
    formatting and is taken from the generator, not diffed against the page."""
    return [ln for ln in lines if ln.strip()]


def find_block(article_lines, anchor, length, style):
    """Return ((block_lines, start, stop), None) for the published block.

    The block's END is found STRUCTURALLY -- title, then the table, then an
    optional table-note paragraph -- not by counting the generated fragment's
    lines. Counting was a real bug: when the generated fragment was longer than
    the published block (a new note line, an extra column row), the span ran
    past the table and swallowed the paragraph after it. It silently deleted
    two lines of prose from the Version 1.82 page before this was caught.

    `length` is therefore unused for locating the end and kept only so callers
    read naturally; it is the caller's job to compare contents.
    """
    hits = [i for i, ln in enumerate(article_lines) if ln.strip() == anchor.strip()]
    if not hits:
        return None, f"anchor {anchor.strip()!r} not found in the article"
    if len(hits) > 1:
        return None, f"anchor {anchor.strip()!r} appears {len(hits)} times; cannot identify one block"

    i = start = hits[0]
    if style == "heading":
        # The heading is not part of the block; the table under it is. A
        # section may open with a paragraph before its table -- the periods
        # section does -- so prose is skipped, but only as far as the NEXT
        # heading. Without that bound a section with no table would silently
        # adopt the next section's.
        i += 1
        while i < len(article_lines) and not article_lines[i].lstrip().startswith("|"):
            if article_lines[i].startswith("#"):
                return None, (f"no table between {anchor.strip()!r} and the next "
                              f"heading {article_lines[i].strip()!r}")
            i += 1
        if i >= len(article_lines):
            return None, f"no table found under {anchor.strip()!r}"
        start = i
    else:
        i += 1  # past the title line

    while i < len(article_lines) and not article_lines[i].strip():
        i += 1
    if i >= len(article_lines) or not article_lines[i].lstrip().startswith("|"):
        return None, f"no table follows {anchor.strip()!r}"
    while i < len(article_lines) and article_lines[i].lstrip().startswith("|"):
        i += 1
    stop = i

    # an optional note paragraph, only if it is the very next non-blank line
    j = i
    while j < len(article_lines) and not article_lines[j].strip():
        j += 1
    if j < len(article_lines) and article_lines[j].lstrip().startswith('<p class="table-note"'):
        stop = j + 1

    return (article_lines[start:stop], start, stop), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="replace the article blocks with the generated ones")
    args = ap.parse_args()

    csv_path = RESULTS / "scalebench-results.csv"
    meta_path = RESULTS / "metadata.json"
    if not csv_path.exists():
        sys.exit(f"no results of record at {csv_path}; run the benchmark and commit its CSV")
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}

    with tempfile.TemporaryDirectory() as tmp:
        proc = subprocess.run(
            [sys.executable, str(GEN),
             "--results", str(csv_path), "--outdir", tmp,
             "--stata", meta.get("stata", "unknown"),
             "--platform", meta.get("platform", "unknown"),
             "--date", meta.get("date", "unknown"),
             "--trials", str(meta.get("trials", ""))],
            capture_output=True, text=True)
        if proc.returncode != 0:
            sys.exit(f"the table generator refused:\n{proc.stderr}")

        failures, checked = [], 0
        edits = {}
        for name, (article, style, anchor) in PLACEMENT.items():
            frag_path = pathlib.Path(tmp) / name
            if not frag_path.exists():
                # The results file may legitimately not carry every scan (for
                # example a field-only run with no tier F). Say so rather than
                # passing silently, so a partial run cannot look complete.
                print(f"  no fragment generated for {name} -- not in the results file")
                continue
            title, want = block_of(frag_path.read_text(encoding="utf-8"))
            if style == "heading":
                # the page carries no table label, so the generated one is not
                # published and must not be written or compared
                want = want[1:]
                while want and not want[0].strip():
                    want.pop(0)
            art_lines = article.read_text(encoding="utf-8").splitlines()
            found, why = find_block(art_lines, anchor if style == "heading" else title,
                                    len(want), style)
            checked += 1
            if found is None:
                failures.append(f"{article.name}: {name}: {why}")
                continue
            got, start, stop = found
            if content(got) != content(want):
                if args.write:
                    edits.setdefault(article, []).append((start, stop, want))
                else:
                    diff = []
                    for a, b in zip(content(got), content(want)):
                        if a != b:
                            diff.append(f"      published: {a}\n      measured:  {b}")
                    if len(content(got)) != len(content(want)):
                        diff.append(f"      published has {len(content(got))} lines, "
                                    f"measured has {len(content(want))}")
                    failures.append(f"{article.name}: {name} differs from the measurement:\n"
                                    + "\n".join(diff[:6]))

        if args.write and edits:
            for article, spans in edits.items():
                lines = article.read_text(encoding="utf-8").splitlines()
                # last span first, so earlier spans keep their indices
                for start, stop, want in sorted(spans, key=lambda x: -x[0]):
                    lines[start:stop] = want
                article.write_text("\n".join(lines) + "\n", encoding="utf-8")
                print(f"  rewrote {len(spans)} table(s) in {article.name}")
            return

        # The provenance sentence is the claim that was false before any of
        # this existed: the article named a Stata release the numbers had not
        # been measured on. Tables being right does not fix that, so the
        # interpreter and the date are checked against the metadata too.
        import datetime
        if meta.get("stata") and meta.get("date"):
            d = datetime.date.fromisoformat(meta["date"])
            human = f"{d.day} {d:%B} {d.year}"
            for article in {a for a, _, _ in PLACEMENT.values()}:
                body = article.read_text(encoding="utf-8")
                if meta["stata"] not in body:
                    failures.append(
                        f"{article.name}: publishes speed tables but never names "
                        f"{meta['stata']}, which is the interpreter that measured them")
                if human not in body:
                    failures.append(
                        f"{article.name}: publishes speed tables but never names "
                        f"the measurement date ({human})")

        if failures:
            print(f"\n{len(failures)} of {checked} published tables disagree with the "
                  f"committed benchmark results:\n", file=sys.stderr)
            for f in failures:
                print(f"  {f}", file=sys.stderr)
            print("\nRe-run with --write to refresh them from the measurement.",
                  file=sys.stderr)
            sys.exit(1)

        if checked == 0:
            sys.exit("no tables were checked -- this gate is checking nothing")
        print(f"website speed tables OK: {checked} tables match the committed results")


if __name__ == "__main__":
    main()
