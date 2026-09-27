#!/usr/bin/env Rscript
# RT074: fix_weights = "varying" on a panel with no sampling weights.
# R stacks the two periods of every comparison as repeated cross sections
# whenever fix_weights is "varying" on a panel, weights or not
# (compute.att_gt2.R:589, force_rc), so each period carries weight one. With a
# covariate under the doubly robust estimator the stacked standard errors
# differ from the panel ones. The last scenario is an outcome constant within
# every unit: R reports ATT(g,t) of rounding size and standard errors, not a
# table of zeros with none.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt074/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt074")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

scenarios <- data.frame(
  scenario = c("varying_dr", "varying_reg", "varying_ipw", "flat_varying_dr"),
  method = c("dr", "reg", "ipw", "dr"),
  outcome = c("y", "y", "y", "yflat"),
  stringsAsFactors = FALSE)

z <- expand.grid(time = 1:4, id = 1:120)[, c("id", "time")]
z$g <- c(0, 2, 3, 4)[1 + (z$id - 1) %/% 30]
z$x <- ((z$id * 7) %% 13) / 8 - 3 / 4
z$y <- ((z$id * 5) %% 11) / 4 + z$time / 2 + z$x * z$time / 3 +
  ifelse(z$g > 0 & z$time >= z$g, 1 + (z$time - z$g) / 2, 0) +
  ((z$id * z$time) %% 7 - 3) / 8
z$yflat <- ((z$id * 5) %% 11) / 4 + z$x
z <- z[order(z$id, z$time), c("id", "time", "g", "x", "y", "yflat")]
rownames(z) <- NULL
input <- "inputs/panel.csv"
write.csv(z, file.path(out, input), row.names = FALSE)
inputs <- list(list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z)))

attout <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  a <- suppressWarnings(did::att_gt(
    yname = s$outcome, tname = "time", idname = "id", gname = "g", data = z,
    xformla = ~x, control_group = "nevertreated", base_period = "universal",
    est_method = s$method, fix_weights = "varying", bstrap = FALSE, cband = FALSE))
  attout[[k]] <- data.frame(scenario = s$scenario, group = a$group, time = a$t,
    att = a$att, se = a$se)
}
write.csv(do.call(rbind, attout), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE)
inputs[[length(inputs) + 1L]] <- list(path = "inputs/scenarios.csv", sha256 = sha(file.path(out, "inputs/scenarios.csv")), rows = nrow(scenarios), columns = ncol(scenarios))
outputs <- list(list(path = "expected/r/attgt.csv", schema = "attgt", sha256 = sha(file.path(out, "expected/r/attgt.csv"))))
manifest <- list(matrix_id = "RT074", fixture_family = "r-fix-weights-varying-unweighted",
  normative_source = "did 2.5.1 compute.att_gt2.R:589 (force_rc <- !is.null(dp2$fix_weights) && dp2$fix_weights == \"varying\" && dp2$panel), whatever the weights",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt074/generate.R", path = "tools/parity/generators/rt074/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "Stata ATT(g,t) and standard errors", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "group", "time"),
      note = "ATT(g,t) of rounding size (the flat outcome) is compared on an absolute scale.")),
  approved_divergence = NULL,
  scope_note = "A 120-unit, four-period balanced panel with a time-invariant covariate and no sampling weights, under fix_weights = \"varying\": dr, reg and ipw on an outcome that varies, and dr on an outcome constant within every unit. Every cell is compared.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT074 written:", nrow(do.call(rbind, attout)), "cells.\n")
print(do.call(rbind, attout))
