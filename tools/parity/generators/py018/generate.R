#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/py018/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/py018")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

set.seed(47)
zw <- expand.grid(id = 1:90, period = 1:4)
zw$G <- ifelse(zw$id <= 30, 0, ifelse(zw$id <= 60, 2, 3))
unit_x <- rnorm(90)
zw$X <- unit_x[zw$id]
zw$Y <- 0.5 * zw$X + 0.2 * zw$period + (zw$G > 0 & zw$period >= zw$G) +
  rnorm(nrow(zw), 0, 0.2)
zw$w <- ifelse(zw$G == 3, 0, 1)
write.csv(zw, file.path(fixture, "inputs/zero-weight-failure.csv"), row.names = FALSE, na = "")

set.seed(42)
n_units <- 50
n_periods <- 4
normal <- data.frame(
  id = rep(seq_len(n_units), each = n_periods),
  year = rep(2003:(2003 + n_periods - 1), n_units)
)
normal$group <- rep(c(rep(2004, 20), rep(2006, 15), rep(0, 15)), each = n_periods)
normal$y <- rnorm(nrow(normal)) + ifelse(normal$group > 0 & normal$year >= normal$group, 1, 0)
write.csv(normal, file.path(fixture, "inputs/normal.csv"), row.names = FALSE, na = "")

set.seed(42)
n_periods_tiny <- 4
tiny_groups <- c(2005, rep(2006, 30), rep(0, 30))
tiny <- data.frame(
  id = rep(seq_along(tiny_groups), each = n_periods_tiny),
  year = rep(2003:(2003 + n_periods_tiny - 1), length(tiny_groups))
)
tiny$group <- rep(tiny_groups, each = n_periods_tiny)
tiny$y <- rnorm(nrow(tiny)) + ifelse(tiny$group > 0 & tiny$year >= tiny$group, 1, 0)
write.csv(tiny, file.path(fixture, "inputs/tiny-group.csv"), row.names = FALSE, na = "")

set.seed(42)
collinear_groups <- c(rep(2005, 20), rep(2006, 20), rep(0, 20))
collinear <- data.frame(
  id = rep(seq_along(collinear_groups), each = 4),
  year = rep(2003:2006, length(collinear_groups))
)
collinear$group <- rep(collinear_groups, each = 4)
collinear$y <- rnorm(nrow(collinear))
collinear$x1 <- rnorm(nrow(collinear))
collinear$x2 <- rnorm(nrow(collinear))
collinear$x2[collinear$group == 2005] <- collinear$x1[collinear$group == 2005]
write.csv(collinear, file.path(fixture, "inputs/collinear-covariates.csv"), row.names = FALSE, na = "")

set.seed(20260610)
overlap <- expand.grid(id = 1:200, period = 1:3)
gvals <- c(0, 2, 3)
overlap$G <- gvals[(overlap$id - 1) %% 3 + 1]
overlap$Xsep <- 1 * (overlap$G > 0)
overlap$Y <- 0.1 * overlap$period + (overlap$G > 0 & overlap$period >= overlap$G) +
  rnorm(nrow(overlap), 0, 0.5)
write.csv(overlap, file.path(fixture, "inputs/overlap-failure.csv"), row.names = FALSE, na = "")

set.seed(123)
singular_groups <- c(rep(2, 20), rep(3, 20), rep(4, 20), 0)
singular <- data.frame(
  id = rep(seq_along(singular_groups), each = 4),
  period = rep(1:4, length(singular_groups))
)
singular$G <- rep(singular_groups, each = 4)
singular_unit_x <- rnorm(length(singular_groups))
singular$X <- singular_unit_x[singular$id]
singular$Y <- 0.2 * singular$period + 0.4 * singular$X +
  (singular$G > 0 & singular$period >= singular$G) + rnorm(nrow(singular), 0, 0.1)
write.csv(singular, file.path(fixture, "inputs/singular-control.csv"), row.names = FALSE, na = "")

set.seed(09142024)
small_comparison <- did::build_sim_dataset(did::reset.sim())
small_comparison_keep_id <- unique(subset(small_comparison, G == 0)$id)[1]
small_comparison <- subset(small_comparison, (G != 0) | (id == small_comparison_keep_id))
write.csv(small_comparison, file.path(fixture, "inputs/small-comparison-upstream.csv"), row.names = FALSE, na = "")

att_to_df <- function(scenario, out) {
  data.frame(
    scenario = scenario,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    att_missing = as.integer(is.na(out$att)),
    se_missing = as.integer(is.na(out$se)),
    stringsAsFactors = FALSE
  )
}

capture_warnings <- function(expr) {
  warnings <- character()
  value <- withCallingHandlers(
    expr,
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warnings = warnings)
}

