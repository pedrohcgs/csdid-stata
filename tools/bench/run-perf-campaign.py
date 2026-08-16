#!/usr/bin/env python3
"""Run a timing instrument across several trees, in rotation, and report every
round.

    python3 tools/bench/run-perf-campaign.py --instrument perf-agg-warm \\
        --tag s6-agg --rounds 12 --arms head=HEAD,s5=e239d9a,base=c28b35e

WHY A DRIVER AND NOT A LOOP. Three things decide whether a sub-per-cent timing
reading means anything, and all three are arrangement rather than arithmetic:

  ONE DIRECTORY. Every arm runs from the same working directory with only
  `src/' swapped, and the instrument do-file is copied in from the tree that
  launched the campaign, so it is byte-identical on every arm. Two checkouts
  side by side would differ in path length and in what the filesystem cached.

  ROTATION. Arm order rotates by round and reverses on even rounds, so each arm
  runs first, in the middle and last in equal measure over each block of
  len(arms) rounds -- so a campaign should run a MULTIPLE of len(arms) rounds
  for the balance to hold exactly. A machine that warms up,
  throttles, or picks up somebody else's job during the campaign then drifts
  ACROSS the arms rather than into one of them.

  EVERY ROUND SURVIVES. The raw per-round rows are appended to
  tools/bench/perfscale/<tag>.csv and the report is computed from that file, so
  a reading can be re-derived, disputed, or re-read by someone who did not run
  it. The statistic is the per-round PAIRED per cent difference -- the two arms
  in a round ran minutes apart on the same machine in the same state -- reported
  as its median with the count of rounds the subject arm was slower. A median of
  twelve paired differences and a 12-of-12 count say different things and both
  are printed; neither is a p-value and neither is claimed to be one.

ARMS. `name=rev' names a git revision (exported with `git archive'); `name=path'
names a directory holding a `src/' -- which is how a candidate under
construction is measured against its own parent without committing it first.

The engine is loaded from source on every arm (the instruments set adopath), so
nothing here is built and nothing here sees the compiled library's search
position. That cost is real and belongs to run-session-warmup.py.
"""

import argparse
import csv
import shutil
import statistics
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTDIR = ROOT / "tools" / "bench" / "perfscale"

# Every instrument writes tag,arm,round,cell,... and ends each row with a
# seconds value; these say where the rest of the columns are.
INSTRUMENTS = {
    "perf-agg-warm": {
        "cols": ["tag", "arm", "round", "cell", "position", "block", "nunits",
                 "reps", "seconds"],
        "bucket": None,
    },
    "perf-inproc-routes": {
        "cols": ["tag", "arm", "round", "cell", "route", "position", "nunits",
                 "reps", "bucket", "seconds"],
        "bucket": "bucket",
    },
}


def sh(cmd, **kw):
    proc = subprocess.run(cmd, **kw)
    if proc.returncode != 0:
        raise SystemExit(f"command failed: {' '.join(str(c) for c in cmd)}")


def materialize(name, spec, armroot):
    """One arm's src/ tree, from a directory or from a git revision."""
    dest = armroot / name
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    path = Path(spec).expanduser()
    if path.is_dir() and (path / "src").is_dir():
        shutil.copytree(path / "src", dest / "src")
        origin = str(path.resolve())
    else:
        with (dest / "src.tar").open("wb") as tar:
            proc = subprocess.run(["git", "archive", spec, "src"],
                                  cwd=ROOT, stdout=tar)
        if proc.returncode != 0:
            raise SystemExit(f"arm {name}: not a directory with src/ and not a git revision: {spec}")
        sh(["tar", "-xf", "src.tar"], cwd=dest)
        (dest / "src.tar").unlink()
        origin = subprocess.run(["git", "rev-parse", spec], cwd=ROOT,
                                capture_output=True, text=True).stdout.strip()
    if not (dest / "src" / "mata" / "csdid.mata").is_file():
        raise SystemExit(f"arm {name}: no src/mata/csdid.mata under {spec}")
    return dest, origin


def scan_log(workdir):
    """stata-mp -b exits 0 even when the do-file aborts; the log is the truth.

    The batch log is named after one of the arguments rather than after the
    do-file, so it is not predicted -- the working directory is emptied of logs
    before each run and whatever appears is the run's own.
    """
    logs = sorted(workdir.glob("*.log"))
    if not logs:
        raise SystemExit(f"no Stata log written in {workdir}")
    bad = []
    for log in logs:
        for i, line in enumerate(log.read_text(errors="replace").splitlines(), 1):
            s = line.strip()
            if (s.startswith("r(") and s.endswith(");")) or s == "assertion is false":
                bad.append(f"{log}:{i}:{s}")
    if bad:
        raise SystemExit("Uncaught Stata error:\n" + "\n".join(bad[-20:]))


def rows_of(out, spec):
    with out.open(newline="") as f:
        for rec in csv.reader(f):
            if len(rec) != len(spec["cols"]):
                continue
            yield dict(zip(spec["cols"], rec))


