#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt001/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt001")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

mk_two_cluster <- function(seed) {
  set.seed(seed)
  G <- 30L
  sz <- rep(c(2L, 4L, 6L), length.out = G)
  N <- sum(sz)
  cl <- rep(seq_len(G), sz)
  region <- rep(sample(1:5, G, TRUE), times = sz)
  alpha <- rnorm(G, 0, 1)[cl]
  nu <- rnorm(N)
  Tt <- 5L
  eta <- matrix(rnorm(G * Tt, 0, 1.5), G, Tt)
  g <- sample(c(0L, 2L, 3L, 4L), N, TRUE, c(.4, .2, .2, .2))
  d <- data.frame(
    id = rep(seq_len(N), each = Tt),
    period = rep(seq_len(Tt), N),
    cluster = rep(cl, each = Tt),
    region = rep(region, each = Tt),
    g = rep(g, each = Tt),
    a = rep(alpha, each = Tt),
    nu = rep(nu, each = Tt)
  )
  d$y <- d$a + d$nu + 0.4 * d$period + eta[cbind(d$cluster, d$period)] +
    (d$g != 0L & d$period >= d$g) + rnorm(nrow(d))
  d[order(d$id, d$period), ]
}

warned <- function(expr) {
  flag <- FALSE
  value <- withCallingHandlers(
    force(expr),
    warning = function(c) {
      if (grepl("cluster information needed is not available", conditionMessage(c))) {
        flag <<- TRUE
      }
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warned = flag)
}

agg <- function(m, ty, ...) suppressMessages(aggte(m, type = ty, bstrap = FALSE, cband = FALSE, ...))

d <- mk_two_cluster(11)
write.csv(d, file.path(fixture, "inputs/two-cluster.csv"), row.names = FALSE, na = "")

mc <- suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  tname = "period",
  idname = "id",
  gname = "g",
  data = d,
  clustervars = "cluster",
  control_group = "nevertreated",
  bstrap = FALSE
)))

mi <- suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  tname = "period",
  idname = "id",
  gname = "g",
  data = d,
  control_group = "nevertreated",
  bstrap = FALSE
)))

rows <- list()
add_row <- function(scenario, agg_type, request, warning_expected, obj) {
  rows[[length(rows) + 1]] <<- data.frame(
    scenario = scenario,
    agg_type = agg_type,
    request = request,
    warning_expected = as.integer(warning_expected),
    overall_att = obj$overall.att,
    overall_se = obj$overall.se,
    finite_effect_se = as.integer(all(is.finite(obj$se.egt))),
    stringsAsFactors = FALSE
  )
}

for (ty in c("simple", "dynamic")) {
  inherited <- warned(agg(mc, ty))
  same <- warned(agg(mc, ty, clustervars = "cluster"))
  add_row("clustered_inherited", ty, "inherited", inherited$warned, inherited$value)
  add_row("clustered_same_override", ty, "cluster", same$warned, same$value)
}

for (ty in c("simple", "dynamic", "group", "calendar")) {
  iid <- warned(agg(mi, ty))
  add_row("unclustered_iid", ty, "none", iid$warned, iid$value)
}

clustered_dynamic <- warned(agg(mc, "dynamic"))

analytic <- do.call(rbind, rows)
write.csv(analytic, file.path(fixture, "expected/r/analytic-overrides.csv"), row.names = FALSE, na = "")

relations <- data.frame(
  relation = c(
    "clustered_same_equals_inherited"
  ),
  lhs_scenario = c(
    "clustered_same_override"
  ),
  rhs_scenario = c(
    "clustered_inherited"
  ),
  agg_type = c("dynamic"),
  expectation = c("equal"),
  min_abs_se_delta = c(0),
  stringsAsFactors = FALSE
)
write.csv(relations, file.path(fixture, "expected/r/relations.csv"), row.names = FALSE, na = "")

upstream_map <- data.frame(
  source_file = "tests/testthat/test-aggte-clustervars-override.R",
  source_sha256 = "6af533e96b6847b7a988d1c617ba89ea1dd0c22c6e8b451bf4c5520d984c99d6",
  source_test = c(
    "inherited clustering and same-variable override are honored without warning",
    "aggte warns and falls back to i.i.d. when att_gt was not clustered (analytic)",
    "aggte bootstrap override warns and falls back instead of erroring",
    "aggte refuses to switch to a different cluster variable than att_gt used"
  ),
  mapped_scenario = c(
    "clustered_inherited;clustered_same_override",
    "unclustered_iid;unclustered_cluster_override",
    "pending-bootstrap-aggregation",
    "clustered_region_override"
  ),
  assertion_family = c(
    "no warning; same-variable override matches inherited clustered SE",
    "Stata reports unclustered aggregation but rejects a new aggregation cluster after unclustered estimation",
    "R aggregation bootstrap override has no closed public Stata aggregation bootstrap surface",
    "mismatched cluster request exits nonzero with a clear diagnostic"
  ),
  coverage_status = c("mapped", "approved-divergence", "approved-divergence", "mapped"),
  divergence_id = c("", "RT001-DIV001", "RT001-DIV001", ""),
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = "RT001-DIV001",
  source_tests = "aggte bootstrap override and unsafe analytical cluster override fallbacks",
  reason = "The R source exercises aggregation-level cluster override behavior through aggte(). For Stata public statistical safety, csdid_stats now accepts inherited clustering and same-cluster override, but errors on mismatched clusters or new cluster requests after an unclustered estimation rather than falling back to non-clustered SEs.",
  accepted_behavior = "Stata maps inherited clustering and same-cluster override. Mismatched or unavailable aggregation cluster requests must exit nonzero with a clear message. Bootstrap aggregation remains tracked by F035/RT018.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "RT001",
  fixture_family = "r-aggte-clustervars-override",
  normative_source = "R did 2.5.1 tests/testthat/test-aggte-clustervars-override.R",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D004", "D013", "D014"),
  tolerance_ids = c("EXACT", "TOL002"),
  inputs = list(list(path = "inputs/two-cluster.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt001/generate.R", path = "tools/parity/generators/rt001/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 11),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence"),
    list(path = "expected/r/analytic-overrides.csv", schema = "aggte-cluster-override-grid"),
    list(path = "expected/r/relations.csv", schema = "aggte-cluster-override-relations")
  ),
  comparison_plan = list(
    list(actual = "Stata csdid_stats cluster override analytical output", expected = "expected/r/analytic-overrides.csv", tolerance_id = "TOL002", key_columns = c("scenario", "agg_type", "request")),
    list(actual = "Stata safe cluster-override relations", expected = "expected/r/relations.csv", tolerance_id = "EXACT", key_columns = c("relation"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "RT001 maps inherited clustering, same-cluster override, and mismatched-cluster refusal. Unsafe fallback from unavailable aggregation clusters is recorded as RT001-DIV001, along with the R aggregation bootstrap override subtest."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
