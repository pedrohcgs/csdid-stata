#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f037/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f037")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:90
times <- 1:5
d <- expand.grid(id = ids, period = times)
d <- d[order(d$id, d$period), ]
unit_g <- ifelse(ids <= 28, 3, ifelse(ids <= 56, 4, ifelse(ids <= 72, 5, 0)))
unit_x <- 0.7 * sin(ids * 0.31) + 0.2 * (ids %% 4 == 0)
d$G <- rep(unit_g, each = length(times))
d$X <- rep(unit_x, each = length(times))
d$Y0 <- 1.2 + 0.35 * d$period + 0.30 * d$X +
  0.05 * cos(d$id + d$period) + 0.04 * (d$id %% 6)
d$TE <- ifelse(d$G > 0 & d$period >= d$G,
               0.75 + 0.12 * (d$period - d$G) + 0.03 * d$G,
               0)
d$Y <- d$Y0 + d$TE
d$Y0 <- NULL
d$TE <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

scenario_specs <- list()
for (em in c("dr", "reg", "ipw")) {
  for (cg in c("nevertreated", "notyettreated")) {
    for (bp in c("varying", "universal")) {
      scenario_specs[[paste("combo_a", em, cg, bp, sep = "__")]] <- list(
        family = "method-control-base",
        method = em, control_group = cg, base_period = bp,
        panel = TRUE, anticipation = 0L, agg_type = "simple"
      )
    }
  }
}
for (em in c("dr", "reg", "ipw")) {
  for (panel in c(TRUE, FALSE)) {
    scenario_specs[[paste("combo_b", em, ifelse(panel, "panel", "rc"), sep = "__")]] <- list(
      family = "method-panel",
      method = em, control_group = "nevertreated", base_period = "varying",
      panel = panel, anticipation = 0L, agg_type = "dynamic"
    )
  }
}
for (em in c("dr", "reg", "ipw")) {
  for (ant in c(0L, 1L)) {
    scenario_specs[[paste("combo_c", em, paste0("ant", ant), sep = "__")]] <- list(
      family = "method-anticipation",
      method = em, control_group = "nevertreated", base_period = "varying",
      panel = TRUE, anticipation = ant, agg_type = "simple"
    )
  }
}
for (em in c("dr", "reg", "ipw")) {
  for (agg_type in c("simple", "dynamic", "group", "calendar")) {
    scenario_specs[[paste("combo_f", em, agg_type, sep = "__")]] <- list(
      family = "method-aggte",
      method = em, control_group = "nevertreated", base_period = "varying",
      panel = TRUE, anticipation = 0L, agg_type = agg_type
    )
  }
}

agg_to_df <- function(scenario, type, agg) {
  if (type == "simple") {
    out <- data.frame(
      scenario = scenario,
      type = type,
      egt = NA_real_,
      att = agg$overall.att,
      se = agg$overall.se,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  } else {
    out <- data.frame(
      scenario = scenario,
      type = type,
      egt = agg$egt,
      att = agg$att.egt,
      se = agg$se.egt,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  }
  out$seq <- seq_len(nrow(out))
  out
}

att_rows <- list()
agg_rows <- list()
scenario_rows <- list()
for (scenario in names(scenario_specs)) {
  spec <- scenario_specs[[scenario]]
  call_args <- list(
    yname = "Y",
    tname = "period",
    gname = "G",
    data = d,
    panel = spec$panel,
    xformla = ~ X,
    control_group = spec$control_group,
    bstrap = FALSE,
    cband = FALSE,
    est_method = spec$method,
    base_period = spec$base_period,
    anticipation = spec$anticipation
  )
  if (spec$panel) call_args$idname <- "id"
  mp <- suppressWarnings(do.call(att_gt, call_args))
  att_rows[[scenario]] <- data.frame(
    scenario = scenario,
    group = mp$group,
    time = mp$t,
    event_time = mp$t - mp$group,
    att = mp$att,
    se = mp$se,
    inffunc_col = seq_along(mp$att)
  )
  agg <- suppressWarnings(aggte(mp, type = spec$agg_type, bstrap = FALSE, cband = FALSE, na.rm = TRUE))
  agg_rows[[scenario]] <- agg_to_df(scenario, spec$agg_type, agg)
  scenario_rows[[scenario]] <- data.frame(
    scenario = scenario,
    family = spec$family,
    method = spec$method,
    control_group = spec$control_group,
    base_period = spec$base_period,
    panel = spec$panel,
    anticipation = spec$anticipation,
    agg_type = spec$agg_type
  )
}

attgt <- do.call(rbind, att_rows)
aggte <- do.call(rbind, agg_rows)
scenarios <- do.call(rbind, scenario_rows)

write.csv(scenarios, file.path(fixture, "expected/r/scenarios.csv"), row.names = FALSE, na = "")
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(aggte, file.path(fixture, "expected/r/aggte.csv"), row.names = FALSE, na = "")

divergence <- data.frame(
  divergence_id = "F037-DIV001",
  surface = "python-deep-parametric-grid-residuals",
  reason = "The F037 fixture freezes the R-anchored analytical combination grid for method/control/base, method/panel, method/anticipation, and method/aggregation axes. Python-only stochastic bootstrap combinations and exhaustive integration-grid expansion are inherited surfaces already tracked by PY017/PY003-style gates rather than this compact R-anchored feature row.",
  accepted_behavior = "Stata must match R did 2.5.1 ATT(g,t) and aggregation values for the frozen analytical grid; broader Python parameterization inheritance remains covered by PY017 and related Python gates.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "F037",
  fixture_family = "python-parametric-combinations",
  normative_source = "Python csdid test_parametric_combinations.py deep grid, anchored to R did 2.5.1 expected values",
  source_commit = "0a96e5e21e880cbbc703b8ff77bee8b207debc2a5ff9865b86e37ee45c123028",
  decision_refs = c("D001", "D004"),
  tolerance_ids = c("TOL001", "TOL002"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f037/generate.R", path = "tools/parity/generators/f037/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/scenarios.csv", schema = "parametric-scenarios"),
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/aggte.csv", schema = "aggte"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "expected/new-stata/aggte.csv", expected = "expected/r/aggte.csv", tolerance_id = "TOL002", key_columns = c("scenario", "type", "seq"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "Approved-divergence F037/PY017 parametric-combination evidence for method x control-group x base-period, method x panel, method x anticipation, and method x aggte-type analytical grids with one numeric covariate. F037-DIV001 records that Python-only stochastic bootstrap combinations and exhaustive integration-grid expansion are inherited surfaces covered by PY017/PY003-style gates rather than this compact R-anchored feature row."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
