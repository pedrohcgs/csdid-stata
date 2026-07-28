# Tolerance Registry v1

Status: frozen for conformance profile v1.

Tolerance IDs in `inst/spec/feature-matrix.csv` are binding. A comparison may
use a looser tolerance only through a recorded approved divergence.

## EXACT

Use for names, option defaults, statuses, booleans, command return codes, sample
masks, row/column ordering, fixture manifests, diagnostics, warning classes,
error classes, command syntax, and dependency decisions.

Threshold: byte-for-byte equality after documented normalization.

## TOL001 Scalar Numeric Parity

Use for deterministic point estimates, aggregation estimates, standard errors,
critical values, p-values, and scalar diagnostics exported from R `did` 2.5.1.

Threshold: absolute tolerance `1e-10`, relative tolerance `1e-10`.

Justification: deterministic scalar outputs should match at double precision
apart from harmless runtime ordering differences.

## TOL002 Matrix And Vector Parity

Use for covariance matrices, influence-function summaries, standard-error
vectors, aggregation weight vectors, and plot-data numeric columns.

Threshold: absolute tolerance `1e-8`, relative tolerance `1e-8`.

Justification: matrix accumulations may differ slightly by loop ordering, but
this threshold is tight enough to expose algorithmic disagreement.

## TOL003 Bootstrap Quantities

Use for seeded multiplier/bootstrap quantities and bootstrap summaries.

Threshold: exported seeded draws must match exactly when the fixture covers an
implemented shared draw stream. The public seeded rademacher path mirrors
BMisc/R's multiplier stream; fixtures that do not export raw draws must record
that boundary explicitly. If a runtime path cannot share a draw stream, compare
deterministic summary quantities using absolute tolerance `5e-4` and relative
tolerance `5e-4`, and require the fixture manifest to record seed, draw count,
draw distribution, and reason exact draw parity is unavailable for that path.

## TOL004 Published JEL Tables

Use for numeric values in committed or generated JEL tables when published
precision is coarser than the underlying output.

Threshold: absolute tolerance `5e-5` for values reported to four decimals;
otherwise one half unit in the last displayed decimal place. When underlying
R/Stata comparison artifacts are available, also compare those under TOL001 or
TOL002.

## TOL005 Plot Data

Use for extracted plot coordinates, estimates, lower/upper bounds, event-time
labels after numeric normalization, and grouping variables before rendering.

Threshold: absolute tolerance `1e-8`, relative tolerance `1e-8` for numeric
columns; EXACT for labels and ordering.

## TOL006 Rendered Graphs

Use only after plot-data parity passes.

Threshold: no numeric threshold. Rendered graph differences are acceptable only
when the fixture records plot-data parity, the difference is cosmetic, and the
release report names the accepted difference. PDF identity is not required.

## TOL007 Performance Budgets

Use for wall-clock and memory budgets in `inst/spec/bench-budgets.yml`.

Threshold: fail against frozen budgets for default benchmark tiers. Opt-in large
and JEL budgets may be marked release-note exceptions only with an approved
performance note.

## TOL008 Stochastic Monte Carlo Sanity

Use for release/nightly Monte Carlo checks that validate coverage and bias
rather than individual draw equality.

Threshold: absolute bias no larger than `0.02` in standardized effect units and
empirical coverage within `0.03` of nominal for the configured simulation size,
unless the simulation manifest sets a stricter threshold.
