#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f009/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f009")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:60
times <- 1:5
gmap <- c(rep(3, 20), rep(5, 20), rep(0, 20))
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- rep(gmap, each = length(times))
id_eff <- (d$id %% 9) * 0.07
time_eff <- 0.25 * d$time
anticipatory_effect <- ifelse(d$g > 0 & d$time == d$g - 1, -0.4, 0)
treat <- ifelse(d$g > 0 & d$time >= d$g,
                0.9 + 0.15 * (d$time - d$g),
                0)
d$y <- id_eff + time_eff + anticipatory_effect + treat + 0.015 * d$id * (d$time == 5)

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

rows <- list()
for (anticipation in c(0, 1)) {
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
    est_method = "reg",
    base_period = "varying",
    anticipation = anticipation
  )
  rows[[as.character(anticipation)]] <- data.frame(
    anticipation = anticipation,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period,
    est_method = out$DIDparams$est_method,
    panel_mode = "panel",
    sample_n = nrow(d),
    inffunc_col = seq_along(out$att)
  )
}
anticipation_grid <- do.call(rbind, rows)
write.csv(anticipation_grid, file.path(fixture, "expected/r/anticipation-grid.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F009",
  fixture_family = "anticipation",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D010"),
  tolerance_ids = c("TOL001", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f009/generate.R", path = "tools/parity/generators/f009/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/r/anticipation-grid.csv", schema = "anticipation-grid")),
  comparison_plan = list(list(actual = "expected/new-stata/anticipation-grid.csv", expected = "expected/r/anticipation-grid.csv", tolerance_id = "TOL001", key_columns = c("anticipation", "group", "time"))),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
