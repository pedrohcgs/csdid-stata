#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Extract a script from website/code-appendix.md back into a runnable file.
#
# The appendix is the published contract: it states that every number in the
# comparison article comes from one of the scripts reproduced on that page.
# Some of those scripts have no other copy in the tree, so re-measuring with a
# freshly written harness would quietly break that promise -- the page would
# describe one protocol and the tables would come from another.
#
# This extracts the published text verbatim, undoing only the HTML escaping
# that publishing applied, so the script that runs IS the script on the page.
#
# Usage:
#   python3 tools/bench/extract-appendix-script.py --list
#   python3 tools/bench/extract-appendix-script.py --name scalebench_f.sh --out <dir>
# ---------------------------------------------------------------------------

import argparse
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
APPENDIX = ROOT / "website" / "code-appendix.md"

# <summary><code>NAME</code> &mdash; description</summary>
# <pre><code>...body...</code></pre>
BLOCK = re.compile(
    r"<summary><code>(?P<name>[^<]+)</code>.*?</summary>\s*"
    r"<pre><code>(?P<body>.*?)</code></pre>",
    re.S,
)


def blocks():
    text = APPENDIX.read_text(encoding="utf-8")
    return [(m.group("name").strip(), m.group("body")) for m in BLOCK.finditer(text)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--name")
    ap.add_argument("--out")
    args = ap.parse_args()

    found = blocks()
    if args.list:
        for name, body in found:
            print(f"{name:<34} {len(body.splitlines()):>5} lines")
        return

    if not args.name or not args.out:
        sys.exit("need --name and --out (or --list)")

    matches = [(n, b) for n, b in found if n == args.name]
    if not matches:
        sys.exit(f"no block named {args.name!r} in {APPENDIX}; try --list")
    if len(matches) > 1:
        sys.exit(f"{len(matches)} blocks named {args.name!r} -- ambiguous, refusing")

    name, body = matches[0]
    # Publishing escaped &, < and > . Nothing else was transformed, so
    # unescaping is the exact inverse and the result is the authored script.
    source = html.unescape(body)
    if not source.endswith("\n"):
        source += "\n"

    outdir = pathlib.Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    target = outdir / name
    target.write_text(source, encoding="utf-8")
    if name.endswith(".sh"):
        target.chmod(0o755)

    # An escaped entity surviving into the output means the unescape missed a
    # case and the script would run differently from the published one.
    leftover = [e for e in ("&gt;", "&lt;", "&amp;", "&quot;", "&#") if e in source]
    if leftover:
        sys.exit(f"{name}: unescaped entities survived: {leftover}")

    print(f"wrote {target} ({len(source.splitlines())} lines)")


if __name__ == "__main__":
    main()
