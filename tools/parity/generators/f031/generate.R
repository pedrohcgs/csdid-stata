#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f031/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f031")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/new-stata"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:40
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 14, 3, ifelse(d$id <= 28, 4, 0))
d$x1 <- 0.25 * d$time + 0.15 * sin(0.5 * d$id)
d$x2 <- 0.10 * d$time + 0.20 * cos(0.4 * d$id)
d$w <- 1 + 0.1 * (d$id %% 5) + 0.02 * d$time
d$y0 <- 0.9 + 0.40 * d$time + 0.25 * d$x1 - 0.10 * d$x2 +
  0.03 * sin(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.7 + 0.08 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

safety_contract <- list(
  matrix_id = "F031",
  fixture_family = "mutation-temp-safety",
  normative_source = "R did 2.5.1 output semantics mapped to Stata state hygiene",
  checks = list(
    data_values_and_order_unchanged = TRUE,
    variable_order_unchanged = TRUE,
    variable_labels_unchanged = TRUE,
    dataset_characteristics_unchanged = TRUE,
    user_matrix_unchanged = TRUE,
    package_global_macro_writes_absent = TRUE,
    frame_context_unchanged_when_frames_available = TRUE,
    auxiliary_frame_preserved_when_frames_available = TRUE,
    supported_postestimation_surface_does_not_mutate_data = TRUE,
    saverif_estimation_restores_active_data = TRUE,
    saved_rif_postestimation_does_not_mutate_active_data = TRUE,
    rejected_options_do_not_replace_prior_estimates = TRUE
  ),
  scope_note = "F031 state-hygiene gate covers supported estimation, saved-RIF estimation, saved-RIF postestimation, current-frame preservation when frames are available, auxiliary-frame preservation when frames are available, absence of package global macro writes in source files, csdid_estat display/tidy/glance, csdid_stats simple/group/calendar/dynamic, csdid_plot supported plot-data exports, invalid-option rejection, and preservation of data values, order, variable order, labels, characteristics, and user matrices."
)
writeLines(
  jsonlite::toJSON(safety_contract, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/mutation-safety.json")
)

manifest <- list(
  matrix_id = "F031",
  fixture_family = "mutation-temp-safety",
  normative_source = "R did 2.5.1 output semantics mapped to Stata state hygiene",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D009", "D016"),
  tolerance_ids = c("EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f031/generate.R", path = "tools/parity/generators/f031/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/new-stata/mutation-safety.json", schema = "mutation-safety")),
  comparison_plan = list(list(actual = "live Stata data/state", expected = "expected/new-stata/mutation-safety.json", tolerance_id = "EXACT", key_columns = c("check"))),
  approved_divergence = NULL,
  scope_note = safety_contract$scope_note
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
