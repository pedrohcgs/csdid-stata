#!/usr/bin/env Rscript
# RT071: type = "group" with max_e and na.rm on a sub-unit-spaced time axis.
# R screens each cohort on the RAW calendar, g <= t <= g + max_e
# (compute.aggte.R:177), then recodes periods and cohorts to ranks (:252-253)
# and averages the cells whose RANK lies within max_e of the cohort's
# (:335-:344). When periods sit less than one time() unit apart the raw window
# is the wider of the two, so a cohort whose only estimated post cells lie
# between them passes the screen and has nothing to average, and
# get_agg_inf_func stops (:777-781). Cohort 1.7 is unobserved at 1.7 and 2.2,
# its first two post periods; its cell at 2.7 is inside the raw window
# [1.7, 2.7] and outside the rank window {1.7, 2.2}.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt071/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt071")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
exact <- function(v) ifelse(is.na(v), "", sprintf("%.17g", v))

per <- c(1, 1.2, 1.7, 2.2, 2.7, 3.1)
cohorts <- c(0, 0, 1.7, 2.2, 2.7, 3.1)
z <- expand.grid(k = seq_along(per), id = 1:180)[, c("id", "k")]
z$time <- per[z$k]
z$g <- cohorts[1 + (z$id - 1) %/% 30]
z$y <- ((z$id * 7) %% 11) / 4 + 0.3 * z$time + ((z$id * z$k) %% 7 - 3) / 8 +
  ifelse(z$g > 0 & z$time >= z$g, 1 + 0.5 * (z$time - z$g), 0)
z <- z[!(z$g == 1.7 & z$time %in% c(1.7, 2.2)), c("id", "time", "g", "y")]
rownames(z) <- NULL
input <- "inputs/subunit_axis.csv"
e <- z
for (v in c("time", "g", "y")) e[[v]] <- exact(e[[v]])
write.csv(e, file.path(out, input), row.names = FALSE, quote = FALSE)
inputs <- list(list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z)))

fit <- suppressWarnings(did::att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
  data = z, allow_unbalanced_panel = TRUE, control_group = "nevertreated",
  base_period = "universal", anticipation = 0, est_method = "reg", bstrap = FALSE, cband = FALSE))

cases <- data.frame(
  case = c("group_maxe1_narm", "group_narm", "group_maxe05_narm", "simple_maxe1_narm", "group_maxe1"),
  type = c("group", "group", "group", "simple", "group"),
  max_e = c(1, Inf, 0.5, 1, 1),
  na_rm = c(TRUE, TRUE, TRUE, TRUE, FALSE),
  stringsAsFactors = FALSE)
rows <- list(); refusals <- list()
for (k in seq_len(nrow(cases))) {
  c <- cases[k, ]
  ag <- tryCatch(did::aggte(fit, type = c$type, max_e = c$max_e, na.rm = c$na_rm, bstrap = FALSE, cband = FALSE),
    error = function(err) conditionMessage(err))
  if (is.character(ag)) {
    refusals[[length(refusals) + 1L]] <- data.frame(case = c$case, message = ag)
    next
  }
  egt <- if (c$type == "group") ag$egt else numeric(0)
  rows[[length(rows) + 1L]] <- data.frame(case = c$case,
    row = c(rep("effect", length(egt)), "overall"),
    egt = exact(c(egt, NA)), att = exact(c(ag$att.egt[seq_along(egt)], ag$overall.att)),
    se = exact(c(ag$se.egt[seq_along(egt)], ag$overall.se)))
}
write.csv(do.call(rbind, rows), file.path(out, "expected/r/aggte.csv"), row.names = FALSE, quote = FALSE)
write.csv(do.call(rbind, refusals), file.path(out, "expected/r/refusals.csv"), row.names = FALSE)
write.csv(cases, file.path(out, "inputs/cases.csv"), row.names = FALSE)
inputs[[length(inputs) + 1L]] <- list(path = "inputs/cases.csv", sha256 = sha(file.path(out, "inputs/cases.csv")), rows = nrow(cases), columns = ncol(cases))
outputs <- list(
  list(path = "expected/r/aggte.csv", schema = "aggte-group", sha256 = sha(file.path(out, "expected/r/aggte.csv"))),
  list(path = "expected/r/refusals.csv", schema = "refusal-message", sha256 = sha(file.path(out, "expected/r/refusals.csv"))))
manifest <- list(matrix_id = "RT071", fixture_family = "r-group-window-subunit-axis",
  normative_source = "did 2.5.1 compute.aggte.R:177 (raw-scale na.rm screen), :252-253 (rank recode), :335-344 (rank-scale group window), :777-781 (get_agg_inf_func stop on an empty selection)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt071/generate.R", path = "tools/parity/generators/rt071/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "csdid_stats group/simple with dropmissing and the case's max_e(): cohort effects, overall ATT and standard errors", expected = "expected/r/aggte.csv", tolerance_id = "TOL001", key_columns = c("case", "row", "egt")),
    list(actual = "the cases R stops on are refused with rc 498, through csdid_stats and estat", expected = "expected/r/refusals.csv", tolerance_id = "EXACT", key_columns = c("case"))),
  approved_divergence = NULL,
  scope_note = "Axis {1, 1.2, 1.7, 2.2, 2.7, 3.1}, cohorts 1.7, 2.2, 2.7, 3.1 and 60 never-treated units, 30 units per cohort; cohort 1.7 unobserved at 1.7 and 2.2, estimated under bal(none).")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT071 written:", nrow(do.call(rbind, rows)), "rows,", length(refusals), "refusals.\n")
