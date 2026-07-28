#!/usr/bin/env bash
# Assemble the csdid-stata release payload into a checkout of that repository.
#
#   build-release-payload.sh <path-to-csdid-stata-checkout>
#
# The two repositories hold different things and answer different questions.
# csdid-stata answers "what is this, should I trust it, will it stay
# trustworthy": the package, the evidence for it, and the method that keeps it
# honest. csdid additionally holds the deliberation behind it --
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
WITHHELD_DOCS=(
  frontier-model-review-prompts.md
  model-improvement-required-tests.md
  handoff-release-candidate-readme.md
  release-notes-v2.0.0-rc1.md
  public-v2.0.0-blockers.md
  pr-readiness.md
  parser-refactor-plan.md
)

echo "== replacing the superseded 1.82 sources =="
( cd "$TARGET" && git rm -r --quiet --ignore-unmatch codes test ) || true

echo "== root files =="
for f in NEWS.md LICENSE csdid.pkg stata.toc .gitignore; do
  cp "$ROOT/$f" "$TARGET/$f" && echo "   $f"
done
# The package README, not this repository's.
cp "$ROOT/packaging/README.md" "$TARGET/README.md"
echo "   README.md  (from packaging/README.md)"

echo "== directories =="
for d in src pkg tests examples tools website; do
  rsync -a --delete --exclude '__pycache__' --exclude '*.log' \
        "$ROOT/$d/" "$TARGET/$d/" && echo "   $d/"
done
# packaging/ exists only to hold the package README, which is already placed.
rm -rf "$TARGET/packaging"

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
if grep -qs "csdid" "$TARGET/README.md"; then
  echo "   FAIL: the development README reached the package repository" >&2; fail=1
fi
head -1 "$TARGET/README.md" | grep -q "^# csdid:" || {
  echo "   FAIL: README.md is not the package README" >&2; fail=1; }
[ -d "$TARGET/reports" ] && { echo "   FAIL: reports/ must not ship" >&2; fail=1; }
[ -d "$TARGET/packaging" ] && { echo "   FAIL: packaging/ must not ship" >&2; fail=1; }
for m in csdid.pkg stata.toc; do
  [ -f "$TARGET/$m" ] || { echo "   FAIL: $m missing; net install would not work" >&2; fail=1; }
done
while read -r _ p; do
  [ -f "$TARGET/$p" ] || { echo "   FAIL: csdid.pkg names a missing file: $p" >&2; fail=1; }
done < <(grep -E "^f " "$TARGET/csdid.pkg")
[ "$fail" = "0" ] && echo "   payload checks passed"

echo
echo "payload assembled in $TARGET"
echo "nothing committed. review with: git -C \"$TARGET\" status"
exit "$fail"
