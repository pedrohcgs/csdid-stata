#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f010/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f010")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids_t <- 1:10
ids_c <- 11:20
d <- rbind(
  data.frame(id = rep(ids_t, each = 2),
             time = rep(1:2, times = length(ids_t)),
             g = 2),
  data.frame(id = rep(ids_c, each = 2),
             time = rep(1:2, times = length(ids_c)),
             g = 0)
)
d$x1 <- sin((d$id %% 5) * 0.7) + 0.25 * (d$time == 2)
d$x2 <- cos((d$id %% 4) * 0.9) - 0.15 * (d$time == 2)
d$y <- with(d, ifelse(
  g == 2,
  0.15 * id + 0.6 * time + 0.4 * x1 - 0.2 * x2 + 1.0 * (time == 2),
  -0.08 * id + 0.3 * time + 0.4 * x1 - 0.2 * x2 + 0.025 * id * (time == 2)
))
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

ids <- 1:45
times <- 1:4
d_staggered <- expand.grid(id = ids, time = times)
d_staggered <- d_staggered[order(d_staggered$id, d_staggered$time), ]
d_staggered$g <- ifelse(d_staggered$id <= 15, 3,
                        ifelse(d_staggered$id <= 30, 4, 0))
d_staggered$x1 <- sin(0.25 * d_staggered$id) + 0.10 * d_staggered$time
d_staggered$x2 <- cos(0.33 * d_staggered$id) - 0.08 * d_staggered$time
d_staggered$y <- with(
  d_staggered,
  0.35 * time + 0.24 * x1 - 0.16 * x2 + 0.02 * (id %% 6) +
    ifelse(g > 0 & time >= g, 0.70 + 0.12 * (time - g) + 0.03 * (g == 4), 0) +
    0.015 * id * (time == 4)
)
write.csv(d_staggered, file.path(fixture, "inputs/input-staggered.csv"), row.names = FALSE, na = "")

rows <- list()
for (method in c("dr", "reg", "ipw")) {
  out <- att_gt(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    data = d,
    panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = method,
    base_period = "varying"
  )
  rows[[method]] <- data.frame(
    method = method,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period
  )
}
method_grid <- do.call(rbind, rows)
write.csv(method_grid, file.path(fixture, "expected/r/method-grid.csv"), row.names = FALSE, na = "")

cov_rows <- list()
for (method in c("dr", "reg", "ipw")) {
  out <- att_gt(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    xformla = ~ x1 + x2,
    data = d,
    panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = method,
    base_period = "varying"
  )
  cov_rows[[method]] <- data.frame(
    method = method,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period
  )
}
covariate_method_grid <- do.call(rbind, cov_rows)
write.csv(covariate_method_grid, file.path(fixture, "expected/r/covariate-method-grid.csv"), row.names = FALSE, na = "")

rc_rows <- list()
for (method in c("dr", "reg", "ipw")) {
  out <- att_gt(
    yname = "y",
    tname = "time",
    gname = "g",
    data = d,
    panel = FALSE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = method,
    base_period = "varying"
  )
  rc_rows[[method]] <- data.frame(
    method = method,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period,
    panel_mode = "repeated-cross-section"
  )
}
rc_method_grid <- do.call(rbind, rc_rows)
write.csv(rc_method_grid, file.path(fixture, "expected/r/rc-method-grid.csv"), row.names = FALSE, na = "")

rc_cov_rows <- list()
for (method in c("dr", "reg", "ipw")) {
  out <- att_gt(
    yname = "y",
    tname = "time",
    gname = "g",
    xformla = ~ x1 + x2,
    data = d,
    panel = FALSE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = method,
    base_period = "varying"
  )
  rc_cov_rows[[method]] <- data.frame(
    method = method,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period,
    panel_mode = "repeated-cross-section"
  )
}
rc_covariate_method_grid <- do.call(rbind, rc_cov_rows)
write.csv(rc_covariate_method_grid, file.path(fixture, "expected/r/rc-covariate-method-grid.csv"), row.names = FALSE, na = "")