def report(out, spec, arms):
    """Per-round paired per cent differences, median and count, per cell.

    TOTAL is the wall time the round's timers actually accumulated -- seconds
    per call times the calls made -- so a cell is weighted by what it costs and
    not by how many of it the instrument chose to run.
    """
    bucket = spec["bucket"]
    # (cell, round) -> arm -> seconds
    seen = {}
    for rec in rows_of(out, spec):
        # Round 0 is the settle round: the first timed block of the first
        # process of a campaign reads 20-30% high on the shortest cell while
        # the machine is still faulting the harness in. It is run, written and
        # excluded here by declaration, not dropped after being looked at.
        if int(rec["round"]) == 0:
            continue
        if bucket and rec[bucket] != "total":
            key = (f"{rec['cell']}:{rec[bucket]}", int(rec["round"]))
            wall = float(rec["seconds"])
        else:
            key = (rec["cell"], int(rec["round"]))
            wall = float(rec["seconds"]) * (float(rec["reps"]) if not bucket else 1.0)
        prior = seen.setdefault(key, {}).get(rec["arm"])
        # An instrument that writes several blocks per round is read on the
        # smallest of them: interference only ever adds time.
        seen[key][rec["arm"]] = wall if prior is None else min(prior, wall)

    cells = sorted({k[0] for k in seen}, key=lambda c: (":" in c, c))
    headline = [c for c in cells if ":" not in c]
    rounds = sorted({k[1] for k in seen})
    for r in rounds:
        for a in arms:
            tot = sum(seen.get((c, r), {}).get(a, 0.0) for c in headline)
            seen.setdefault(("TOTAL", r), {})[a] = tot
    cells = ["TOTAL"] + cells

    width = max(len(c) for c in cells)
    for i, subject in enumerate(arms):
        for reference in arms[i + 1:]:
            print(f"\n{subject} vs {reference}   (per-round paired % difference; "
                  f"median, rounds {subject} slower)")
            for cell in cells:
                diffs = []
                for r in rounds:
                    a = seen.get((cell, r), {}).get(subject)
                    b = seen.get((cell, r), {}).get(reference)
                    if a is None or b is None or b == 0:
                        continue
                    diffs.append(100.0 * (a / b - 1.0))
                if not diffs:
                    continue
                slower = sum(1 for d in diffs if d > 0)
                print(f"  {cell:<{width}}  {statistics.median(diffs):+7.2f}%  "
                      f"{slower:>2}/{len(diffs)}   "
                      f"[{min(diffs):+.2f} .. {max(diffs):+.2f}]")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--instrument", required=True, choices=sorted(INSTRUMENTS))
    p.add_argument("--tag", required=True)
    p.add_argument("--arms", required=True,
                   help="name=rev-or-directory, comma separated; the first is the subject")
    p.add_argument("--rounds", type=int, default=12)
    p.add_argument("--nunits", default="")
    p.add_argument("--workdir", default="")
    p.add_argument("--report-only", action="store_true",
                   help="re-read an existing csv and print the report again")
    args = p.parse_args()

    spec = INSTRUMENTS[args.instrument]
    arms = []
    for item in args.arms.split(","):
        name, _, ref = item.partition("=")
        if not ref:
            raise SystemExit(f"arm must be name=rev-or-directory: {item}")
        arms.append((name.strip(), ref.strip()))

    OUTDIR.mkdir(parents=True, exist_ok=True)
    out = OUTDIR / f"{args.tag}.csv"

    if args.report_only:
        report(out, spec, [n for n, _ in arms])
        return

    workdir = Path(args.workdir) if args.workdir else ROOT / "build" / f"campaign-{args.tag}"
    if workdir.exists():
        shutil.rmtree(workdir)
    (workdir / "tools" / "bench").mkdir(parents=True)
    dofile = f"{args.instrument}.do"
    shutil.copy2(ROOT / "tools" / "bench" / dofile, workdir / "tools" / "bench" / dofile)

    armroot = workdir / "arms"
    origins = {}
    for name, ref in arms:
        _, origin = materialize(name, ref, armroot)
        origins[name] = origin

    if out.exists():
        out.unlink()

    # The pre-registration, printed before the first round runs and repeated at
    # the head of the report, because a design declared afterwards is not one.
    print(f"campaign {args.tag}: instrument {args.instrument}, {args.rounds} rounds, "
          f"{len(arms)} arms, one directory with only src/ swapped")
    for name, ref in arms:
        print(f"  arm {name:<8} {ref}  ->  {origins[name]}")
    print("  statistic: per-round paired % difference, median over rounds, "
          "count of rounds the subject is slower")
    print("  rotation: arm order rotates by round and reverses on even rounds")
    print("  round 0 is a settle round: run, written to the csv, excluded from the statistic")
    sys.stdout.flush()

    for r in range(0, args.rounds + 1):
        # Latin-square rotation, then reverse on alternate PASSES over the
        # square rather than on alternate rounds. The cyclic shift alone gives
        # every arm every position once per len(arms) rounds; reversing on even
        # ROUNDS undoes that for even arm counts -- at two arms the subject ran
        # first in every round, and at four arms two arms never ran first
        # (measured, S6 checker P1: a position is worth 0.2-0.4% of a total).
        order = arms[(r - 1) % len(arms):] + arms[:(r - 1) % len(arms)]
        if ((r - 1) // len(arms)) % 2 == 1:
            order = list(reversed(order))
        for name, _ in order:
            # The swap is a symlink and not a copy: copying a megabyte of
            # source immediately before a timed run leaves the machine doing
            # filesystem work during the first block of it, which showed up as
            # a 20% spread on the shortest cell.
            src = workdir / "src"
            if src.is_symlink() or src.exists():
                src.unlink()
            src.symlink_to(armroot / name / "src")
            for stale in workdir.glob("*.log"):
                stale.unlink()
            argv = [str(workdir), str(out), args.tag, name, str(r)]
            if args.nunits:
                argv.append(str(args.nunits))
            sh(["stata-mp", "-b", "do", f"tools/bench/{dofile}", *argv], cwd=workdir)
            scan_log(workdir)
        label = "settle" if r == 0 else f"{r}/{args.rounds}"
        print(f"  round {label} done ({', '.join(n for n, _ in order)})")
        sys.stdout.flush()

    report(out, spec, [n for n, _ in arms])
    print(f"\nraw rounds: {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
