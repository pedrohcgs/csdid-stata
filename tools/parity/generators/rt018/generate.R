#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt018/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt018")
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

source_file <- "tests/testthat/test-mboot-postprocess.R"
source_sha <- "184431a6dbf1f2dc56f2ac91aaf47592938c6b10026f21e41084e6ed500fdc6d"
source_tests <- c(
  "mboot on an all-degenerate influence function returns NA crit.val and all-NA se",
  "mboot pmax-fold critical value equals the old row-wise apply reference"
)

upstream_map <- data.frame(
  source_file = source_file,
  source_sha256 = source_sha,
  source_test = source_tests,
  mapped_scenario = "r-mboot-helper-postprocess-only",
  assertion_family = c(
    "R mboot() helper all-degenerate internal influence-function branch has no public Stata command analogue",
    "R mboot() helper row-wise critical-value post-processing equivalence has no public Stata command analogue"
  ),
  coverage_status = "approved-divergence",
  divergence_id = "RT018-DIV001",
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = "RT018-DIV001",
  source_tests = paste(source_tests, collapse = "; "),
  reason = "R test-mboot-postprocess.R directly calls the internal mboot() helper with synthetic influence-function matrices and DIDparams-like lists. The Stata port has no public mboot helper command or object API.",
  accepted_behavior = "Public Stata multiplier-bootstrap behavior is verified through csdid, csdid_stats, clustered bootstrap, simultaneous-band, and inference rows; exact R helper internals remain outside the frozen public command surface.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "RT018",
  fixture_family = "r-mboot-postprocess",
  normative_source = "R did 2.5.1 tests/testthat/test-mboot-postprocess.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  decision_refs = c("D004", "D014"),
  tolerance_ids = c("EXACT"),
  inputs = list(),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt018/generate.R", path = "tools/parity/generators/rt018/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "Approved R-only mboot helper divergence registry", expected = "expected/contract/approved-divergence.csv", tolerance_id = "EXACT", key_columns = c("divergence_id"))
  ),
  approved_divergence = list(
    status = "approved-divergence",
    path = "expected/contract/approved-divergence.csv",
    reason = "The R source exercises the internal mboot() helper directly, which is outside the frozen Stata public command profile."
  ),
  scope_note = "RT018 records both R did test-mboot-postprocess.R blocks as approved divergences because they directly test the internal mboot() helper on synthetic influence-function matrices and DIDparams-like lists. Public Stata multiplier-bootstrap behavior remains verified through csdid/csdid_stats bootstrap, simultaneous-band, cluster-bootstrap, and inference rows."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
