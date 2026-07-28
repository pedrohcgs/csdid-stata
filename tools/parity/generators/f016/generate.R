#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f016/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f016")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids_t <- 1:12
ids_c <- 21:34
d <- rbind(
  data.frame(id = rep(ids_t, each = 2),
             time = rep(1:2, times = length(ids_t)),
             g = 2),
  data.frame(id = rep(ids_c, each = 2),
             time = rep(1:2, times = length(ids_c)),
             g = 0)
)
d$cl <- ((d$id - 1) %% 6) + 1
d$cl_bad <- d$cl
d$cl_bad[d$id == 5 & d$time == 2] <- 99
d$x1 <- sin(d$id * 0.31) + 0.20 * d$time + 0.05 * (d$id %% 3)
d$x2 <- cos(d$id * 0.17) - 0.10 * d$time + 0.03 * (d$id %% 4)
d$y <- with(d, ifelse(
  g == 2,
  0.2 * id + 0.7 * time + 0.35 * x1 - 0.18 * x2 + 1.1 * (time == 2),
  -0.1 * id + 0.4 * time + 0.35 * x1 - 0.18 * x2 + 0.03 * id * (time == 2)
))
d$wt <- with(d, 1 + 0.02 * id + 0.15 * time + 0.1 * (g == 2))
d <- subset(d, !(id %in% c(3, 4, 22, 23) & time == 1))
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

rows_uniform <- list()
for (id in 1:10) {
  for (tt in 2:4) rows_uniform[[length(rows_uniform) + 1]] <- data.frame(id = id, time = tt, g = 4)
}
for (id in 11:20) {
  for (tt in 1:3) rows_uniform[[length(rows_uniform) + 1]] <- data.frame(id = id, time = tt, g = 0)
}
for (id in 21:30) {
  for (tt in 2:4) rows_uniform[[length(rows_uniform) + 1]] <- data.frame(id = id, time = tt, g = 0)
}
d_uniform <- do.call(rbind, rows_uniform)
d_uniform$x <- sin(0.20 * d_uniform$id) + 0.10 * d_uniform$time
d_uniform$y <- with(d_uniform,
                    0.30 * id + 0.70 * time + 0.20 * x +
                    ifelse(g > 0 & time >= g, 1.20, 0))
write.csv(d_uniform, file.path(fixture, "inputs/input-uniform-count.csv"), row.names = FALSE, na = "")

make_rt027_unbalanced <- function(seed = 202L, n_clusters = 24L, periods = 6L) {
  set.seed(seed)
  cluster_size <- 2L + rpois(n_clusters, 3)
  n_units <- sum(cluster_size)
  cl <- rep(seq_len(n_clusters), times = cluster_size)
  id <- seq_len(n_units)
  unit_alpha <- rnorm(n_units, 0, 0.7)
  unit_nu <- rnorm(n_units, 0, 0.4)
  cluster_period_shock <- matrix(rnorm(n_clusters * periods, 0, 0.6), n_clusters, periods)
  g_unit <- sample(c(3L, 4L, 5L, 0L), n_units, replace = TRUE,
                   prob = c(0.22, 0.22, 0.20, 0.36))
  out <- data.frame(
    id = rep(id, each = periods),
    time = rep(seq_len(periods), times = n_units),
    cluster = rep(cl, each = periods),
    g = rep(g_unit, each = periods),
    alpha = rep(unit_alpha, each = periods),
    nu = rep(unit_nu, each = periods)
  )
  out$y <- with(out,
                alpha + nu + 0.55 * time +
                cluster_period_shock[cbind(cluster, time)] +
                1.35 * (g != 0L & time >= g) +
                0.15 * pmax(time - g, 0) * (g != 0L) +
                rnorm(nrow(out), 0, 0.25))
  out <- out[order(out$id, out$time), ]
  drop_rows <- sample(seq_len(nrow(out)), floor(0.16 * nrow(out)))
  out <- out[-drop_rows, ]
  out <- out[sample(seq_len(nrow(out))), ]
  out[, c("id", "time", "cluster", "g", "y")]
}

