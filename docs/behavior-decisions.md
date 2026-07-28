# Behavior Decisions

Status: frozen for conformance profile v1.

These decisions define the implementation contract for the first Stata `csdid`
rewrite. A future implementation may change them only through a new decision
record and a conformance-profile update.

## D001 Source Of Truth

Status: accepted

Decision: R `did` 2.5.1 at GitHub commit
`9aba07d054a798558ac9b551887f5cb592d8db10` is the primary source of truth for
estimator behavior, defaults, sample handling, inference, aggregation, plotting
data, examples, and public test behavior. Python `csdid` at commit
`555f28bc12fcafa9c099e6e5503a30a4c22fc89f` supplies deeper tests where useful,
but cannot override R. Existing Stata `csdid` at commit
`fdbae25521a941314af8d84ec0c93fb0596daa8e` is legacy evidence only.

Rejected alternatives: use current Stata as oracle; average across references;
let Python override R on edge cases.

Required evidence: reference locks, R fixture outputs, Python deeper-test map,
legacy Stata option inventory.

## D002 New Codebase Default

Status: accepted

Decision: Build a new Stata codebase with compatibility wrappers for retained
legacy entry points. Do not incrementally patch legacy implementation internals
unless a later provenance review explicitly allows reuse. The new codebase must
keep `csdid`, `csdid_estat`, `csdid_stats`, and `csdid_plot` command surfaces
unless the frozen option matrix marks a specific behavior removed.

Rejected alternatives: patch current ado files in place; preserve legacy
internals for speed; change the public command name.

Required evidence: command-surface tests, provenance ledger, migration guide.

## D003 Unbalanced Panels

Status: accepted

Decision: New Stata defaults must follow the owner-specified R `did` semantics
for unbalanced data: when an unbalanced panel is analyzed under the
R-compatible unbalanced-panel mode, the estimator must use
repeated-cross-section computations while preserving the correct standard-error
behavior. The observed R 2.5.1 function signature has
`allow_unbalanced_panel = FALSE`, but the owner requirement for this Stata port
is that the default must not reproduce current Stata's pair-balanced drop
behavior. Therefore v1 must expose an explicit R-signature-compatible balancing
option, while the Stata package default for an actually unbalanced panel uses
the R repeated-cross-section computation path. This owner-directed default is
binding unless superseded by a later decision. Current Stata pair-balanced and
full-balanced behavior may exist only behind explicit compatibility options
with soft-deprecation warnings. It may not be the default.

Rejected alternatives: keep current pair-balanced default; silently drop to
balanced units; require users to know `bal(unbal)`.

Required evidence: F016 R/Python/legacy/new-Stata fixture, standard-error
fixture, sample-mask fixture, and compatibility-warning or explicit rejection
tests for legacy balance modes.

## D004 Test Inheritance

Status: accepted

Decision: Every applicable R `did` test file must map to Stata coverage or an
approved exclusion. Every Python `csdid` deeper test file must map to Stata
coverage or an approved exclusion. The feature matrix is the binding test map.

Rejected alternatives: cover only selected smoke tests; defer Python deeper
coverage until after release; rely on JEL replication alone.

Required evidence: RT001-RT030 and PY001-PY024 matrix rows.

## D005 Defaults

Status: accepted

Decision: Stata defaults must match R `did` 2.5.1 defaults except where this
contract records an owner-directed default, currently D003 for actually
unbalanced panels. Legacy defaults that depart from R or from D003 must move to
explicit compatibility options and warn.

Key defaults to freeze during implementation include control group, base period,
bootstrap/cband behavior, significance level, unbalanced-panel handling,
estimation method mapping, and aggregation defaults.

Rejected alternatives: preserve old Stata defaults for continuity; expose R
defaults only through an option.

Required evidence: default snapshot tests and legacy migration docs.

## D006 JEL Replication

Status: accepted

Decision: `pedrohcgs/JEL-DiD` is a release-blocking empirical acceptance suite.
Core package parity follows R `did` 2.5.1, but JEL replication must preserve and
compare the JEL repository's own pinned scripts, tables, figures, and dependency
metadata. The JEL `renv.lock` observed in the reference checkout pins R `did`
2.3.0; this is the original empirical artifact target, not the package-wide
statistical oracle. If reproducing a committed JEL artifact requires behavior
that differs from R `did` 2.5.1, record a JEL empirical compatibility decision
and keep default package behavior aligned with the v1 conformance profile.

Rejected alternatives: ignore JEL because it used older package versions; compare
only selected JEL tables; require rendered-PDF identity before plot-data parity.

Required evidence: JEL001-JEL018 matrix rows, generated table comparisons, plot
data comparisons, isolated ado-path run.

## D007 License And Provenance

Status: accepted

Decision: Until a deliberate license change is made, implementation code must be
clean-room relative to R `did` GPL-3 code, existing Stata `csdid`, Python
`csdid`, and engineering-reference packages. Generated numerical outputs,
behavioral specs, public docs, and tests may be used as parity targets. Any
copied or adapted implementation code requires an explicit provenance entry and
a license-compatible package decision before use.

Rejected alternatives: copy R or legacy Stata internals without review; use
engineering-reference source snippets without provenance; leave license
undefined.

Required evidence: `PROVENANCE.md`, source-use statement in final reports,
license audit before release.

