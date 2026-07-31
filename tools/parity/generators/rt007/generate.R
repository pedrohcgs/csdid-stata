#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt007/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt007")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

make_clustered_shocks <- function(seed, G = 50L) {
  set.seed(seed)
  sz <- rep(c(1L, 2L, 4L, 10L), length.out = G)
  N <- sum(sz)
  cl <- rep(seq_len(G), times = sz)
  alpha <- rnorm(G, 0, 1)[cl]
  nu <- rnorm(N, 0, 1)
  per <- 1:4
  eta <- matrix(rnorm(G * 4L, 0, 1.5), G, 4L)
  g <- sample(c(2L, 3L, 0L), G, replace = TRUE, prob = c(.34, .33, .33))[cl]
  d <- data.frame(
    id = rep(seq_len(N), each = 4L),
    t = rep(per, N),
    cl = rep(cl, each = 4L),
    g = rep(g, each = 4L),
    a = rep(alpha, each = 4L),
    nu = rep(nu, each = 4L)
  )
  d$y <- d$a + d$nu + 0.3 * d$t + eta[cbind(d$cl, d$t)] + (d$g != 0L & d$t >= d$g) + rnorm(nrow(d))
  d[order(d$id, d$t), ]
}

make_bootstrap_panel <- function(seed, within, G = 60L) {
  set.seed(seed)
  sz <- rep(c(1L, 2L, 4L, 10L), length.out = G)
  N <- sum(sz)
  cl <- rep(seq_len(G), times = sz)
  alpha <- rnorm(G, 0, 1)[cl]
  nu <- rnorm(N, 0, 1)
  eta <- matrix(rnorm(G * 4L, 0, 1.5), G, 4L)
  g <- if (within) {
    sample(c(2L, 3L, 0L), N, replace = TRUE, prob = c(.34, .33, .33))
  } else {
    sample(c(2L, 3L, 0L), G, replace = TRUE, prob = c(.34, .33, .33))[cl]
  }
  d <- data.frame(
    id = rep(seq_len(N), each = 4L),
    t = rep(1:4, N),
    cl = rep(cl, each = 4L),
    g = rep(g, each = 4L),
    a = rep(alpha, each = 4L),
    nu = rep(nu, each = 4L)
  )
  d$y <- d$a + d$nu + 0.3 * d$t + eta[cbind(d$cl, d$t)] + (d$g != 0L & d$t >= d$g) + rnorm(nrow(d))
  d[order(d$id, d$t), ]
}

make_rcs <- function(seed, G = 60L, per_cell = 6L) {
  set.seed(seed)
  per <- 1:4
  gC <- sample(c(2L, 3L, 0L), G, replace = TRUE, prob = c(.34, .33, .33))
  aC <- rnorm(G, 0, 1)
  eta <- matrix(rnorm(G * 4L, 0, 1.5), G, 4L)
  rows <- list()
  k <- 0L
  for (cl in seq_len(G)) for (tt in per) {
    y <- aC[cl] + 0.3 * tt + eta[cl, tt] + (gC[cl] != 0L & tt >= gC[cl]) + rnorm(per_cell)
    k <- k + 1L
    rows[[k]] <- data.frame(t = tt, cl = cl, g = gC[cl], y = y)
  }
  do.call(rbind, rows)[sample(G * 4L * per_cell), ]
}

target_rows <- function(res, scenario) {
  cv <- res$DIDparams$cluster_vector
  inf <- as.matrix(res$inffunc)
  S <- rowsum(inf, cv)
  se_target <- sqrt(colSums(S^2)) / nrow(inf)
  data.frame(
    scenario = scenario,
    group = res$group,
    time = res$t,
    event_time = res$t - res$group,
    att = res$att,
    se = res$se,
    target_se = as.numeric(se_target),
    cluster_vector_n = length(cv),
    inffunc_n = nrow(inf),
    n_clusters = length(unique(cv)),
    stringsAsFactors = FALSE
  )
}