d_rt027 <- make_rt027_unbalanced()
write.csv(d_rt027, file.path(fixture, "inputs/rt027-unbalanced-cluster.csv"), row.names = FALSE, na = "")

run_attgt <- function(method, weight_var, covariates) {
  args <- list(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    data = d,
    panel = TRUE,
    allow_unbalanced_panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = method,
    base_period = "varying"
  )
  if (weight_var != "none") args$weightsname <- weight_var
  if (covariates == "x1_x2") args$xformla <- ~ x1 + x2
  out <- do.call(att_gt, args)

  data.frame(
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
    est_method = method,
    weight_var = weight_var,
    covariates = covariates,
    panel_mode = "allow_unbalanced",
    sample_n = nrow(d),
    inffunc_col = seq_along(out$att)
  )
}

scenarios <- expand.grid(
  est_method = c("dr", "reg", "ipw"),
  weight_var = c("none", "wt"),
  covariates = c("none", "x1_x2"),
  stringsAsFactors = FALSE
)
attgt <- do.call(rbind, Map(run_attgt, scenarios$est_method, scenarios$weight_var, scenarios$covariates))
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")

run_cluster <- function(method, weight_var, covariates) {
  args <- list(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    data = d,
    panel = TRUE,
    allow_unbalanced_panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = method,
    base_period = "varying",
    clustervars = "cl"
  )
  if (weight_var != "none") args$weightsname <- weight_var
  if (covariates == "x1_x2") args$xformla <- ~ x1 + x2
  out <- do.call(att_gt, args)

  data.frame(
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period,
    est_method = method,
    weight_var = weight_var,
    covariates = covariates,
    panel_mode = "allow_unbalanced",
    clustervar = "cl",
    n_clusters = length(unique(out$DIDparams$cluster_vector)),
    sample_n = nrow(d),
    inffunc_col = seq_along(out$att),
    stringsAsFactors = FALSE
  )
}
cluster_grid <- do.call(rbind, Map(run_cluster, scenarios$est_method, scenarios$weight_var, scenarios$covariates))
write.csv(cluster_grid, file.path(fixture, "expected/r/cluster-grid.csv"), row.names = FALSE, na = "")

time_varying_cluster <- tryCatch(
  att_gt(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    data = d,
    panel = TRUE,
    allow_unbalanced_panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = "reg",
    base_period = "varying",
    clustervars = "cl_bad"
  ),
  error = function(e) conditionMessage(e)
)
writeLines(jsonlite::toJSON(list(time_varying_cluster_error = time_varying_cluster), auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/r/events.json"))

uniform <- att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d_uniform,
  panel = TRUE,
  allow_unbalanced_panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "varying"
)
uniform_attgt <- data.frame(
  group = uniform$group,
  time = uniform$t,
  event_time = uniform$t - uniform$group,
  att = uniform$att,
  se = uniform$se,
  control_group = uniform$DIDparams$control_group,
  base_period = uniform$DIDparams$base_period,
  est_method = "reg",
  panel_mode = "allow_unbalanced",
  sample_n = nrow(d_uniform),
  inffunc_col = seq_along(uniform$att)
)
write.csv(uniform_attgt, file.path(fixture, "expected/r/uniform-count-attgt.csv"), row.names = FALSE, na = "")

rt027_out <- suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d_rt027,
  panel = TRUE,
  allow_unbalanced_panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "universal",
  clustervars = "cluster"
)))
rt027_attgt <- data.frame(
  group = rt027_out$group,
  time = rt027_out$t,
  event_time = rt027_out$t - rt027_out$group,
  att = rt027_out$att,
  se = rt027_out$se,
  control_group = rt027_out$DIDparams$control_group,
  base_period = rt027_out$DIDparams$base_period,
  est_method = "reg",
  panel_mode = "allow_unbalanced",
  clustervar = "cluster",
  n_clusters = length(unique(rt027_out$DIDparams$cluster_vector)),
  cluster_vector_n = length(rt027_out$DIDparams$cluster_vector),
  inffunc_n = nrow(rt027_out$inffunc),
  sample_n = nrow(d_rt027),
  inffunc_col = seq_along(rt027_out$att),
  stringsAsFactors = FALSE
)
write.csv(rt027_attgt, file.path(fixture, "expected/r/rt027-cluster-attgt.csv"), row.names = FALSE, na = "")

