#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt023/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt023")
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

source_sha <- "7aa2650b67772424643c84a71e20ba9cd1056afa414f939aebb9031956960fe8"
source_tests <- c(
  "indicator() vectorization matches the row-wise definition exactly",
  "test.mboot equals the explicit per-draw multiplier bootstrap (unclustered)",
  "test.mboot equals the explicit clustered multiplier bootstrap",
  "test.mboot multi-chunk tiling accumulates across chunks correctly"
)

upstream_map <- data.frame(
  source_file = "tests/testthat/test-pretest-vectorization.R",
  source_sha256 = source_sha,
  source_test = source_tests,
  mapped_scenario = "r-conditional-pretest-helper-only",
  assertion_family = c(
    "R indicator() helper has no public Stata command analogue",
    "R conditional-pretest test.mboot() helper has no public Stata command analogue",
    "R conditional-pretest clustered test.mboot() helper has no public Stata command analogue",
    "R skipped large transient-array helper stress has no public Stata command analogue"
  ),
  coverage_status = "approved-divergence",
  divergence_id = "RT023-DIV001",
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE)
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = "RT023-DIV001",
  source_tests = paste(source_tests, collapse = "; "),
  reason = "R test-pretest-vectorization.R directly validates conditional-pretest helper internals: indicator() and test.mboot() arrays. The Stata port has no public conditional_did_pretest or MP.TEST command/object surface.",
  accepted_behavior = "Stata bootstrap and clustered bootstrap behavior is verified through public csdid/csdid_stats inference rows; conditional-pretest helper internals remain outside the frozen Stata command surface.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE)
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "RT023",
  fixture_family = "r-pretest-vectorization",
  normative_source = "R did 2.5.1 tests/testthat/test-pretest-vectorization.R",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D004", "D014"),
  tolerance_ids = c("EXACT"),
  inputs = list(),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt023/generate.R", path = "tools/parity/generators/rt023/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "Approved R-only conditional-pretest helper divergence registry", expected = "expected/contract/approved-divergence.csv", tolerance_id = "EXACT", key_columns = c("divergence_id"))
  ),
  approved_divergence = list(
    status = "approved-divergence",
    path = "expected/contract/approved-divergence.csv",
    reason = "The R source directly exercises conditional-pretest helper internals that are not public Stata commands."
  ),
  scope_note = "RT023 records all four R did test-pretest-vectorization.R blocks as approved divergences because they directly test indicator() and test.mboot() helper internals for conditional pre-tests, including an R skipped large-array tiling path. The Stata port has no public conditional_did_pretest or MP.TEST surface; public bootstrap behavior remains verified through csdid/csdid_stats inference rows."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