## D008 Legacy Stata Compatibility

Status: accepted

Decision: Existing Stata behavior is retained only when it is useful for
migration and does not compromise R-parity defaults. Retained legacy behavior
must be opt-in, documented, and covered by tests comparing legacy and R-parity
behavior. Unretained legacy behavior is classified as removed or
unsupported-by-design in `docs/legacy-stata-compatibility.md`.

Rejected alternatives: retain all current behavior; remove all legacy options;
make compatibility warnings optional.

Required evidence: legacy option inventory, deprecation warnings, compatibility
tests.

## D009 Stata Engineering References

Status: accepted

Decision: The Mauricio Caceres Bravo and Sergio Correia repositories listed in
`docs/stata-engineering-references.md` are engineering references for
architecture, performance, testing, dependency policy, and Stata package style.
They do not override R `did` 2.5.1 for statistical behavior, defaults, samples,
or inference.

Rejected alternatives: treat engineering references as optional reading only;
copy their internals without provenance; add hard runtime dependencies without
fallback analysis.

Required evidence: frozen engineering plan, dependency policy, engineering
audit, benchmarks, provenance ledger.

## D010 Treatment Timing Encodings

Status: accepted

Decision: R `did` uses group variable value `0` for never-treated units. New
Stata must accept `gvar == 0` as never treated. Missing `gvar`, negative
treatment dates, treatment before the first observed period, treatment in the
first period, and inconsistent within-unit treatment dates must follow R
validation and diagnostics unless the feature matrix records an approved
Stata-specific divergence.

Rejected alternatives: preserve all current Stata treatment-date rules; silently
coerce missing treatment timing to never-treated.

Required evidence: F021-F023 and RT010/RT011.

## D011 Control Groups And Base Periods

Status: accepted

Decision: `nevertreated` and `notyettreated` controls and `varying` and
`universal` base-period behavior must match R. Stata aliases may be added for
ergonomics only if the canonical behavior and output remain R-parity.

Rejected alternatives: keep current Stata pre-treatment gap defaults where they
disagree; expose only old `long`/`long2` semantics.

Required evidence: F007-F009, RT005, PY016.

## D012 Weights

Status: accepted

Decision: Stata must match R `weightsname` and `fix_weights` behavior for
balanced panels, unbalanced panels, and repeated cross sections. Time-varying
weights must be tested explicitly. Existing Stata `iweight` syntax can remain as
syntax sugar only after normalization to the R contract.

Rejected alternatives: treat all Stata weights as legacy; ignore time-varying
weights; use current Stata weight semantics when R differs.

Required evidence: F012, F028, RT005, PY017.

## D013 Inference

Status: accepted

Decision: Analytical standard errors, multiplier bootstrap, clustering,
simultaneous bands, p-values, and aggregation inference must match R. Stata
wild-bootstrap interfaces may be retained as wrappers only if their outputs map
to R-compatible behavior or are marked legacy-compatible.

Rejected alternatives: rely on legacy Stata bootstrap output as oracle; test
point estimates only; omit off-diagonal influence-function/covariance checks.

Required evidence: F013-F015, F035, RT007, RT015, RT017-RT018, PY002, PY004,
PY012, PY015.

## D014 Aggregation And Postestimation

Status: accepted

Decision: `simple`, `group`, `calendar`, and `dynamic` aggregation must match R.
Existing `csdid_estat` and `csdid_stats` workflows should remain as Stata
interfaces to the R-parity aggregation contract, including saved RIF/posting
behavior where retained.

Rejected alternatives: preserve current aggregation semantics when they differ;
make aggregation a separate non-parity feature.

Required evidence: F003-F006, F025-F027, F034, RT002-RT003, PY001.

## D015 Plotting

Status: accepted

Decision: Stata plotting commands must expose graph behavior suitable for Stata
users, but tests should first verify extracted plot data against R/Python
semantics. Rendered graph differences are acceptable only as documented cosmetic
divergences after plot-data parity passes.

Rejected alternatives: compare rendered PDFs only; ignore plotting; copy R
`ggplot2` visual styling literally.

Required evidence: F028, RT013, PY010, JEL010-JEL018.

## D016 Release Support

Status: accepted

Decision: v1 must support clean installation in an isolated ado path, default
offline tests, opt-in full parity tests, Stata-version checks, and no hidden
network/user-path dependencies. Optional dependencies must have explicit
availability checks and fallbacks or be declared test-only.

Rejected alternatives: depend on the user's global ado tree; require internet in
default tests; use unpinned SSC installs in release checks.

Required evidence: F050, ENG003, ENG005, hardening final report.

## D017 Fixture And Reference Schemas

Status: accepted

Decision: Fixture paths, manifests, expected-output schemas, source-test hashes,
and reference locks are part of the frozen contract. F, RT, and PY matrix rows
use `tests/fixtures/parity/{matrix_id_lowercase}`. JEL rows use
`tests/fixtures/jel/{matrix_id_lowercase}`. Every generated fixture must follow
`inst/spec/fixture-schemas.md`.

Rejected alternatives: let each generator choose ad hoc artifact paths; compare
unstructured logs only; defer source-test hashes until implementation.

Required evidence: `inst/spec/fixture-schemas.md`,
`tools/parity/reference-lock/*`, `tools/parity/source-test-inventory.csv`.
