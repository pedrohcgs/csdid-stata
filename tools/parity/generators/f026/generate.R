#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f026/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f026")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/new-stata"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:48
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 16, 3, ifelse(d$id <= 32, 4, 0))
d$cl <- ((d$id - 1) %% 8) + 1
d$x1 <- 0.30 * d$time + 0.20 * sin(0.4 * d$id) + 0.08 * (d$cl %% 2 == 0)
d$x2 <- 0.15 * d$time + 0.25 * cos(0.6 * d$id) - 0.05 * (d$cl %% 3 == 0)
d$y0 <- 1.2 + 0.45 * d$time + 0.30 * d$x1 - 0.18 * d$x2 +
  0.12 * sin(d$cl) + 0.04 * cos(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.8 + 0.10 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

attgt_cols <- c(
  "group", "time", "event_time", "att", "se",
  "n_treat_t", "n_treat_pre", "n_control_t", "n_control_pre"
)
group_prob_cols <- c("group", "prob", "n_units")
unit_group_cols <- c("id", "group")
aggte_cols <- c("egt", "att", "se", "overall_att", "overall_se")
if_cols <- paste0("c", 1:6)
row_names_6 <- paste0("r", 1:6)

attgt_surface <- function(cmdline, panel_mode, idvar, clustervar = "", n_units,
                          if_rows, n_clusters = NULL) {
  scalars <- list(
    N = nrow(d),
    N_units = n_units,
    N_attgt = 6,
    N_groups = 2,
    N_time = 4,
    anticipation = 0,
    level = 95
  )
  if (!is.null(n_clusters)) scalars$N_clusters <- n_clusters
  list(
    e_cmd = "csdid",
    e_properties = "",
    macros = list(
      cmd = "csdid",
      cmdline = cmdline,
      version = "2.0.0",
      yname = "y",
      timevar = "time",
      gvar = "g",
      idvar = idvar,
      clustervar = clustervar,
      panel_mode = panel_mode,
      control_group = "nevertreated",
      method = "reg",
      method_requested = "reg",
      weightvar = "",
      base_period = "varying",
      fix_weights = ""
    ),
    scalars = scalars,
    matrices = list(
      attgt = list(rows = 6, cols = 9),
      inffunc = list(rows = if_rows, cols = 6),
      group_prob = list(rows = 2, cols = 3),
      unit_group = list(rows = n_units, cols = 2)
    ),
    matrix_stripes = list(
      attgt = list(rownames = row_names_6, colnames = attgt_cols),
      inffunc = list(colnames = if_cols),
      group_prob = list(colnames = group_prob_cols),
      unit_group = list(colnames = unit_group_cols)
    )
  )
}

ereturn_contract <- list(
  matrix_id = "F026",
  fixture_family = "stored-results",
  normative_source = "R did 2.5.1 output semantics mapped to Stata e()",
  scenarios = list(
    panel_reg = attgt_surface(
      "csdid y, ivar(id) time(time) gvar(g) method(reg)",
      "panel", "id", n_units = 48, if_rows = 48
    ),
    rc_reg = attgt_surface(
      "csdid y, time(time) gvar(g) method(reg)",
      "repeated-cross-section", "", n_units = nrow(d), if_rows = nrow(d)
    ),
    panel_reg_cluster = attgt_surface(
      "csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl)",
      "panel", "id", clustervar = "cl", n_units = 48, if_rows = 48,
      n_clusters = 8
    ),
    post_simple = list(
      added_macros = list(agg_type = "simple"),
      added_scalars = list(agg_level = 95, N_aggte = 1),
      matrices = list(aggte = list(rows = 1, cols = 5)),
      matrix_stripes = list(aggte = list(rownames = "r1", colnames = aggte_cols))
    )
  ),
  postestimation_available = list(
    "csdid_estat attgt" = TRUE,
    "csdid_stats simple" = TRUE
  )
)
writeLines(
  jsonlite::toJSON(ereturn_contract, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/ereturn.json")
)

manifest <- list(
  matrix_id = "F026",
  fixture_family = "stored-results",
  normative_source = "R did 2.5.1 output semantics mapped to Stata e()",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D009", "D014"),
  tolerance_ids = c("EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f026/generate.R", path = "tools/parity/generators/f026/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/new-stata/ereturn.json", schema = "ereturn")),
  comparison_plan = list(list(actual = "live Stata e()", expected = "expected/new-stata/ereturn.json", tolerance_id = "EXACT", key_columns = c("scenario", "name"))),
  approved_divergence = NULL,
  scope_note = "Exact stored-result contract for ATT(g,t), influence-function, group-probability, unit-group, clustered metadata, repeated-cross-section metadata, simple aggregation, and the stored-result postestimation surfaces covered by F026. Plot-data behavior remains F028."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
