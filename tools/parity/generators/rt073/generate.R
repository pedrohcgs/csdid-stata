#!/usr/bin/env Rscript
# RT073: the values a decimal axis gives names and labels.
# Coefficient names, plot labels and the small-group warning write a cohort,
# period or event time as text. On {1, 1.2, 1.7, 2.2, 2.7, 3.1} the cells are
# indexed by one-decimal values, and the event times R computes as t - g carry
# binary residues: 3.1 - 2.2 is 0.89999999999999991 and 1 - 2.2 is
# -1.2000000000000002. On {1, 1.2, 2, 2.2, 3} R reports 3 - 2 = 1 and
# 2.2 - 1.2 = 1.0000000000000002 as two event times (unique() is exact). This
# fixture records R's exact values; the Stata test checks that every name and
# label reads back as one of them.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt073/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt073")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
exact <- function(v) ifelse(is.na(v), "", sprintf("%.17g", v))

make_axis <- function(per, cohorts, sizes) {
  g <- rep(cohorts, times = sizes)
  z <- expand.grid(k = seq_along(per), id = seq_along(g))[, c("id", "k")]
  z$time <- per[z$k]
  z$g <- g[z$id]
  z$y <- ((z$id * 7) %% 11) / 4 + 0.3 * z$time + ((z$id * z$k) %% 7 - 3) / 8 +
    ifelse(z$g > 0 & z$time >= z$g, 1 + 0.5 * (z$time - z$g), 0)
  z[, c("id", "time", "g", "y")]
}
axes <- list(
  onedecimal = make_axis(c(1, 1.2, 1.7, 2.2, 2.7, 3.1), c(0, 1.7, 2.2, 2.7, 3.1), c(40, 20, 20, 3, 20)),
  residue = make_axis(c(1, 1.2, 2, 2.2, 3), c(0, 1.2, 2), c(30, 30, 30)))

inputs <- list(); cells <- list(); aggs <- list(); warns <- list()
for (a in names(axes)) {
  z <- axes[[a]]
  input <- file.path("inputs", paste0(a, ".csv"))
  e <- z
  for (v in c("time", "g", "y")) e[[v]] <- exact(e[[v]])
  write.csv(e, file.path(out, input), row.names = FALSE, quote = FALSE)
  inputs[[length(inputs) + 1L]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z))
  msgs <- character(0)
  fit <- withCallingHandlers(did::att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
      data = z, control_group = "notyettreated", base_period = "universal", anticipation = 0,
      est_method = "reg", bstrap = FALSE, cband = FALSE),
    warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") })
  if (length(msgs)) warns[[length(warns) + 1L]] <- data.frame(axis = a, message = msgs)
  cells[[length(cells) + 1L]] <- data.frame(axis = a, group = exact(fit$group), time = exact(fit$t))
  for (type in c("dynamic", "group", "calendar")) {
    ag <- did::aggte(fit, type = type, bstrap = FALSE, cband = FALSE)
    aggs[[length(aggs) + 1L]] <- data.frame(axis = a, type = type, egt = exact(ag$egt),
      att = exact(ag$att.egt), se = exact(ag$se.egt))
  }
}
write.csv(do.call(rbind, cells), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, quote = FALSE)
write.csv(do.call(rbind, aggs), file.path(out, "expected/r/aggte.csv"), row.names = FALSE, quote = FALSE)
write.csv(do.call(rbind, warns), file.path(out, "expected/r/warnings.csv"), row.names = FALSE)
outputs <- list(
  list(path = "expected/r/attgt.csv", schema = "attgt-keys", sha256 = sha(file.path(out, "expected/r/attgt.csv"))),
  list(path = "expected/r/aggte.csv", schema = "aggte", sha256 = sha(file.path(out, "expected/r/aggte.csv"))),
  list(path = "expected/r/warnings.csv", schema = "warning-message", sha256 = sha(file.path(out, "expected/r/warnings.csv"))))
manifest <- list(matrix_id = "RT073", fixture_family = "r-decimal-axis-names",
  normative_source = "did 2.5.1 compute.aggte.R:450 (eseq <- unique(originalt - originalgroup), exact); pre_process_did2.R small-group warning (toString of the cohorts)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt073/generate.R", path = "tools/parity/generators/rt073/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "every ATT(g,t) coefficient name reads back as R's (group, time), none is att_#", expected = "expected/r/attgt.csv", tolerance_id = "EXACT", key_columns = c("axis", "group", "time")),
    list(actual = "every posted estat event/group/calendar name reads back as R's event time, cohort or period, none is eff_#; plot x_label reads back as x", expected = "expected/r/aggte.csv", tolerance_id = "EXACT", key_columns = c("axis", "type", "egt")),
    list(actual = "the small-group warning names the cohorts R names", expected = "expected/r/warnings.csv", tolerance_id = "EXACT", key_columns = c("axis"))),
  approved_divergence = NULL,
  scope_note = "Axis {1, 1.2, 1.7, 2.2, 2.7, 3.1} with cohorts 1.7, 2.2, 2.7 (three units, below R's group-size threshold) and 3.1 and a never-treated group; axis {1, 1.2, 2, 2.2, 3} with cohorts 1.2 and 2, where the event times 1 and 1.0000000000000002 are distinct. Not-yet-treated comparison, universal base, method reg.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT073 written:", nrow(do.call(rbind, cells)), "cells,", nrow(do.call(rbind, aggs)), "aggregated rows,", nrow(do.call(rbind, warns)), "warnings.\n")
