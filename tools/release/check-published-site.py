#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Does the local site checkout match this source?
#
# Compares built HTML and assets, file by file, with the csdid/ directory in
# the local website repository. This detects a stale prepared payload. It
# does not inspect a deployment, a remote Git revision, or HTTP responses.
# Publishing and checking the served site are separate release steps.
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

        print(f"built {len(built)} files, site checkout has {len(live)}")
        if not (missing or extra or differ):
            print("the site checkout matches the built source; deployment and HTTP are not checked")
            return 0

        print("\nthe site checkout does NOT match the built source:", file=sys.stderr)
        for k in missing:
            print(f"   built here but missing from site checkout: {k}", file=sys.stderr)
        for k in extra:
            print(f"   in site checkout but not built here: {k}", file=sys.stderr)
        for k in differ:
            print(f"   differs: {k}", file=sys.stderr)
        print("\n   prepare the site checkout with: bash tools/release/publish-website.sh",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
