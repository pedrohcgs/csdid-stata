#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt017/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt017")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

make_clustered <- function(seed, bal, G = 40L) {
  set.seed(seed)
  sz <- if (bal) rep(4L, G) else rep(c(1L, 2L, 3L, 8L), length.out = G)
  N <- sum(sz)
  cl <- rep(seq_len(G), times = sz)
  a <- rnorm(G, 0, 1)[cl]
  nu <- rnorm(N, 0, 1)
  g <- ifelse(runif(N) < 0.5, 2L, 0L)
  d <- data.frame(
    id = rep(seq_len(N), each = 3L),
    t = rep(1:3, N),
    cl = rep(cl, each = 3L),
    g = rep(g, each = 3L),
    a = rep(a, each = 3L),
    nu = rep(nu, each = 3L)
  )
  d$y <- d$a + d$nu + 0.5 * d$t + (d$g == 2L & d$t >= 2L) + rnorm(nrow(d))
  d[order(d$id, d$t), ]
}

cluster_targets <- function(res, scenario, input, seed, bal) {
  k <- which(res$group == 2L & res$t == 2L)
  cv <- res$DIDparams$cluster_vector
  inf <- as.matrix(res$inffunc)[, k]
  n <- nrow(res$inffunc)
  S <- as.numeric(rowsum(matrix(inf, ncol = 1L), cv))
  nc <- as.numeric(table(cv))
  Gc <- length(S)
  target_sum <- sqrt(sum(S^2)) / n
  target_mean <- sqrt(sum((S / nc)^2)) / Gc
  data.frame(
    scenario = scenario,
    input = input,
    data_seed = seed,
    balanced_clusters = bal,
    k = k,
    group = res$group[k],
    time = res$t[k],
    att = res$att[k],
    se_r = res$se[k],
    target_sum = target_sum,
    target_mean = target_mean,
    rel_sum_mean_gap = abs(target_sum - target_mean) / target_mean,
    cluster_vector_n = length(cv),
    inffunc_n = n,
    n_clusters = Gc,
    source_biters = 5000L,
    stringsAsFactors = FALSE
  )
}

unbalanced <- make_clustered(101L, bal = FALSE)
balanced <- make_clustered(202L, bal = TRUE)
invalid <- make_clustered(303L, bal = FALSE)
invalid$cl2 <- invalid$cl

write.csv(unbalanced, file.path(fixture, "inputs/clustered-unbalanced.csv"), row.names = FALSE, na = "")
write.csv(balanced, file.path(fixture, "inputs/clustered-balanced.csv"), row.names = FALSE, na = "")
write.csv(invalid, file.path(fixture, "inputs/clustered-invalid.csv"), row.names = FALSE, na = "")

run_boot <- function(d) {
  att_gt(
    yname = "y",
    tname = "t",
    idname = "id",
    gname = "g",
    data = d,
    control_group = "nevertreated",
    bstrap = TRUE,
    biters = 5000L,
    clustervars = "cl",
    pl = FALSE,
    cband = FALSE,
    base_period = "varying",
    est_method = "reg"
  )
}

unbalanced_res <- run_boot(unbalanced)
balanced_res <- run_boot(balanced)
targets <- rbind(
  cluster_targets(unbalanced_res, "unbalanced_cluster_sum_target", "clustered-unbalanced.csv", 101L, FALSE),
  cluster_targets(balanced_res, "balanced_cluster_sum_equals_mean", "clustered-balanced.csv", 202L, TRUE)
)
write.csv(targets, file.path(fixture, "expected/r/cluster-targets.csv"), row.names = FALSE, na = "")

