#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt027/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt027")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

make_ub_clustered <- function(seed, G = 40L, unbalanced = TRUE) {
  set.seed(seed)
  sz <- 1L + rpois(G, 4)
  N <- sum(sz)
  cl <- rep(seq_len(G), times = sz)
  alpha <- rnorm(G, 0, 1)[cl]
  nu <- rnorm(N, 0, 1)
  Tt <- 6L
  eta <- matrix(rnorm(G * Tt, 0, 1), G, Tt)
  g <- sample(c(3L, 4L, 5L, 0L), N, replace = TRUE, prob = c(.2, .2, .2, .4))
  d <- data.frame(
    id = rep(seq_len(N), each = Tt),
    period = rep(seq_len(Tt), N),
    cluster = rep(cl, each = Tt),
    g = rep(g, each = Tt),
    a = rep(alpha, each = Tt),
    nu = rep(nu, each = Tt)
  )
  d$y <- d$a + d$nu + 0.5 * d$period + eta[cbind(d$cluster, d$period)] +
    2 * (d$g != 0L & d$period >= d$g) + rnorm(nrow(d))
  d <- d[order(d$id, d$period), ]
  if (unbalanced) d <- d[sample(nrow(d), floor(0.85 * nrow(d))), ]
  d
}

fit <- function(d, faster, clustered, allow_unbalanced = TRUE) {
  suppressWarnings(suppressMessages(att_gt(
    yname = "y",
    tname = "period",
    idname = "id",
    gname = "g",
    data = d,
    panel = TRUE,
    control_group = "nevertreated",
    base_period = "universal",
    bstrap = FALSE,
    cband = FALSE,
    allow_unbalanced_panel = allow_unbalanced,
    faster_mode = faster,
    est_method = "reg",
    clustervars = if (clustered) "cluster" else NULL
  )))
}

cluster_n <- function(obj) {
  cv <- obj$DIDparams$cluster_vector
  if (is.null(cv)) return(NA_integer_)
  length(unique(cv))
}

cluster_vector_n <- function(obj) {
  cv <- obj$DIDparams$cluster_vector
  if (is.null(cv)) return(NA_integer_)
  length(cv)
}

attgt_rows <- function(obj, scenario, panel_shape, cluster_mode, faster) {
  data.frame(
    scenario = scenario,
    panel_shape = panel_shape,
    cluster_mode = cluster_mode,
    faster_mode = faster,
    group = obj$group,
    time = obj$t,
    event_time = obj$t - obj$group,
    att = obj$att,
    se = obj$se,
    n_clusters = cluster_n(obj),
    cluster_vector_n = cluster_vector_n(obj),
    inffunc_n = nrow(obj$inffunc),
    stringsAsFactors = FALSE
  )
}