input_404 <- make_clustered_shocks(404L)
input_505 <- make_clustered_shocks(505L)
input_panel_between <- make_bootstrap_panel(11L, within = FALSE)
input_panel_within <- make_bootstrap_panel(11L, within = TRUE)
input_rcs_909 <- make_rcs(909L)
input_rcs_909_id <- input_rcs_909
input_rcs_909_id$uid <- seq_len(nrow(input_rcs_909_id))
input_rcs_910 <- make_rcs(910L)

write.csv(input_404, file.path(fixture, "inputs/clustered-shocks-404.csv"), row.names = FALSE, na = "")
write.csv(input_505, file.path(fixture, "inputs/clustered-shocks-505.csv"), row.names = FALSE, na = "")
write.csv(input_panel_between, file.path(fixture, "inputs/panel-between-11.csv"), row.names = FALSE, na = "")
write.csv(input_panel_within, file.path(fixture, "inputs/panel-within-11.csv"), row.names = FALSE, na = "")
write.csv(input_rcs_909, file.path(fixture, "inputs/rcs-909.csv"), row.names = FALSE, na = "")
write.csv(input_rcs_909_id, file.path(fixture, "inputs/rcs-909-id.csv"), row.names = FALSE, na = "")
write.csv(input_rcs_910, file.path(fixture, "inputs/rcs-910.csv"), row.names = FALSE, na = "")

att_panel <- function(d, cluster = TRUE, faster = FALSE) {
  att_gt(
    yname = "y", tname = "t", idname = "id", gname = "g", data = d,
    control_group = "nevertreated", bstrap = FALSE,
    clustervars = if (cluster) "cl" else NULL,
    base_period = "varying", faster_mode = faster
  )
}

att_rcs <- function(d, id = NULL, faster = FALSE) {
  args <- list(
    yname = "y", tname = "t", gname = "g", data = d,
    control_group = "nevertreated", bstrap = FALSE,
    clustervars = "cl", panel = FALSE,
    base_period = "varying", faster_mode = faster
  )
  if (!is.null(id)) args$idname <- id
  do.call(att_gt, args)
}

analytic <- rbind(
  target_rows(att_panel(input_404, cluster = TRUE, faster = FALSE), "panel_404_regular"),
  target_rows(att_panel(input_404, cluster = TRUE, faster = TRUE), "panel_404_fast"),
  target_rows(att_rcs(input_rcs_909, faster = FALSE), "rcs_909_omitted_regular"),
  target_rows(att_rcs(input_rcs_909, faster = TRUE), "rcs_909_omitted_fast"),
  target_rows(att_rcs(input_rcs_909_id, id = "uid", faster = FALSE), "rcs_909_id_regular"),
  target_rows(att_rcs(input_rcs_909_id, id = "uid", faster = TRUE), "rcs_909_id_fast")
)
write.csv(analytic, file.path(fixture, "expected/r/analytical-targets.csv"), row.names = FALSE, na = "")

panel_cl <- att_panel(input_404, cluster = TRUE, faster = FALSE)
panel_iid <- att_panel(input_404, cluster = FALSE, faster = FALSE)
k_panel <- which(panel_cl$group == 2L & panel_cl$t == 2L)
contrast <- data.frame(
  scenario = "panel_404_cluster_vs_iid",
  group = 2L,
  time = 2L,
  se_cluster = panel_cl$se[k_panel],
  se_iid = panel_iid$se[k_panel],
  rel_gap = abs(panel_cl$se[k_panel] - panel_iid$se[k_panel]) / panel_iid$se[k_panel],
  stringsAsFactors = FALSE
)
write.csv(contrast, file.path(fixture, "expected/r/cluster-iid-contrast.csv"), row.names = FALSE, na = "")

