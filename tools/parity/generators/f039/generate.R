#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f039/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f039")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

set.seed(9142024)
n_units <- 180
times <- 1:4
ids <- seq_len(n_units)
unit_g <- rep(c(0, 3, 4), each = n_units / 3)
unit_x <- rnorm(n_units)
unit_alpha <- rnorm(n_units, sd = 0.30)
cluster <- (ids %% 10) + 1

d <- do.call(rbind, lapply(times, function(period) {
  eps <- rnorm(n_units, sd = 0.55)
  treated <- unit_g > 0 & period >= unit_g
  data.frame(
    id = ids,
    period = period,
    G = unit_g,
    Y = unit_alpha + 0.30 * unit_x + 0.10 * period + eps + ifelse(treated, 1.0, 0),
    X = unit_x,
    cluster = cluster
  )
}))
d <- d[order(d$id, d$period), ]
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

scenario_specs <- list()
for (panel_mode in c("panel", "repeated-cross-section")) {
  for (method in c("dr", "reg", "ipw")) {
    scenario <- paste(panel_mode, method, sep = "__")
    scenario_specs[[scenario]] <- list(panel = panel_mode == "panel", method = method)
  }
}

agg_to_df <- function(scenario, method, panel_mode, agg_type, agg) {
  if (agg_type == "simple") {
    out <- data.frame(
      scenario = scenario,
      method = method,
      panel_mode = panel_mode,
      agg_type = agg_type,
      egt = NA_real_,
      att = agg$overall.att,
      se = agg$overall.se,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  } else {
    out <- data.frame(
      scenario = scenario,
      method = method,
      panel_mode = panel_mode,
      agg_type = agg_type,
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

summarize_dimensions <- function(scenario, method, panel_mode, out) {
  inf <- as.matrix(out$inffunc)
  data.frame(
    scenario = scenario,
    method = method,
    panel_mode = panel_mode,
    n_inffunc_rows = nrow(inf),
    n_inffunc_cols = ncol(inf),
    n_att = length(out$att),
    n_obs = nrow(d),
    positive_finite_se_count = sum(is.finite(out$se) & out$se > 0),
    finite_att_count = sum(is.finite(out$att)),
    nonzero_if_count = sum(abs(inf) > 1e-12, na.rm = TRUE),
    all_finite_if = as.integer(all(is.finite(inf)))
  )
}

att_rows <- list()
agg_rows <- list()
dimension_rows <- list()
scenario_rows <- list()

for (scenario in names(scenario_specs)) {
  spec <- scenario_specs[[scenario]]
  panel_mode <- ifelse(spec$panel, "panel", "repeated-cross-section")
  call_args <- list(
    yname = "Y",
    tname = "period",
    gname = "G",
    xformla = ~ X,
    data = d,
    panel = spec$panel,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = spec$method,
    base_period = "varying"
  )
  if (spec$panel) call_args$idname <- "id"

  mp <- suppressWarnings(do.call(att_gt, call_args))
  att_rows[[scenario]] <- data.frame(
    scenario = scenario,
    method = spec$method,
    panel_mode = panel_mode,
    group = mp$group,
    time = mp$t,
    event_time = mp$t - mp$group,
    att = mp$att,
    se = mp$se,
    inffunc_col = seq_along(mp$att)
  )
  dimension_rows[[scenario]] <- summarize_dimensions(scenario, spec$method, panel_mode, mp)
  scenario_rows[[scenario]] <- data.frame(
    scenario = scenario,
    method = spec$method,
    panel_mode = panel_mode,
    panel = spec$panel,
    control_group = "nevertreated",
    base_period = "varying",
    xformla = "~ X",
    bstrap = FALSE,
    cband = FALSE
  )

  for (agg_type in c("simple", "dynamic", "group", "calendar")) {
    agg <- suppressWarnings(aggte(mp, type = agg_type, bstrap = FALSE, cband = FALSE, na.rm = TRUE))
    agg_rows[[paste(scenario, agg_type, sep = "::")]] <- agg_to_df(
      scenario,
      spec$method,
      panel_mode,
      agg_type,
      agg
    )
  }
}

attgt <- do.call(rbind, att_rows)
aggte <- do.call(rbind, agg_rows)
dimensions <- do.call(rbind, dimension_rows)
scenarios <- do.call(rbind, scenario_rows)

write.csv(scenarios, file.path(fixture, "expected/r/scenarios.csv"), row.names = FALSE, na = "")
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(aggte, file.path(fixture, "expected/r/aggte.csv"), row.names = FALSE, na = "")
write.csv(dimensions, file.path(fixture, "expected/r/inference-dimensions.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F039",
  fixture_family = "python-inference-inheritance",
  normative_source = "Python csdid test_inference.py deeper inference checks, anchored to R did 2.5.1 expected values",
  source_commit = "0a96e5e21e880cbbc703b8ff77bee8b207debc2a5ff9865b86e37ee45c123028",
  decision_refs = c("D001", "D004", "D014"),
  tolerance_ids = c("TOL002"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f039/generate.R", path = "tools/parity/generators/f039/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 9142024),
  expected_outputs = list(
    list(path = "expected/r/scenarios.csv", schema = "inference-scenarios"),
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/aggte.csv", schema = "aggte"),
    list(path = "expected/r/inference-dimensions.csv", schema = "inference-dimensions")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "expected/new-stata/aggte.csv", expected = "expected/r/aggte.csv", tolerance_id = "TOL002", key_columns = c("scenario", "agg_type", "seq")),
    list(actual = "expected/new-stata/inference-dimensions.csv", expected = "expected/r/inference-dimensions.csv", tolerance_id = "EXACT", key_columns = c("scenario"))
  ),
  approved_divergence = NULL,
  scope_note = "Partial F039/Python test_inference.py inheritance for analytical panel and true repeated-cross-section inference across dr/reg/ipw with one numeric covariate. It checks finite positive ATT(g,t) SEs, influence-function dimensions, and simple/dynamic/group/calendar aggregation SE parity against R did 2.5.1. PY012 covers unclustered bootstrap-vs-analytical rough agreement, and PY002/PY004/PY005/PY015/F014/F035 cover inherited Python clustered inference smoke."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
