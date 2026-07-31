#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f011/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f011")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:36
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 12, 3, ifelse(d$id <= 24, 4, 0))
d$f <- ((d$id - 1) %% 3) + 1
d$f_2 <- as.numeric(d$f == 2)
d$f_3 <- as.numeric(d$f == 3)
d$x1 <- 0.40 * d$time + 0.20 * (d$f == 2) - 0.15 * (d$f == 3) + 0.15 * sin(1.7 * d$id)
d$x2 <- 0.25 * d$time + 0.30 * cos(1.1 * d$id) + 0.05 * (d$id %% 4 == 0)
d$residual <- 0.08 * cos(1.7 * d$id + 0.4 * d$time)
d$untreated <- 1.5 + 0.7 * d$time + 0.45 * d$x1 - 0.25 * d$x2 + 0.30 * (d$f == 2) - 0.20 * (d$f == 3) + d$residual
d$effect <- ifelse(d$g > 0 & d$time >= d$g, 1.1 + 0.15 * (d$time - d$g) + 0.05 * (d$f == 3), 0)
d$y <- d$untreated + d$effect
d$untreated <- NULL
d$effect <- NULL
d$residual <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

set.seed(11)
sparse_nunit <- 80
sparse_periods <- 1:3
sparse <- expand.grid(id = 1:sparse_nunit, period = sparse_periods)
sparse <- sparse[order(sparse$id, sparse$period), ]
sparse_g <- rep(c(0, 2), each = sparse_nunit / 2)
sparse_fac <- rep(1, sparse_nunit)
sparse_fac[sparse_g == 2] <- sample(c(1, 2), sum(sparse_g == 2), TRUE)
sparse_eta <- rnorm(sparse_nunit)
sparse$g <- sparse_g[sparse$id]
sparse$fac <- sparse_fac[sparse$id]
sparse$f_b <- as.numeric(sparse$fac == 2)
sparse$y <- sparse_eta[sparse$id] + sparse$period +
  1 * (sparse$g == 2 & sparse$period >= 2) + rnorm(nrow(sparse), sd = 0.1)
write.csv(sparse, file.path(fixture, "inputs/sparse-factor.csv"), row.names = FALSE, na = "")

specs <- list(
  numeric = list(formula = ~ x1 + x2, panel = TRUE, method = "reg"),
  factor = list(formula = ~ factor(f) + x1, panel = TRUE, method = "reg"),
  factor_dr = list(formula = ~ factor(f) + x1, panel = TRUE, method = "dr"),
  factor_ipw = list(formula = ~ factor(f) + x1, panel = TRUE, method = "ipw"),
  interaction = list(formula = ~ x1 * x2, panel = TRUE, method = "reg"),
  interaction_dr = list(formula = ~ x1 * x2, panel = TRUE, method = "dr"),
  interaction_ipw = list(formula = ~ x1 * x2, panel = TRUE, method = "ipw"),
  square = list(formula = ~ I(x1^2) + x2, panel = TRUE, method = "reg"),
  square_dr = list(formula = ~ I(x1^2) + x2, panel = TRUE, method = "dr"),
  square_ipw = list(formula = ~ I(x1^2) + x2, panel = TRUE, method = "ipw"),
  rc_numeric = list(formula = ~ x1 + x2, panel = FALSE, method = "reg"),
  rc_numeric_dr = list(formula = ~ x1 + x2, panel = FALSE, method = "dr"),
  rc_numeric_ipw = list(formula = ~ x1 + x2, panel = FALSE, method = "ipw"),
  rc_factor = list(formula = ~ factor(f) + x1, panel = FALSE, method = "reg"),
  rc_factor_dr = list(formula = ~ factor(f) + x1, panel = FALSE, method = "dr"),
  rc_factor_ipw = list(formula = ~ factor(f) + x1, panel = FALSE, method = "ipw"),
  rc_interaction = list(formula = ~ x1 * x2, panel = FALSE, method = "reg"),
  rc_interaction_dr = list(formula = ~ x1 * x2, panel = FALSE, method = "dr"),
  rc_interaction_ipw = list(formula = ~ x1 * x2, panel = FALSE, method = "ipw"),
  rc_square = list(formula = ~ I(x1^2) + x2, panel = FALSE, method = "reg"),
  rc_square_dr = list(formula = ~ I(x1^2) + x2, panel = FALSE, method = "dr"),
  rc_square_ipw = list(formula = ~ I(x1^2) + x2, panel = FALSE, method = "ipw")
)

rows <- list()
for (scenario in names(specs)) {
  args <- list(
    yname = "y",
    tname = "time",
    gname = "g",
    xformla = specs[[scenario]]$formula,
    data = d,
    panel = specs[[scenario]]$panel,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = specs[[scenario]]$method,
    base_period = "varying"
  )
  if (specs[[scenario]]$panel) args$idname <- "id"
  out <- do.call(att_gt, args)
  rows[[scenario]] <- data.frame(
    scenario = scenario,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period,
    est_method = specs[[scenario]]$method,
    panel_mode = ifelse(specs[[scenario]]$panel, "panel", "repeated-cross-section")
  )
}
covariate_grid <- do.call(rbind, rows)
write.csv(covariate_grid, file.path(fixture, "expected/r/covariate-grid.csv"), row.names = FALSE, na = "")

