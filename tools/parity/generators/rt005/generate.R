#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt005/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

py003_generator <- file.path(root, "tools/parity/generators/py003/generate.py")
py003_output <- system2("python3", py003_generator, stdout = TRUE, stderr = TRUE)
invisible(py003_output)

fixture <- file.path(root, "tests/fixtures/parity/rt005")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

py003_fixture <- file.path(root, "tests/fixtures/parity/py003")
input_files <- list.files(file.path(py003_fixture, "inputs"), full.names = TRUE)
for (src in input_files) {
  invisible(file.copy(src, file.path(fixture, "inputs", basename(src)), overwrite = TRUE))
}
input_meta <- lapply(list.files(file.path(fixture, "inputs"), full.names = TRUE), function(path) {
  dat <- read.csv(path)
  list(path = file.path("inputs", basename(path)), rows = nrow(dat), columns = ncol(dat))
})

source_file <- "tests/testthat/test-att_gt.R"
source_sha <- "ac654d0ea602886f19cc43418231741dbad6a3e605bfb6d76b08de2ce595453c"
source_tests <- c(
  "att_gt works w/o dynamics, time effects, or group effects",
  "att_gt works using ipw",
  "two period case",
  "no covariates case",
  "repeated cross section",
  "ipw repeated cross sections",
  "repeated cross sections dynamic effects",
  "unbalanced panel",
  "not yet treated comparison group",
  "aggregations",
  "unequally spaced groups",
  "some units treated in first period",
  "min and max length of exposures",
  "anticipation",
  "significance level and uniform confidence bands",
  "malformed data",
  "varying or universal base period",
  "small groups",
  "small comparison group",
  "custom estimation method",
  "sampling weights",
  "works when user column is literally named 'gname'",
  "works when user column is literally named 'gname' with faster_mode",
  "time-varying weights: faster_mode matches slow mode (default fix_weights=NULL)",
  "fix_weights options: faster_mode matches slow mode (balanced panel)",
  "time-invariant weights: all fix_weights options produce identical ATTs",
  "message emitted for time-varying weights in balanced panel",
  "no message for time-invariant weights",
  "notyettreated with time-varying weights: faster_mode matches",
  "RC with time-varying weights: faster_mode matches",
  "fix_weights validation",
  "unbalanced panel fix_weights with units missing from reference period",
  "IF consistency: balanced panel, all fix_weights x est_method x base_period",
  "IF consistency: balanced panel, notyettreated control group",
  "IF consistency: repeated cross-sections, default weights x est_method",
  "IF consistency: unbalanced panel, default weights x est_method",
  "IF consistency: no covariates (xformla=~1), all data types",
  "clustered standard errors",
  "faster mode enabled for panel data",
  "faster model enabled for repeated cross sectional data",
  "faster model enabled for unbalanced panel data and time-varying covariates",
  "faster_mode = TRUE matches baseline on filtered sim dataset when there are not subsequent cohort and time periods",
  "faster_mode time indexing matches baseline with repeated cross-sections",
  "faster_mode time indexing matches baseline with panel data and varying base period",
  "faster_mode time indexing with non-consecutive time periods",
  "faster_mode time indexing with universal base period"
)

