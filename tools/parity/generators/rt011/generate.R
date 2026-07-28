#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt011/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt011")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

set.seed(20260401)
sp <- did::reset.sim(time.periods = 4, n = 300)
d <- did::build_sim_dataset(sp)
names(d) <- tolower(names(d))
d$cl <- d$id %% 10
d$cl2 <- d$id %% 7
d$tw <- d$period + runif(nrow(d))
write.csv(d, file.path(fixture, "inputs/sim-error-handling.csv"), row.names = FALSE, na = "")

no_never <- d[d$g > 0, , drop = FALSE]
write.csv(no_never, file.path(fixture, "inputs/no-never-treated.csv"), row.names = FALSE, na = "")

treated_ids <- unique(d$id[d$g > 0])
control_ids <- unique(d$id[d$g == 0])
small_ids <- c(treated_ids[1:2], control_ids[1:min(50, length(control_ids))])
small <- d[d$id %in% small_ids, , drop = FALSE]
write.csv(small, file.path(fixture, "inputs/small-groups.csv"), row.names = FALSE, na = "")

missing_data <- d
missing_data$y[1:5] <- NA_real_
missing_data$g[6:7] <- NA_real_
missing_data$x[8:9] <- NA_real_
write.csv(missing_data, file.path(fixture, "inputs/missing-inputs.csv"), row.names = FALSE, na = "")

reversal <- d
target_id <- reversal$id[1]
periods <- sort(unique(reversal$period))
reversal$g[reversal$id == target_id & reversal$period == periods[1]] <- 0
reversal$g[reversal$id == target_id & reversal$period == periods[2]] <- 2
write.csv(reversal, file.path(fixture, "inputs/treatment-reversal.csv"), row.names = FALSE, na = "")

source_sha <- "66b0e390e67447f0c154ed386036bd497eb7af42c9610b41680a79a3077f50b7"
source_tests <- c(
  "att_gt errors on invalid est_method string",
  "att_gt errors on non-character non-function est_method",
  "att_gt errors on invalid fix_weights value",
  "att_gt rejects non-exact control_group and base_period values in both modes",
  "att_gt rejects negative or non-numeric anticipation in both modes",
  "att_gt rejects invalid scalar logical controls before base R errors",
  "att_gt rejects invalid cores before parallel code sees it",
  "att_gt rejects argument-referenced internal variable names in both modes",
  "att_gt rejects invalid xformla before formula internals in both modes",
  "slow path rejects malformed column-name arguments before ambiguous indexing",
  "att_gt drops rows with missing gname and non-finite numeric inputs in both modes",
  "att_gt errors on panel=TRUE without idname in both modes",
  "att_gt still runs with panel=FALSE and no idname in both modes",
  "att_gt errors on invalid alp",
  "att_gt errors on invalid biters when bootstrapping",
  "simulation helpers reject invalid scalar controls before raw R errors",
  "trimmer rejects malformed exported utility arguments",
  "test.mboot rejects malformed bootstrap inputs before recycling",
  "mboot rejects malformed direct helper inputs before raw errors",
  "process_attgt rejects malformed group-time result lists",
  "aggte rejects invalid scalar controls before base R errors",
  "plotting helpers reject invalid scalar controls before ggplot errors",
  "mboot rejects invalid scalar controls before bootstrap internals",
  "att_gt errors on fix_weights with panel=FALSE",
  "att_gt warns on extra args with built-in est_method",
  "att_gt messages about anticipation",
  "att_gt computes clustered SEs without the bootstrap (no 'requires bootstrap' warning)",
  "att_gt errors on missing column name (slower mode)",
  "att_gt errors on missing column name (faster_mode)",
  "att_gt errors on non-numeric tname",
  "att_gt errors on non-numeric gname",
  "att_gt errors on non-numeric outcome variable in both modes",
  "att_gt still accepts logical and integer outcomes in both modes",
  "att_gt errors on treatment reversals (faster_mode)",
  "att_gt warns on missing data dropped",
  "att_gt warns on small groups",
  "att_gt handles data with .w column (slower mode)",
  "att_gt messages on time-varying weights (panel)",
  "clustervars contract enforced in all faster_mode x bstrap combinations",
  "one extra cluster variable still works in all faster_mode x bstrap combinations",
  "aggte errors on invalid type",
  "aggte errors when ATTs contain NA and na.rm=FALSE",
  "att_gt handles singular covariance for Wald test gracefully",
  "att_gt warns on overlap violations",
  "slow path warns once per failed cell, matching fast-path wording, with accurate Wald diagnosis",
  "att_gt warns when no pre-treatment periods for Wald test",
  "empty-cell warning names the actually-empty base period under base_period='universal' in both modes",
  "'no never-treated group' warning is identical across modes and discloses the period filtering",
  "balanced-panel coercion warning counts dropped units identically in both modes"
)

