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
# The attestation harness: R generators run under a trace on the reference
# estimator's own functions, which prints a marker to stderr WHEN THEY
# EXECUTE. Provenance is then attested by execution, not by the lexical
# presence of a call (cold-audit round 11: a call in a comment satisfied
# the old grep).
# Installed as R_PROFILE_USER so each generator still runs as its own
# `Rscript generate.R` -- its --file= self-location and sibling source()
# calls keep working -- while the estimator functions are traced the
# moment their package loads.
cat > "$scratch/csdid-attest-profile.R" <<'ATTEOF'
local({
  # the exit expression must be SELF-CONTAINED: trace() evaluates it in the
  # traced function's frame, where no profile-local helper exists
  arm <- function(pkg, fns) {
    setHook(packageEvent(pkg, "onLoad"), function(...) {
      suppressMessages(suppressWarnings({
        for (fn in fns) {
          try(trace(fn, where = asNamespace(pkg),
                    exit = quote(cat("CSDID_ATTEST_CALL\n", file = stderr())),
                    print = FALSE), silent = TRUE)
        }
      }))
    })
  }
  arm("did", c("att_gt", "aggte"))
  arm("DRDID", c("drdid", "drdid_panel", "drdid_rc", "reg_did_panel",
                 "reg_did_rc", "std_ipw_did_panel", "std_ipw_did_rc"))
})
ATTEOF
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
  # A fixture may carry BOTH generators: generate.R authors expected/r and
  # generate.py authors expected/contract and metadata. The old if/else ran
  # only the R one, so in 17 dual-generator fixtures nothing the Python
  # generator authors was ever reproduced, and a forged coverage row in a
  # committed contract file survived regeneration byte-untouched (in-house
  # review, gates lens; the identical forgery in a .py-only fixture was
  # caught). Every generator present runs, and every file any of them
  # writes is byte-diffed below.
  gen_failed=0
  : > "$scratch/$id.log"
  if [ -f "tools/parity/generators/$id/generate.R" ]; then
    if ! (cd "$scratch" && R_PROFILE_USER="$scratch/csdid-attest-profile.R" Rscript "tools/parity/generators/$id/generate.R" >>"$scratch/$id.log" 2>&1); then
      gen_failed=1
    fi
  fi
  if [ "$gen_failed" -eq 0 ] && [ -f "tools/parity/generators/$id/generate.py" ]; then
    if ! (cd "$scratch" && python3 "tools/parity/generators/$id/generate.py" >>"$scratch/$id.log" 2>&1); then
      gen_failed=1
    fi
  fi
  if [ "$gen_failed" -ne 0 ]; then
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
    if ! grep -q 'CSDID_ATTEST_CALL' "$scratch/$id.log"; then
      # A derived-reference oracle -- computed from first principles where
      # the reference package has no counterpart mode -- may declare itself
      # instead: the exemption is then explicit in the generator's own diff.
      if ! grep -q 'CSDID-ORACLE: derived-reference' "tools/parity/generators/$id/generate.R"; then
        echo "R generator $id wrote under expected/r without the reference estimator ever EXECUTING (no attested call, no declared derived-reference exemption); a hard-coded oracle certifies nothing" >&2
        fail=1
        continue
      fi
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

# committed oracles that the regeneration no longer produces are orphans
# certifying nothing. Inputs and metadata are diffed above whenever a
# generator writes them; the expected/r channel -- the numbers this gate
# certifies -- must be reproduced by every fixture. The expected/contract
# channel is generator-authored in some fixtures (the py family) and a
# hand-maintained claim registry in others (the rt family), so its orphan
# rule is scoped: in any fixture whose regeneration wrote at least one
# contract file, EVERY committed contract file must have been regenerated --
# a committed extra beside generator-authored ones is the forgery surface
# the dual-generator fix above closes. Hand-maintained registries (no
# generator writes there) are reviewed as claims, not certified here.
while IFS= read -r f; do
  if [ ! -f "$scratch/$f" ]; then
    echo "committed $f was NOT regenerated by any generator" >&2; fail=1
  fi
done < <(find tests/fixtures/parity -type f -path '*/expected/r/*')
for cd_committed in tests/fixtures/parity/*/expected/contract; do
  [ -d "$cd_committed" ] || continue
  cd_scratch="$scratch/$cd_committed"
  n_regen=$(find "$cd_scratch" -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$n_regen" -gt 0 ] || continue
  while IFS= read -r f; do
    if [ ! -f "$scratch/$f" ]; then
      echo "committed $f sits beside generator-authored contract files but was NOT regenerated" >&2; fail=1
    fi
  done < <(find "$cd_committed" -type f)
done

if [ "$fail" -ne 0 ]; then
  echo "R ORACLE REGENERATION FAILED" >&2
  exit 1
fi
echo "R oracles regenerated and byte-identical: $n_ok generators, $n_files files"
