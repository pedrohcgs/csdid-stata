#!/usr/bin/env bash
set -euo pipefail

doc="docs/stata-engineering-references.md"
for path in \
  src/ado/csdid.ado \
  src/ado/csdid_estat.ado \
  src/ado/csdid_stats.ado \
  src/ado/csdid_plot.ado \
  src/mata/csdid.mata \
  src/help/csdid.sthlp \
  src/help/csdid_postestimation.sthlp \
  src/help/csdid_estat.sthlp \
  src/help/csdid_stats.sthlp \
  src/help/csdid_plot.sthlp; do
  test -f "$path"
done

grep -qE 'ado wrappers own syntax parsing' "$doc"
grep -qE 'Mata kernels own group/time indexing' "$doc"
grep -qE 'postestimation commands consume stored matrices' "$doc"
grep -qE 'Stata 15-compatible' "$doc"
grep -qE 'csdid`, `csdid_estat`, `csdid_stats`, and[[:space:]]*$' "$doc"
