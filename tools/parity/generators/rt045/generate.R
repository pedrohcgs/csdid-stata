#!/usr/bin/env Rscript
# RT045: refusals decided on the settled sample.
# With no never-treated units R coerces the latest cohort to never-treated and
# removes the periods from its date on (pre_process_did2.R:246-265); it then
# recomputes the cohort list and stops when it is empty (:405-407), measures
# the coerced group as rows over the remaining periods and stops when it is
# below reqsize (:433-452), and stops when no (g,t) cell can be formed
# (compute.att_gt2.R:782-785). Each refusal here is decided on a sample the
# pre-estimation scan does not see.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt045/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt045")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
outcome <- function(d) ((d$id * 7 + d$t * 3) %% 11) / 8 + d$t + (d$t >= d$g)

designs <- list()
# latest cohort (4) small: 3 rows per period on repeated cross sections
r <- do.call(rbind, lapply(1:4, function(t) data.frame(t = t, g = rep(c(2, 3, 4), c(20, 20, 3)))))
r$id <- seq_len(nrow(r)); designs$small_latest_rcs <- r
# the same on an unbalanced panel: six cohort-4 units, each missing one or two
# periods (ids 41 and 44 miss two)
p <- expand.grid(t = 1:4, id = 1:46)
p$g <- ifelse(p$id <= 20, 2, ifelse(p$id <= 40, 3, 4))
designs$small_latest_unbal <- p[!(p$g == 4 & ((p$id + p$t) %% 3 == 0)), ]
# and on a balanced panel: three cohort-4 units
b <- expand.grid(t = 1:4, id = 1:43)
b$g <- ifelse(b$id <= 20, 2, ifelse(b$id <= 40, 3, 4)); designs$small_latest_bal <- b
# cohort 2 seen only in period 3, which the fallback removes: no cohort left
e <- expand.grid(t = 1:3, id = 1:20); e$g <- 3
designs$empty_cohorts <- rbind(e, data.frame(t = 3, id = 21:25, g = 2))
# periods 1, 3, 4 with anticipation(1): the varying base forms no cell
n <- expand.grid(t = c(1, 3, 4), id = 1:40); n$g <- ifelse(n$id <= 20, 3, 4)
designs$no_cells <- n
for (nm in names(designs)) {
  d <- designs[[nm]]
  d$y <- outcome(d)
  d <- d[order(d$id, d$t), c("id", "t", "g", "y")]
  rownames(d) <- NULL
  designs[[nm]] <- d
}

sc <- function(scenario, design, panel, unbalanced, control, base = "universal", anticipation = 0L, stata) {
  data.frame(scenario, design, panel, unbalanced, control, base, anticipation, stata_options = stata, stringsAsFactors = FALSE)
}
scenarios <- rbind(
  sc("small_latest_rcs", "small_latest_rcs", FALSE, FALSE, "nevertreated", stata = "time(t) gvar(g) nevertreated"),
  sc("small_latest_unbal", "small_latest_unbal", TRUE, TRUE, "nevertreated", stata = "ivar(id) time(t) gvar(g) bal(none) nevertreated"),
  sc("small_latest_bal", "small_latest_bal", TRUE, FALSE, "nevertreated", stata = "ivar(id) time(t) gvar(g) nevertreated"),
  sc("empty_cohorts_rcs_notyet", "empty_cohorts", FALSE, FALSE, "notyettreated", stata = "time(t) gvar(g) notyet"),
  sc("empty_cohorts_rcs_never", "empty_cohorts", FALSE, FALSE, "nevertreated", stata = "time(t) gvar(g) nevertreated"),
  sc("empty_cohorts_none_notyet", "empty_cohorts", TRUE, TRUE, "notyettreated", stata = "ivar(id) time(t) gvar(g) bal(none) notyet"),
  sc("empty_cohorts_none_never", "empty_cohorts", TRUE, TRUE, "nevertreated", stata = "ivar(id) time(t) gvar(g) bal(none) nevertreated"),
  sc("empty_cohorts_full_notyet", "empty_cohorts", TRUE, FALSE, "notyettreated", stata = "ivar(id) time(t) gvar(g) notyet"),
  sc("empty_cohorts_full_never", "empty_cohorts", TRUE, FALSE, "nevertreated", stata = "ivar(id) time(t) gvar(g) nevertreated"),
  sc("no_cells_notyet", "no_cells", TRUE, FALSE, "notyettreated", "varying", 1L, "ivar(id) time(t) gvar(g) notyet base_period(varying) anticipation(1)"),
  sc("no_cells_never", "no_cells", TRUE, FALSE, "nevertreated", "varying", 1L, "ivar(id) time(t) gvar(g) nevertreated base_period(varying) anticipation(1)"),
  sc("no_cells_universal", "no_cells", TRUE, FALSE, "notyettreated", "universal", 1L, "ivar(id) time(t) gvar(g) notyet base_period(universal) anticipation(1)"))
