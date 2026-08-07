#!/usr/bin/env bash
set -euo pipefail

# The multiplier-bootstrap kernel must be chosen by PROBLEM SIZE alone, never by
# the replication count.
#
# There used to be a `biters <= 64' branch routing large-n, few-replication jobs
# to a third kernel that accumulated one replication at a time. It was slower
# AND less accurate than the table kernel at every size measured -- 12.0s
# against 0.64s on 20,000 units by 499 replications, and 5.0e-15 against
# 2.5e-15 relative error against a quad-precision reference. There was no
# configuration in which it was the right choice.
#
# Worse, it produced a cliff pointing the wrong way, which a user could hit
# without knowing kernels existed: asking for FEWER replications made the
# command SLOWER. Measured on 60,000 units, reps(64) took 5.083s where reps(65)
# took 2.963s. After the branch was removed, 2.774s and 2.988s -- monotone.
#
# This is asserted structurally rather than by timing, because a wall-clock
# assertion in a test suite is a flake waiting to happen, and the property we
# actually want is that the SELECTOR cannot depend on the replication count.

MATA="src/mata/csdid.mata"

# and the selector must not branch on the replication count
selector=$(awk '/^real matrix csdid__bmisc_bootstrap_auto\(/,/^}/' "$MATA")
if [ -z "$selector" ]; then
  echo "csdid__bmisc_bootstrap_auto not found -- this gate is checking nothing" >&2
  exit 1
fi

# There is now ONE kernel and no routing at all, which is stronger than
# "routed by size and not by replication count": nothing about the problem can
# select a different summation order, so the answer depends on the data, the
# options and the seed and on nothing else.
#
# Comments are stripped first, so the explanatory notes in the code neither
# satisfy nor trip this test.
stripped=$(printf '%s\n' "$selector" | sed 's://.*::')
if printf '%s\n' "$stripped" | grep -qE '(biters|rows\(x\)|cols\(x\)) *(<=|<|>=|>|==)'; then
  echo "the bootstrap kernel selector must not branch on the problem at all: a size- or replication-dependent route means the same data and seed can be summed in two different orders, which is the reproducibility contract this gate exists to prevent" >&2
  exit 1
fi

# ...and the retired kernels must not reappear anywhere in the engine
for retired in csdid__bmisc_bootstrap_dot csdid__bmisc_bootstrap_dense; do
  if grep -n "$retired" "$MATA"; then
    echo "$retired was retired; the multiplier bootstrap has one kernel" >&2
    exit 1
  fi
done

# the surviving kernel must actually be the one being called
if ! printf '%s\n' "$stripped" | grep -qE 'csdid__bmisc_bootstrap_matrix'; then
  echo "the bootstrap selector does not call the table kernel -- this gate is checking nothing" >&2
  exit 1
fi

echo "bootstrap kernel policy OK: one kernel, no routing"
