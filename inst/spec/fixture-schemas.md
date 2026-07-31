# Fixture Schemas

Status: frozen for conformance profile v1.

All parity fixtures use canonical paths from `inst/spec/feature-matrix.csv`:

- F, RT, and PY rows: `tests/fixtures/parity/{matrix_id_lowercase}`.
- JEL rows: `tests/fixtures/jel/{matrix_id_lowercase}`.
- Engineering rows: docs/reports paths named in the matrix.

Each fixture directory must contain `metadata/manifest.json`. Expected-output
files use CSV or JSON with UTF-8 text and normalized missing values.

## `metadata/manifest.json`

Required keys:

- `matrix_id`
- `fixture_family`
- `normative_source`
- `source_commit`
- `decision_refs`
- `tolerance_ids`
- `inputs`: list of `{path, sha256, rows, columns}`
- `generators`: list of `{runtime, command, path, sha256}`
- `runtimes`: list of `{name, version, package_versions}`
- `rng`: `{seed, kind, draws, distribution}` or `null`
- `expected_outputs`: list of `{path, schema, sha256}`
- `comparison_plan`: list of `{actual, expected, tolerance_id, key_columns}`
- `approved_divergence`: `null` or `{decision_ref, explanation}`

## ATT(g,t) Table

File name: `expected/{source}/attgt.csv`

Required columns:

- `group`
- `time`
- `event_time`
- `att`
- `se`
- `crit_val`
- `ci_low`
- `ci_high`
- `control_group`
- `base_period`
- `est_method`
- `panel_mode`
- `sample_n`
- `inffunc_col`

Primary key: `group,time`.

## Influence-Function Summary

File name: `expected/{source}/inffunc-summary.csv`

Required columns:

- `group`
- `time`
- `n_rows`
- `mean`
- `sd`
- `l1_norm`
- `l2_norm`
- `min`
- `max`
- `nonzero_count`

Full influence-function matrices may be stored only for small fixtures. Large
fixtures should store summaries plus hashes of full artifacts.

## Sample Mask

File name: `expected/{source}/sample-mask.csv`

Required columns:

- `rowid`
- `id`
- `time`
- `group`
- `included`
- `drop_reason`
- `cell_membership`

Primary key: `rowid`. `drop_reason` uses stable codes, not prose.

## Aggregation Table

File name: `expected/{source}/aggregation-{type}.csv`

Required columns:

- `type`
- `term`
- `event_time`
- `group`
- `time`
- `estimate`
- `se`
- `crit_val`
- `ci_low`
- `ci_high`
- `weight`
- `included_cells`

Primary key depends on `type` and must be recorded in the manifest.

## Plot Data

File name: `expected/{source}/plot-data.csv`

Required columns:

- `plot_type`
- `series`
- `x`
- `x_label`
- `estimate`
- `ci_low`
- `ci_high`
- `group`
- `time`
- `event_time`
- `significant`

Labels and row order use EXACT. Numeric columns use TOL005.

## Error And Warning Events

File name: `expected/{source}/events.json`

Each event object must include:

- `return_code`
- `event_type`: `error` or `warning`
- `event_key`: stable machine-readable identifier
- `offending_option`
- `message_normalized`

Tests compare `return_code`, `event_type`, `event_key`, and
`offending_option` exactly. Full message text is compared after whitespace and
path normalization.

## Legacy Migration Checklist

File name: `expected/new-stata/migration-checklist.csv`

Required columns:

- `gate`
- `surface`
- `classification`
- `canonical_behavior`
- `evidence`
- `document`

Rows use EXACT matching. `surface` is the primary key. `evidence` contains
semicolon-separated matrix row or decision identifiers. `document` must point to
the contract migration document that explains the user-facing behavior.

## Source Test Map

File name: `expected/contract/upstream-test-map.csv`

Required columns:

- `source_file`
- `source_sha256`
- `source_test`
- `mapped_scenario`
- `assertion_family`
- `coverage_status`

Rows use EXACT matching. `source_test` is the primary key. `coverage_status`
must be `mapped`, `pending`, `approved-exclusion`, or `approved-divergence`.
Any value other than `mapped` must identify the governing decision or blocker
in the manifest scope note or approved-divergence block.

## Stata Stored Results

File name: `expected/new-stata/ereturn.json`

Required keys:

- `e_cmd`
- `e_properties`
- `macros`
- `scalars`
- `matrices`
- `matrix_stripes`
- `postestimation_available`

Matrix row and column stripes use EXACT.

## Normalization Rules

- Sort rows by the schema primary key before comparison.
- Represent missing numeric values as empty CSV fields plus a manifest-declared
  missing-code map when Stata extended missings are relevant.
- Normalize `NaN`, `Inf`, and `-Inf` as strings in JSON and as manifest-declared
  sentinel values in CSV.
- Preserve variable names exactly. Variable labels and value labels are compared
  only in fixtures that explicitly opt in.
- Normalize paths to fixture-relative paths.
- Numeric exports must use at least 17 significant digits.