mapped_scenario <- c(
  "basic-covariate-panel",
  "basic-no-covariate-panel-ipw",
  "two-period-aggregation",
  "no-covariates",
  "repeated-cross-section",
  "ipw-repeated-cross-section",
  "rc-dynamic-effects",
  "allow_unbalanced",
  "notyettreated-and-no-never",
  "aggregation-dynamic-group-calendar-balance",
  "unequally-spaced-groups",
  "first-period-treated-warning",
  "dynamic-min-max-window",
  "anticipation-dynamic",
  "level-and-cband",
  "malformed-data-validation",
  "varying-vs-universal-base",
  "small-treated-groups",
  "small-comparison-group",
  "r-custom-estimator-callback",
  "sampling-weights",
  "reserved-column-names",
  "reserved-column-names-fast",
  "time-varying-weights-fast",
  "fixweights-balanced-fast",
  "fixweights-time-invariant",
  "time-varying-weight-message",
  "time-invariant-weight-no-message",
  "notyettreated-time-varying-weights-fast",
  "rc-time-varying-weights-fast",
  "fixweights-validation-custom-callback",
  "fixweights-unbalanced-reference-period",
  "if-consistency-balanced",
  "if-consistency-notyettreated",
  "if-consistency-rc",
  "if-consistency-unbalanced",
  "if-consistency-no-covariates",
  "clustered-se",
  "fast-panel",
  "fast-rc",
  "fast-unbalanced-time-varying",
  "fast-filtered-sim",
  "fast-time-indexing-rc",
  "fast-time-indexing-panel",
  "fast-time-indexing-nonconsecutive",
  "fast-time-indexing-universal"
)
assertion_family <- c(
  "Stata dr/reg panel covariate ATT(g,t) cells are finite and near the simulated effect",
  "Stata dr/ipw panel no-covariate ATT(g,t) cells are finite and near the simulated effect",
  "Stata simple/group/dynamic/calendar aggregation is finite and near the simulated two-period effect",
  "Stata dr/reg no-covariate panel ATT(g,t) cells are finite and near the simulated effect",
  "Stata dr/reg repeated-cross-section ATT(g,t) cells are finite and near the simulated effect",
  "Stata dr/ipw repeated-cross-section ATT(g,t) cells are finite",
  "Stata repeated-cross-section dynamic aggregation tracks the exposure-varying DGP",
  "Stata unbalanced ivar() data routes through the owner-directed allow_unbalanced path",
  "Stata not-yet-treated controls and no-never fallback are finite and diagnostic messages are emitted",
  "Stata aggregation surfaces cover dynamic/group/calendar plus balance_e behavior",
  "Stata nonconsecutive time-period dynamic aggregation is finite",
  "Stata drops first-period-treated units with a diagnostic",
  "Stata dynamic min_e/max_e windowing respects requested exposure bounds",
  "Stata anticipation changes dynamic event-time effects as expected",
  "Stata cband/pointwise critical-value metadata is coherent",
  "Stata invalid id variable and malformed inputs fail clearly",
  "Stata varying and universal base-period dynamic aggregations are finite",
  "Stata small treated groups warn while other cells remain estimable",
  "Stata small comparison-group behavior is covered by warning/error and not-yet-treated gates",
  "R function-valued est_method callbacks have no public Stata command analogue",
  "Stata unit weights match the unweighted subset result",
  "Stata supports user columns literally named like API argument names",
  "Stata reserved-name behavior is covered together with fast/baseline equality gates",
  "Stata requested fast path matches standard path under time-varying weights",
  "Stata fix_weights modes produce finite balanced-panel results and fast equality",
  "Stata time-invariant weights produce identical ATT(g,t) values across fixed-weight modes",
  "Stata emits the frozen time-varying-weight diagnostic",
  "Stata emits no time-varying-weight diagnostic for time-invariant weights",
  "Stata requested fast path matches standard path for not-yet-treated time-varying weights",
  "Stata requested fast path matches standard path for repeated-cross-section time-varying weights",
  "Stata validates invalid fix_weights values and unsupported repeated-cross-section fixed modes; R custom callback subcases diverge",
  "Stata unbalanced fixed-weight reference-period behavior is finite under allow_unbalanced routing",
  "Stata fast/baseline equality preserves ATT(g,t) and influence-function summaries for balanced panels",
  "Stata fast/baseline equality preserves ATT(g,t) and influence-function summaries for not-yet-treated panels",
  "Stata fast/baseline equality preserves ATT(g,t) and influence-function summaries for repeated cross-sections",
  "Stata fast/baseline equality preserves ATT(g,t) and influence-function summaries for unbalanced panels",
  "Stata fast/baseline equality preserves ATT(g,t) and influence-function summaries without covariates",
  "Stata clustered analytical SE metadata and positive SEs are verified",
  "Stata requested fast path equals standard path for panel data",
  "Stata requested fast path equals standard path for repeated cross-sections",
  "Stata requested fast path equals standard path for unbalanced panels with time-varying covariates",
  "Stata requested fast path equals standard path on filtered simulation data",
  "Stata requested fast path equals standard path for repeated-cross-section time indexing",
  "Stata requested fast path equals standard path for panel time indexing",
  "Stata requested fast path equals standard path for nonconsecutive time periods",
  "Stata requested fast path equals standard path for universal-base time indexing"
)
coverage_status <- rep("mapped", length(source_tests))
divergence_id <- rep("", length(source_tests))
coverage_status[source_tests == "custom estimation method"] <- "approved-divergence"
divergence_id[source_tests == "custom estimation method"] <- "RT005-DIV001"
coverage_status[source_tests == "fix_weights validation"] <- "approved-divergence"
divergence_id[source_tests == "fix_weights validation"] <- "RT005-DIV002"

