#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt014/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt014")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

set.seed(20260401)
sp <- did::reset.sim()
d <- did::build_sim_dataset(sp)
names(d) <- tolower(names(d))
write.csv(d, file.path(fixture, "inputs/sim-glance.csv"), row.names = FALSE, na = "")

mp_slow <- suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  xformla = ~ x,
  data = d,
  tname = "period",
  idname = "id",
  gname = "g",
  est_method = "dr",
  bstrap = FALSE,
  faster_mode = FALSE
)))

mp_fast <- suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  xformla = ~ x,
  data = d,
  tname = "period",
  idname = "id",
  gname = "g",
  est_method = "dr",
  bstrap = FALSE,
  faster_mode = TRUE
)))

agg_types <- c("simple", "dynamic", "group", "calendar")
agg_slow <- lapply(setNames(agg_types, agg_types), function(tp) {
  suppressWarnings(aggte(mp_slow, type = tp, bstrap = FALSE, cband = FALSE))
})
agg_fast <- lapply(setNames(agg_types, agg_types), function(tp) {
  suppressWarnings(aggte(mp_fast, type = tp, bstrap = FALSE, cband = FALSE))
})

glance_row <- function(object, gl, source) {
  data.frame(
    object = object,
    source = source,
    nrow = nrow(gl),
    nobs = gl$nobs,
    ngroup = gl$ngroup,
    ntime = gl$ntime,
    control_group = gl$control.group,
    est_method = gl$est.method,
    has_type = as.integer("type" %in% names(gl)),
    type = if ("type" %in% names(gl)) gl$type else NA_character_,
    any_missing = as.integer(any(is.na(gl))),
    stringsAsFactors = FALSE
  )
}

metadata_rows <- list(
  glance_row("MP_slow", glance(mp_slow), "slow"),
  glance_row("MP_fast", glance(mp_fast), "fast")
)
for (tp in agg_types) {
  metadata_rows[[length(metadata_rows) + 1]] <- glance_row(
    paste0("aggte_", tp, "_slow"),
    glance(agg_slow[[tp]]),
    "slow"
  )
  metadata_rows[[length(metadata_rows) + 1]] <- glance_row(
    paste0("aggte_", tp, "_fast"),
    glance(agg_fast[[tp]]),
    "fast"
  )
}
metadata <- do.call(rbind, metadata_rows)
write.csv(metadata, file.path(fixture, "expected/r/glance-metadata.csv"), row.names = FALSE, na = "")

relations <- data.frame(
  relation = c(
    "mp_fast_equals_slow_nobs",
    "mp_fast_equals_slow_ngroup",
    "mp_fast_equals_slow_ntime",
    "mp_fast_equals_slow_control_group",
    "mp_fast_equals_slow_est_method",
    paste0("aggte_", agg_types, "_nobs_matches_mp")
  ),
  lhs_object = c(rep("MP_fast", 5), paste0("aggte_", agg_types, "_slow")),
  rhs_object = c(rep("MP_slow", 5), rep("MP_slow", length(agg_types))),
  field = c("nobs", "ngroup", "ntime", "control_group", "est_method", rep("nobs", length(agg_types))),
  expectation = "equal",
  stringsAsFactors = FALSE
)
write.csv(relations, file.path(fixture, "expected/r/glance-relations.csv"), row.names = FALSE, na = "")

mapped_tests <- c(
  "glance.MP returns a one-row data.frame",
  "glance.MP has expected columns",
  "glance.MP values are reasonable",
  "glance.MP nobs matches nobs.MP",
  "glance.MP works with faster_mode = TRUE",
  "glance.MP agrees between faster_mode settings",
  "glance.AGGTEobj returns a one-row data.frame for all 4 types",
  "glance.AGGTEobj has expected columns",
  "glance.AGGTEobj type column matches requested type",
  "glance.AGGTEobj values are not NULL or NA",
  "glance.AGGTEobj works with faster_mode = TRUE",
  "glance.MP and glance.AGGTEobj agree on nobs"
)
divergent_tests <- c(
  "glance.MP works when DIDparams lacks faster_mode",
  "glance.AGGTEobj works when DIDparams lacks faster_mode",
  "nobs.AGGTEobj works when DIDparams lacks faster_mode",
  "glance.MP works with a custom est_method function",
  "glance.AGGTEobj works with a custom est_method function"
)

