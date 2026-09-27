#!/usr/bin/env Rscript
# RT061: the warnings R raises, and their order, when fix_weights(base_period)
# or fix_weights(first_period) excludes units on an unbalanced panel. R judges
# a cell's validity on the rows before the exclusion (valid_did_cohort,
# compute.att_gt2.R:463-468), then drops the units the target period does not
# observe and announces it (:534-577, the warning at :570), then raises its
# four corner warnings on the rows that are left, with no validity test
# (run_DRDID, :267-284). A cell whose corner is empty before the exclusion
# therefore still gets the exclusion line and the corners the exclusion adds.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt061/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt061")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

outcome <- function(z) (z$id %% 5) / 4 + 0.5 * z$t + ifelse(z$g > 0 & z$t >= z$g, 1 + (z$t - z$g) / 2, 0) +
  ((z$id * z$t) %% 7 - 3) / 8
# Five periods. Never-treated ids 1-8 and cohort 3 (ids 11-16) complete except
# where a shape removes rows; cohort 4 is ids 21-26.
panel <- function(drop) {
  z <- expand.grid(i = 1:8, t = 1:5, g = c(0, 3, 4))
  z$id <- z$i + c(0, 10, 20)[match(z$g, c(0, 3, 4))]
  z <- z[!(z$g > 0 & z$i > 6), ]
  z$y <- outcome(z)
  z <- z[!drop(z), c("id", "t", "g", "y")]
  z <- z[order(z$id, z$t), ]
  rownames(z) <- NULL
  z
}
# treated-gaps: cohort 3 is never observed in period 1, the first period;
# cohort 4 is never observed in period 3, its base period.
treated <- panel(function(z) (z$g == 3 & z$t == 1) | (z$g == 4 & z$t == 3))
# control-gaps: no never-treated unit is observed in period 1, and three cohort-4
# units are not either.
control <- panel(function(z) (z$g == 0 & z$t == 1) | (z$id %in% 21:23 & z$t == 1))
write.csv(treated, file.path(out, "inputs/treated-gaps.csv"), row.names = FALSE)
write.csv(control, file.path(out, "inputs/control-gaps.csv"), row.names = FALSE)

scenarios <- data.frame(
  scenario = c("treated-first", "treated-base", "treated-first-dr", "treated-unset", "control-first", "control-base"),
  data = c("treated-gaps", "treated-gaps", "treated-gaps", "treated-gaps", "control-gaps", "control-gaps"),
  fix_weights = c("first_period", "base_period", "first_period", "", "first_period", "base_period"),
  method = c("reg", "reg", "dr", "reg", "reg", "reg"), stringsAsFactors = FALSE)
families <- "^No units in group|^No available control units|^Some units not observed in"
warn_rows <- list(); att_rows <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  d <- if (s$data == "treated-gaps") treated else control
  w <- character(0)
  a <- withCallingHandlers(did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g", data = d,
      panel = TRUE, allow_unbalanced_panel = TRUE, control_group = "nevertreated",
      base_period = "universal", est_method = s$method,
      fix_weights = if (nzchar(s$fix_weights)) s$fix_weights else NULL,
      bstrap = FALSE, cband = FALSE),
    warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
  w <- w[grepl(families, w)]
  warn_rows[[k]] <- data.frame(scenario = rep(s$scenario, length(w)), seq = seq_along(w), message = w)
  att_rows[[k]] <- data.frame(scenario = s$scenario, group = a$group, time = a$t, att = a$att, se = a$se)
}
write.csv(do.call(rbind, warn_rows), file.path(out, "expected/r/warnings.csv"), row.names = FALSE)
write.csv(do.call(rbind, att_rows), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE)
inputs <- lapply(c("inputs/treated-gaps.csv", "inputs/control-gaps.csv", "inputs/scenarios.csv"), function(p)
  list(path = p, sha256 = sha(file.path(out, p))))
outputs <- lapply(c("warnings.csv", "attgt.csv"), function(nm)
  list(path = paste0("expected/r/", nm), schema = if (nm == "attgt.csv") "attgt" else "warning-sequence",
       sha256 = sha(file.path(out, "expected/r", nm))))
manifest <- list(matrix_id = "RT061", fixture_family = "r-fixweights-exclusion-warnings",
  normative_source = "did 2.5.1 compute.att_gt2.R:463-468 (valid_did_cohort on the rows before the exclusion), :534-577 (fix_weights exclusion and its warning) and run_DRDID :267-284 (the four corner warnings on the rows after it, ungated)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt061/generate.R", path = "tools/parity/generators/rt061/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "the exclusion and corner warnings csdid prints, in order", expected = "expected/r/warnings.csv", tolerance_id = "EXACT", key_columns = c("scenario", "seq")),
    list(actual = "Stata ATT(g,t) and standard errors", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "group", "time"))),
  approved_divergence = NULL,
  scope_note = "Unbalanced panels under bal(none) with a treated cohort, or the whole comparison group, missing the fix_weights target period; reg and dr; one scenario without fix_weights as the unchanged control.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT061 written\n")
