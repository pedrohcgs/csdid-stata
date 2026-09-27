#!/usr/bin/env Rscript
# RT047: aggregation verdicts when the only estimable cohort has no
# post-treatment cell. Cohorts 3 and 4, no never-treated units, anticipation 1:
# cohort 4 becomes the comparison group, periods from 3 on are removed, and
# cohort 3 keeps only its reference and one pre-treatment cell. R refuses every
# aggregation type with and without na.rm (compute.aggte.R:185-187 for the
# group screen).
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt047/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt047")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

d <- expand.grid(t = 1:4, id = 1:40)[, c("id", "t")]
d$g <- ifelse(d$id <= 20, 3, 4)
d$y <- ((d$id * 7 + d$t * 3) %% 11) / 8 + d$t
input <- "inputs/pre_only_cohort.csv"
write.csv(d, file.path(out, input), row.names = FALSE)
a <- suppressMessages(suppressWarnings(did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
  data = d, control_group = "nevertreated", anticipation = 1, base_period = "universal",
  est_method = "reg", bstrap = FALSE, cband = FALSE)))
stopifnot(length(a$att) == 2, all(a$t < a$group))
status <- list()
for (type in c("simple", "group", "calendar", "dynamic")) for (na_rm in c(FALSE, TRUE)) {
  agg <- tryCatch(suppressWarnings(did::aggte(a, type = type, na.rm = na_rm, bstrap = FALSE, cband = FALSE)), error = function(e) e)
  status[[length(status) + 1L]] <- data.frame(type, na_rm = as.integer(na_rm),
    failed = as.integer(inherits(agg, "error")), message = if (inherits(agg, "error")) conditionMessage(agg) else "")
}
status <- do.call(rbind, status)
write.csv(status, file.path(out, "expected/r/aggregation_status.csv"), row.names = FALSE)
manifest <- list(matrix_id = "RT047", fixture_family = "r-aggregation-pre-only-cohort",
  normative_source = "did 2.5.1 compute.aggte.R (group na.rm screen :177-187; empty-aggregation stops)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = list("EXACT"), inputs = list(list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt047/generate.R", path = "tools/parity/generators/rt047/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = list(list(path = "expected/r/aggregation_status.csv", schema = "aggregation_status", sha256 = sha(file.path(out, "expected/r/aggregation_status.csv")))),
  comparison_plan = list(list(actual = "csdid_stats return code for the four types with and without dropmissing", expected = "expected/r/aggregation_status.csv", tolerance_id = "EXACT", key_columns = c("type", "na_rm"))),
  approved_divergence = NULL,
  scope_note = "One estimable cohort whose every cell is pre-treatment; every aggregation refuses in R.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
print(status[, 1:3])
