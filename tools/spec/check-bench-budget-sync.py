#!/usr/bin/env python3
"""The frozen budget spec and the budget the gate enforces must agree, row by row.

`max_stata_over_r` for each benchmark is written in two places:

  * inst/spec/bench-budgets.yml -- `status: frozen`, the normative document,
    the thing a reader consults to learn what the project promises;
  * tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv -- the
    fixture tools/bench/run-f049-ratio.py reads, and the only one of the two
    that can turn a run red.

Nothing else connects them, and a budget is normally changed in one place at a
time, so the two drift apart with no run to say so. The failure mode is silent
in both directions: a spec that promises more than the gate demands makes the
frozen document a fiction, and a spec that promises less than the gate demands
means a regression can land inside the published promise and still pass.

Checks:

  1. The two carry the same set of benchmark names.
  2. Every name carries the same `max_stata_over_r` in both, compared as a
     number so 2 and 2.0 are the same budget and 1.8 and 1.85 are not.

Exit 0 on success; print every disagreement and exit 1 otherwise.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SPEC = os.path.join(ROOT, "inst", "spec", "bench-budgets.yml")
FIXTURE = os.path.join(
    ROOT, "tests", "fixtures", "parity", "f049", "expected", "contract",
    "r-relative-budgets.csv",
)

# The spec is read with a two-key scanner rather than a YAML library: the
# repository's test dependencies are python3 and Rscript, and adding PyYAML to
# run one gate would make the gate the reason for a dependency. The shape being
# read is fixed and flat -- `budgets:` holds one two-space-indented block per
# benchmark, and `max_stata_over_r` is a four-space-indented scalar inside it.
BENCH_RE = re.compile(r"^  ([A-Za-z0-9_]+):\s*$")
BUDGET_RE = re.compile(r"^    max_stata_over_r:\s*([0-9.]+)\s*$")


def read_spec(path):
    budgets = {}
    current = None
    in_budgets = False
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("budgets:"):
                in_budgets = True
                continue
            if not in_budgets:
                continue
            # any top-level key ends the budgets block
            if line[:1] not in (" ", "\n", "#") and line.strip():
                in_budgets = False
                continue
            m = BENCH_RE.match(line.rstrip("\n"))
            if m:
                current = m.group(1)
                continue
            m = BUDGET_RE.match(line.rstrip("\n"))
            if m and current is not None:
                budgets[current] = float(m.group(1))
    return budgets


def read_fixture(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return {
            row["benchmark"]: float(row["max_stata_over_r"])
            for row in csv.DictReader(fh)
        }


def main():
    problems = []
    spec = read_spec(SPEC)
    fixture = read_fixture(FIXTURE)

    if not spec:
        problems.append("no max_stata_over_r rows parsed out of %s" % SPEC)
    if not fixture:
        problems.append("no rows parsed out of %s" % FIXTURE)

    only_spec = sorted(set(spec) - set(fixture))
    only_fixture = sorted(set(fixture) - set(spec))
    for name in only_spec:
        problems.append(
            "%s carries max_stata_over_r in the spec but is not a row of the "
            "enforced fixture" % name
        )
    for name in only_fixture:
        problems.append(
            "%s is a row of the enforced fixture but carries no "
            "max_stata_over_r in the spec" % name
        )

    for name in sorted(set(spec) & set(fixture)):
        if spec[name] != fixture[name]:
            problems.append(
                "%s: spec says max_stata_over_r %g, the enforced fixture says "
                "%g" % (name, spec[name], fixture[name])
            )

    if problems:
        for p in problems:
            print("FAIL: %s" % p, file=sys.stderr)
        return 1

    print("bench budget spec sync ok (%d rows)" % len(fixture))
    return 0


if __name__ == "__main__":
    sys.exit(main())
