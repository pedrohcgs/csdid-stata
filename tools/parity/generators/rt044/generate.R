#!/usr/bin/env Rscript
# RT044: bal(full) with no never-treated units keeps R's single fold.
# R folds cohorts beyond the last period (plus anticipation) into the
# never-treated group once, on the calendar before any row is dropped
# (pre_process_did2.R:207-214). With no never-treated units it then coerces the
# latest cohort and removes the periods from its date on (:246-265), and only
# after that balances the panel (:356-384). Here the last period is held only
# by two units of the latest cohort, which the period filter removes; a fold
# re-read from the shortened calendar would turn the treated cohorts dated
# after it into comparison units.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt044/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt044")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

# Periods 1-3 for every unit, plus a period 6 observed only for two units of
# the latest cohort (5). "two" has cohorts 4 and 5; "three" adds cohort 3.
make_data <- function(cohorts) {
  n <- 10L * length(cohorts)
  d <- expand.grid(time = 1:3, id = seq_len(n))[, c("id", "time")]
  d$g <- rep(cohorts, each = 10L)[d$id]
  d <- rbind(d, data.frame(id = n + 1:2, time = 6, g = 5))
  d$x <- ((d$id * 5) %% 9) / 8
  d$y <- ((d$id * 7 + d$time * 3) %% 11) / 8 + d$time + d$x * d$time / 4 +
    (d$time >= d$g) + (d$g == 4) * d$time / 2
  d <- d[order(d$id, d$time), c("id", "time", "g", "x", "y")]
  rownames(d) <- NULL
  d
}
designs <- list(two = make_data(c(4, 5)), three = make_data(c(3, 4, 5)))
scenarios <- data.frame(
  scenario = c("two_varying_reg", "two_universal_reg", "three_varying_reg", "three_universal_reg", "three_universal_dr"),
  design = c("two", "two", "three", "three", "three"),
  base_period = c("varying", "universal", "varying", "universal", "universal"),
  method = c("reg", "reg", "reg", "reg", "dr"),
  stringsAsFactors = FALSE)

inputs <- list()
for (nm in names(designs)) {
  input <- file.path("inputs", paste0(nm, ".csv"))
  write.csv(designs[[nm]], file.path(out, input), row.names = FALSE)
  inputs[[length(inputs) + 1L]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(designs[[nm]]), columns = ncol(designs[[nm]]))
}
attout <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  run <- function(fast) {
    warned <- FALSE
    a <- withCallingHandlers(did::att_gt(
      yname = "y", tname = "time", idname = "id", gname = "g", data = designs[[s$design]],
      xformla = if (s$method == "dr") ~x else NULL, control_group = "nevertreated",
      base_period = s$base_period, est_method = s$method, bstrap = FALSE, cband = FALSE,
      faster_mode = fast),
      warning = function(w) {
        if (grepl("No never-treated group is available", conditionMessage(w), fixed = TRUE)) warned <<- TRUE
        invokeRestart("muffleWarning")
      })
    stopifnot(warned)
    a
  }
  a <- run(TRUE)
  slow <- run(FALSE)
  stopifnot(identical(a$group, slow$group), identical(a$t, slow$t),
    all(abs(a$att - slow$att) <= 1e-10 * (1 + abs(a$att)), na.rm = TRUE),
    identical(is.na(a$se), is.na(slow$se)))
  attout[[k]] <- data.frame(scenario = s$scenario, group = a$group, time = a$t,
    att = a$att, se = a$se, n_units = a$n)
}
write.csv(do.call(rbind, attout), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE)
inputs[[length(inputs) + 1L]] <- list(path = "inputs/scenarios.csv", sha256 = sha(file.path(out, "inputs/scenarios.csv")), rows = nrow(scenarios), columns = ncol(scenarios))
outputs <- list(list(path = "expected/r/attgt.csv", schema = "attgt", sha256 = sha(file.path(out, "expected/r/attgt.csv"))))
manifest <- list(matrix_id = "RT044", fixture_family = "r-single-fold-before-balance",
  normative_source = "did 2.5.1 pre_process_did2.R:207-214 (as-if-never fold on the raw period list), :246-265 (latest cohort coerced, periods from its date removed), :356-384 (balancing afterwards)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt044/generate.R", path = "tools/parity/generators/rt044/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "Stata ATT(g,t), standard errors and unit count under nevertreated bal(full)", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "group", "time"))),
  approved_divergence = NULL,
  scope_note = "No never-treated units; a last period held only by two latest-cohort units that the no-never period filter removes. Both bases, reg and dr with a covariate; R's fast and slow paths agree and both warn that the latest cohort becomes the comparison group.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT044 written:", nrow(do.call(rbind, attout)), "cells.\n")
