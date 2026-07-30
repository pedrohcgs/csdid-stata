# csdid Examples

These examples are small runnable workflows. They use synthetic data so
they can run without external dependencies.

Run from a Stata session where csdid is installed:

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
