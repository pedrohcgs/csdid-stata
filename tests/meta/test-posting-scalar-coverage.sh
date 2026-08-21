#!/usr/bin/env bash
# Every e() scalar that estimation or aggregation posts must survive
# _csdid_post_replace_bv, which does `ereturn clear' and re-posts from a
# hand-maintained enumeration. A scalar missing from that enumeration is
# destroyed by `csdid ..., agg(event)' and by `estat <type>, post' -- silently,
# because the printed output is produced before the post.
#
# This has happened twice. F-055 lost time_first, so balance_e() broke after
# any estat event; and wald_stat/wald_df/wald_pvalue went missing together, so
# a run that printed a pre-test p-value then failed `confirm scalar
# e(wald_pvalue)', which help csdid names as the test for "a p-value was
# printed". The gate exists so there is no third time.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

POST="src/ado/_csdid_post.ado"
test -f "$POST"

# The enumeration: everything between `local scalar_names' and the line that
# closes it (the continuation lines end in ///).
enumerated="$(awk '
  /local scalar_names/ {inblock=1}
  inblock {print}
  inblock && !/\/\/\/[[:space:]]*$/ {inblock=0}
' "$POST" | sed 's/local scalar_names//; s|///||g' | tr -s ' \t' '\n' | sed '/^$/d' | sort -u)"

if [[ -z "$enumerated" ]]; then
  echo "could not read scalar_names out of $POST" >&2
  exit 1
fi

# Scalars rescued by their own named code path in _csdid_post_replace_bv
# rather than through scalar_names. Each must be readable in that file, which
# is checked below, so this list cannot drift into a blanket exemption.
declare -a SEPARATE=(
  bootstrap_accelerator_rc
  bootstrap_accelerator_seconds
  agg_boot_accel_rc
  reps
)

for name in "${SEPARATE[@]}"; do
  # Either an explicit `ereturn scalar <name> =' or a named loop that re-posts
  # it (reps/rseed are re-posted in whichever form they were stored).
  if ! grep -qE "ereturn scalar ${name} =|foreach x in .*\b${name}\b" "$POST"; then
    echo "$name is listed as separately rescued but $POST never re-posts it" >&2
    exit 1
  fi
done

missing=""
for src in src/ado/csdid.ado src/ado/csdid_stats.ado; do
  posted="$(grep -oE 'ereturn scalar [A-Za-z_][A-Za-z0-9_]*' "$src" | awk '{print $3}' | sort -u)"
  for name in $posted; do
    if grep -qx -- "$name" <<<"$enumerated"; then
      continue
    fi
    skip=0
    for exempt in "${SEPARATE[@]}"; do
      [[ "$name" == "$exempt" ]] && skip=1
    done
    [[ $skip -eq 1 ]] && continue
    missing="$missing $src:$name"
  done
done

if [[ -n "$missing" ]]; then
  echo "e() scalars posted but not carried across _csdid_post_replace_bv:$missing" >&2
  echo "add them to scalar_names in $POST, or give them a named rescue and list them in SEPARATE here" >&2
  exit 1
fi

# Seed check: the gate has to be able to fail. A name the enumeration does not
# contain must be reported.
if grep -qx -- "definitely_not_a_posted_scalar" <<<"$enumerated"; then
  echo "seed check failed: the enumeration matched a name that cannot be in it" >&2
  exit 1
fi

echo "posting scalar coverage ok"
