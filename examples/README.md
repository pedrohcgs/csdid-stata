# csdid Examples

These examples are small runnable workflows. Examples 01-05 build their own
synthetic data, so they need nothing but Stata and csdid. Example 06 uses the
mpdta extract shipped in `examples/data/mpdta.csv`. Nothing is downloaded.

Run them from a Stata session where csdid is installed, with the repository
root as the working directory — the `do` lines below are written relative to
it, and `06_mpdta_workflow.do` resolves its data file relative to `c(pwd)`
(the repository root, or `examples/` itself):

```stata
do examples/01_balanced_panel.do
do examples/02_unbalanced_weighted_clustered.do
do examples/03_repeated_cross_section.do
do examples/04_postestimation_exports.do
do examples/05_legacy_migration.do
do examples/06_mpdta_workflow.do
```

## Files

- `01_balanced_panel.do`: balanced panel with covariates, default doubly robust
  estimation, event replay, and simple aggregation.
- `02_unbalanced_weighted_clustered.do`: unbalanced panel with covariates,
  weights, clustered analytical standard errors, event aggregation, and plot
  data export.
- `03_repeated_cross_section.do`: repeated cross-section workflow with weights
  and IPW.
- `04_postestimation_exports.do`: saved RIF workflow, `estat event`, tidy and
  glance exports, and plot data export.
- `05_legacy_migration.do`: modern replacements for legacy unbalanced-panel,
  universal-base event-study, and full-storage workflows.
- `06_mpdta_workflow.do`: MPDTA applied-data workflow with default estimation,
  event replay, simple/group/calendar/event aggregation, and plot-data export.

These examples are smoke workflows, not a substitute for the test suite
under tests/.