scenarios$stata_options <- ifelse(grepl("base_period", scenarios$stata_options), scenarios$stata_options,
  paste0(scenarios$stata_options, " base_period(", scenarios$base, ")"))

inputs <- list()
for (nm in names(designs)) {
  input <- file.path("inputs", paste0(nm, ".csv"))
  write.csv(designs[[nm]], file.path(out, input), row.names = FALSE)
  inputs[[length(inputs) + 1L]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(designs[[nm]]), columns = 4L)
}
status <- attout <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  msgs <- character(0)
  for (fast in c(TRUE, FALSE)) {
    a <- tryCatch(suppressMessages(suppressWarnings(did::att_gt(
      yname = "y", tname = "t", idname = if (s$panel) "id" else NULL, gname = "g",
      data = designs[[s$design]], panel = s$panel, allow_unbalanced_panel = s$unbalanced,
      control_group = s$control, base_period = s$base, anticipation = s$anticipation,
      est_method = "reg", bstrap = FALSE, cband = FALSE, faster_mode = fast))),
      error = function(e) e)
    msgs <- c(msgs, if (inherits(a, "error")) conditionMessage(a) else "")
    if (fast && !inherits(a, "error")) attout[[length(attout) + 1L]] <- data.frame(
      scenario = s$scenario, group = a$group, time = a$t, att = a$att, se = a$se)
  }
  # the default (fast) route is normative; the slow route must also stop
  stopifnot((msgs[1] == "") == (msgs[2] == ""))
  status[[k]] <- data.frame(scenario = s$scenario, refused = as.integer(msgs[1] != ""), message = msgs[1])
}
write.csv(do.call(rbind, status), file.path(out, "expected/r/estimation_status.csv"), row.names = FALSE)
write.csv(do.call(rbind, attout), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE)
inputs[[length(inputs) + 1L]] <- list(path = "inputs/scenarios.csv", sha256 = sha(file.path(out, "inputs/scenarios.csv")), rows = nrow(scenarios), columns = ncol(scenarios))
outputs <- lapply(c("estimation_status", "attgt"), function(nm) list(path = paste0("expected/r/", nm, ".csv"), schema = nm, sha256 = sha(file.path(out, "expected/r", paste0(nm, ".csv")))))
manifest <- list(matrix_id = "RT045", fixture_family = "r-settled-sample-refusals",
  normative_source = "did 2.5.1 pre_process_did2.R:246-265 (latest cohort coerced, periods cut), :419-421 (No valid groups), :433-452 (never-treated group too small), compute.att_gt2.R:782-785 (no valid (g, t) cells)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt045/generate.R", path = "tools/parity/generators/rt045/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(list(actual = "Stata return code, refusal message and the absence of internal frames; cells of the one estimable scenario", expected = c("expected/r/estimation_status.csv", "expected/r/attgt.csv"), tolerance_id = "TOL001", key_columns = c("scenario"))),
  approved_divergence = NULL,
  scope_note = "Refusals R reaches only after the no-never-treated period cut: a coerced latest cohort too small (repeated cross sections, unbalanced and balanced panels), an empty cohort list (three sample modes, both comparison groups), and an empty cell grid under the varying base; the universal base of the last design estimates. R's fast and slow routes agree on every verdict.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT045 written:", nrow(scenarios), "scenarios.\n")
