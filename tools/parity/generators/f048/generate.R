#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f048/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f048")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

set.seed(48048)
nsim <- 200L
n_treat <- 120L
n_control <- 120L
true_att <- 1.0
nominal <- 0.95
zcrit <- qnorm(1 - (1 - nominal) / 2)

make_rep <- function(sim) {
  n_units <- n_treat + n_control
  ids <- seq_len(n_units)
  g <- c(rep(2L, n_treat), rep(0L, n_control))
  alpha <- rnorm(n_units, sd = 0.8)
  eps_pre <- rnorm(n_units, sd = 1.0)
  eps_post <- rnorm(n_units, sd = 1.0)
  data.frame(
    sim = sim,
    id = rep(ids, each = 2),
    time = rep(1:2, times = n_units),
    g = rep(g, each = 2),
    y = c(rbind(
      alpha + 0.35 + eps_pre,
      alpha + 0.70 + eps_post + ifelse(g == 2L, true_att, 0)
    ))
  )
}

input <- do.call(rbind, lapply(seq_len(nsim), make_rep))
write.csv(input, file.path(fixture, "inputs/sim-input.csv"), row.names = FALSE, na = "")

per_rep_rows <- vector("list", nsim)
for (sim in seq_len(nsim)) {
  d <- input[input$sim == sim, ]
  out <- suppressWarnings(att_gt(
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
  ))
  att <- out$att[out$group == 2 & out$t == 2]
  se <- out$se[out$group == 2 & out$t == 2]
  per_rep_rows[[sim]] <- data.frame(
    sim = sim,
    true_att = true_att,
    att = att,
    se = se,
    bias = att - true_att,
    ci_low = att - zcrit * se,
    ci_high = att + zcrit * se,
    covered = as.integer(att - zcrit * se <= true_att & true_att <= att + zcrit * se),
    stringsAsFactors = FALSE
  )
}

per_rep <- do.call(rbind, per_rep_rows)
summary <- data.frame(
  nsim = nsim,
  n_treat = n_treat,
  n_control = n_control,
  true_att = true_att,
  nominal = nominal,
  zcrit = zcrit,
  mean_att = mean(per_rep$att),
  mean_bias = mean(per_rep$bias),
  abs_bias = abs(mean(per_rep$bias)),
  coverage = mean(per_rep$covered),
  coverage_error = abs(mean(per_rep$covered) - nominal),
  mcse_att = sd(per_rep$att) / sqrt(nsim),
  stringsAsFactors = FALSE
)

write.csv(per_rep, file.path(fixture, "expected/r/per-rep.csv"), row.names = FALSE, na = "")
write.csv(summary, file.path(fixture, "expected/r/summary.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F048",
  fixture_family = "monte-carlo-sanity",
  normative_source = "R did 2.5.1 and known two-period randomized DGP",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("TOL008", "TOL002"),
  inputs = list(list(path = "inputs/sim-input.csv", rows = nrow(input), columns = ncol(input))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f048/generate.R", path = "tools/parity/generators/f048/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 48048, kind = "Mersenne-Twister", draws = nsim, distribution = "normal unit effects and shocks"),
  expected_outputs = list(
    list(path = "expected/r/per-rep.csv", schema = "monte-carlo-per-rep"),
    list(path = "expected/r/summary.csv", schema = "monte-carlo-summary")
  ),
  comparison_plan = list(
    list(actual = "build/test-artefacts/f048/per-rep.csv", expected = "expected/r/per-rep.csv", tolerance_id = "TOL002", key_columns = c("sim")),
    list(actual = "build/test-artefacts/f048/summary.csv", expected = "expected/r/summary.csv", tolerance_id = "TOL008", key_columns = c("nsim"))
  ),
  approved_divergence = NULL,
  scope_note = "Known-DGP Monte Carlo sanity gate for a two-period balanced panel with one treated cohort, nevertreated controls, method(reg), analytical SEs, and a true ATT of 1.0. Stata must match R did 2.5.1 per-rep ATT/SE under TOL002 and satisfy TOL008: absolute mean bias <= 0.02 and empirical 95% coverage within 0.03. This is a release sanity gate, not exhaustive stochastic inference coverage."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
