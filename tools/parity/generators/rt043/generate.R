#!/usr/bin/env Rscript
# RT043: the base period under anticipation on a decimal time axis.
# R takes the last period t with t + anticipation < g (compute.att_gt.R:301).
# On the axis {1, 1.2, 1.7, 2.2, 2.7}, 2.2 - 1 is 1.2000000000000002, so the
# subtractive test t < g - anticipation admits 1.2 as cohort 2.2's base where
# R's additive test rejects it and uses 1.0. Every post-treatment cell of the
# cohort, and every universal-base cell, is differenced against that period.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt043/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt043")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

scenarios <- data.frame(
  scenario = c("decimal_ant1_universal_reg", "decimal_ant1_varying_reg", "decimal_ant1_universal_dr"),
  method = c("reg", "reg", "dr"),
  base_period = c("universal", "varying", "universal"),
  stringsAsFactors = FALSE)

per <- c(1.0, 1.2, 1.7, 2.2, 2.7)
z <- expand.grid(time = per, id = 1:90)[, c("id", "time")]
z$g <- c(0, 2.2, 2.7)[1 + (z$id - 1) %/% 30]
z$x <- ((z$id * 7) %% 13) / 8 - 3 / 4
z$y <- ((z$id * 5) %% 11) / 4 + 2 * z$time + z$x * z$time / 2 +
  ifelse(z$g > 0 & z$time >= z$g, 1 + (z$time - z$g), 0) +
  ((z$id * round(10 * z$time)) %% 7 - 3) / 8
z <- z[order(z$id, z$time), c("id", "time", "g", "x", "y")]
rownames(z) <- NULL
input <- "inputs/decimal_axis.csv"
write.csv(z, file.path(out, input), row.names = FALSE)
inputs <- list(list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z)))

attout <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  a <- suppressWarnings(did::att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = z,
    xformla = if (s$method == "dr") ~x else NULL,
    control_group = "nevertreated", base_period = s$base_period, anticipation = 1,
    est_method = s$method, bstrap = FALSE, cband = FALSE))
  attout[[k]] <- data.frame(scenario = s$scenario, group = a$group, time = a$t,
    att = a$att, se = a$se, n_units = a$n)
}
write.csv(do.call(rbind, attout), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE)
inputs[[length(inputs) + 1L]] <- list(path = "inputs/scenarios.csv", sha256 = sha(file.path(out, "inputs/scenarios.csv")), rows = nrow(scenarios), columns = ncol(scenarios))
outputs <- list(list(path = "expected/r/attgt.csv", schema = "attgt", sha256 = sha(file.path(out, "expected/r/attgt.csv"))))
manifest <- list(matrix_id = "RT043", fixture_family = "r-anticipation-base-period",
  normative_source = "did 2.5.1 compute.att_gt.R:301 (idx_g <- which((tlist + anticipation) < glist[g])); pre_process_did2.R:279 (glist > first_period + anticipation)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt043/generate.R", path = "tools/parity/generators/rt043/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "Stata ATT(g,t), standard errors and unit count", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "group", "time"))),
  approved_divergence = NULL,
  scope_note = "A five-period decimal axis where t + 1 < g and t < g - 1 disagree in binary floating point for cohort 2.2 and period 1.2. Universal and varying bases, reg and dr with a covariate; every cell is compared.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT043 written:", nrow(do.call(rbind, attout)), "cells.\n")
