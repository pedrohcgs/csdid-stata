#!/usr/bin/env bash
# Assemble the csdid-stata release payload into a checkout of that repository.
#
#   build-release-payload.sh <path-to-csdid-stata-checkout>
#
# The two repositories hold different things and answer different questions.
# csdid-stata answers "what is this, should I trust it, will it stay
# trustworthy": the package, the evidence for it, and the method that keeps it
# honest. csdid-stata-porting additionally holds the deliberation behind it --
# review rounds, blocker trackers, handoff notes -- which nobody installing a
# Stata package needs.
#
# Two things are easy to get wrong by hand, and this script exists so they are
# not done by hand:
#
#   - README.md at the root of THIS repository describes the development
#     repository. It must never ship. The package's README is
#     packaging/README.md and becomes README.md over there.
#   - reports/, dist/ and a handful of internal process documents stay behind.
#
# The script only writes into the target checkout. It commits nothing and
# pushes nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -d "$TARGET/.git" ]; then
  echo "usage: build-release-payload.sh <path-to-csdid-stata-checkout>" >&2
  exit 2
fi
TARGET="$(cd "$TARGET" && pwd)"

# Internal process documents: deliberation rather than method.
# Withheld only where nothing shipped depends on them. Three documents that
# looked like internal process -- handoff-release-candidate-readme.md,
# release-notes-v2.0.0-rc1.md and parser-refactor-plan.md -- are required by
# tests/meta/test-release-productization.sh, so withholding them left the
# released repository failing its own gate. Anything a shipped gate reads is
# part of the evidence, whatever it looks like.
WITHHELD_DOCS=(
  frontier-model-review-prompts.md
  model-improvement-required-tests.md
  public-v2.0.0-blockers.md
  pr-readiness.md
)

echo "== replacing the superseded 1.82 sources =="
( cd "$TARGET" && git rm -r --quiet --ignore-unmatch codes test ) || true

echo "== root files =="
for f in NEWS.md LICENSE PROVENANCE.md csdid.pkg stata.toc .gitignore; do
  cp "$ROOT/$f" "$TARGET/$f" && echo "   $f"
done
# The package README, not this repository's.
cp "$ROOT/packaging/README.md" "$TARGET/README.md"
echo "   README.md  (from packaging/README.md)"

echo "== directories =="
for d in src pkg tests examples tools website inst .github; do
  rsync -a --delete --exclude '__pycache__' --exclude '*.log' \
        "$ROOT/$d/" "$TARGET/$d/" && echo "   $d/"
done
# packaging/ exists only to hold the package README, which is already placed.
rm -rf "$TARGET/packaging"

# Reports cited as EVIDENCE ship; the rest is deliberation and stays behind.
# The distinction is not editorial: inst/spec/feature-matrix.csv names some of
# these in artifact_path, validate-contract.py requires others, and several meta
# gates read them. Withholding them wholesale left the released repository
# unable to pass its own spec tier -- six checks failed on missing reports.
EVIDENCE_REPORTS=(
  engineering-audit.md
  hardening-status.md
  implementation-status.md
  jel-full-reproduction-result.md
  jel-replication-summary.md
  legacy-candidate-performance-certification.md
  oracle-review.md
)
echo "== reports cited as evidence =="
mkdir -p "$TARGET/reports/final-release" "$TARGET/reports/templates"
for f in "${EVIDENCE_REPORTS[@]}"; do
  cp "$ROOT/reports/$f" "$TARGET/reports/$f"
done
cp "$ROOT/reports/final-release/README.md" "$TARGET/reports/final-release/README.md"
cp "$ROOT"/reports/templates/*.md "$TARGET/reports/templates/"
echo "   reports/ (${#EVIDENCE_REPORTS[@]} cited + final-release + templates)"

echo "== docs, less the internal process documents =="
mkdir -p "$TARGET/docs"
rm -f "$TARGET"/docs/*.md
n=0
for f in "$ROOT"/docs/*.md; do
  b="$(basename "$f")"
  skip=0
  for w in "${WITHHELD_DOCS[@]}"; do [ "$b" = "$w" ] && skip=1; done
  [ "$skip" = "1" ] && continue
  cp "$f" "$TARGET/docs/$b"; n=$((n + 1))
done
echo "   docs/ ($n of $(ls "$ROOT"/docs/*.md | wc -l | tr -d ' '))"

echo "== checks =="
fail=0
# inst/spec carries the feature matrix and the pinned upstream test inventories.
# Without it validate-contract.py, check-upstream-coverage.py, preflight-digest.sh
# and several meta gates all fail on the first invocation -- so the released
# repository could not run its own preflight. The earlier version of this script
# omitted inst/ and every check below still passed, which is why the check that
# actually exercises the tooling was added at the end.
for d in inst/spec src pkg tests tools docs website examples; do
  [ -d "$TARGET/$d" ] || { echo "   FAIL: $d/ missing from the payload" >&2; fail=1; }
done
if grep -qs "csdid-stata-porting" "$TARGET/README.md"; then
  echo "   FAIL: the development README reached the package repository" >&2; fail=1
fi
head -1 "$TARGET/README.md" | grep -q "^# csdid:" || {
  echo "   FAIL: README.md is not the package README" >&2; fail=1; }
# reports/ ships only the evidence-cited subset; deliberation must not appear.
for f in external-release-review.md release-next-steps-2026-07-09.md csdidjl-repo-audit.md; do
  [ -f "$TARGET/reports/$f" ] && { echo "   FAIL: deliberation shipped: reports/$f" >&2; fail=1; }
done
[ -d "$TARGET/packaging" ] && { echo "   FAIL: packaging/ must not ship" >&2; fail=1; }
for m in csdid.pkg stata.toc; do
  [ -f "$TARGET/$m" ] || { echo "   FAIL: $m missing; net install would not work" >&2; fail=1; }
done
while read -r _ p; do
  [ -f "$TARGET/$p" ] || { echo "   FAIL: csdid.pkg names a missing file: $p" >&2; fail=1; }
done < <(grep -E "^f " "$TARGET/csdid.pkg")
# The decisive check: can the payload run its own consistency gates? Structural
# checks pass happily on a tree that cannot execute anything.
if [ "$fail" = "0" ]; then
  echo "   running the payload's own spec tier"
  if ( cd "$TARGET" && bash tools/release/preflight.sh --fast >/tmp/payload-spec.log 2>&1 ); then
    echo "   payload spec tier passes"
  else
    echo "   FAIL: the payload cannot pass its own spec tier:" >&2
    tail -12 /tmp/payload-spec.log >&2
    fail=1
  fi
fi

[ "$fail" = "0" ] && echo "   payload checks passed"

echo
echo "payload assembled in $TARGET"
echo "nothing committed. review with: git -C \"$TARGET\" status"
exit "$fail"
