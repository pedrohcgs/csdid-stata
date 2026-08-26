#!/usr/bin/env bash
# Regenerate EVERY committed R oracle from its generator, in a scratch tree,
# with the pinned R packages, and byte-diff the result against the committed
# fixtures. This is the step the preflight's parity tier NAMES; the cheap
# environment gate (check-r-oracles.sh) proves the pinned versions are
# installed, and this proves the frozen numbers are what that R still
# produces. A fixture edited by hand, a deleted oracle file, a generator
# whose output drifted, or a generator/fixture inventory mismatch all fail
# loudly here. (Cold-audit R2: the tier used to run only the environment
# gate while carrying the regeneration's name -- a forged oracle passed.)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail=0
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# ---- inventory must agree in both directions ------------------------------
# A generator is generate.R (an R oracle) or generate.py (a contract
# fixture); the jel directory feeds the separate JEL tier.
gen_ids=""
for d in tools/parity/generators/*/; do
  id="$(basename "$d")"
  [ "$id" = "jel" ] && continue
  if [ ! -f "$d/generate.R" ] && [ ! -f "$d/generate.py" ]; then
    echo "generator dir $id holds no generate.R or generate.py" >&2; fail=1
    continue
  fi
  gen_ids="$gen_ids $id"
  if [ ! -d "tests/fixtures/parity/$id" ]; then
    echo "generator $id has no committed fixture directory" >&2; fail=1
  fi
done
for fd in tests/fixtures/parity/*/; do
  id="$(basename "$fd")"
  if [ ! -f "tools/parity/generators/$id/generate.R" ] && [ ! -f "tools/parity/generators/$id/generate.py" ]; then
    echo "fixture $id has no generator; its oracles cannot be certified" >&2; fail=1
  fi
done
[ "$fail" -ne 0 ] && { echo "R ORACLE REGENERATION FAILED (inventory)" >&2; exit 1; }

# ---- regenerate into the scratch tree -------------------------------------
# generate.R resolves the repo root from its own script path, so a copy of
# tools/parity under the scratch root writes into $scratch/tests/... .
mkdir -p "$scratch/tools" "$scratch/tests"
cp -R tools/parity "$scratch/tools/parity"
# read-only inputs some generators consume from the repo root
[ -d inst ] && cp -R inst "$scratch/inst"
if [ -d examples/data ]; then
  mkdir -p "$scratch/examples"
  cp -R examples/data "$scratch/examples/data"
fi

# Some generators CONSUME committed input data rather than producing it
# (rt004 reads hand-authored panels); seed every fixture's inputs so both
# kinds run. A generator that regenerates its inputs simply overwrites the
# seed, and the byte-diff below still compares whatever it wrote.
for fd in tests/fixtures/parity/*/; do
  id="$(basename "$fd")"
  # replicate the committed directory skeleton: the cwd-relative generators
  # write.csv straight into expected/r/ and cannot create directories
  while IFS= read -r sub; do
    mkdir -p "$scratch/tests/fixtures/parity/$id/${sub#"$fd"}"
  done < <(find "$fd" -type d)
  if [ -d "$fd/inputs" ]; then
    cp -R "$fd/inputs" "$scratch/tests/fixtures/parity/$id/"
  fi
done

n_ok=0
for id in $gen_ids; do
  if [ -f "tools/parity/generators/$id/generate.R" ]; then
    runner="Rscript tools/parity/generators/$id/generate.R"
  else
    runner="python3 tools/parity/generators/$id/generate.py"
  fi
  if ! (cd "$scratch" && $runner >"$scratch/$id.log" 2>&1); then
    echo "generator $id FAILED; log tail:" >&2
    tail -5 "$scratch/$id.log" >&2
    fail=1
    continue
  fi
  # A zero exit is not production (cold-audit F6): a generator that writes
  # nothing under expected/ must fail, or an inventoried generator with no
  # oracle at all would count as certified.
  produced=$(find "$scratch/tests/fixtures/parity/$id/expected" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$produced" -eq 0 ]; then
    echo "generator $id exited 0 but produced NO file under expected/; that is not a certification" >&2
    fail=1
    continue
  fi
  # Provenance (cold-audit rounds 7 and 9): expected/r is authored by the
  # reference estimator BY DEFINITION. A python generator that writes
  # beneath it would launder non-R numbers into the R-oracle channel, and
  # an R generator that writes there without ever CALLING the estimator
  # would launder hard-coded ones -- byte-identity certifies
  # reproducibility, not provenance. Both refuse here; the semantic half
  # of provenance (the right arguments to the right calls) is what code
  # review of the generator diff is for. Generators that author only
  # inputs, metadata, or contract channels owe no estimator call.
  r_authored=$(find "$scratch/tests/fixtures/parity/$id/expected/r" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$r_authored" -gt 0 ]; then
    if [ ! -f "tools/parity/generators/$id/generate.R" ]; then
      echo "generator $id is not an R generator but wrote $r_authored file(s) under expected/r; only R may author the R-oracle channel" >&2
      fail=1
      continue
    fi
    if ! grep -qE 'att_gt|aggte|drdid' "tools/parity/generators/$id/generate.R"; then
      echo "R generator $id wrote under expected/r without ever calling the reference estimator (no att_gt/aggte/drdid call); a hard-coded oracle certifies nothing" >&2
      fail=1
      continue
    fi
  fi
  n_ok=$((n_ok + 1))
done

# ---- byte-diff: everything the generators wrote must match the tree -------
n_files=0
while IFS= read -r f; do
  rel="${f#"$scratch/"}"
  n_files=$((n_files + 1))
  if [ ! -f "$rel" ]; then
    echo "regenerated $rel is not in the committed tree" >&2; fail=1
  elif ! cmp -s "$f" "$rel"; then
    echo "committed $rel DIFFERS from what pinned R regenerates" >&2; fail=1
  fi
done < <(find "$scratch/tests" -type f)

# committed R oracles that the regeneration no longer produces are orphans
# certifying nothing. Inputs and metadata are diffed above whenever a
# generator writes them, but only the expected/r channel -- the numbers this
# gate exists to certify -- must be reproduced by every fixture.
while IFS= read -r f; do
  if [ ! -f "$scratch/$f" ]; then
    echo "committed $f was NOT regenerated by any generator" >&2; fail=1
  fi
done < <(find tests/fixtures/parity -type f -path '*/expected/r/*')

if [ "$fail" -ne 0 ]; then
  echo "R ORACLE REGENERATION FAILED" >&2
  exit 1
fi
echo "R oracles regenerated and byte-identical: $n_ok generators, $n_files files"
