#!/usr/bin/env Rscript

# Record provenance without the maintainer's home directory: these fixtures are
# published, and an absolute path both leaks the layout and means nothing on
# another machine.
abbrev_home <- function(p) sub(path.expand("~"), "~", p, fixed = TRUE)

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f040/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

python_test_rel <- "csdid/test_csdid/test_jel_replication.py"
r_test_rel <- "tests/testthat/test-jel_replication.R"
python_ref <- Sys.getenv("CSDID_PYTHON_REF", file.path(path.expand("~"), "Documents/GitHub/csdid_python"))
r_ref <- Sys.getenv("R_DID_REFERENCE", file.path(path.expand("~"), "Documents/GitHub/did"))
python_file <- file.path(python_ref, python_test_rel)
r_file <- file.path(r_ref, r_test_rel)

source_audit <- data.frame(
  source = c("python-csdid", "r-did"),
  frozen_path = c(python_test_rel, r_test_rel),
  frozen_hash = c(
    "0eba34481cb0fdacf92b81040430cc353b9d2ce72e503af8676f4677a27baa32",
    ""
  ),
  observed_checkout = abbrev_home(c(python_ref, r_ref)),
  observed_exists = c(as.integer(file.exists(python_file)), as.integer(file.exists(r_file))),
  status = c(
    ifelse(file.exists(python_file), "available", "absent-in-available-checkout"),
    ifelse(file.exists(r_file), "available", "absent-in-available-checkout")
  ),
  stringsAsFactors = FALSE
)

coverage <- data.frame(
  scenario_id = c(
    "jel_table7_point_estimates",
    "jel_2xt_attgt_no_covariates",
    "jel_2xt_covariate_methods",
    "jel_gxt_no_covariates_notyet",
    "jel_gxt_dr_covariates_notyet",
    "jel_faster_mode_table7_dr_weighted"
  ),
  r_test_block = c(
    "JEL Table 7: 2x2 CS-DiD point estimates match",
    "JEL 2xT: event study ATT(g,t) point estimates match",
    "JEL 2xT: event study with covariates matches across methods",
    "JEL GxT: staggered event study without covariates matches",
    "JEL GxT: staggered event study with DR covariates matches",
    "JEL: faster_mode matches regular mode"
  ),
  python_test_path = python_test_rel,
  stata_gate = c("F041", "F042", "F042", "F043", "F043", "F040"),
  stata_test_file = c(
    "tests/stata/test-f041.do",
    "tests/stata/test-f042.do",
    "tests/stata/test-f042.do",
    "tests/stata/test-f043.do",
    "tests/stata/test-f043.do",
    "tests/stata/test-f040.do"
  ),
  fixture_manifest = c(
    "tests/fixtures/parity/f041/metadata/manifest.json",
    "tests/fixtures/parity/f042/metadata/manifest.json",
    "tests/fixtures/parity/f042/metadata/manifest.json",
    "tests/fixtures/parity/f043/metadata/manifest.json",
    "tests/fixtures/parity/f043/metadata/manifest.json",
    "tests/fixtures/parity/f040/metadata/manifest.json"
  ),
  tolerance_id = c("TOL004", "TOL004", "TOL004", "TOL004", "TOL004", "TOL002"),
  coverage_status = "covered",
  coverage_note = c(
    "F041 verifies actual JEL Table 7 analytical simple aggregation against R did 2.5.1 for reg/ipw/dr, weighted and unweighted, and records committed display values.",
    "F042 verifies raw ATT(g,t), dynamic aggregation, and post-window dynamic summaries for the actual JEL 2xT no-covariate weighted regression event-study sample.",
    "F042 verifies dynamic aggregation, post-window summaries, base-period behavior, and finite covariate-method outputs for reg/ipw/dr on the actual JEL 2xT sample.",
    "F043 verifies actual JEL GxT timing-group trend data, raw ATT(g,t), dynamic aggregation, and post-window summaries for weighted not-yet-treated no-covariate DR.",
    "F043 verifies actual JEL GxT raw ATT(g,t), dynamic aggregation, and post-window summaries for weighted not-yet-treated DR with covariates.",
    "F040 verifies the JEL Table 7 weighted DR covariate design with fast requested; Stata reports fast_used=1, uses the panel-mode-specific fast compute_path, and matches explicit nofast for ATT(g,t) and simple aggregation matrices."
  ),
  stringsAsFactors = FALSE
)

