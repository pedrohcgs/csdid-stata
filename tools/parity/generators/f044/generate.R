#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))
# Record provenance without the maintainer's home directory: this fixture is
# published, and an absolute path both leaks the layout and means nothing on
# another machine.
abbrev_home <- function(p) sub(path.expand("~"), "~", p, fixed = TRUE)

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f044/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

# Resolution order, identical in every generator that needs the JEL checkout:
# $JEL_DID_REFERENCE, then the sibling GitHub/JEL-DiD checkout, then the /tmp
# path an earlier version of these scripts used as its only default. Two of
# these generators used to accept ONLY the /tmp path, so a perfectly good
# sibling checkout still stopped the run -- and because that stop happened
# midway through tests/run-smoke.sh, every gate after it silently never ran.
jel_candidates <- c(
  Sys.getenv("JEL_DID_REFERENCE", ""),
  file.path(path.expand("~"), "Documents/GitHub/JEL-DiD"),
  "/tmp/jel-did-reference"
)
jel_candidates <- jel_candidates[nzchar(jel_candidates)]
jel_found <- jel_candidates[dir.exists(jel_candidates)]
if (length(jel_found) == 0) {
  stop(
    paste0(
      "JEL reference checkout not found. Set JEL_DID_REFERENCE, or create one of:\n  ",
      paste(jel_candidates, collapse = "\n  ")
    ),
    call. = FALSE
  )
}
jel_root <- jel_found[1]
fixture <- file.path(root, "tests/fixtures/parity/f044")
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

rows <- data.frame(
  artifact_id = c(
    "JEL001", "JEL002",
    sprintf("JEL%03d", 3:9),
    sprintf("JEL%03d", 10:18)
  ),
  artifact_type = c(
    "r-master-script", "stata-master-script",
    rep("table", 7),
    rep("figure", 9)
  ),
  r_artifact = c(
    "scripts/R/00_master_did_jel.R",
    "",
    sprintf("tables/table%d_R.tex", 1:7),
    sprintf("figures/figure%d_R.pdf", 1:9)
  ),
  stata_artifact = c(
    "",
    "scripts/Stata/00_stata_master_did_jel.do",
    sprintf("tables/table%d_stata.tex", 1:7),
    sprintf("figures/figure%d_stata.pdf", 1:9)
  ),
  stata_test_file = c(
    "tests/stata/jel/test-r-master.do",
    "tests/stata/jel/test-stata-master.do",
    sprintf("tests/stata/jel/test-table%d.do", 1:7),
    sprintf("tests/stata/jel/test-figure%d.do", 1:9)
  ),
  smoke_gate = c(
    "none",
    "none",
    rep("none", 6),
    "F041-table7-analytical-smoke",
    "none",
    "F042-figure2-trends-smoke",
    "F042-figure3-dynamic-smoke",
    "F042-figure4-dynamic-smoke",
    "F043-figure5-trends-smoke",
    "F043-figure6-dynamic-smoke",
    "none",
    "none",
    "F043-figure9-dynamic-smoke"
  ),
  release_status = c(
    rep("full-reproduction-pass", 18)
  ),
  release_blocking = 1,
  stringsAsFactors = FALSE
)

rows$r_exists <- ifelse(rows$r_artifact == "", 1L, as.integer(file.exists(file.path(jel_root, rows$r_artifact))))
rows$stata_exists <- ifelse(rows$stata_artifact == "", 1L, as.integer(file.exists(file.path(jel_root, rows$stata_artifact))))
rows$reference_root <- abbrev_home(jel_root)
rows <- rows[, c(
  "artifact_id",
  "artifact_type",
  "r_artifact",
  "stata_artifact",
  "r_exists",
  "stata_exists",
  "stata_test_file",
  "smoke_gate",
  "release_status",
  "release_blocking",
  "reference_root"
)]

evidence <- rows[rows$release_blocking == 1, c(
  "artifact_id",
  "artifact_type",
  "r_artifact",
  "stata_artifact",
  "smoke_gate",
  "release_status"
)]
evidence$evidence_report <- "reports/jel-full-reproduction-result.md"
evidence$full_gate <- "CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh"
evidence$analysis_gate <- "CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh --analyze-existing"

write.csv(rows, file.path(fixture, "expected/contract/jel-artifact-inventory.csv"), row.names = FALSE, na = "")
write.csv(evidence, file.path(fixture, "expected/contract/full-reproduction-evidence.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F044",
  fixture_family = "jel-all-artifact-inventory",
  normative_source = "JEL-DiD all-artifact release gate D006",
  source_commit = "50f4f183783d2344f85bc4f39bcbcc1b7eba6466",
  decision_refs = c("D006", "D013", "D014", "D015"),
  tolerance_ids = c("TOL004", "TOL005", "TOL006"),
  inputs = list(list(path = "expected/contract/jel-artifact-inventory.csv", rows = nrow(rows), columns = ncol(rows))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f044/generate.R", path = "tools/parity/generators/f044/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/contract/jel-artifact-inventory.csv", schema = "jel-artifact-inventory"),
    list(path = "expected/contract/full-reproduction-evidence.csv", schema = "jel-full-reproduction-evidence")
  ),
  comparison_plan = list(
    list(actual = "JEL reference artifact availability", expected = "expected/contract/jel-artifact-inventory.csv", tolerance_id = "EXACT", key_columns = c("artifact_id")),
    list(actual = "Full JEL reproduction report", expected = "expected/contract/full-reproduction-evidence.csv", tolerance_id = "EXACT", key_columns = c("artifact_id"))
  ),
  full_reproduction_evidence = list(
    status = "pass",
    report = "reports/jel-full-reproduction-result.md",
    reason = "F044 is terminal because the opt-in full JEL R/Stata master reproduction gate completes both masters, passes against regenerated R did 2.5.1, and records historical R artifact drift separately for release-owner evidence disposition."
  ),
  scope_note = "F044 confirms all JEL001-JEL018 artifacts are mapped and present in the reference checkout, records the opt-in full reproduction evidence, and pairs with tests/fixtures/jel artifact audits. Rendered Stata PDF byte/pixel drift is governed by the semantic audit in reports/jel-full-reproduction-result.md."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
