#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f008/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f008")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:48
times <- 1:4
gmap <- c(rep(3, 16), rep(4, 16), rep(0, 16))
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- rep(gmap, each = length(times))
id_eff <- (d$id %% 7) * 0.11
time_eff <- d$time * 0.4
later_pre_trend <- ifelse(d$g == 4 & d$time < 4, 0.22 * d$time, 0)
treat <- ifelse(d$g > 0 & d$time >= d$g,
                0.8 + 0.2 * (d$time - d$g) + 0.03 * d$g,
                0)
d$y <- id_eff + time_eff + later_pre_trend + treat + 0.02 * d$id * (d$time == 4)

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

rows <- list()
for (control_group in c("nevertreated", "notyettreated")) {
  out <- att_gt(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    data = d,
    panel = TRUE,
    control_group = control_group,
    bstrap = FALSE,
    cband = FALSE,
    est_method = "reg",
    base_period = "varying"
  )
  rows[[control_group]] <- data.frame(
    control_group = control_group,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    base_period = out$DIDparams$base_period,
    est_method = out$DIDparams$est_method,
    panel_mode = "panel",
    sample_n = nrow(d),
    inffunc_col = seq_along(out$att)
  )
}
control_grid <- do.call(rbind, rows)
write.csv(control_grid, file.path(fixture, "expected/r/control-group-grid.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F008",
  fixture_family = "control-group",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D011"),
  tolerance_ids = c("TOL001", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f008/generate.R", path = "tools/parity/generators/f008/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/r/control-group-grid.csv", schema = "control-group-grid")),
  comparison_plan = list(list(actual = "expected/new-stata/control-group-grid.csv", expected = "expected/r/control-group-grid.csv", tolerance_id = "TOL001", key_columns = c("control_group", "group", "time"))),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
