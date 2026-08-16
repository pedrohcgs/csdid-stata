#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Does the live site match this source?
#
# Every website gate here reads the markdown in website/. None of them reads
# what psantanna.com/csdid actually serves, and those are different repositories.
# On 2026-08-07 the source was corrected -- the published speed range paired one
# table's floor with another's ceiling -- and the live site kept serving the
# wrong figure until it was republished by hand a day later. Every gate stayed
# green throughout, because none of them could see the published page.
#
# Same shape as the shipped plugin that sat nine days behind its own source: an
# artifact nothing exercised.
#
# Compares the BUILT html, file by file, against what the site repository holds.
# Not a numbers-only spot check: a stale page usually differs in prose too, and
# a comparison that looks only where it expects trouble finds only the trouble
# it expected.
#
# Usage:
#   python3 tools/release/check-published-site.py
#   CSDID_SITE_ROOT=/path/to/pedrohcgs.github.io python3 ...
#
# Exit 0 match, 1 drift, 2 cannot check (no site checkout, or no Jekyll). Two
# is distinct on purpose: a check that could not run is not a check that passed.
# ---------------------------------------------------------------------------

import hashlib
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SITE_ROOT = pathlib.Path(
    os.environ.get("CSDID_SITE_ROOT", pathlib.Path.home() / "Documents/GitHub/pedrohcgs.github.io")
).expanduser()
LIVE = SITE_ROOT / "csdid"


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    if not (SITE_ROOT / ".git").is_dir():
        print(f"cannot check: no site repository at {SITE_ROOT}", file=sys.stderr)
        print("  set CSDID_SITE_ROOT to a checkout of pedrohcgs/pedrohcgs.github.io",
              file=sys.stderr)
        return 2
    if not LIVE.is_dir():
        print(f"cannot check: {LIVE} does not exist", file=sys.stderr)
        return 2
    if not shutil.which("jekyll"):
        print("cannot check: jekyll is not on PATH, so the source cannot be built",
              file=sys.stderr)
        print("  gem install --user-install jekyll kramdown-parser-gfm", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        build = pathlib.Path(tmp) / "site"
        proc = subprocess.run(
            ["jekyll", "build", "--destination", str(build)],
            cwd=ROOT / "website", capture_output=True, text=True)
        if proc.returncode != 0:
            print("the Jekyll build failed:", file=sys.stderr)
            print(proc.stderr[-2000:], file=sys.stderr)
            return 2

        built = {p.relative_to(build): p for p in build.rglob("*") if p.is_file()}
        live = {p.relative_to(LIVE): p for p in LIVE.rglob("*") if p.is_file()}
        if not built:
            print("the build produced no files -- refusing to report a match", file=sys.stderr)
            return 2

        missing = sorted(set(built) - set(live))
        extra = sorted(set(live) - set(built))
        differ = sorted(k for k in set(built) & set(live)
                        if digest(built[k]) != digest(live[k]))

        print(f"built {len(built)} files, live has {len(live)}")
        if not (missing or extra or differ):
            print("the live site matches this source")
            return 0

        print("\nthe live site does NOT match this source:", file=sys.stderr)
        for k in missing:
            print(f"   built here but not live: {k}", file=sys.stderr)
        for k in extra:
            print(f"   live but not built here: {k}", file=sys.stderr)
        for k in differ:
            print(f"   differs: {k}", file=sys.stderr)
        print("\n   republish with: bash tools/release/publish-website.sh --push",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
