#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f013/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f013")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:36
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 12, 3, ifelse(d$id <= 24, 4, 0))
d$x1 <- 0.35 * d$time + 0.20 * sin(0.7 * d$id) + 0.10 * (d$id %% 3 == 0)
d$x2 <- 0.20 * d$time + 0.25 * cos(0.5 * d$id) - 0.08 * (d$id %% 4 == 0)
d$y0 <- 1.0 + 0.55 * d$time + 0.35 * d$x1 - 0.15 * d$x2 + 0.05 * cos(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.9 + 0.12 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

scenario_specs <- list(
  panel_reg = list(panel = TRUE, method = "reg", formula = NULL),
  panel_cov_dr = list(panel = TRUE, method = "dr", formula = ~ x1 + x2),
  rc_reg = list(panel = FALSE, method = "reg", formula = NULL)
)

summarize_inffunc <- function(scenario, out) {
  inf <- as.matrix(out$inffunc)
  sumsq <- colSums(inf^2)
  data.frame(
    scenario = scenario,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    inffunc_col = seq_along(out$att),
    n_rows = nrow(inf),
    mean = colMeans(inf),
    sd = apply(inf, 2, sd),
    l1_norm = colSums(abs(inf)),
    l2_norm = sqrt(sumsq),
    min = apply(inf, 2, min),
    max = apply(inf, 2, max),
    nonzero_count = colSums(abs(inf) > 1e-12),
    sum = colSums(inf),
    sumsq = sumsq,
    se_from_if = sqrt(sumsq) / nrow(inf)
  )
}

attgt_rows <- list()
inffunc_rows <- list()
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
    est_method = spec$method,
    base_period = "varying"
  )
  if (spec$panel) call_args$idname <- "id"
  if (!is.null(spec$formula)) call_args$xformla <- spec$formula
  out <- do.call(att_gt, call_args)
  attgt_rows[[scenario]] <- data.frame(
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
    sample_n = nrow(d),
    inffunc_col = seq_along(out$att)
  )
  inffunc_rows[[scenario]] <- summarize_inffunc(scenario, out)
}

attgt <- do.call(rbind, attgt_rows)
inffunc_summary <- do.call(rbind, inffunc_rows)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(inffunc_summary, file.path(fixture, "expected/r/inffunc-summary.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F013",
  fixture_family = "analytical-inference",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D014"),
  tolerance_ids = c("TOL002"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f013/generate.R", path = "tools/parity/generators/f013/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/inffunc-summary.csv", schema = "inffunc-summary")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "expected/new-stata/inffunc-summary.csv", expected = "expected/r/inffunc-summary.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time", "inffunc_col"))
  ),
  approved_divergence = NULL,
  scope_note = "Analytical ATT(g,t) SE and influence-function dimension/summary parity for balanced panel no-covariate, balanced panel numeric-covariate dr, and true repeated-cross-section no-covariate slices; multiplier bootstrap and clustered inference remain F014/F015."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
