#!/usr/bin/env bash
set -euo pipefail

# The speed gains against Version 1.82 are measured in ONE place -- the four
# tables on website/articles/speed-vs-182.md -- and then quoted on three other
# pages: the front page's headline claim, the guides index, and the comparison
# article's cross-reference.
#
# A quoted number has no way of noticing that the table it came from moved.
# This derives the range from the tables and checks every page that states it,
# so re-measuring cannot leave the site contradicting itself.
#
# It also catches the error that was live when this gate was written: two pages
# said the gains "range from 16x to 208x". 16x is the smallest gain in the
# PERIODS table; the smallest on the page is 5.3x, in the sampling-scheme
# table. The stated floor came from one table and the ceiling from another,
# which reads as a measured range and is not one.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LADDER="$ROOT/website/articles/speed-vs-182.md"
FIELD="$ROOT/website/articles/csdid-against-the-field.md"
GUIDES="$ROOT/website/guides.md"
INDEX="$ROOT/website/index.md"

for f in "$LADDER" "$FIELD" "$GUIDES" "$INDEX"; do
  [ -f "$f" ] || { echo "missing $f -- this gate is checking nothing" >&2; exit 1; }
done

# The gain column is the last cell of a table row: "| 35x |" or "| **61x** |".
mapfile -t GAINS < <(grep -oE '\| \*{0,2}[0-9]+(\.[0-9]+)?x\*{0,2} \|$' "$LADDER" \
                     | grep -oE '[0-9]+(\.[0-9]+)?')

if [ "${#GAINS[@]}" -lt 8 ]; then
  echo "found only ${#GAINS[@]} gain cells in speed-vs-182.md; the page has four tables and this gate is not reading them" >&2
  exit 1
fi

MIN=$(printf '%s\n' "${GAINS[@]}" | sort -g | head -1)
MAX=$(printf '%s\n' "${GAINS[@]}" | sort -g | tail -1)
echo "speed-vs-182 tables: ${#GAINS[@]} cells, gains ${MIN}x to ${MAX}x"

fail=0

# ---------------------------------------------------------------------------
# Any page stating a range must state THIS range. Ranges are written as
# "from AxB to Cx" or "range from Ax to Cx"; both forms are matched.
# ---------------------------------------------------------------------------
for page in "$FIELD" "$GUIDES" "$LADDER"; do
  rel="${page#"$ROOT"/}"
  while read -r stated; do
    [ -z "$stated" ] && continue
    lo="${stated%%|*}"
    hi="${stated##*|}"
    if [ "$lo" != "$MIN" ] || [ "$hi" != "$MAX" ]; then
      echo "FAIL $rel states the range as ${lo}x to ${hi}x; the tables measure ${MIN}x to ${MAX}x" >&2
      fail=1
    fi
  done < <(grep -oE 'from [0-9]+(\.[0-9]+)?x to [0-9]+(\.[0-9]+)?x' "$page" \
           | sed -E 's/from ([0-9.]+)x to ([0-9.]+)x/\1|\2/')
done

# ---------------------------------------------------------------------------
# The front page rounds ("sometimes be 200x faster"). A round number need not
# equal the maximum, but it must not EXCEED what was measured.
# ---------------------------------------------------------------------------
while read -r claim; do
  [ -z "$claim" ] && continue
  if awk "BEGIN{exit !($claim > $MAX)}"; then
    echo "FAIL website/index.md claims ${claim}x faster than Version 1.82; the largest measured gain is ${MAX}x" >&2
    fail=1
  fi
done < <(grep -oE '[0-9]+(\.[0-9]+)?x faster than Version 1\.82' "$INDEX" \
         | grep -oE '^[0-9]+(\.[0-9]+)?')

[ "$fail" -eq 0 ] || exit 1
echo "website speed claims OK: every stated range and headline matches the measured tables"