zw_out <- suppressWarnings(suppressMessages(att_gt(
  yname = "Y",
  tname = "period",
  idname = "id",
  gname = "G",
  xformla = ~ X,
  data = zw,
  weightsname = "w",
  est_method = "dr",
  faster_mode = FALSE,
  bstrap = FALSE,
  cband = FALSE
)))

normal_out <- suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  tname = "year",
  idname = "id",
  gname = "group",
  data = normal,
  est_method = "dr",
  bstrap = FALSE,
  cband = FALSE
)))

tiny_out <- suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  tname = "year",
  idname = "id",
  gname = "group",
  data = tiny,
  est_method = "dr",
  bstrap = FALSE,
  cband = FALSE
)))

collinear_capture <- capture_warnings(suppressMessages(att_gt(
  yname = "y",
  tname = "year",
  idname = "id",
  gname = "group",
  xformla = ~ x1 + x2,
  data = collinear,
  est_method = "dr",
  bstrap = FALSE,
  cband = FALSE
)))
collinear_out <- collinear_capture$value
collinear_warning_count <- length(collinear_capture$warnings)

overlap_capture <- capture_warnings(suppressMessages(att_gt(
  yname = "Y",
  tname = "period",
  idname = "id",
  gname = "G",
  xformla = ~ Xsep,
  data = overlap,
  est_method = "dr",
  faster_mode = FALSE,
  bstrap = FALSE,
  cband = FALSE
)))
overlap_out <- overlap_capture$value
overlap_warning_count <- sum(grepl("overlap condition violated for group", overlap_capture$warnings))
wald_missing_warning_count <- sum(grepl("missing or zero variance", overlap_capture$warnings))

singular_reg_capture <- capture_warnings(suppressMessages(att_gt(
  yname = "Y",
  tname = "period",
  idname = "id",
  gname = "G",
  xformla = ~ X,
  data = singular,
  est_method = "reg",
  control_group = "notyettreated",
  faster_mode = FALSE,
  bstrap = FALSE,
  cband = FALSE
)))
singular_reg_out <- singular_reg_capture$value
singular_reg_warning_count <- sum(grepl("singular or numerically ill-conditioned", singular_reg_capture$warnings))

singular_dr_capture <- capture_warnings(suppressMessages(att_gt(
  yname = "Y",
  tname = "period",
  idname = "id",
  gname = "G",
  xformla = ~ X,
  data = singular,
  est_method = "dr",
  control_group = "notyettreated",
  faster_mode = FALSE,
  bstrap = FALSE,
  cband = FALSE
)))
singular_dr_out <- singular_dr_capture$value
singular_dr_warning_count <- sum(grepl("singular or numerically ill-conditioned", singular_dr_capture$warnings))

run_small_comparison <- function(method) {
  capture_warnings(suppressMessages(att_gt(
    yname = "Y",
    tname = "period",
    idname = "id",
    gname = "G",
    xformla = ~ X,
    data = small_comparison,
    est_method = method,
    control_group = "notyettreated",
    faster_mode = FALSE,
    bstrap = FALSE,
    cband = FALSE
  )))
}

small_dr_capture <- run_small_comparison("dr")
small_dr_out <- small_dr_capture$value
small_reg_capture <- run_small_comparison("reg")
small_reg_out <- small_reg_capture$value
small_ipw_capture <- run_small_comparison("ipw")
small_ipw_out <- small_ipw_capture$value

failure_pattern <- rbind(
  att_to_df("zero_weight_group_failure", zw_out),
  att_to_df("normal_data_unaffected", normal_out),
  att_to_df("tiny_group_no_crash", tiny_out),
  att_to_df("collinear_covariates_no_crash", collinear_out),
  att_to_df("overlap_failure", overlap_out),
  att_to_df("singular_notyet_reg", singular_reg_out),
  att_to_df("singular_notyet_dr", singular_dr_out),
  att_to_df("small_comparison_notyet_dr", small_dr_out),
  att_to_df("small_comparison_notyet_reg", small_reg_out),
  att_to_df("small_comparison_notyet_ipw", small_ipw_out)
)
write.csv(failure_pattern, file.path(fixture, "expected/r/failure-pattern.csv"), row.names = FALSE, na = "")