upstream_map <- rbind(
  data.frame(
    source_file = "tests/testthat/test-glance.R",
    source_sha256 = "eb89be6352de487c4fe03983001673e96cda9c8930f9557a4b48f3ce48fe54c3",
    source_test = mapped_tests,
    mapped_scenario = c(
      "MP_slow",
      "MP_slow",
      "MP_slow",
      "MP_slow",
      "MP_fast",
      "MP_fast_vs_slow",
      "aggte_all",
      "aggte_dynamic_slow",
      "aggte_all",
      "aggte_all",
      "aggte_fast_all",
      "aggte_all_vs_MP"
    ),
    assertion_family = c(
      "one-row data.frame mapped to one-row Stata glance export",
      "expected glance columns mapped to Stata-normalized names",
      "positive counts and expected control/method metadata",
      "nobs equals unique units",
      "fast request returns positive metadata",
      "fast and slow metadata agree",
      "one-row data.frame for simple/dynamic/group/calendar",
      "expected aggregation glance columns mapped to Stata-normalized names",
      "aggregation type column matches requested type",
      "no missing aggregation glance metadata",
      "fast request returns aggregation metadata",
      "aggregation nobs equals MP nobs"
    ),
    coverage_status = "mapped",
    stringsAsFactors = FALSE
  ),
  data.frame(
    source_file = "tests/testthat/test-glance.R",
    source_sha256 = "eb89be6352de487c4fe03983001673e96cda9c8930f9557a4b48f3ce48fe54c3",
    source_test = divergent_tests,
    mapped_scenario = "r-object-model-only",
    assertion_family = c(
      "R saved-object DIDparams slot mutation has no public Stata command analogue",
      "R saved-object DIDparams slot mutation has no public Stata command analogue",
      "R saved-object DIDparams slot mutation has no public Stata command analogue",
      "R user-supplied estimator callback has no public Stata command analogue",
      "R user-supplied estimator callback has no public Stata command analogue"
    ),
    coverage_status = "approved-divergence",
    stringsAsFactors = FALSE
  )
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = c("RT014-DIV001", "RT014-DIV002"),
  source_tests = c(
    paste(divergent_tests[1:3], collapse = "; "),
    paste(divergent_tests[4:5], collapse = "; ")
  ),
  reason = c(
    "R mutates internal DIDparams slots on saved S3 objects; the Stata port exposes command results and saved RIF artifacts, not mutable R object slots.",
    "R accepts an arbitrary estimator callback function; the Stata public command surface intentionally supports the frozen dr/reg/ipw methods and legacy aliases only."
  ),
  accepted_behavior = c(
    "Stata glance exports do not depend on a public faster_mode object slot and are verified for standard and fast-request command results.",
    "Custom estimator callbacks remain outside the public Stata command surface; method metadata is verified for dr/reg/ipw."
  ),
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "RT014",
  fixture_family = "r-glance-output",
  normative_source = "R did 2.5.1 tests/testthat/test-glance.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  decision_refs = c("D004", "D014"),
  tolerance_ids = c("EXACT", "TOL002"),
  inputs = list(list(path = "inputs/sim-glance.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt014/generate.R", path = "tools/parity/generators/rt014/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 20260401),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence"),
    list(path = "expected/r/glance-metadata.csv", schema = "glance-metadata"),
    list(path = "expected/r/glance-relations.csv", schema = "glance-relations")
  ),
  comparison_plan = list(
    list(actual = "Stata csdid_estat glance metadata", expected = "expected/r/glance-metadata.csv", tolerance_id = "EXACT", key_columns = c("object")),
    list(actual = "Stata glance metadata relations", expected = "expected/r/glance-relations.csv", tolerance_id = "EXACT", key_columns = c("relation"))
  ),
  approved_divergence = list(
    status = "approved-divergence",
    path = "expected/contract/approved-divergence.csv",
    reason = "R object-slot mutation and arbitrary estimator callback tests do not map to the public Stata command surface."
  ),
  scope_note = "RT014 maps the public glance.MP and glance.AGGTEobj metadata tests from R did test-glance.R to Stata csdid_estat glance exports for standard, fast-request, and simple/dynamic/group/calendar aggregation results. Approved divergence covers R-only DIDparams slot mutation tests and arbitrary custom estimator callback tests, which have no public Stata command analogue."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
