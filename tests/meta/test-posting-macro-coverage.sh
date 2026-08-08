#!/usr/bin/env bash
# Every e() MACRO that estimation or aggregation posts must survive
# _csdid_post_replace_bv, which does `ereturn clear' and re-posts from a
# hand-maintained enumeration (`local local_names'). A macro missing from it is
# destroyed by `csdid ..., agg(event)' and by `estat <type>, post'.
#
# The sibling gate test-posting-scalar-coverage.sh has guarded the SCALARS
# since two of them were lost this way. Macros had no such gate, and on
# 2026-08-07 an automated review of the release pull request found e(wtype) and
# e(wexp) -- the weight type and expression, both documented in csdid.sthlp as
# how you recover what the user typed -- silently emptied by any post.
#
# Same defect class, same file, one enumeration over. This closes it.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

POST="src/ado/_csdid_post.ado"
test -f "$POST"

enumerated="$(awk '
  /local local_names/ {inblock=1}
  inblock {print}
  inblock && !/\/\/\/[[:space:]]*$/ {inblock=0}
' "$POST" | sed 's/local local_names//; s|///||g' | tr -s ' \t' '\n' | sed '/^$/d' | sort -u)"

if [[ -z "$enumerated" ]]; then
  echo "could not read local_names out of $POST" >&2
  exit 1
fi

# Macros that _csdid_post_replace_bv restores through their own named path
# rather than through local_names. Each must be visibly re-posted in that file,
# checked below, so this cannot become a blanket exemption.
# Two ways a macro can legitimately survive without appearing in local_names,
# and they are checked differently so neither becomes a blanket exemption.
#
# RESCUED: read out of e() before the clear and written back after. Deleting
# either half fails the gate.
declare -a RESCUED=(
  bootstrap_accelerator
  bootstrap_accelerator_status
  bootstrap_accelerator_file
  agg_boot_accelerator
  agg_boot_accel_status
  rseed
)

# REESTABLISHED: not carried at all, but set unconditionally by the poster, so
# its value after a post is correct by construction rather than preserved.
declare -a REESTABLISHED=(
  estat_cmd
)

for name in "${RESCUED[@]}"; do
  # Read either directly as e(name), or through a foreach loop that names it
  # and reads e(`x') -- which is how reps and rseed are carried, because they
  # may be stored as a scalar or as a macro.
  if ! grep -qE "e\(${name}\)" "$POST" && ! grep -qE "foreach [a-z]+ in .*\b${name}\b" "$POST"; then
    echo "$name is listed as rescued but $POST never reads it out of e()" >&2
    exit 1
  fi
  if ! grep -qE "ereturn local ${name}[ =]|foreach .*\b${name}\b|local ${name}\b" "$POST"; then
    echo "$name is listed as rescued but $POST never re-posts it" >&2
    exit 1
  fi
done

for name in "${REESTABLISHED[@]}"; do
  if ! grep -qE "ereturn local ${name} " "$POST"; then
    echo "$name is listed as re-established but $POST never sets it" >&2
    exit 1
  fi
done

SEPARATE=( "${RESCUED[@]}" "${REESTABLISHED[@]}" )

missing=""
for src in src/ado/csdid.ado src/ado/csdid_stats.ado; do
  posted="$(grep -oE 'ereturn local [A-Za-z_][A-Za-z0-9_]*' "$src" | awk '{print $3}' | sort -u)"
  for name in $posted; do
    grep -qx -- "$name" <<<"$enumerated" && continue
    skip=0
    for exempt in "${SEPARATE[@]}"; do
      [[ "$name" == "$exempt" ]] && skip=1 && break
    done
    [[ "$skip" == 1 ]] && continue
    missing="$missing $src:$name"
  done
done

if [[ -n "$missing" ]]; then
  echo "e() macros posted at estimation but not carried across _csdid_post_replace_bv:" >&2
  for m in $missing; do echo "   $m" >&2; done
  echo "   add them to \`local local_names' in $POST, or give them a named rescue path" >&2
  exit 1
fi

echo "posting macro coverage OK: every posted e() macro survives the post round trip"