control_rows <- list()
idx <- 1
for (panel_mode in c("panel", "repeated-cross-section")) {
  for (covariates in c("none", "numeric")) {
    for (control_group in c("nevertreated", "notyettreated")) {
      for (method in c("dr", "reg", "ipw")) {
        xformla <- if (covariates == "numeric") ~ x1 + x2 else NULL
        args <- list(
          yname = "y",
          tname = "time",
          gname = "g",
          xformla = xformla,
          data = d_staggered,
          panel = panel_mode == "panel",
          control_group = control_group,
          bstrap = FALSE,
          cband = FALSE,
          est_method = method,
          base_period = "varying"
        )
        if (panel_mode == "panel") args$idname <- "id"
        out <- do.call(att_gt, args)
        control_rows[[idx]] <- data.frame(
          panel_mode = panel_mode,
          covariates = covariates,
          control_group = control_group,
          method = method,
          group = out$group,
          time = out$t,
          event_time = out$t - out$group,
          att = out$att,
          se = out$se,
          base_period = out$DIDparams$base_period,
          stringsAsFactors = FALSE
        )
        idx <- idx + 1
      }
    }
  }
}
control_method_grid <- do.call(rbind, control_rows)
write.csv(control_method_grid, file.path(fixture, "expected/r/control-method-grid.csv"), row.names = FALSE, na = "")

invalid <- tryCatch(
  att_gt(yname = "y", tname = "time", idname = "id", gname = "g", data = d, est_method = "bad"),
  error = function(e) conditionMessage(e)
)
writeLines(jsonlite::toJSON(list(invalid_method_error = invalid), auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F010",
  fixture_family = "method-boundary",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("TOL001", "EXACT"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/input-staggered.csv", rows = nrow(d_staggered), columns = ncol(d_staggered))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f010/generate.R", path = "tools/parity/generators/f010/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/method-grid.csv", schema = "method-grid"),
    list(path = "expected/r/covariate-method-grid.csv", schema = "method-grid"),
    list(path = "expected/r/rc-method-grid.csv", schema = "method-grid"),
    list(path = "expected/r/rc-covariate-method-grid.csv", schema = "method-grid"),
    list(path = "expected/r/control-method-grid.csv", schema = "method-control-grid"),
    list(path = "expected/r/events.json", schema = "events")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/method-grid.csv", expected = "expected/r/method-grid.csv", tolerance_id = "TOL001", key_columns = c("method", "group", "time")),
    list(actual = "expected/new-stata/covariate-method-grid.csv", expected = "expected/r/covariate-method-grid.csv", tolerance_id = "TOL001", key_columns = c("method", "group", "time")),
    list(actual = "expected/new-stata/rc-method-grid.csv", expected = "expected/r/rc-method-grid.csv", tolerance_id = "TOL001", key_columns = c("method", "group", "time")),
    list(actual = "expected/new-stata/rc-covariate-method-grid.csv", expected = "expected/r/rc-covariate-method-grid.csv", tolerance_id = "TOL001", key_columns = c("method", "group", "time")),
    list(actual = "expected/new-stata/control-method-grid.csv", expected = "expected/r/control-method-grid.csv", tolerance_id = "TOL001", key_columns = c("panel_mode", "covariates", "control_group", "method", "group", "time"))
  ),
  approved_divergence = NULL,
  scope_note = "Built-in panel and true repeated-cross-section dr/reg/ipw method boundary for no-covariate and numeric-covariate cells, plus a staggered all-method nevertreated/notyettreated control-group grid for panel and repeated-cross-section paths. Stata-side test also covers soft-deprecated legacy aliases dripw -> dr and stdipw -> ipw plus invalid legacy method rejection. Broader DRDID boundary parity remains incomplete."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
