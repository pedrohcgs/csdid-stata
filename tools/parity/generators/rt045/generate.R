#!/usr/bin/env Rscript
# RT045: refusals decided on the settled sample.
# With no never-treated units, the latest cohort supplies comparisons and
# periods from its treatment date net of anticipation are removed. The
# settled sample can then have a comparison cohort below the size guard,
# no remaining treated cohort, or only one period. The current reference
# refuses the one-period case under both base-period conventions.
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
# After first-period treatment removal, balancing removes the only remaining
# never-treated unit. Rechecking comparison availability consumes the last
# cohort and leaves no treated group, rather than a one-unit fit.
designs$postbalance_empty <- data.frame(
  id = c(2,1,4,4,3,2,2,1), t = c(2,6,2,3,3,3,6,4),
  g = c(6,3,3,3,0,6,6,3))
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
  sc("no_cells_universal", "no_cells", TRUE, FALSE, "notyettreated", "universal", 1L, "ivar(id) time(t) gvar(g) notyet base_period(universal) anticipation(1)"),
  sc("postbalance_empty", "postbalance_empty", TRUE, FALSE, "notyettreated", "universal", 1L, "ivar(id) time(t) gvar(g) notyet base_period(universal) anticipation(1)"))
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
  normative_source = "did 2.5.1.904 pre_process_did2.R: no-never fallback, settled cohort/period availability, and minimum comparison-group size",
  source_commit = "48863b646e657f2aaa5cc9e9d2e7b9d764a6a44e", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt045/generate.R", path = "tools/parity/generators/rt045/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(list(actual = "Stata return code, named refusal reason and absence of internal frames for all thirteen settled-sample cases", expected = c("expected/r/estimation_status.csv", "expected/r/attgt.csv"), tolerance_id = "TOL001", key_columns = c("scenario"))),
  approved_divergence = NULL,
  scope_note = "Refusals R reaches only after the no-never-treated period cut: a coerced latest cohort too small (repeated cross sections, unbalanced and balanced panels), an empty cohort list (three sample modes, both comparison groups), and a single surviving period under either base convention, and balancing that removes the only never-treated unit after the first-period trim. R's fast and slow routes agree on every verdict.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT045 written:", nrow(scenarios), "scenarios.\n")
