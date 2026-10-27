#!/usr/bin/env python3
"""Validate explicitly historical website results against their released code."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "2.0.1"
TAG = "a1ef9ef20b2d2a29c6d097712a10165b0116a43b"
COMMIT = "f98bcea0691b1670c409bb7e3cc81d60705b4f84"
PAGES = ("articles/csdid-against-the-field.md",
         "articles/speed-vs-182.md", "code-appendix.md")
PROTECTED_TREES = ("tools/bench/field/results",
                   "tools/bench/field/historical-results", "website/assets")
CHECKS = ("tools/release/check-website-speed-tables.py",
          "tools/release/check-website-speed-prose.py",
          "tests/meta/test-website-speed-claims.sh",
          "tools/release/sync-code-appendix.py")


def check_reference_identity(tag_oid, commit_oid):
    if (tag_oid, commit_oid) != (TAG, COMMIT):
        raise ValueError("historical publication requires the original public v2.0.1 tag and commit")


def git(reference, *args, **kwargs):
    env = dict(os.environ, GIT_NO_REPLACE_OBJECTS="1")
    return subprocess.run(["git", "-C", str(reference), *args],
                          env=env, check=True, **kwargs)


def verify_reference(reference):
    try:
        tag = git(reference, "rev-parse", "refs/tags/v2.0.1",
                  capture_output=True, text=True).stdout.strip()
        commit = git(reference, "rev-parse", "refs/tags/v2.0.1^{}",
                     capture_output=True, text=True).stdout.strip()
    except subprocess.CalledProcessError as error:
        raise ValueError("the reference checkout must contain public v2.0.1; fetch its original tag") from error
    check_reference_identity(tag, commit)


def files(root):
    return {p.relative_to(root) for p in root.rglob("*") if p.is_file()}


def verify_evidence(root, baseline):
    """The historical route cannot substitute newer inputs into an old proof."""
    protected = set(CHECKS)
    bench = baseline / "tools/bench"
    if not bench.is_dir():
        raise ValueError("historical benchmark sources are missing")
    protected.update(str(p.relative_to(baseline)) for p in bench.rglob("*") if p.is_file())
    for name in PROTECTED_TREES:
        expected, current = files(baseline / name), files(root / name)
        if not expected or current != expected:
            raise ValueError(f"historical evidence inventory changed: {name}")
        protected.update(str(Path(name) / p) for p in expected)
    for name in sorted(protected):
        original, current = baseline / name, root / name
        if not original.is_file() or not current.is_file() or original.read_bytes() != current.read_bytes():
            raise ValueError(f"historical evidence or validator changed: {name}")


def validate_disclosure(root):
    source = (root / "src/ado/csdid.ado").read_text()
    package = (root / "pkg/csdid.ado").read_text()
    versions = [re.search(r"^\*! csdid ([0-9.]+) ", text) for text in (source, package)]
    if not all(versions) or versions[0][1] != versions[1][1]:
        raise ValueError("current source and package versions differ")
    current = versions[0][1]
    if tuple(map(int, current.split("."))) <= tuple(map(int, VERSION.split("."))):
        raise ValueError("historical publication needs a newer current release")
    for name in PAGES:
        path = root / "website" / name
        if not path.is_file():
            raise ValueError(f"missing historical benchmark page: {name}")
        text = path.read_text()
        front = text.split("---", 2)[1] if text.startswith("---\n") else ""
        if not re.search(r"(?m)^benchmark_version:[ \t]*2[.]0[.]1[ \t]*$", front):
            raise ValueError(f"missing historical benchmark version: {name}")
    layout = (root / "website/_layouts/default.html").read_text()
    layout = re.sub(r"<!--.*?-->", "", layout, flags=re.S)
    layout = re.sub(r"{%\s*comment\s*%}.*?{%\s*endcomment\s*%}", "", layout, flags=re.S)
    for token in ("benchmark-scope", "page.benchmark_version",
                  "has not been remeasured", "Version " + current):
        if token not in layout:
            raise ValueError("missing visible historical-result disclosure: " + token)
    index = (root / "website/index.md").read_text().split("## Speed", 1)[-1].split("## Also in R and Python", 1)[0]
    if VERSION not in index or current not in index or "remeasured" not in index:
        raise ValueError("homepage speed summary must identify the historical measurements")


def check(root, reference):
    verify_reference(reference)
    validate_disclosure(root)
    with tempfile.TemporaryDirectory(prefix="csdid-historical-site-") as directory:
        work = Path(directory)
        archive, baseline = work / "reference.tar", work / "reference"
        baseline.mkdir()
        git(reference, "archive", "--format=tar", "--output=" + str(archive), COMMIT)
        with tarfile.open(archive) as stream:
            stream.extractall(baseline, filter="data")
        verify_evidence(root, baseline)
        # Validate the actual proposed pages and prose on their measured code.
        shutil.rmtree(baseline / "website")
        shutil.copytree(root / "website", baseline / "website",
                        ignore=shutil.ignore_patterns("_site", ".jekyll-cache"))
        shutil.copyfile(root / "NEWS.md", baseline / "NEWS.md")
        readme = root / ("packaging/README.md" if (root / "packaging").is_dir() else "README.md")
        shutil.copyfile(readme, baseline / "README.md")
        for relative in CHECKS:
            interpreter = "bash" if relative.endswith(".sh") else sys.executable
            result = subprocess.run([interpreter, relative], cwd=baseline,
                                    capture_output=True, text=True)
            if result.returncode:
                raise ValueError(f"historical website validation failed: {relative}\n"
                                 + result.stdout + result.stderr)
            print(result.stdout.strip())
    print(f"Historical {VERSION} website evidence verified against {COMMIT}; "
          "current-release performance is not certified.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-checkout", required=True, type=Path,
                        help="public csdid-stata checkout containing the original v2.0.1 tag")
    args = parser.parse_args()
    try:
        check(ROOT, args.reference_checkout.resolve())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))


if __name__ == "__main__":
    main()