rt027_agg_rows <- list()
for (agg_type in c("simple", "group", "calendar", "dynamic")) {
  agg <- suppressWarnings(suppressMessages(aggte(rt027_out, type = agg_type, bstrap = FALSE, cband = FALSE)))
  egt <- agg$egt
  att_egt <- agg$att.egt
  se_egt <- agg$se.egt
  if (is.null(egt)) {
    egt <- NA_real_
    att_egt <- agg$overall.att
    se_egt <- agg$overall.se
  }
  rt027_agg_rows[[agg_type]] <- data.frame(
    agg_type = agg_type,
    seq = seq_along(att_egt),
    egt = egt,
    att = att_egt,
    se = se_egt,
    overall_att = agg$overall.att,
    overall_se = agg$overall.se,
    n_clusters = length(unique(rt027_out$DIDparams$cluster_vector)),
    stringsAsFactors = FALSE
  )
}
write.csv(do.call(rbind, rt027_agg_rows), file.path(fixture, "expected/r/rt027-cluster-aggte.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F016",
  fixture_family = "unbalanced-panel",
  normative_source = "R did 2.5.1 allow_unbalanced_panel path with owner-directed Stata default",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D003"),
  tolerance_ids = c("TOL002", "EXACT"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/input-uniform-count.csv", rows = nrow(d_uniform), columns = ncol(d_uniform)),
    list(path = "inputs/rt027-unbalanced-cluster.csv", rows = nrow(d_rt027), columns = ncol(d_rt027))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f016/generate.R", path = "tools/parity/generators/f016/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/cluster-grid.csv", schema = "attgt-cluster-grid"),
    list(path = "expected/r/uniform-count-attgt.csv", schema = "attgt"),
    list(path = "expected/r/rt027-cluster-attgt.csv", schema = "attgt-cluster-grid"),
    list(path = "expected/r/rt027-cluster-aggte.csv", schema = "aggte-cluster-grid"),
    list(path = "expected/r/events.json", schema = "events")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("est_method", "weight_var", "covariates", "group", "time")),
    list(actual = "expected/new-stata/cluster-grid.csv", expected = "expected/r/cluster-grid.csv", tolerance_id = "TOL002", key_columns = c("est_method", "weight_var", "covariates", "group", "time")),
    list(actual = "expected/new-stata/uniform-count-attgt.csv", expected = "expected/r/uniform-count-attgt.csv", tolerance_id = "TOL002", key_columns = c("group", "time")),
    list(actual = "expected/new-stata/rt027-cluster-attgt.csv", expected = "expected/r/rt027-cluster-attgt.csv", tolerance_id = "TOL002", key_columns = c("group", "time")),
    list(actual = "expected/new-stata/rt027-cluster-aggte.csv", expected = "expected/r/rt027-cluster-aggte.csv", tolerance_id = "TOL002", key_columns = c("agg_type", "seq"))
  ),
  approved_divergence = NULL,
  scope_note = "Unbalanced panel is routed through repeated-cross-section estimators by default. Fixture covers dr/reg/ipw with no covariates and x1+x2 covariates, each with and without iweights, matching clustered SEs for the same grid, time-varying cluster rejection, the inherited uniform-row-count-but-missing-periods balance-detection edge case, and a partial RT027-style shuffled unbalanced clustered universal-base aggregation stress slice. Soft-deprecated legacy balance aliases are covered by F017; broader inherited unbalanced stress tests remain covered by RT/PY rows."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
