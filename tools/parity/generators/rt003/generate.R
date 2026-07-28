#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt003/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt003")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

agg_to_df <- function(scenario, type, agg) {
  if (type == "simple") {
    data.frame(
      scenario = scenario,
      type = type,
      seq = 1L,
      egt = NA_real_,
      att = agg$overall.att,
      se = agg$overall.se,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se,
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      scenario = scenario,
      type = type,
      seq = seq_along(agg$att.egt),
      egt = agg$egt,
      att = agg$att.egt,
      se = agg$se.egt,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se,
      stringsAsFactors = FALSE
    )
  }
}

set.seed(5)
sp_single <- did::reset.sim(time.periods = 4)
d_single_all <- did::build_sim_dataset(sp_single)
g1 <- sort(unique(d_single_all$G[d_single_all$G > 0]))[1]
d_single <- d_single_all[d_single_all$G == 0 | d_single_all$G == g1, ]
write.csv(d_single, file.path(fixture, "inputs/single-treated.csv"), row.names = FALSE, na = "")

mp_single <- suppressWarnings(suppressMessages(att_gt(
  yname = "Y",
  xformla = ~X,
  data = d_single,
  tname = "period",
  idname = "id",
  gname = "G",
  bstrap = FALSE
)))
single_aggs <- do.call(rbind, lapply(c("simple", "group", "dynamic", "calendar"), function(type) {
  agg_to_df("single_treated_all_types", type, suppressWarnings(suppressMessages(aggte(mp_single, type = type, bstrap = FALSE, cband = FALSE))))
}))

set.seed(6)
sp_window <- did::reset.sim(time.periods = 5)
d_window <- did::build_sim_dataset(sp_window)
write.csv(d_window, file.path(fixture, "inputs/dynamic-window.csv"), row.names = FALSE, na = "")

mp_window <- suppressWarnings(suppressMessages(att_gt(
  yname = "Y",
  xformla = ~X,
  data = d_window,
  tname = "period",
  idname = "id",
  gname = "G",
  bstrap = FALSE
)))
dynamic_window <- suppressWarnings(suppressMessages(aggte(
  mp_window,
  type = "dynamic",
  min_e = -1,
  max_e = 1,
  bstrap = FALSE,
  cband = FALSE
)))
stopifnot(all(dynamic_window$egt >= -1 & dynamic_window$egt <= 1))
stopifnot(length(dynamic_window$att.egt) == length(dynamic_window$egt))

aggs <- rbind(single_aggs, agg_to_df("dynamic_min_max_window", "dynamic", dynamic_window))
write.csv(aggs, file.path(fixture, "expected/r/aggte.csv"), row.names = FALSE, na = "")

source_file <- "tests/testthat/test-aggte-edge-coverage.R"
source_sha <- "774a712a6c3c035c4330658a3078b57b6e0031676c034331a6852cb197cb8065"
upstream_map <- data.frame(
  source_file = source_file,
  source_sha256 = source_sha,
  source_test = c(
    "aggte handles a single treated group for every aggregation type",
    "aggte dynamic with min_e / max_e windows returns a consistent event-time set"
  ),
  mapped_scenario = c(
    "single_treated_all_types",
    "dynamic_min_max_window"
  ),
  assertion_family = c(
    "simple/group/dynamic/calendar aggregations return finite overall ATT and SE for one treated group plus never-treated controls",
    "dynamic aggregation with min_e=-1 and max_e=1 returns only event times in the closed window and aligned ATT/event-time vectors"
  ),
  coverage_status = "mapped",
  divergence_id = "",
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

manifest <- list(
  matrix_id = "RT003",
  fixture_family = "r-aggte-edge-coverage",
  normative_source = "R did 2.5.1 tests/testthat/test-aggte-edge-coverage.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  source_sha256 = source_sha,
  decision_refs = c("D003", "D009"),
  tolerance_ids = c("TOL001", "EXACT"),
  inputs = list(
    list(path = "inputs/single-treated.csv", rows = nrow(d_single), columns = ncol(d_single)),
    list(path = "inputs/dynamic-window.csv", rows = nrow(d_window), columns = ncol(d_window))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt003/generate.R", path = "tools/parity/generators/rt003/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(kind = "R default", seeds = c(single_treated = 5, dynamic_window = 6)),
  expected_outputs = list(
    list(path = "expected/r/aggte.csv", schema = "aggte-edge-coverage"),
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map")
  ),
  comparison_plan = list(
    list(actual = "Stata csdid_stats aggregation matrices", expected = "expected/r/aggte.csv", tolerance_id = "TOL001", key_columns = c("scenario", "type", "seq")),
    list(actual = "Mapped source tests", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test"))
  ),
  approved_divergence = NULL,
  scope_note = "RT003 maps both public aggte edge-coverage tests from R did: single-treated-group aggregation for simple/group/dynamic/calendar and dynamic min_e/max_e event-window consistency."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
