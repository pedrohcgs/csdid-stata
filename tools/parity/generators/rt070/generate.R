#!/usr/bin/env Rscript
# RT070: the first period of a decimal time axis, carried exactly.
# R tests a cohort's usability as glist > first_period + anticipation
# (pre_process_did2.R:279) and truncates a balanced event study at
# balance_e - t2orig(maxT) + t2orig(1) (compute.aggte.R:463), both on the exact
# first period. On a fractional-year monthly axis (2000 + m/12) the first period
# needs seventeen significant digits, and a period one ulp below a short
# decimal (1.02 - eps) prints as that decimal at sixteen, so a first period
# rounded on its way through a text macro drops the boundary event time R
# reports and refuses a cohort R estimates.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt070/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt070")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
as_float <- function(v) readBin(writeBin(v, raw(), size = 4), "double", size = 4, n = length(v))
exact <- function(v) ifelse(is.na(v), "", sprintf("%.17g", v))

scenarios <- data.frame(
  scenario = c("month_double", "month_float", "month_unbalanced", "guard_ulp", "guard_exact", "latest_only"),
  control = c("notyet", "notyet", "notyet", "both", "both", "both"),
  anticipation = c(0L, 0L, 0L, 1L, 1L, 0L),
  stringsAsFactors = FALSE)

# A monthly axis 2000 + m/12, m = 5..28: the first period 2000 + 5/12 does not
# round-trip at sixteen significant digits. Cohorts at the 7th, 13th and 24th
# period and a never-treated group, 25 units each.
make_month <- function(float = FALSE, drop_one = FALSE) {
  tm <- 2000 + (5:28) / 12
  if (float) tm <- as_float(tm)
  cohort <- c(0, tm[7], tm[13], tm[24])
  z <- expand.grid(k = seq_along(tm), id = 1:100)[, c("id", "k")]
  gk <- c(0L, 7L, 13L, 24L)[1 + (z$id - 1) %/% 25]
  z$time <- tm[z$k]
  z$g <- cohort[1 + (z$id - 1) %/% 25]
  z$y <- ((z$id * 7) %% 11) / 4 + z$k / 6 + ((z$id * z$k) %% 7 - 3) / 8 +
    ifelse(gk > 0 & z$k >= gk, 1.5 + (z$k - gk) / 10, 0)
  # one unit short of a period: bal(full) drops it, under notyet the
  # pre-balance cohort grid is the one the estimation keeps
  if (drop_one) z <- z[!(z$id == 3 & z$k == 10), ]
  z[, c("id", "time", "g", "y")]
}
# First period 1.02 - eps (the double just below 1.02) or exactly 1.02, then
# 1.5, 2.02, 2.5; a never-treated group and cohort 2.02, 30 units each. Under
# anticipation(1), 2.02 > (1.02 - eps) + 1 holds and 2.02 > 1.02 + 1 does not.
make_guard <- function(ulp) {
  per <- c(if (ulp) 1.02 - .Machine$double.eps else 1.02, 1.5, 2.02, 2.5)
  z <- expand.grid(k = 1:4, id = 1:60)[, c("id", "k")]
  z$time <- per[z$k]
  z$g <- ifelse(z$id <= 30, 0, 2.02)
  z$y <- ((z$id * 5) %% 11) / 4 + z$k + ((z$id * z$k) %% 7 - 3) / 8 +
    ifelse(z$g > 0 & z$k >= 3, 1 + (z$k - 3) / 4, 0)
  z[, c("id", "time", "g", "y")]
}
# No never-treated group: units first treated in the first period and a
# cohort at 2000 + 8/12, which the fallback consumes as the comparison group,
# so no cohort is left to estimate.
make_latest <- function() {
  tm <- 2000 + (5:10) / 12
  z <- expand.grid(k = 1:6, id = 1:60)[, c("id", "k")]
  gk <- ifelse(z$id <= 30, 1L, 4L)
  z$time <- tm[z$k]
  z$g <- tm[gk]
  z$y <- ((z$id * 7) %% 11) / 4 + z$k / 6 + ((z$id * z$k) %% 7 - 3) / 8 + ifelse(z$k >= gk, 1, 0)
  z[, c("id", "time", "g", "y")]
}
data_for <- function(s) switch(s,
  month_double = make_month(), month_float = make_month(float = TRUE),
  month_unbalanced = make_month(drop_one = TRUE),
  guard_ulp = make_guard(TRUE), guard_exact = make_guard(FALSE), latest_only = make_latest())

