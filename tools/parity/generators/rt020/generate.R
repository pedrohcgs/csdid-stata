#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt020/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt020")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

set.seed(20260619)
sp <- did::reset.sim(n = 500)
panel_data <- did::build_sim_dataset(sp)
rc_data <- did::build_sim_dataset(sp, panel = FALSE)
names(panel_data) <- tolower(names(panel_data))
names(rc_data) <- tolower(names(rc_data))
write.csv(panel_data, file.path(fixture, "inputs/panel.csv"), row.names = FALSE, na = "")
write.csv(rc_data, file.path(fixture, "inputs/repeated-cross-section.csv"), row.names = FALSE, na = "")

source_file <- "tests/testthat/test-mutation-safety.R"
source_sha <- "f31e6211fbba13b3e8c49d1e9fa10a8c350c36d0258fc253e7798b9c6c41f5fb"
rows <- expand.grid(
  case_name = c("panel_df", "panel_dt", "rc_df", "rc_dt"),
  faster_mode = c(FALSE, TRUE),
  stringsAsFactors = FALSE
)
rows$source_file <- source_file
rows$source_sha256 <- source_sha
rows$source_test <- "att_gt does not mutate caller data in either implementation"
rows$mapped_scenario <- paste0(
  ifelse(grepl("^panel", rows$case_name), "panel", "repeated_cross_section"),
  ifelse(rows$faster_mode, "_fast", "_regular")
)
rows$assertion_family <- ifelse(
  grepl("_dt$", rows$case_name),
  "R data.table object-class mutation check has no separate Stata object-class analogue; active Stata dataset mutation safety is verified by mode",
  "active dataset names, values, and row order are unchanged after estimation"
)
rows$coverage_status <- ifelse(grepl("_dt$", rows$case_name), "approved-divergence", "mapped")
rows$divergence_id <- ifelse(grepl("_dt$", rows$case_name), "RT020-DIV001", "")
upstream_map <- rows[, c("source_file", "source_sha256", "source_test", "mapped_scenario", "assertion_family", "coverage_status", "divergence_id")]
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = "RT020-DIV001",
  source_tests = "panel_dt/rc_dt cases in test-mutation-safety.R",
  reason = "R distinguishes data.frame and data.table object mutation. Stata exposes one active dataset/frame object rather than separate data.frame/data.table classes.",
  accepted_behavior = "Stata verifies that active dataset variable names, values, and row order are unchanged for panel and repeated-cross-section inputs with and without requested fast mode.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

scenarios <- data.frame(
  scenario = c("panel_regular", "panel_fast", "repeated_cross_section_regular", "repeated_cross_section_fast"),
  input = c("panel.csv", "panel.csv", "repeated-cross-section.csv", "repeated-cross-section.csv"),
  fast = c(FALSE, TRUE, FALSE, TRUE),
  panel_mode = c("panel", "panel", "allow_unbalanced", "allow_unbalanced"),
  stringsAsFactors = FALSE
)
write.csv(scenarios, file.path(fixture, "expected/contract/scenarios.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "RT020",
  fixture_family = "r-mutation-safety",
  normative_source = "R did 2.5.1 tests/testthat/test-mutation-safety.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  decision_refs = c("D004", "D016"),
  tolerance_ids = c("EXACT"),
  inputs = list(
    list(path = "inputs/panel.csv", rows = nrow(panel_data), columns = ncol(panel_data)),
    list(path = "inputs/repeated-cross-section.csv", rows = nrow(rc_data), columns = ncol(rc_data))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt020/generate.R", path = "tools/parity/generators/rt020/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 20260619),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence"),
    list(path = "expected/contract/scenarios.csv", schema = "mutation-safety-scenarios")
  ),
  comparison_plan = list(
    list(actual = "Stata active dataset state after csdid", expected = "expected/contract/scenarios.csv", tolerance_id = "EXACT", key_columns = c("scenario")),
    list(actual = "Mapped source tests", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test", "mapped_scenario"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "RT020 maps R test-mutation-safety.R to Stata active dataset mutation safety. Stata verifies variable names, values, and row order are unchanged for panel and repeated-cross-section inputs with and without requested fast mode. The R data.frame/data.table object-class split is recorded as an approved divergence because Stata has one active dataset/frame object model."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
