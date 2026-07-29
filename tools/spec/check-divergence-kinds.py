#!/usr/bin/env python3
"""Every approved divergence is classified, and every classification is live.

Each fixture records its own approved divergences next to the tests that
inherit them, which is the right place for the detail but a poor place to see
the shape of the whole. Read one at a time they all look equally weighty;
read together, the question that matters is how many are differences in
*behaviour* rather than differences in *surface*. This gate keeps
inst/spec/divergence-kinds.csv in exact correspondence with the fixtures so
that summary can be trusted.

Two failure modes, both silent without a gate:

  * a new divergence is added to a fixture and never classified, so the
    summary quietly understates what the port diverges on;
  * a divergence is retired from a fixture and its classification is left
    behind, so the summary quietly overstates it.

Recognised kinds:

  behavioral-default    csdid computes different numbers than R because an
                        omitted-option default resolves differently. State
                        the option and the two agree. These are the only
                        divergences a user can observe in an estimate.
  stata-surface         The Stata command surface deliberately omits, renames
                        or restricts something R exposes.
  language-surface      An R or Python language feature with no Stata
                        analogue: callables, formula bases, data.table,
                        factor internals, plotting objects.
  internal-api          The upstream test calls a non-exported helper or
                        inspects object internals; there is no public surface
                        on either side to compare.
  test-placement        The behaviour IS covered, by a different fixture.
  upstream-conflict     R and Python disagree; R governs.
  upstream-version      The upstream test compares against a historical
                        release of the reference implementation.
  upstream-not-a-test   The upstream file is a script or notebook, not an
                        assertion.

Run: python3 tools/spec/check-divergence-kinds.py
"""

from __future__ import annotations

import csv
import glob
import io
import pathlib
import sys
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "inst/spec/divergence-kinds.csv"

KINDS = {
    "behavioral-default",
    "stata-surface",
    "language-surface",
    "internal-api",
    "test-placement",
    "upstream-conflict",
    "upstream-version",
    "upstream-not-a-test",
}


def fixture_divergences() -> dict[str, str]:
    found: dict[str, str] = {}
    pattern = str(ROOT / "tests/fixtures/parity/*/expected/contract/approved-divergence.csv")
    for path in sorted(glob.glob(pattern)):
        fixture = pathlib.Path(path).parts[-4]
        with io.open(path, encoding="utf-8") as fh:
            for row in csv.DictReader(fh):
                did = (row.get("divergence_id") or "").strip()
                if did:
                    found[did] = fixture
    return found


def main() -> int:
    if not REGISTRY.is_file():
        print(f"missing registry: {REGISTRY}", file=sys.stderr)
        return 1

    classified: dict[str, str] = {}
    with io.open(REGISTRY, encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            classified[row["divergence_id"].strip()] = row["divergence_kind"].strip()

    live = fixture_divergences()
    errors = []

    for did, fixture in sorted(live.items()):
        if did not in classified:
            errors.append(f"  {did} (in {fixture}) is not classified in {REGISTRY.name}")

    for did in sorted(classified):
        if did not in live:
            errors.append(f"  {did} is classified but no fixture declares it; retire the row")

    for did, kind in sorted(classified.items()):
        if kind not in KINDS:
            errors.append(f"  {did} has unrecognised kind {kind!r}")

    if errors:
        print("divergence classification is out of step with the fixtures:", file=sys.stderr)
        for e in errors:
            print(e, file=sys.stderr)
        return 1

    counts = Counter(classified[d] for d in live)
    behavioral = counts.get("behavioral-default", 0)
    print(f"divergence kinds OK ({len(live)} divergences across {len(set(live.values()))} fixtures)")
    for kind, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {n:3d}  {kind}")
    print(f"\n{behavioral} of {len(live)} are behavioural; the rest are surface, "
          f"placement or upstream-shape differences.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