write_fixture <- function(id, fixture_name, family, source_test_path, source_kind, approved_divergence) {
  fixture <- file.path(root, "tests/fixtures/parity", fixture_name)
  dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

  fixture_coverage <- coverage
  fixture_coverage$matrix_id <- id
  fixture_coverage$source_test_path <- source_test_path
  fixture_coverage$source_kind <- source_kind
  fixture_coverage <- fixture_coverage[, c(
    "matrix_id",
    "source_kind",
    "source_test_path",
    "scenario_id",
    "r_test_block",
    "python_test_path",
    "stata_gate",
    "stata_test_file",
    "fixture_manifest",
    "tolerance_id",
    "coverage_status",
    "coverage_note"
  )]

  write.csv(fixture_coverage, file.path(fixture, "expected/contract/scenario-coverage.csv"), row.names = FALSE, na = "")
  write.csv(source_audit, file.path(fixture, "expected/contract/source-audit.csv"), row.names = FALSE, na = "")

  manifest <- list(
    matrix_id = id,
    fixture_family = family,
    normative_source = "R did 2.5.1 JEL replication tests and Python csdid JEL inheritance map, with JEL-DiD empirical smoke gates as executable evidence",
    source_commit = list(
      r_did = "9aba07d054a798558ac9b551887f5cb592d8db10",
      python_csdid = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
      jel_did = "50f4f183783d2344f85bc4f39bcbcc1b7eba6466"
    ),
    decision_refs = c("D001", "D004", "D006", "D013", "D014", "D015"),
    tolerance_ids = c("TOL002", "TOL004", "TOL005"),
    inputs = list(
      list(path = "expected/contract/scenario-coverage.csv", rows = nrow(fixture_coverage), columns = ncol(fixture_coverage)),
      list(path = "expected/contract/source-audit.csv", rows = nrow(source_audit), columns = ncol(source_audit))
    ),
    generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f040/generate.R", path = "tools/parity/generators/f040/generate.R")),
    runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
    rng = NULL,
    expected_outputs = list(
      list(path = "expected/contract/scenario-coverage.csv", schema = "test-inheritance-coverage"),
      list(path = "expected/contract/source-audit.csv", schema = "reference-source-audit")
    ),
    comparison_plan = list(
      list(actual = "Stata-confirmed scenario coverage", expected = "expected/contract/scenario-coverage.csv", tolerance_id = "EXACT", key_columns = c("scenario_id")),
      list(actual = "Stata JEL fast-request optimized equality", expected = "live nofast matrices", tolerance_id = "TOL002", key_columns = c("group", "time"))
    ),
    approved_divergence = approved_divergence,
    scope_note = paste(
      "This fixture maps the R/Python JEL inheritance surface to executable Stata smoke gates.",
      "It does not replace F044/JEL001-JEL018 all-artifact replication.",
      "The local Python checkout observed by the generator lacks the frozen PY014 source path, so Python-specific JEL inheritance remains an approved source-availability divergence until that path is available."
    )
  )

  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
    file.path(fixture, "metadata/manifest.json")
  )
}

python_divergence <- list(
  status = "approved-divergence",
  reason = "The frozen Python PY014 source path csdid/test_csdid/test_jel_replication.py is absent in the available local Python checkout. Equivalent JEL scenarios are inherited through the R did JEL test and executable F041-F043/F040 gates; this does not certify unavailable Python-specific source contents."
)

write_fixture(
  "F040",
  "f040",
  "python-jel-inheritance",
  python_test_rel,
  "python-test-map",
  python_divergence
)
write_fixture(
  "RT016",
  "rt016",
  "r-jel-test-inheritance",
  r_test_rel,
  "r-test-map",
  NULL
)
write_fixture(
  "PY014",
  "py014",
  "python-jel-test-inheritance",
  python_test_rel,
  "python-test-map",
  python_divergence
)
