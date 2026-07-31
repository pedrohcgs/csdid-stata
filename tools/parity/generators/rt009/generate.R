#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt009/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt009")
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

source_file <- "tests/testthat/test-conditional-did-pretest.R"
source_sha <- "c09ea5dce40d692776f14ac6b53de39100f9d25f38bd5db87ea182daafdc83b7"
source_tests <- c(
  "conditional did pre-test",
  "pretest setup-bundle/y-override path is bit-identical to the legacy data-copy loop",
  "conditional pre-test CvM is on the bootstrap scale (R>=4.0 orientation regression)"
)

upstream_map <- data.frame(
  source_file = source_file,
  source_sha256 = source_sha,
  source_test = source_tests,
  mapped_scenario = "r-conditional-pretest-public-helper-only",
  assertion_family = c(
    "R conditional_did_pretest() CvM/CvMcval helper output has no public Stata command analogue",
    "R conditional_did_pretest() precompute/legacy exact helper-path equality has no public Stata command analogue",
    "R conditional_did_pretest() bootstrap-scale orientation regression has no public Stata command analogue"
  ),
  coverage_status = "approved-divergence",
  divergence_id = "RT009-DIV001",
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = "RT009-DIV001",
  source_tests = paste(source_tests, collapse = "; "),
  reason = "R test-conditional-did-pretest.R directly validates the exported conditional_did_pretest()/MP.TEST helper surface. The frozen Stata command profile does not expose a standalone conditional pretest command or MP.TEST object surface.",
  accepted_behavior = "Stata pre-period diagnostics and bootstrap behavior remain verified through public csdid, csdid_stats, csdid_estat, and inference rows; no standalone conditional_did_pretest analogue is added for this port.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "RT009",
  fixture_family = "r-conditional-did-pretest",
  normative_source = "R did 2.5.1 tests/testthat/test-conditional-did-pretest.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  decision_refs = c("D004", "D014"),
  tolerance_ids = c("EXACT"),
  inputs = list(),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt009/generate.R", path = "tools/parity/generators/rt009/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "Approved R-only conditional pretest helper divergence registry", expected = "expected/contract/approved-divergence.csv", tolerance_id = "EXACT", key_columns = c("divergence_id"))
  ),
  approved_divergence = list(
    status = "approved-divergence",
    path = "expected/contract/approved-divergence.csv",
    reason = "The R source exercises a standalone conditional_did_pretest()/MP.TEST helper surface that is outside the frozen Stata public command profile."
  ),
  scope_note = "RT009 records all three R did test-conditional-did-pretest.R blocks as approved divergences because they directly test the standalone conditional_did_pretest()/MP.TEST helper surface and its internal precompute/bootstrap-scale paths. The Stata port has no public conditional_did_pretest or MP.TEST surface; public bootstrap and pre-period behavior remain verified through csdid/csdid_stats/csdid_estat inference rows."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