inputs <- list(); attout <- list(); dynout <- list(); refout <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  z <- data_for(s$scenario)
  input <- file.path("inputs", paste0(s$scenario, ".csv"))
  e <- z
  for (v in c("time", "g", "y")) e[[v]] <- exact(e[[v]])
  write.csv(e, file.path(out, input), row.names = FALSE, quote = FALSE)
  inputs[[k]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z))
  controls <- if (s$control == "both") c("notyettreated", "nevertreated") else "notyettreated"
  for (cg in controls) {
    fit <- tryCatch(suppressWarnings(did::att_gt(
      yname = "y", tname = "time", idname = "id", gname = "g", data = z,
      control_group = cg, base_period = "universal", anticipation = s$anticipation,
      est_method = "reg", bstrap = FALSE, cband = FALSE)),
      error = function(err) conditionMessage(err))
    if (is.character(fit)) {
      refout[[length(refout) + 1L]] <- data.frame(scenario = s$scenario, control = cg, message = fit)
      next
    }
    attout[[length(attout) + 1L]] <- data.frame(scenario = s$scenario, control = cg,
      group = exact(fit$group), time = exact(fit$t), att = exact(fit$att), se = exact(fit$se))
    if (startsWith(s$scenario, "month")) {
      for (be in 0:1) {
        ag <- did::aggte(fit, type = "dynamic", balance_e = be, bstrap = FALSE, cband = FALSE)
        dynout[[length(dynout) + 1L]] <- data.frame(scenario = s$scenario, balance_e = be,
          egt = exact(ag$egt), att = exact(ag$att.egt), se = exact(ag$se.egt))
      }
    }
  }
}
write.csv(do.call(rbind, attout), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, quote = FALSE)
write.csv(do.call(rbind, dynout), file.path(out, "expected/r/dynamic.csv"), row.names = FALSE, quote = FALSE)
write.csv(do.call(rbind, refout), file.path(out, "expected/r/refusals.csv"), row.names = FALSE)
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE)
inputs[[length(inputs) + 1L]] <- list(path = "inputs/scenarios.csv", sha256 = sha(file.path(out, "inputs/scenarios.csv")), rows = nrow(scenarios), columns = ncol(scenarios))
outputs <- list(
  list(path = "expected/r/attgt.csv", schema = "attgt", sha256 = sha(file.path(out, "expected/r/attgt.csv"))),
  list(path = "expected/r/dynamic.csv", schema = "aggte-dynamic", sha256 = sha(file.path(out, "expected/r/dynamic.csv"))),
  list(path = "expected/r/refusals.csv", schema = "refusal-message", sha256 = sha(file.path(out, "expected/r/refusals.csv"))))
manifest <- list(matrix_id = "RT070", fixture_family = "r-decimal-axis-first-period",
  normative_source = "did 2.5.1 pre_process_did2.R:279 (glist > first_period + anticipation); compute.aggte.R:463 (eseq >= balance_e - t2orig(maxT) + t2orig(1))",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt070/generate.R", path = "tools/parity/generators/rt070/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "e(time_first) equals the first period exactly; csdid_stats dynamic, balance(0|1) event times (exact), effects and standard errors, from e() and from a saverif() file", expected = "expected/r/dynamic.csv", tolerance_id = "TOL001", key_columns = c("scenario", "balance_e", "egt")),
    list(actual = "the one-ulp first period estimates R's cells under both comparison groups", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "control", "group", "time")),
    list(actual = "the exact first period, and a latest cohort the no-never-treated fallback consumes, refuse with rc 459 under both comparison groups", expected = "expected/r/refusals.csv", tolerance_id = "EXACT", key_columns = c("scenario", "control"))),
  approved_divergence = NULL,
  scope_note = "A 24-period monthly axis 2000 + m/12 stored as double and as float (the Stata test recasts time() and gvar() to float; every value is float-representable), and the same axis with one unit short of a period under bal(full); a four-period axis whose first period is 1.02 - eps or exactly 1.02, cohort 2.02 under anticipation(1); a monthly axis with no never-treated group whose only usable cohort, 2000 + 8/12, is the latest.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT070 written:", nrow(do.call(rbind, attout)), "cells,", nrow(do.call(rbind, dynout)), "event-time rows,", length(refout), "refusals.\n")