mapped_tests <- c(
  "att_gt errors on invalid est_method string",
  "att_gt errors on invalid fix_weights value",
  "att_gt rejects non-exact control_group and base_period values in both modes",
  "att_gt rejects negative or non-numeric anticipation in both modes",
  "slow path rejects malformed column-name arguments before ambiguous indexing",
  "att_gt drops rows with missing gname and non-finite numeric inputs in both modes",
  "att_gt still runs with panel=FALSE and no idname in both modes",
  "att_gt errors on invalid alp",
  "att_gt errors on invalid biters when bootstrapping",
  "aggte rejects invalid scalar controls before base R errors",
  "att_gt errors on fix_weights with panel=FALSE",
  "att_gt computes clustered SEs without the bootstrap (no 'requires bootstrap' warning)",
  "att_gt errors on missing column name (slower mode)",
  "att_gt errors on missing column name (faster_mode)",
  "att_gt errors on non-numeric tname",
  "att_gt errors on non-numeric gname",
  "att_gt errors on non-numeric outcome variable in both modes",
  "att_gt still accepts logical and integer outcomes in both modes",
  "att_gt errors on treatment reversals (faster_mode)",
  "att_gt warns on missing data dropped",
  "att_gt warns on small groups",
  "att_gt messages on time-varying weights (panel)",
  "clustervars contract enforced in all faster_mode x bstrap combinations",
  "one extra cluster variable still works in all faster_mode x bstrap combinations",
  "aggte errors on invalid type",
  "aggte errors when ATTs contain NA and na.rm=FALSE",
  "att_gt warns on overlap violations",
  "slow path warns once per failed cell, matching fast-path wording, with accurate Wald diagnosis",
  "'no never-treated group' warning is identical across modes and discloses the period filtering"
)

scenario_for <- function(test_name) {
  switch(test_name,
    "att_gt errors on invalid est_method string" = "invalid_method",
    "att_gt errors on invalid fix_weights value" = "invalid_fix_weights",
    "att_gt rejects non-exact control_group and base_period values in both modes" = "invalid_control_and_base",
    "att_gt rejects negative or non-numeric anticipation in both modes" = "invalid_anticipation",
    "slow path rejects malformed column-name arguments before ambiguous indexing" = "missing_or_malformed_column_names",
    "att_gt drops rows with missing gname and non-finite numeric inputs in both modes" = "missing_or_nonfinite_inputs",
    "att_gt still runs with panel=FALSE and no idname in both modes" = "repeated_cross_section_no_ivar",
    "att_gt errors on invalid alp" = "invalid_level",
    "att_gt errors on invalid biters when bootstrapping" = "invalid_bootstrap_reps",
    "aggte rejects invalid scalar controls before base R errors" = "invalid_aggregation_controls",
    "att_gt errors on fix_weights with panel=FALSE" = "fix_weights_requires_panel",
    "att_gt computes clustered SEs without the bootstrap (no 'requires bootstrap' warning)" = "clustered_analytical_no_bootstrap_warning",
    "att_gt errors on missing column name (slower mode)" = "missing_column_standard",
    "att_gt errors on missing column name (faster_mode)" = "missing_column_fast_request",
    "att_gt errors on non-numeric tname" = "nonnumeric_time",
    "att_gt errors on non-numeric gname" = "nonnumeric_group",
    "att_gt errors on non-numeric outcome variable in both modes" = "nonnumeric_outcome",
    "att_gt still accepts logical and integer outcomes in both modes" = "integer_outcome",
    "att_gt errors on treatment reversals (faster_mode)" = "treatment_reversal",
    "att_gt warns on missing data dropped" = "missing_data_dropped",
    "att_gt warns on small groups" = "small_group_warning",
    "att_gt messages on time-varying weights (panel)" = "time_varying_weights_message",
    "clustervars contract enforced in all faster_mode x bstrap combinations" = "cluster_contract_validation",
    "one extra cluster variable still works in all faster_mode x bstrap combinations" = "one_extra_cluster_works",
    "aggte errors on invalid type" = "invalid_aggregation_type",
    "aggte errors when ATTs contain NA and na.rm=FALSE" = "aggte_na_rm_validation",
    "att_gt warns on overlap violations" = "overlap_warning",
    "slow path warns once per failed cell, matching fast-path wording, with accurate Wald diagnosis" = "overlap_warning_count_guard",
    "'no never-treated group' warning is identical across modes and discloses the period filtering" = "no_never_treated_fallback",
    "r-only-or-approved-divergence"
  )
}

