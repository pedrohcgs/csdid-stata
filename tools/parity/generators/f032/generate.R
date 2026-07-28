#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f032/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f032")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:60
times <- 1:5
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 18, 3, ifelse(d$id <= 38, 4, ifelse(d$id <= 48, 5, 0)))
d$x1 <- 0.10 * d$time + 0.20 * sin(0.25 * d$id)
d$x2 <- 0.15 * cos(0.30 * d$id) + 0.03 * d$time
d$y0 <- 0.8 + 0.37 * d$time + 0.08 * (d$id %% 7) +
  0.05 * sin(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g,
               0.65 + 0.11 * (d$time - d$g) + 0.02 * d$g,
               0)
d$w <- 1 + 0.02 * (d$id %% 5) + 0.01 * d$time
d$cl <- 1 + (d$id %% 10)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

shuffled <- d[order((d$id * 37 + d$time * 101) %% 997, d$time, d$id), ]
write.csv(shuffled, file.path(fixture, "inputs/input-shuffled.csv"), row.names = FALSE, na = "")

unbalanced <- d[!(d$id %% 11 == 0 & d$time %in% c(2, 5)), ]
write.csv(unbalanced, file.path(fixture, "inputs/input-unbalanced.csv"), row.names = FALSE, na = "")

mp <- att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "varying"
)

attgt <- data.frame(
  group = mp$group,
  time = mp$t,
  event_time = mp$t - mp$group,
  att = mp$att,
  se = mp$se,
  inffunc_col = seq_along(mp$att)
)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")

agg_rows <- list()
for (type in c("simple", "group", "calendar", "dynamic")) {
  agg <- suppressWarnings(aggte(mp, type = type, bstrap = FALSE, cband = FALSE))
  if (type == "simple") {
    out <- data.frame(
      type = type,
      egt = NA_real_,
      att = agg$overall.att,
      se = agg$overall.se,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  }
  else {
    out <- data.frame(
      type = type,
      egt = agg$egt,
      att = agg$att.egt,
      se = agg$se.egt,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  }
  agg_rows[[type]] <- out
}
aggte <- do.call(rbind, agg_rows)
write.csv(aggte, file.path(fixture, "expected/r/aggte.csv"), row.names = FALSE, na = "")

option_rows <- list()
idx <- 1
for (control_group in c("nevertreated", "notyettreated")) {
  for (base_period in c("varying", "universal")) {
    opt <- att_gt(
      yname = "y",
      tname = "time",
      idname = "id",
      gname = "g",
      data = d,
      panel = TRUE,
      control_group = control_group,
      bstrap = FALSE,
      cband = FALSE,
      est_method = "reg",
      base_period = base_period
    )
    option_rows[[idx]] <- data.frame(
      control_group = control_group,
      base_period = base_period,
      group = opt$group,
      time = opt$t,
      event_time = opt$t - opt$group,
      att = opt$att,
      se = opt$se,
      inffunc_col = seq_along(opt$att),
      stringsAsFactors = FALSE
    )
    idx <- idx + 1
  }
}
fast_option_grid <- do.call(rbind, option_rows)
write.csv(fast_option_grid, file.path(fixture, "expected/r/fast-option-grid.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F032",
  fixture_family = "optimized-path-equivalence",
  normative_source = "R did 2.5.1 plus Stata baseline/fast equivalence",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D009"),
  tolerance_ids = c("TOL002"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/input-shuffled.csv", rows = nrow(shuffled), columns = ncol(shuffled)),
    list(path = "inputs/input-unbalanced.csv", rows = nrow(unbalanced), columns = ncol(unbalanced))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f032/generate.R", path = "tools/parity/generators/f032/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/aggte.csv", schema = "aggte-all-types"),
    list(path = "expected/r/fast-option-grid.csv", schema = "attgt-fast-option-grid")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/baseline-attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("group", "time")),
    list(actual = "expected/new-stata/fast-attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("group", "time")),
    list(actual = "expected/new-stata/fast-shuffled-attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("group", "time")),
    list(actual = "expected/new-stata/fast-clustered-vs-baseline.csv", expected = "live clustered baseline", tolerance_id = "TOL002", key_columns = c("group", "time")),
    list(actual = "expected/new-stata/fast-all-surface-grid.csv", expected = "live nofast comparison grid", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "expected/new-stata/fast-vs-baseline-if-summary.csv", expected = "live baseline summaries", tolerance_id = "TOL002", key_columns = c("group", "time", "inffunc_col")),
    list(actual = "expected/new-stata/fast-vs-baseline-aggte.csv", expected = "expected/r/aggte.csv", tolerance_id = "TOL002", key_columns = c("type", "egt")),
    list(actual = "expected/new-stata/fast-option-grid.csv", expected = "expected/r/fast-option-grid.csv", tolerance_id = "TOL002", key_columns = c("control_group", "base_period", "group", "time"))
  ),
  approved_divergence = NULL,
  scope_note = "F032 optimized-path equivalence fixture covers fast/nofast equivalence across balanced panels, repeated cross sections, allow_unbalanced routing, dr/reg/ipw, covariates, weights, fix_weights, clustered analytical SEs, bootstrap smoke, influence-function summaries, Gram matrix, row-order invariance, simple/group/calendar/dynamic aggregations, and nevertreated/notyettreated by varying/universal base-period option grids. Default fast(auto) and explicit fast now report fast_used=1 for every supported public surface; explicit nofast is the baseline/debug path. Broader inherited R faster_mode and Python fast-path grids remain tracked by RT012, RT025, RT027, and PY009 rows."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
