#!/usr/bin/env python3
"""src/, pkg/, tests/ and tools/ ship to users; nothing in them may read as a
private note.

All four directories are copied whole into the release payload -- src/ and pkg/
are the package itself, and the engine source is installed beside the compiled
library and read by anyone who wants to know what a number came from -- so
every comment, echo string and file header in them is read by someone deciding
whether to trust the package. Three kinds of text are wrong there no matter how
true they are, because they address a reader who is not there:

  * SESSION SLUGS -- `session-2026-08-14' and the like. They name a working
    period nobody outside this repository can look up. Worse when the slug is
    part of a PATH: the payload builder strips tools/bench/field/session-*, so
    an engine comment citing a file under one sent the reader of the installed
    package to something that is not in the tree they have. That is what
    widening this gate past tests/ and tools/ found.
  * MODEL AND VENDOR NAMES -- who or what happened to be typing. A scratchpad
    path is the usual carrier: it arrives inside a captured traceback or a
    recorded input path and names a directory on one machine.
  * PULL-REQUEST AND ISSUE REFERENCES -- `PR #412', `the release pull
    request'. The number resolves in a repository the reader cannot see.

What this does NOT object to is the engineering rationale around them. A
comment saying which failure a check catches, what was measured, or why a
budget is the number it is, is the reason the check is legible at all. Only
the private framing goes.

The list of things that do not ship is mirrored from
tools/release/build-release-payload.sh and checked against it whenever that
script is present, so the two cannot drift; in the released tree the script is
gone and the paths it strips are gone with it.

Run: python3 tools/spec/check-shipped-vocabulary.py
Exit 0 on success; print every hit with file, line and rule, and exit 1.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SHIPPED_DIRS = ("src", "pkg", "tests", "tools")
PAYLOAD_BUILDER = os.path.join(ROOT, "tools", "release", "build-release-payload.sh")

# Mirrors the src/, pkg/, tests/ and tools/ entries of STRIP_PATHS in the
# payload builder. A trailing * is a prefix match, as it is there.
NOT_SHIPPED = (
    "src/ado/csdid_bootstrap_macosx.plugin",
    "tools/bench/field/session-*",
    "tools/parity/reference-lock/workflow-lock.json",
    "tools/release/build-handoff-bundle.sh",
    "tools/validate-contract.py",
    "tests/meta/test-engineering-audit.sh",
    "tests/meta/test-gate-qualification.sh",
    "tests/meta/test-optional-fastpath-policy.sh",
    "tests/meta/test-legacy-performance-certification.sh",
    "tests/meta/test-release-productization.sh",
    "tests/meta/test-performance-plan.sh",
    "tests/meta/test-dependency-policy.sh",
    "tests/meta/test-engineering-architecture.sh",
    "tests/meta/test-engineering-inventory.sh",
    "tests/meta/test-feature-matrix-integrity.sh",
    "tools/bench/threeway",
    "tools/bench/run-archive-ab.py",
    "tools/release/handoff-install.do",
    "tools/release/verify-handoff-install.do",
    "tools/release/build-release-payload.sh",
)

# Files that must contain this vocabulary because they are what forbids it.
# Each is required to exist: an exemption for a file nobody kept is an
# exemption that has stopped being about anything, and this gate says so
# rather than carrying it.
DEFINES_THE_VOCABULARY = (
    "tools/release/check-help-surface.py",
    "tools/spec/check-shipped-vocabulary.py",
)

RULES = (
    ("session-slug",
     re.compile(r"session-(?:19|20)\d{2}-\d{2}"),
     "a session slug"),
    ("model-name",
     re.compile(r"(?i)\b(?:codex|copilot|chatgpt|claude|anthropic|gemini|"
                r"gpt-?[0-9]\w*|llama-?[0-9]\w*)\b"),
     "the name of a model or model vendor"),
    # A bare `#123' is not enough to go on: a hex colour in a plotting script
    # is written the same way. The reference has to name itself -- a cue word,
    # a `PR #' prefix, or a forge URL.
    ("pull-request-reference",
     re.compile(r"(?i)\bpull request\b|\bmerge request\b|\bPR\s*#\s*\d+"
                r"|\b(?:issue|issues|fixes|closes|resolves|reverts|see)"
                r"\s+#\s*\d{1,6}\b|\bGH-\d+\b"
                r"|github\.com/[\w.-]+/[\w.-]+/(?:pull|issues)/\d+"),
     "a pull-request or issue reference"),
)

# Suffixes of files that carry no prose at all. Frozen numeric fixtures and
# compiled artifacts are read by machines; scanning them buys nothing and a
# false hit in one cannot be fixed by rewording.
SKIP_SUFFIXES = (".mlib", ".plugin", ".dta", ".png", ".pdf", ".gph", ".o",
                 ".pyc", ".zip", ".gz")


def strip_paths_in_builder():
    """The shipped-directory entries of STRIP_PATHS, read from the builder."""
    with open(PAYLOAD_BUILDER, encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(r'STRIP_PATHS="(.*?)"', text, re.S)
    if not m:
        return None
    entries = m.group(1).replace("\\\n", " ").split()
    return {e for e in entries if e.split("/")[0] in SHIPPED_DIRS}


def shipped_docs_in_builder():
    """The docs/ basenames the payload keeps, read from the builder.

    docs/ is handled by whitelist, not by STRIP_PATHS: the builder deletes
    docs/*.md outright and copies SHIPPED_DOCS back. Mirroring only STRIP_PATHS
    therefore leaves the doc half of "does the reader have this file?"
    unguarded, which is how a citation to a charter that does not ship survived
    inside the shipped engine.
    """
    with open(PAYLOAD_BUILDER, encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(r"SHIPPED_DOCS=\((.*?)\)", text, re.S)
    if not m:
        return None
    return {b for b in m.group(1).split() if b.endswith(".md")}


DOC_CITATION = re.compile(r"docs/([a-zA-Z0-9._-]+\.md)")


def does_not_ship(rel):
    for pattern in NOT_SHIPPED:
        if pattern.endswith("*"):
            if rel.startswith(pattern[:-1]):
                return True
        elif rel == pattern or rel.startswith(pattern + "/"):
            return True
    return False


def shipped_files():
    """Tracked files only, so the count is reproducible.

    os.walk also returned whatever batch logs and build droppings happened to
    be on disk, which moved the reported file count between runs and gave a
    local Stata log a way to turn a SHIPPED-TREE gate red.
    """
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z", *SHIPPED_DIRS],
                         capture_output=True, text=True, check=True)
    for rel in sorted(p for p in out.stdout.split("\0") if p):
        if does_not_ship(rel) or rel.endswith(SKIP_SUFFIXES):
            continue
        full = os.path.join(ROOT, rel)
        if os.path.isfile(full):
            yield rel, full


def scan(rel, full):
    try:
        with open(full, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except (UnicodeDecodeError, OSError):
        return []
    hits = []
    for n, line in enumerate(lines, 1):
        for name, pattern, why in RULES:
            m = pattern.search(line)
            if m:
                hits.append((rel, n, name, why, m.group(0)))
    return hits


def main():
    problems = []

    # The exclusion list above is a copy. Prove it is the same copy.
    if os.path.isfile(PAYLOAD_BUILDER):
        theirs = strip_paths_in_builder()
        if theirs is None:
            problems.append("could not read STRIP_PATHS out of %s"
                            % os.path.relpath(PAYLOAD_BUILDER, ROOT))
        else:
            for missing in sorted(theirs - set(NOT_SHIPPED)):
                problems.append(
                    "%s is stripped from the payload but this gate still scans "
                    "it; add it to NOT_SHIPPED" % missing)
            for extra in sorted(set(NOT_SHIPPED) - theirs):
                problems.append(
                    "%s is in this gate's NOT_SHIPPED but the payload no longer "
                    "strips it; it ships and must be scanned" % extra)

    # A shipped file may only send its reader to a doc the reader will have.
    # In the development tree the builder's SHIPPED_DOCS whitelist says which
    # docs will ship; in the ASSEMBLED payload the builder has stripped itself,
    # but there the whitelist has already been applied -- so the docs/ files on
    # disk ARE the answer, and the check reads reality instead of intent.
    if os.path.isfile(PAYLOAD_BUILDER):
        docs = shipped_docs_in_builder()
        if docs is None:
            problems.append("could not read SHIPPED_DOCS out of %s"
                            % os.path.relpath(PAYLOAD_BUILDER, ROOT))
    else:
        docs_dir = os.path.join(ROOT, "docs")
        docs = {f for f in os.listdir(docs_dir) if f.endswith(".md")}             if os.path.isdir(docs_dir) else set()
    if docs is not None:
        for rel, full in shipped_files():
            try:
                with open(full, encoding="utf-8") as fh:
                    lines = fh.read().splitlines()
            except (UnicodeDecodeError, OSError):
                continue
            for n, line in enumerate(lines, 1):
                for cited in DOC_CITATION.findall(line):
                    if cited not in docs:
                        problems.append(
                            "%s:%d cites docs/%s, which the payload does not "
                            "ship; the installed tree has no such file"
                            % (rel, n, cited))

    for rel in DEFINES_THE_VOCABULARY:
        if not os.path.isfile(os.path.join(ROOT, rel)):
            problems.append(
                "%s is exempt from this gate but does not exist; drop the "
                "exemption" % rel)

    scanned = 0
    for rel, full in shipped_files():
        if rel in DEFINES_THE_VOCABULARY:
            continue
        scanned += 1
        for hit_rel, n, name, why, text in scan(rel, full):
            problems.append("%s:%d [%s] %s: %r"
                            % (hit_rel, n, name, why, text))

    if not scanned:
        problems.append("scanned no files under any shipped directory -- this gate "
                        "is checking nothing")

    if problems:
        for p in problems:
            print("FAIL: %s" % p, file=sys.stderr)
        print("\nShipped package, test and tool files address a stranger evaluating "
              "the package.\nKeep the rationale; drop the private framing.",
              file=sys.stderr)
        return 1

    print("shipped vocabulary ok (%d files under %s)"
          % (scanned, "/, ".join(SHIPPED_DIRS) + "/"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