divergence_id_for <- function(test_name) {
  if (test_name %in% c(
    "att_gt errors on non-character non-function est_method",
    "att_gt rejects invalid scalar logical controls before base R errors",
    "att_gt rejects invalid cores before parallel code sees it",
    "att_gt rejects argument-referenced internal variable names in both modes",
    "att_gt rejects invalid xformla before formula internals in both modes",
    "att_gt errors on panel=TRUE without idname in both modes",
    "att_gt handles data with .w column (slower mode)"
  )) return("RT011-DIV001")
  if (test_name %in% c(
    "simulation helpers reject invalid scalar controls before raw R errors",
    "trimmer rejects malformed exported utility arguments",
    "test.mboot rejects malformed bootstrap inputs before recycling",
    "mboot rejects malformed direct helper inputs before raw errors",
    "process_attgt rejects malformed group-time result lists",
    "plotting helpers reject invalid scalar controls before ggplot errors",
    "mboot rejects invalid scalar controls before bootstrap internals",
    "att_gt handles singular covariance for Wald test gracefully"
  )) return("RT011-DIV002")
  return("RT011-DIV003")
}

upstream_map <- data.frame(
  source_file = "tests/testthat/test-error-handling.R",
  source_sha256 = source_sha,
  source_test = source_tests,
  mapped_scenario = vapply(source_tests, scenario_for, character(1)),
  assertion_family = ifelse(
    source_tests %in% mapped_tests,
    "public Stata command-surface diagnostic or successful fallback check",
    "approved divergence: R-only helper, object, argument-shape, or messaging surface"
  ),
  coverage_status = ifelse(source_tests %in% mapped_tests, "mapped", "approved-divergence"),
  divergence_id = ifelse(source_tests %in% mapped_tests, "", vapply(source_tests, divergence_id_for, character(1))),
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE)
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = c("RT011-DIV001", "RT011-DIV002", "RT011-DIV003"),
  source_tests = vapply(c("RT011-DIV001", "RT011-DIV002", "RT011-DIV003"), function(id) {
    paste(upstream_map$source_test[upstream_map$divergence_id == id], collapse = "; ")
  }, character(1)),
  reason = c(
    "R accepts argument shapes and internal column names that Stata syntax either cannot express or intentionally exposes through different public options.",
    "R-only helper functions and mutable S3 object internals are not part of the frozen Stata command surface.",
    "R public messaging and preprocessing choices differ from the owner-directed Stata surface, including unsupported extra dots, anticipation notes, no-Wald-pretest surface, and unbalanced-panel handling."
  ),
  accepted_behavior = c(
    "Stata validates the corresponding public varlist/options and records unsupported or syntactically impossible shapes as non-public-surface divergences.",
    "Stata verifies command-level bootstrap, aggregation, plotting, and saved-artifact behavior through public commands rather than direct R helper calls.",
    "Stata rejects unsupported extra options, keeps anticipation as stored metadata, omits R Wald-pretest reporting, and routes unbalanced panels to the R-compatible repeated-cross-section estimator by default."
  ),
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE)
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "RT011",
  fixture_family = "r-error-handling",
  normative_source = "R did 2.5.1 tests/testthat/test-error-handling.R",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D003", "D004", "D010", "D014", "D015"),
  tolerance_ids = c("EXACT", "TOL002"),
  inputs = list(
    list(path = "inputs/sim-error-handling.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/no-never-treated.csv", rows = nrow(no_never), columns = ncol(no_never)),
    list(path = "inputs/small-groups.csv", rows = nrow(small), columns = ncol(small)),
    list(path = "inputs/missing-inputs.csv", rows = nrow(missing_data), columns = ncol(missing_data)),
    list(path = "inputs/treatment-reversal.csv", rows = nrow(reversal), columns = ncol(reversal))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt011/generate.R", path = "tools/parity/generators/rt011/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 20260401, compact_simulation = "did::reset.sim(time.periods = 4, n = 300)"),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "Stata captured diagnostics and success checks", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test")),
    list(actual = "Approved R-only divergence registry", expected = "expected/contract/approved-divergence.csv", tolerance_id = "EXACT", key_columns = c("divergence_id"))
  ),
  approved_divergence = list(
    status = "approved-divergence",
    path = "expected/contract/approved-divergence.csv",
    reason = "R test-error-handling.R mixes public diagnostics with R-only helper/object/argument-shape surfaces and owner-directed Stata divergences."
  ),
  scope_note = "RT011 maps R did test-error-handling.R public diagnostics through Stata csdid/csdid_stats/csdid_plot command checks for invalid options, missing or malformed variables, sample dropping, repeated cross-sections without ivar(), invalid levels/bootstrap reps, clustering, aggregation validation, overlap and no-never-treated warnings. Approved divergence records R-only helper APIs, mutable object internals, unrepresentable argument shapes, graph helper scalar controls, Wald-pretest messaging, extra-dot warning behavior, and owner-directed unbalanced-panel handling."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