events <- data.frame(
  scenario = c(
    "overlap_failure", "overlap_failure", "singular_notyet_reg",
    "singular_notyet_dr", "collinear_covariates_no_crash",
    "small_comparison_notyet_dr", "small_comparison_notyet_reg",
    "small_comparison_notyet_ipw", "small_comparison_notyet_dr",
    "small_comparison_notyet_reg", "small_comparison_notyet_ipw"
  ),
  event_key = c(
    "overlap_condition_violated", "wald_missing_zero_variance",
    "singular_control_matrix", "singular_control_matrix", "any_warning",
    "small_group_warning", "small_group_warning", "small_group_warning",
    "overlap_condition_violated", "singular_control_matrix",
    "overlap_condition_violated"
  ),
  event_type = rep("warning", 11),
  expected_count = c(
    overlap_warning_count,
    wald_missing_warning_count,
    singular_reg_warning_count,
    singular_dr_warning_count,
    collinear_warning_count,
    sum(grepl("very few observations", small_dr_capture$warnings)),
    sum(grepl("very few observations", small_reg_capture$warnings)),
    sum(grepl("very few observations", small_ipw_capture$warnings)),
    sum(grepl("overlap condition violated for group", small_dr_capture$warnings)),
    sum(grepl("singular or numerically ill-conditioned", small_reg_capture$warnings)),
    sum(grepl("overlap condition violated for group", small_ipw_capture$warnings))
  ),
  message_normalized = c(
    "overlap condition violated for group",
    "missing or zero variance",
    "singular or numerically ill-conditioned",
    "singular or numerically ill-conditioned",
    "",
    "very few observations",
    "very few observations",
    "very few observations",
    "overlap condition violated for group",
    "singular or numerically ill-conditioned",
    "overlap condition violated for group"
  ),
  stringsAsFactors = FALSE
)
write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

upstream_map <- data.frame(
  source_file = "csdid/test_csdid/test_percell_failure.py",
  source_sha256 = "e15c0c8cde82b8d035fa285f344be7735b775e15d5b0b9fc4dd2159c5f05fe8e",
  source_test = c(
    "test_collinear_covariates_no_crash",
    "test_tiny_group_warns_not_crashes",
    "test_failed_cells_are_nan",
    "test_normal_data_unaffected"
  ),
  mapped_scenario = c(
    "collinear_covariates_no_crash",
    "tiny_group_no_crash",
    "tiny_group_no_crash",
    "normal_data_unaffected"
  ),
  assertion_family = c(
    "no crash; no warning; finite ATT/SE parity",
    "no crash; small-group warning; at least one viable group has finite ATT/SE",
    "viable group 2006 has no missing ATT/SE values",
    "normal panel has no missing ATT/SE values"
  ),
  coverage_status = "mapped",
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/upstream-test-map.json"))

manifest <- list(
  matrix_id = "PY018",
  fixture_family = "python-per-cell-failure",
  normative_source = "Python csdid test_percell_failure.py subordinate to R did 2.5.1 robustness guards",
  source_commit = "e15c0c8cde82b8d035fa285f344be7735b775e15d5b0b9fc4dd2159c5f05fe8e",
  decision_refs = c("D004"),
  tolerance_ids = c("EXACT", "TOL002"),
  inputs = list(
    list(path = "inputs/zero-weight-failure.csv", rows = nrow(zw), columns = ncol(zw)),
    list(path = "inputs/normal.csv", rows = nrow(normal), columns = ncol(normal)),
    list(path = "inputs/tiny-group.csv", rows = nrow(tiny), columns = ncol(tiny)),
    list(path = "inputs/collinear-covariates.csv", rows = nrow(collinear), columns = ncol(collinear)),
    list(path = "inputs/overlap-failure.csv", rows = nrow(overlap), columns = ncol(overlap)),
    list(path = "inputs/singular-control.csv", rows = nrow(singular), columns = ncol(singular)),
    list(path = "inputs/small-comparison-upstream.csv", rows = nrow(small_comparison), columns = ncol(small_comparison))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/py018/generate.R", path = "tools/parity/generators/py018/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed_zero_weight_failure = 47, seed_normal = 42, seed_tiny_group = 42, seed_collinear_covariates = 42, seed_overlap_failure = 20260610, seed_singular_control = 123, seed_small_comparison_upstream = "09142024"),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/r/failure-pattern.csv", schema = "attgt-missing-pattern"),
    list(path = "expected/r/events.csv", schema = "error-warning-events-csv"),
    list(path = "expected/r/events.json", schema = "error-warning-events")
  ),
  comparison_plan = list(
    list(actual = "Mapped Python source tests", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test")),
    list(actual = "Stata ATT(g,t) missing-cell pattern and finite values", expected = "expected/r/failure-pattern.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "Stata overlap warning count", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("scenario", "event_key"))
  ),
  approved_divergence = NULL,
  scope_note = "PY018 maps all four tests in DrSquare/csdid csdid/test_csdid/test_percell_failure.py at sha256 e15c0c8cde82b8d035fa285f344be7735b775e15d5b0b9fc4dd2159c5f05fe8e, anchored to R did 2.5.1 robustness-guard behavior. The gate covers no-crash collinear covariates, tiny-group no-crash and viable-group finite cells, failed-cell missingness checks, and normal-data no-regression checks. It also adds stricter R-backed zero-weight, overlap, singular-control, and small-comparison-group cases with exact missing-pattern and warning-count checks plus TOL002 finite ATT/SE parity."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
