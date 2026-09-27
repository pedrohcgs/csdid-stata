#!/usr/bin/env bash
# The engine teardown (_csdid_engine_teardown in src/ado/_csdid_engine_load.ado)
# drops csdid's single-underscore Mata functions by explicit name, because the
# pattern csdid_*() also matches other packages' names and Mata refuses a
# pattern drop as a whole when any match is a class with a live instance. A
# function added to csdid.mata but not to that list would survive a teardown
# and stop the source fallback with "already exists"; one listed but no longer
# defined is dead weight. The two lists must be the same set.
set -euo pipefail
cd "$(dirname "$0")/../.."

defined="$(grep -E '^[a-z][a-z ]*[a-z]+ +(scalar |vector |rowvector |colvector |matrix )?csdid_[a-zA-Z0-9_]*\(' src/mata/csdid.mata \
  | grep -v '::' | sed -E 's/.*(csdid_[a-zA-Z0-9_]*)\(.*/\1/' | grep -v '^csdid__' | sort -u)"
listed="$(awk '/^program define _csdid_engine_teardown/{on=1} on && /^end/{on=0} on' src/ado/_csdid_engine_load.ado \
  | grep -oE '(^|[[:space:]])csdid_[a-zA-Z0-9][a-zA-Z0-9_]*' | sed -E 's/^[[:space:]]+//' | sort -u)"

if [ -z "$defined" ] || [ -z "$listed" ]; then
  echo "FAIL: could not read the defined or the listed function names" >&2
  exit 1
fi
if [ "$defined" != "$listed" ]; then
  echo "FAIL: the teardown list and csdid.mata's single-underscore functions differ:" >&2
  diff <(echo "$defined") <(echo "$listed") >&2 || true
  exit 1
fi
echo "test-engine-teardown: PASS ($(echo "$defined" | wc -l | tr -d ' ') names)"
