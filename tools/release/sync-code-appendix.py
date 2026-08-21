#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Keep website/code-appendix.md and the scripts in the tree byte-identical.
#
# The appendix opens by promising that every number in the comparison article
# comes from one of the scripts reproduced on that page. That promise is only
# as good as the two copies agreeing, and nothing about a fenced code block
# announces that the script it shows has moved on -- a benchmark gains a column
# for Stata's native xthdidregress and hdidregress, and the published copy goes
# on showing the version without them.
#
# Direction of truth: the file in the tree is what runs, so the file wins and
# the appendix is regenerated from it. The reverse would let an edit made in a
# markdown page silently become the thing readers are told was executed.
#
# Scripts that exist ONLY in the appendix are reported, and --materialize
# writes them into the tree so that every published script has exactly one home.
#
# Usage:
#   python3 tools/release/sync-code-appendix.py            # check, exit 1 on drift
#   python3 tools/release/sync-code-appendix.py --write     # regenerate blocks
#   python3 tools/release/sync-code-appendix.py --materialize
# ---------------------------------------------------------------------------

import argparse
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
APPENDIX = ROOT / "website" / "code-appendix.md"

# Where a published script may live.
#
# Deliberately NOT the session workshop folder. That folder is stripped from
# the public payload, so a published script sourced from it would leave the
# shipped tree carrying this gate and not the file it checks -- the gate would
# fail for anyone who ran the suite after installing. Five scripts were in
# exactly that position when this was written (dgp, validate, time, runners,
# scalebench) and were moved here.
#
# The invariant is checked below rather than trusted: a published script whose
# only source is inside a stripped path is reported, not resolved.
SEARCH = [
    ROOT / "tools" / "bench" / "field",
]

# Paths build-release-payload.sh removes from the public tree. Read from the
# builder rather than restated, so the two cannot drift apart.
def stripped_paths():
    builder = ROOT / "tools" / "release" / "build-release-payload.sh"
    if not builder.exists():
        return []
    text = builder.read_text(encoding="utf-8")
    m = re.search(r'STRIP_PATHS="(.*?)"', text, re.S)
    if not m:
        return []
    return [ROOT / p for p in m.group(1).replace("\\\n", " ").split()]


def inside_stripped(path, stripped):
    for s in stripped:
        try:
            path.relative_to(s)
            return s
        except ValueError:
            continue
    return None
# Where a script with no home yet is written by --materialize.
MATERIALIZE_INTO = ROOT / "tools" / "bench" / "field"

BLOCK = re.compile(
    r"(<summary><code>(?P<name>[^<]+)</code>.*?</summary>\s*<pre><code>)"
    r"(?P<body>.*?)(</code></pre>)",
    re.S,
)


def source_of(name):
    for base in SEARCH:
        p = base / name
        if p.exists():
            return p
    return None


def norm(text):
    """Compare ignoring a trailing newline only. Source files in this tree are
    written without one; a published block gains one. That difference is an
    artifact of the round trip and never a difference in what runs. Nothing
    else is normalised -- indentation and trailing spaces inside a script can
    change what Stata does."""
    return text.rstrip("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="regenerate drifted appendix blocks from the tree")
    ap.add_argument("--materialize", action="store_true",
                    help="write appendix-only scripts into the tree")
    args = ap.parse_args()

    text = APPENDIX.read_text(encoding="utf-8")
    matches = list(BLOCK.finditer(text))
    if not matches:
        sys.exit(f"no code blocks found in {APPENDIX} -- this tool is checking nothing")

    names = [m.group("name").strip() for m in matches]
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        sys.exit(f"duplicate block names in the appendix: {sorted(dupes)}; "
                 "a name must identify one script")

    stripped = stripped_paths()
    drifted, orphans, matched, unshipped = [], [], 0, []
    for m in matches:
        name = m.group("name").strip()
        published = html.unescape(m.group("body"))
        src = source_of(name)
        if src is None:
            orphans.append((name, published))
            continue
        where = inside_stripped(src, stripped)
        if where is not None:
            unshipped.append((name, src, where))
        if norm(published) == norm(src.read_text(encoding="utf-8")):
            matched += 1
        else:
            drifted.append((name, src))

    if args.materialize:
        if not orphans:
            print("every published script already has a source file")
            return
        for name, published in orphans:
            target = MATERIALIZE_INTO / name
            if target.exists():
                continue
            body = published if published.endswith("\n") else published + "\n"
            target.write_text(body, encoding="utf-8")
            if name.endswith(".sh"):
                target.chmod(0o755)
            print(f"  wrote {target.relative_to(ROOT)}")
        return

    if args.write:
        if not drifted:
            print("nothing to regenerate")
            return
        out, last = [], 0
        for m in matches:
            name = m.group("name").strip()
            src = source_of(name)
            if src is None or norm(html.unescape(m.group("body"))) == norm(
                    src.read_text(encoding="utf-8")):
                continue
            body = html.escape(src.read_text(encoding="utf-8"), quote=False)
            if not body.endswith("\n"):
                body += "\n"
            out.append(text[last:m.start("body")])
            out.append(body)
            last = m.end("body")
            print(f"  regenerated {name} from {src.relative_to(ROOT)}")
        out.append(text[last:])
        APPENDIX.write_text("".join(out), encoding="utf-8")
        return

    print(f"{matched} published scripts match their source in the tree")
    fail = False
    if drifted:
        fail = True
        print(f"\n{len(drifted)} published script(s) differ from what runs:", file=sys.stderr)
        for name, src in drifted:
            print(f"   {name}  (source: {src.relative_to(ROOT)})", file=sys.stderr)
        print("\n   The file in the tree is what runs, so it wins."
              "\n   Regenerate with: python3 tools/release/sync-code-appendix.py --write",
              file=sys.stderr)
    if unshipped:
        fail = True
        print(f"\n{len(unshipped)} published script(s) are sourced from a path the "
              "release payload strips:", file=sys.stderr)
        for name, src, where in unshipped:
            print(f"   {name}  ({src.relative_to(ROOT)} is inside "
                  f"{where.relative_to(ROOT)})", file=sys.stderr)
        print("\n   The shipped tree would carry this gate and not the file it"
              "\n   checks, so the suite would fail after installation. Move the"
              "\n   script into a directory that ships.", file=sys.stderr)
    if orphans:
        fail = True
        print(f"\n{len(orphans)} published script(s) have no source file in the tree:",
              file=sys.stderr)
        print("   " + ", ".join(n for n, _ in orphans), file=sys.stderr)
        print("\n   A script that exists only inside a markdown page cannot be run,"
              "\n   linted, or diffed. Write them into the tree with:"
              "\n   python3 tools/release/sync-code-appendix.py --materialize",
              file=sys.stderr)
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