agg_res_cl <- att_panel(input_505, cluster = TRUE, faster = FALSE)
agg_res_iid <- att_panel(input_505, cluster = FALSE, faster = FALSE)
agg_rows <- lapply(c("simple", "group", "dynamic"), function(type) {
  cl <- suppressWarnings(aggte(agg_res_cl, type = type, bstrap = FALSE))
  iid <- suppressWarnings(aggte(agg_res_iid, type = type, bstrap = FALSE))
  data.frame(
    type = type,
    overall_att = cl$overall.att,
    overall_se_cluster = cl$overall.se,
    overall_se_iid = iid$overall.se,
    rel_gap = abs(cl$overall.se - iid$overall.se) / iid$overall.se,
    stringsAsFactors = FALSE
  )
})
write.csv(do.call(rbind, agg_rows), file.path(fixture, "expected/r/aggte-overall.csv"), row.names = FALSE, na = "")

source_file <- "tests/testthat/test-cluster-analytic.R"
source_sha <- "6f7d7bd4ba73c1f92826c799bac176c3a4bfdc6be91a3505625ab602d6c04a56"
map_row <- function(source_test, scenario, assertion) {
  data.frame(
    source_file = source_file,
    source_sha256 = source_sha,
    source_test = source_test,
    mapped_scenario = scenario,
    assertion_family = assertion,
    coverage_status = "mapped",
    divergence_id = "",
    stringsAsFactors = FALSE
  )
}
upstream_map <- do.call(rbind, list(
  map_row("analytical (no-bootstrap) clustered SE for att_gt equals the cluster-sum CRVE (faster_mode TRUE and FALSE)", "panel_404_regular", "analytical clustered ATT(g,t) SE equals cluster-sum target and differs from iid SE"),
  map_row("analytical (no-bootstrap) clustered SE for att_gt equals the cluster-sum CRVE (faster_mode TRUE and FALSE)", "panel_404_fast", "requested fast path preserves analytical clustered ATT(g,t) SE target"),
  map_row("analytical cluster SE agrees with the bootstrap cluster SE (multiple DGPs)", "panel_between_bootstrap", "clustered bootstrap IQR and raw-draw SD scales agree with analytical clustered SE"),
  map_row("analytical cluster SE agrees with the bootstrap cluster SE (multiple DGPs)", "panel_within_bootstrap", "clustered bootstrap IQR and raw-draw SD scales agree with analytical clustered SE"),
  map_row("analytical clustered SE for repeated cross-sections (idname omitted/provided, faster_mode TRUE/FALSE)", "rcs_909_omitted_regular", "repeated-cross-section omitted-id analytical clustered SE equals cluster-sum target"),
  map_row("analytical clustered SE for repeated cross-sections (idname omitted/provided, faster_mode TRUE/FALSE)", "rcs_909_omitted_fast", "repeated-cross-section omitted-id requested fast path preserves clustered SE"),
  map_row("analytical clustered SE for repeated cross-sections (idname omitted/provided, faster_mode TRUE/FALSE)", "rcs_909_id_regular", "repeated-cross-section provided-id analytical clustered SE equals cluster-sum target"),
  map_row("analytical clustered SE for repeated cross-sections (idname omitted/provided, faster_mode TRUE/FALSE)", "rcs_909_id_fast", "repeated-cross-section provided-id requested fast path preserves clustered SE"),
  map_row("clustered bootstrap and analytical SE agree for repeated cross-sections (idname omitted)", "rcs_910_regular_bootstrap", "repeated-cross-section clustered bootstrap agrees with analytical clustered SE"),
  map_row("clustered bootstrap and analytical SE agree for repeated cross-sections (idname omitted)", "rcs_910_fast_bootstrap", "repeated-cross-section clustered bootstrap agrees with analytical clustered SE under requested fast path"),
  map_row("analytical clustered SE flows through aggte at all levels (simple/group/dynamic)", "aggte_simple", "clustered analytical SE propagates to simple aggregation and differs from iid"),
  map_row("analytical clustered SE flows through aggte at all levels (simple/group/dynamic)", "aggte_group", "clustered analytical SE propagates to group aggregation and differs from iid"),
  map_row("analytical clustered SE flows through aggte at all levels (simple/group/dynamic)", "aggte_dynamic", "clustered analytical SE propagates to dynamic aggregation and differs from iid")
))
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