aggte_rows <- function(obj, scenario, panel_shape, cluster_mode, faster) {
  out <- list()
  for (agg_type in c("simple", "group", "dynamic", "calendar")) {
    a <- suppressWarnings(suppressMessages(aggte(obj, type = agg_type, bstrap = FALSE, cband = FALSE)))
    egt <- a$egt
    att <- a$att.egt
    se <- a$se.egt
    if (is.null(egt)) {
      egt <- NA_real_
      att <- a$overall.att
      se <- a$overall.se
    }
    out[[agg_type]] <- data.frame(
      scenario = scenario,
      panel_shape = panel_shape,
      cluster_mode = cluster_mode,
      faster_mode = faster,
      agg_type = agg_type,
      seq = seq_along(att),
      egt = egt,
      att = att,
      se = se,
      overall_att = a$overall.att,
      overall_se = a$overall.se,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, out)
}

unbalanced <- make_ub_clustered(202L, unbalanced = TRUE)
balanced <- make_ub_clustered(55L, unbalanced = FALSE)
write.csv(unbalanced, file.path(fixture, "inputs/unbalanced-clustered.csv"), row.names = FALSE, na = "")
write.csv(balanced, file.path(fixture, "inputs/balanced-clustered.csv"), row.names = FALSE, na = "")

fits <- list(
  unbalanced_cluster_fast_true = fit(unbalanced, TRUE, TRUE, TRUE),
  unbalanced_cluster_fast_false = fit(unbalanced, FALSE, TRUE, TRUE),
  unbalanced_iid_fast_true = fit(unbalanced, TRUE, FALSE, TRUE),
  unbalanced_iid_fast_false = fit(unbalanced, FALSE, FALSE, TRUE),
  balanced_cluster_fast_true = fit(balanced, TRUE, TRUE, FALSE),
  balanced_cluster_fast_false = fit(balanced, FALSE, TRUE, FALSE)
)

meta <- data.frame(
  scenario = names(fits),
  panel_shape = c("unbalanced", "unbalanced", "unbalanced", "unbalanced", "balanced", "balanced"),
  cluster_mode = c("clustered", "clustered", "iid", "iid", "clustered", "clustered"),
  faster_mode = c(TRUE, FALSE, TRUE, FALSE, TRUE, FALSE),
  stringsAsFactors = FALSE
)

attgt <- do.call(rbind, Map(
  function(obj, scenario, panel_shape, cluster_mode, faster_mode) {
    attgt_rows(obj, scenario, panel_shape, cluster_mode, faster_mode)
  },
  fits,
  meta$scenario,
  meta$panel_shape,
  meta$cluster_mode,
  meta$faster_mode
))
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")

agg <- do.call(rbind, Map(
  function(obj, scenario, panel_shape, cluster_mode, faster_mode) {
    aggte_rows(obj, scenario, panel_shape, cluster_mode, faster_mode)
  },
  fits,
  meta$scenario,
  meta$panel_shape,
  meta$cluster_mode,
  meta$faster_mode
))
write.csv(agg, file.path(fixture, "expected/r/aggte.csv"), row.names = FALSE, na = "")

source_file <- "tests/testthat/test-unbalanced-faster-cluster-se.R"
source_sha <- "fd6deb485634bc3db1a9f0dca120d2c0d05c8813fb133b40617b86cb1b12582e"
upstream_map <- data.frame(
  source_file = source_file,
  source_sha256 = source_sha,
  source_test = c(
    "att_gt analytical clustered SE: faster_mode works (not i.i.d. fallback) on an unbalanced panel",
    "aggte: faster_mode TRUE == FALSE on an unbalanced clustered panel (all aggregation types)",
    "no regression: balanced panel still has faster_mode TRUE == FALSE (att_gt + aggte, clustered)"
  ),
  mapped_scenario = c(
    "unbalanced_attgt_clustered_public_results_with_fast_unbalanced_rc",
    "unbalanced_aggte_clustered_and_iid_public_results_with_fast_unbalanced_rc",
    "balanced_attgt_aggte_clustered_fast_path"
  ),
  assertion_family = c(
    "cluster vector aligns with influence functions; clustered SEs match cluster-sum formula; clustered SEs differ from iid; fast request uses the optimized unbalanced-RC path",
    "simple/group/dynamic/calendar aggregation ATT and SE match R faster_mode TRUE/FALSE outputs; Stata fast request uses the optimized unbalanced-RC path",
    "balanced clustered ATT(g,t) and aggregation fast path matches baseline and R did outputs"
  ),
  coverage_status = c("mapped", "mapped", "mapped"),
  divergence_id = c("", "", ""),
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

manifest <- list(
  matrix_id = "RT027",
  fixture_family = "r-unbalanced-faster-cluster-se",
  normative_source = "R did 2.5.1 tests/testthat/test-unbalanced-faster-cluster-se.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  source_sha256 = source_sha,
  decision_refs = c("D003", "D004", "D014"),
  tolerance_ids = c("TOL002", "EXACT"),
  inputs = list(
    list(path = "inputs/unbalanced-clustered.csv", rows = nrow(unbalanced), columns = ncol(unbalanced)),
    list(path = "inputs/balanced-clustered.csv", rows = nrow(balanced), columns = ncol(balanced))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt027/generate.R", path = "tools/parity/generators/rt027/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(kind = "R default", seeds = c(202L, 55L)),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/r/attgt.csv", schema = "attgt-fast-cluster-grid"),
    list(path = "expected/r/aggte.csv", schema = "aggte-fast-cluster-grid")
  ),
  comparison_plan = list(
    list(actual = "Stata ATT(g,t) baseline/fast-request grid", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "Stata aggregation baseline/fast-request grid", expected = "expected/r/aggte.csv", tolerance_id = "TOL002", key_columns = c("scenario", "agg_type", "seq")),
    list(actual = "Mapped source tests", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test"))
  ),
  approved_divergence = NULL,
  scope_note = "RT027 maps all three upstream source tests. Balanced clustered fast and unbalanced clustered/iid fast requests are parity-verified against R did 2.5.1; unbalanced panels now report e(fast_used)=1 with the fast-allow-unbalanced compute path instead of falling back to baseline."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
