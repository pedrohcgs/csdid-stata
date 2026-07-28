#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f015/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f015")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:48
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 16, 3, ifelse(d$id <= 32, 4, 0))
d$cl <- ((d$id - 1) %% 8) + 1
d$cl_bad <- d$cl
d$cl_bad[d$id == 7 & d$time == 4] <- 99
d$x1 <- 0.30 * d$time + 0.20 * sin(0.4 * d$id) + 0.08 * (d$cl %% 2 == 0)
d$x2 <- 0.15 * d$time + 0.25 * cos(0.6 * d$id) - 0.05 * (d$cl %% 3 == 0)
d$cluster_shock <- 0.12 * sin(d$cl)
d$y0 <- 1.2 + 0.45 * d$time + 0.30 * d$x1 - 0.18 * d$x2 + d$cluster_shock + 0.04 * cos(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.8 + 0.10 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
d$cluster_shock <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

scenario_specs <- list(
  panel_reg_cluster = list(panel = TRUE, method = "reg", formula = NULL),
  panel_cov_dr_cluster = list(panel = TRUE, method = "dr", formula = ~ x1 + x2),
  rc_reg_cluster = list(panel = FALSE, method = "reg", formula = NULL)
)

rows <- list()
agg_rows <- list()
for (scenario in names(scenario_specs)) {
  spec <- scenario_specs[[scenario]]
  call_args <- list(
    yname = "y",
    tname = "time",
    gname = "g",
    data = d,
    panel = spec$panel,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    clustervars = "cl",
    est_method = spec$method,
    base_period = "varying"
  )
  if (spec$panel) call_args$idname <- "id"
  if (!is.null(spec$formula)) call_args$xformla <- spec$formula
  out <- do.call(att_gt, call_args)
  rows[[scenario]] <- data.frame(
    scenario = scenario,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    crit_val = NA_real_,
    ci_low = NA_real_,
    ci_high = NA_real_,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period,
    est_method = spec$method,
    panel_mode = ifelse(spec$panel, "panel", "repeated-cross-section"),
    clustervar = "cl",
    n_clusters = length(unique(out$DIDparams$cluster_vector)),
    sample_n = nrow(d),
    inffunc_col = seq_along(out$att)
  )

  for (agg_type in c("simple", "group", "calendar", "dynamic")) {
    agg <- aggte(out, type = agg_type, bstrap = FALSE, cband = FALSE)
    egt <- agg$egt
    att_egt <- agg$att.egt
    se_egt <- agg$se.egt
    if (is.null(egt)) {
      egt <- NA_real_
      att_egt <- agg$overall.att
      se_egt <- agg$overall.se
    }
    agg_rows[[paste(scenario, agg_type, sep = "::")]] <- data.frame(
      scenario = scenario,
      agg_type = agg_type,
      seq = seq_along(att_egt),
      egt = egt,
      att = att_egt,
      se = se_egt,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se,
      clustervar = "cl",
      n_clusters = length(unique(out$DIDparams$cluster_vector))
    )
  }
}

cluster_grid <- do.call(rbind, rows)
write.csv(cluster_grid, file.path(fixture, "expected/r/cluster-grid.csv"), row.names = FALSE, na = "")

cluster_aggte <- do.call(rbind, agg_rows)
write.csv(cluster_aggte, file.path(fixture, "expected/r/cluster-aggte.csv"), row.names = FALSE, na = "")

invalid_cluster <- tryCatch(
  att_gt(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    data = d,
    panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    clustervars = "cl_bad",
    est_method = "reg",
    base_period = "varying"
  ),
  error = function(e) conditionMessage(e)
)
writeLines(jsonlite::toJSON(list(time_varying_cluster_error = invalid_cluster), auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F015",
  fixture_family = "clustered-inference",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D014"),
  tolerance_ids = c("TOL002", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f015/generate.R", path = "tools/parity/generators/f015/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/cluster-grid.csv", schema = "attgt-cluster-grid"),
    list(path = "expected/r/cluster-aggte.csv", schema = "aggte-cluster-grid"),
    list(path = "expected/r/events.json", schema = "events")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/cluster-grid.csv", expected = "expected/r/cluster-grid.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "expected/new-stata/cluster-aggte.csv", expected = "expected/r/cluster-aggte.csv", tolerance_id = "TOL002", key_columns = c("scenario", "agg_type", "seq"))
  ),
  approved_divergence = NULL,
  scope_note = "Analytical cluster-sum SE parity for ATT(g,t) and simple/group/calendar/dynamic aggregation for balanced panel no-covariate, balanced panel numeric-covariate dr, and true repeated-cross-section no-covariate slices, plus time-varying panel cluster validation; inherited Python analytical/bootstrap cluster smoke is covered by PY002/PY004/PY005/PY015 plus F014/F035, RT007 covers inherited R cluster-analytic stress, and RT017 covers inherited R ATT(g,t) cluster-sum bootstrap stress."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