scenarios <- data.frame(
  scenario = c("panel_between_bootstrap", "panel_within_bootstrap", "rcs_910_regular_bootstrap", "rcs_910_fast_bootstrap"),
  input = c("panel-between-11.csv", "panel-within-11.csv", "rcs-910.csv", "rcs-910.csv"),
  id_mode = c("panel", "panel", "omitted", "omitted"),
  fast = c(FALSE, FALSE, FALSE, TRUE),
  biters = c(3000L, 3000L, 5000L, 5000L),
  stata_seed = c(20260701L, 20260702L, 20260703L, 20260704L),
  iqr_rtol = c(.15, .15, .12, .12),
  sd_rtol = c(.06, .06, NA, NA),
  stringsAsFactors = FALSE
)
write.csv(scenarios, file.path(fixture, "expected/contract/bootstrap-scenarios.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "RT007",
  fixture_family = "r-cluster-analytic",
  normative_source = "R did 2.5.1 tests/testthat/test-cluster-analytic.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  decision_refs = c("D004", "D013", "D014"),
  tolerance_ids = c("TOL002", "TOL003", "EXACT"),
  inputs = list(
    list(path = "inputs/clustered-shocks-404.csv", rows = nrow(input_404), columns = ncol(input_404)),
    list(path = "inputs/clustered-shocks-505.csv", rows = nrow(input_505), columns = ncol(input_505)),
    list(path = "inputs/panel-between-11.csv", rows = nrow(input_panel_between), columns = ncol(input_panel_between)),
    list(path = "inputs/panel-within-11.csv", rows = nrow(input_panel_within), columns = ncol(input_panel_within)),
    list(path = "inputs/rcs-909.csv", rows = nrow(input_rcs_909), columns = ncol(input_rcs_909)),
    list(path = "inputs/rcs-909-id.csv", rows = nrow(input_rcs_909_id), columns = ncol(input_rcs_909_id)),
    list(path = "inputs/rcs-910.csv", rows = nrow(input_rcs_910), columns = ncol(input_rcs_910))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt007/generate.R", path = "tools/parity/generators/rt007/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(data_seeds = c(404L, 505L, 11L, 909L, 910L), exact_draw_parity = FALSE),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/bootstrap-scenarios.csv", schema = "cluster-analytic-bootstrap-scenarios"),
    list(path = "expected/r/analytical-targets.csv", schema = "cluster-analytic-attgt-targets"),
    list(path = "expected/r/cluster-iid-contrast.csv", schema = "cluster-iid-contrast"),
    list(path = "expected/r/aggte-overall.csv", schema = "aggte-overall-cluster-targets")
  ),
  comparison_plan = list(
    list(actual = "Stata analytical clustered ATT(g,t) targets", expected = "expected/r/analytical-targets.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "Stata clustered bootstrap IQR/raw draw scales", expected = "expected/contract/bootstrap-scenarios.csv", tolerance_id = "TOL003", key_columns = c("scenario")),
    list(actual = "Stata clustered aggregation overall SEs", expected = "expected/r/aggte-overall.csv", tolerance_id = "TOL002", key_columns = c("type"))
  ),
  approved_divergence = list(
    scope = "clustered_bootstrap_scale_fixture",
    reason = "RT007 verifies cluster-analytic targets and bootstrap-scale relationships, while F035 guards the exact seeded BMisc/R rademacher multiplier stream.",
    accepted_behavior = "Stata exposes e(boot_draws) and verifies the same IQR and raw-draw SD scale relationships against analytical cluster-sum SEs."
  ),
  scope_note = "RT007 maps R did tests/testthat/test-cluster-analytic.R: analytical ATT(g,t) clustered SEs equal cluster-sum targets in regular/requested-fast panel and repeated-cross-section modes, clustered SEs differ from iid SEs when clusters share shocks, clustered bootstrap IQR/raw-draw SD scales agree with analytical SEs for panel DGPs, repeated-cross-section clustered bootstrap agrees with analytical SEs, and clustered analytical SEs propagate through simple/group/dynamic aggregation."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