upstream_map <- data.frame(
  source_file = "tests/testthat/test-mboot-cluster.R",
  source_sha256 = "13955d5d8c5998432833c209351f16c2c197b7e4f88bdc0ce51a842f6e923258",
  source_test = c(
    "clustered mboot SE matches the cluster-sum (Remark 10) for UNBALANCED clusters",
    "clustered mboot SE is unchanged for BALANCED clusters (cluster-sum == cluster-mean)",
    "clustering validation is preserved (at most one cluster variable beyond idname)"
  ),
  mapped_scenario = c(
    "unbalanced_cluster_sum_target",
    "balanced_cluster_sum_equals_mean",
    "reject_multiple_non_id_cluster_variables"
  ),
  assertion_family = c(
    "cluster_vector aligns with influence-function rows, cluster-sum and cluster-mean differ, and reported clustered bootstrap SE tracks the cluster-sum target",
    "cluster_vector aligns with influence-function rows, balanced cluster-sum equals cluster-mean, and reported clustered bootstrap SE tracks the common target",
    "multiple cluster variables beyond idname are rejected"
  ),
  coverage_status = "mapped",
  divergence_id = "",
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

scenarios <- data.frame(
  scenario = c(
    "unbalanced_cluster_sum_target",
    "balanced_cluster_sum_equals_mean",
    "reject_multiple_non_id_cluster_variables"
  ),
  input = c("clustered-unbalanced.csv", "clustered-balanced.csv", "clustered-invalid.csv"),
  data_seed = c(101L, 202L, 303L),
  stata_boot_seed = c(20261701L, 20261702L, 20261703L),
  stata_biters = c(5000L, 5000L, 99L),
  expected_behavior = c(
    "bootstrap_se_tracks_cluster_sum_not_mean",
    "bootstrap_se_tracks_common_sum_mean_target",
    "rejects_multiple_bootstrap_cluster_variables"
  ),
  stringsAsFactors = FALSE
)
write.csv(scenarios, file.path(fixture, "expected/contract/scenarios.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "RT017",
  fixture_family = "r-clustered-multiplier-bootstrap",
  normative_source = "R did 2.5.1 tests/testthat/test-mboot-cluster.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  decision_refs = c("D004", "D013"),
  tolerance_ids = c("TOL003", "EXACT"),
  inputs = list(
    list(path = "inputs/clustered-unbalanced.csv", rows = nrow(unbalanced), columns = ncol(unbalanced)),
    list(path = "inputs/clustered-balanced.csv", rows = nrow(balanced), columns = ncol(balanced)),
    list(path = "inputs/clustered-invalid.csv", rows = nrow(invalid), columns = ncol(invalid))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt017/generate.R", path = "tools/parity/generators/rt017/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(
    data_seeds = c(101L, 202L, 303L),
    source_biters = 5000L,
    exact_draw_parity = TRUE,
    reason = "The public seeded rademacher path mirrors BMisc/R's multiplier stream; RT017 still enforces deterministic cluster-sum targets and source-test Monte Carlo tolerance rather than exporting raw draw matrices."
  ),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/scenarios.csv", schema = "clustered-bootstrap-scenarios"),
    list(path = "expected/r/cluster-targets.csv", schema = "cluster-sum-bootstrap-targets")
  ),
  comparison_plan = list(
    list(actual = "Stata e(inffunc) and e(cluster_vec) cluster-sum targets", expected = "expected/r/cluster-targets.csv", tolerance_id = "TOL002", key_columns = c("scenario")),
    list(actual = "Stata clustered e(boot_attgt) SE for ATT(2,2)", expected = "expected/r/cluster-targets.csv", tolerance_id = "TOL003", key_columns = c("scenario")),
    list(actual = "Stata multiple bootstrap cluster validation", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test"))
  ),
  approved_divergence = list(
    scope = "raw_draw_export_fixture_boundary",
    reason = "RT017 maps public cluster-bootstrap source assertions and does not export raw draw matrices; F035 guards the exact seeded BMisc/R rademacher multiplier stream.",
    accepted_behavior = "Stata must match the R cluster-sum and cluster-mean targets from the influence function, reject multiple non-id cluster variables, and keep clustered bootstrap SEs within the R source-test Monte Carlo tolerance."
  ),
  scope_note = "RT017 maps all three public assertions in R did tests/testthat/test-mboot-cluster.R. Stata verifies cluster_vector/influence-function alignment, unbalanced cluster-sum versus cluster-mean separation, balanced cluster-sum equals cluster-mean, clustered bootstrap SEs track the cluster-sum target for ATT(2,2), and multiple non-id cluster declarations are rejected. F035 guards exact seeded BMisc/R rademacher multiplier-stream parity while RT017 remains a cluster-summed bootstrap inheritance fixture."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