dense_factor_specs <- list()
for (panel_mode in c("panel", "repeated-cross-section")) {
  for (covariate_spec in c("factor", "dummy")) {
    for (method in c("dr", "reg", "ipw")) {
      scenario <- paste(panel_mode, covariate_spec, method, sep = "_")
      dense_factor_specs[[scenario]] <- list(
        panel_mode = panel_mode,
        covariate_spec = covariate_spec,
        method = method,
        formula = if (covariate_spec == "factor") ~ factor(f) + x1 else ~ f_2 + f_3 + x1,
        panel = panel_mode == "panel"
      )
    }
  }
}
dense_factor_rows <- list()
for (scenario in names(dense_factor_specs)) {
  spec <- dense_factor_specs[[scenario]]
  args <- list(
    yname = "y",
    tname = "time",
    gname = "g",
    xformla = spec$formula,
    data = d,
    panel = spec$panel,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = spec$method,
    base_period = "varying"
  )
  if (spec$panel) args$idname <- "id"
  out <- do.call(att_gt, args)
  dense_factor_rows[[scenario]] <- data.frame(
    panel_mode = spec$panel_mode,
    covariate_spec = spec$covariate_spec,
    method = spec$method,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    stringsAsFactors = FALSE
  )
}
dense_factor_grid <- do.call(rbind, dense_factor_rows)
write.csv(dense_factor_grid, file.path(fixture, "expected/r/dense-factor-dummy-grid.csv"), row.names = FALSE, na = "")

capture_warnings <- function(expr) {
  warnings <- character()
  value <- withCallingHandlers(
    expr,
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warnings = warnings)
}

sparse_specs <- list(
  panel_factor = list(panel_mode = "panel", covariate_spec = "factor", formula = ~ factor(fac), panel = TRUE),
  panel_dummy = list(panel_mode = "panel", covariate_spec = "dummy", formula = ~ f_b, panel = TRUE),
  rc_factor = list(panel_mode = "repeated-cross-section", covariate_spec = "factor", formula = ~ factor(fac), panel = FALSE),
  rc_dummy = list(panel_mode = "repeated-cross-section", covariate_spec = "dummy", formula = ~ f_b, panel = FALSE)
)
sparse_rows <- list()
sparse_events <- list()
for (scenario in names(sparse_specs)) {
  spec <- sparse_specs[[scenario]]
  args <- list(
    yname = "y",
    tname = "period",
    gname = "g",
    xformla = spec$formula,
    data = sparse,
    panel = spec$panel,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = "reg",
    base_period = "varying"
  )
  if (spec$panel) args$idname <- "id"
  captured <- capture_warnings(suppressMessages(do.call(att_gt, args)))
  out <- captured$value
  sparse_rows[[scenario]] <- data.frame(
    panel_mode = spec$panel_mode,
    covariate_spec = spec$covariate_spec,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    att_missing = as.integer(is.na(out$att)),
    se_missing = as.integer(is.na(out$se)),
    stringsAsFactors = FALSE
  )
  sparse_events[[scenario]] <- data.frame(
    panel_mode = spec$panel_mode,
    covariate_spec = spec$covariate_spec,
    event_key = "singular_control_matrix",
    expected_count = sum(grepl("singular or numerically ill-conditioned", captured$warnings)),
    message_normalized = "singular or numerically ill-conditioned",
    stringsAsFactors = FALSE
  )
}
sparse_grid <- do.call(rbind, sparse_rows)
sparse_event_grid <- do.call(rbind, sparse_events)
write.csv(sparse_grid, file.path(fixture, "expected/r/sparse-factor-grid.csv"), row.names = FALSE, na = "")
write.csv(sparse_event_grid, file.path(fixture, "expected/r/sparse-factor-events.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F011",
  fixture_family = "covariates",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("TOL001"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/sparse-factor.csv", rows = nrow(sparse), columns = ncol(sparse))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f011/generate.R", path = "tools/parity/generators/f011/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = list(seed_sparse_factor = 11),
  expected_outputs = list(
    list(path = "expected/r/covariate-grid.csv", schema = "attgt-covariate-grid"),
    list(path = "expected/r/dense-factor-dummy-grid.csv", schema = "attgt-dense-factor-dummy-grid"),
    list(path = "expected/r/sparse-factor-grid.csv", schema = "attgt-sparse-factor-grid"),
    list(path = "expected/r/sparse-factor-events.csv", schema = "warning-event-counts")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/covariate-grid.csv", expected = "expected/r/covariate-grid.csv", tolerance_id = "TOL001", key_columns = c("scenario", "est_method", "group", "time")),
    list(actual = "Stata dense factor/manual-dummy ATT(g,t)", expected = "expected/r/dense-factor-dummy-grid.csv", tolerance_id = "TOL001", key_columns = c("panel_mode", "covariate_spec", "method", "group", "time")),
    list(actual = "Stata sparse factor ATT(g,t)", expected = "expected/r/sparse-factor-grid.csv", tolerance_id = "TOL001", key_columns = c("panel_mode", "covariate_spec", "group", "time")),
    list(actual = "Stata sparse factor singular-warning counts", expected = "expected/r/sparse-factor-events.csv", tolerance_id = "EXACT", key_columns = c("panel_mode", "covariate_spec", "event_key"))
  ),
  approved_divergence = NULL,
  scope_note = "Panel and true repeated-cross-section dr/reg/ipw fixture for numeric time-varying covariates, factor-variable expansion, numeric interactions, and squared transformed covariate terms. It also inherits RT019 dense and sparse factor boundaries: dense factor variables must match manually expanded dummies, while rank-deficient sparse factor variables/manual dummies emit R-style singular warnings and preserve missing ATT/SE cells. Broader nuisance-model and DRDID boundary coverage remains covered by F010/F033."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
