#!/usr/bin/env Rscript
# RT048: an event time whose only cell belongs to a cohort with zero weight.
# Cohort 6 carries weight 0 in every row, so its group probability is 0. On the
# periods {1, 2, 3, 6} its universal reference cell (t = 3) is the only cell at
# event time -3, and its estimated cells fail and are dropped under na.rm. R's
# dynamic effect there is sum(att * pg / sum(pg)) = 0/0, reported as NaN
# (compute.aggte.R:479-486).
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt048/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt048")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

d <- expand.grid(t = c(1, 2, 3, 6), id = 1:40)[, c("id", "t")]
d$g <- c(0, 2, 3, 6)[1 + (d$id - 1) %/% 10]
d$w <- ifelse(d$g == 6, 0, 1 + (d$id %% 3) / 4)
d$y <- ((d$id * 7 + d$t * 3) %% 11) / 8 + d$t + (d$g > 0 & d$t >= d$g)
input <- "inputs/zero_weight_cohort.csv"
write.csv(d, file.path(out, input), row.names = FALSE)
a <- suppressMessages(suppressWarnings(did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
  weightsname = "w", data = d, control_group = "nevertreated", base_period = "universal",
  est_method = "reg", bstrap = FALSE, cband = FALSE)))
agg <- suppressWarnings(did::aggte(a, type = "dynamic", na.rm = TRUE, bstrap = FALSE, cband = FALSE))
res <- data.frame(egt = agg$egt, att = agg$att.egt, se = agg$se.egt,
  overall_att = agg$overall.att, overall_se = agg$overall.se)
stopifnot(is.nan(res$att[res$egt == -3]))
write.csv(res, file.path(out, "expected/r/aggte.csv"), row.names = FALSE, na = "")
manifest <- list(matrix_id = "RT048", fixture_family = "r-dynamic-zero-probability-event-time",
  normative_source = "did 2.5.1 compute.aggte.R:479-486 (dynamic.att.e = sum(atte * pg[whiche] / sum(pg[whiche])))",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = list(list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt048/generate.R", path = "tools/parity/generators/rt048/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = list(list(path = "expected/r/aggte.csv", schema = "aggte", sha256 = sha(file.path(out, "expected/r/aggte.csv")))),
  comparison_plan = list(list(actual = "csdid_stats type(dynamic) dropmissing: every event-time effect and SE, NaN as missing", expected = "expected/r/aggte.csv", tolerance_id = "TOL001", key_columns = list("egt"))),
  approved_divergence = NULL,
  scope_note = "A cohort with zero weight in every row; its reference cell alone populates one event time.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
print(res)
