#!/usr/bin/env bash
set -euo pipefail

doc="docs/stata-engineering-references.md"
test -f "$doc"

for repo in \
  "mcaceresb/stata-gtools" \
  "mcaceresb/stata-honestdid" \
  "gphk-metrics/stata-multe" \
  "mcaceresb/stata-staggered" \
  "mcaceresb/stata-pretrends" \
  "sergiocorreia/reghdfe" \
  "sergiocorreia/ftools" \
  "sergiocorreia/ivreghdfe" \
  "sergiocorreia/ppmlhdfe" \
  "sergiocorreia/stata-misc"; do
  grep -qE "$repo" "$doc"
done

hash_count="$(grep -oE '[0-9a-f]{40}' "$doc" | wc -l | tr -d ' ')"
test "$hash_count" -ge 10
grep -qE 'econometric oracle' "$doc"
