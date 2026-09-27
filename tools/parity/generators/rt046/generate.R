#!/usr/bin/env Rscript
# RT046: a dead covariate period on a decimal time axis.
# R removes incomplete rows before it reads the period list, so a period whose
# covariate is missing in every row simply ceases to exist
# (pre_process_did2.R:150 then :194; slow path pre_process_did.R:162, :215);
# a period with only some rows missing keeps
# its survivors. On a float-stored axis (1.2 is 1.2000000476837158) or a
# computed one (0.1 * 14 is 1.4000000000000001) the period must be found by
# its value, not by a printed approximation of it.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt046/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt046")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
as_float <- function(v) readBin(writeBin(v, raw(), size = 4), "double", size = 4, n = length(v))

scenarios <- data.frame(
  scenario = c("float_dead", "computed_dead", "float_onemissing"),
  axis = c("float", "computed", "float"),
  missing = c("period", "period", "one"),
  dead_period = c(2L, 2L, NA_integer_),
  stringsAsFactors = FALSE)
make_data <- function(axis, missing) {
  d <- expand.grid(k = 1:4, id = 1:60)[, c("id", "k")]
  gk <- ifelse(d$id <= 20, 0, ifelse(d$id <= 40, 3, 4))
  d$time <- if (axis == "float") as_float(1 + d$k / 10) else 0.1 * (10 + d$k)
  d$g <- ifelse(gk == 0, 0, if (axis == "float") as_float(1 + gk / 10) else 0.1 * (10 + gk))
  d$x <- ((d$id * 5 + d$k * 3) %% 13) / 8
  d$y <- ((d$id * 7 + d$k * 3) %% 11) / 8 + d$k + d$x * d$k / 4 + (gk > 0 & d$k >= gk)
  if (missing == "period") d$x[d$k == 2] <- NA
  if (missing == "one") d$x[d$id == 2 & d$k == 1] <- NA
  d[, c("id", "time", "g", "x", "y")]
}
inputs <- list(); attout <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  d <- make_data(s$axis, s$missing)
  input <- file.path("inputs", paste0(s$scenario, ".csv"))
  e <- d
  for (v in c("time", "g", "x", "y")) e[[v]] <- ifelse(is.na(e[[v]]), "", sprintf("%.17g", e[[v]]))
  write.csv(e, file.path(out, input), row.names = FALSE, quote = FALSE)
  inputs[[k]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(d), columns = ncol(d))
  a <- suppressWarnings(did::att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
    xformla = ~x, data = d, control_group = "nevertreated", base_period = "universal",
    est_method = "reg", bstrap = FALSE, cband = FALSE))
  attout[[k]] <- data.frame(scenario = s$scenario, group = sprintf("%.17g", a$group),
    time = sprintf("%.17g", a$t), att = a$att, se = a$se, n_units = a$n)
}
write.csv(do.call(rbind, attout), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "", quote = FALSE)
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE, na = "")
inputs[[length(inputs) + 1L]] <- list(path = "inputs/scenarios.csv", sha256 = sha(file.path(out, "inputs/scenarios.csv")), rows = nrow(scenarios), columns = ncol(scenarios))
outputs <- list(list(path = "expected/r/attgt.csv", schema = "attgt", sha256 = sha(file.path(out, "expected/r/attgt.csv"))))
manifest <- list(matrix_id = "RT046", fixture_family = "r-dead-period-decimal-axis",
  normative_source = "did 2.5.1 pre_process_did2.R:150 (row-level complete cases) and :194 (period list read from the surviving rows); slow path pre_process_did.R:162, :215",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list("owner decision 2026-08-28: dead period deleted as R does and announced"),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt046/generate.R", path = "tools/parity/generators/rt046/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(list(actual = "Stata ATT(g,t) and standard errors; the dead-period announcement names exactly the dead period", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "group", "time"))),
  approved_divergence = NULL,
  scope_note = "Float-stored axis (the Stata test recasts time() and gvar() to float; every value is float-representable) and a computed double axis; a covariate dead in period 2, and a single missing covariate value that leaves every period alive.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT046 written:", nrow(do.call(rbind, attout)), "cells.\n")