upstream_map <- data.frame(
  source_file = source_file,
  source_sha256 = source_sha,
  source_test = source_tests,
  mapped_scenario = mapped_scenario,
  assertion_family = assertion_family,
  coverage_status = coverage_status,
  divergence_id = divergence_id,
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = c("RT005-DIV001", "RT005-DIV002"),
  source_tests = c("custom estimation method", "fix_weights validation"),
  reason = c(
    "The R source accepts function-valued est_method callbacks such as DRDID::drdid_imp_panel. The frozen Stata command profile exposes built-in dr/reg/ipw methods and does not accept arbitrary user callback functions.",
    "Most fix_weights validation behavior is public and mapped, but the R source also validates custom estimator callback edge cases. Stata has no public custom-estimator callback surface."
  ),
  accepted_behavior = c(
    "Stata verifies built-in dr/reg/ipw, method validation, DRDID boundary behavior, and fast/baseline equality through F010, F033, RT005, RT012, and PY003-style gates.",
    "Stata verifies invalid fix_weights values, unsupported fixed modes for repeated cross-sections, balanced/unbalanced fixed-weight behavior, and fast/baseline equality for public command options."
  ),
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

scenarios <- data.frame(
  scenario = c(
    "core-attgt",
    "aggregation",
    "unbalanced-and-notyet",
    "weights-fixweights-if",
    "fast-mode",
    "validation-and-names"
  ),
  input = c("sim-data.csv", "dynamic.csv", "unbalanced.csv", "fixweights.csv", "sim-data.csv", "sim-data.csv"),
  expected_behavior = c(
    "Core dr/reg/ipw panel and repeated-cross-section ATT(g,t) results are finite and near the DGP target",
    "Simple/group/dynamic/calendar aggregation, event windows, balance_e, and nonconsecutive time behavior are finite",
    "Unbalanced ivar() data uses the R-compatible allow_unbalanced path; not-yet-treated/no-never behavior is finite and diagnostic",
    "Sampling weights, fix_weights modes, and influence-function summaries behave as frozen",
    "Requested fast path equals standard path for public supported inputs",
    "Malformed inputs, first-period treatment, cband metadata, clustered SEs, and reserved column names are covered"
  ),
  stringsAsFactors = FALSE
)
write.csv(scenarios, file.path(fixture, "expected/contract/scenarios.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "RT005",
  fixture_family = "r-att-gt",
  normative_source = "R did 2.5.1 tests/testthat/test-att_gt.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  source_sha256 = source_sha,
  decision_refs = c("D001", "D003", "D004", "D014"),
  tolerance_ids = c("TOL002", "EXACT"),
  inputs = input_meta,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt005/generate.R", path = "tools/parity/generators/rt005/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(inherits_py003_public_dgp_inputs = TRUE),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence"),
    list(path = "expected/contract/scenarios.csv", schema = "r-att-gt-public-scenarios")
  ),
  comparison_plan = list(
    list(actual = "RT005 source-map and divergence accounting", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test")),
    list(actual = "Stata public att_gt command gates", expected = "PY003-compatible public scenario gate", tolerance_id = "TOL002", key_columns = c("scenario"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "RT005 maps the R did core att_gt test file to Stata public-command gates for estimation, aggregation, allow_unbalanced handling, not-yet-treated controls, anticipation, base periods, weights, fix_weights, influence functions, clustered SEs, fast/baseline equality, validation, and reserved column names. R function-valued custom estimator callback cases are recorded as approved divergences."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
