#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f020/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f020")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:40
times <- 1:4
gmap <- c(rep(3, 20), rep(4, 20))
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- rep(gmap, each = length(times))
d$y <- with(d, (id %% 8) * 0.09 + time * 0.35 +
              ifelse(time >= g, 0.7 + 0.2 * (time - g), 0) +
              0.01 * id * (time == 4))

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

rows <- list()
for (control_group in c("nevertreated", "notyettreated")) {
  out <- suppressWarnings(att_gt(
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
  ))
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
    sample_n = out$n,
    inffunc_col = seq_along(out$att)
  )
}
control_grid <- do.call(rbind, rows)
write.csv(control_grid, file.path(fixture, "expected/r/control-grid.csv"), row.names = FALSE, na = "")

sample_mask <- data.frame(
  rowid = seq_len(nrow(d)),
  id = d$id,
  time = d$time,
  group = ifelse(d$g == max(d$g) & d$time < max(d$g), 0, d$g),
  included = d$time < max(d$g),
  drop_reason = ifelse(d$time >= max(d$g), "post_latest_cohort", ""),
  cell_membership = ifelse(d$time >= max(d$g), "", ifelse(d$g == max(d$g), "latest_as_never", "analysis"))
)
write.csv(sample_mask, file.path(fixture, "expected/r/sample-mask.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F020",
  fixture_family = "no-never-treated",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D010", "D011"),
  tolerance_ids = c("EXACT", "TOL001"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f020/generate.R", path = "tools/parity/generators/f020/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/sample-mask.csv", schema = "sample-mask"),
    list(path = "expected/r/control-grid.csv", schema = "control-grid")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/sample-mask.csv", expected = "expected/r/sample-mask.csv", tolerance_id = "EXACT", key_columns = c("rowid")),
    list(actual = "expected/new-stata/control-grid.csv", expected = "expected/r/control-grid.csv", tolerance_id = "TOL001", key_columns = c("control_group", "group", "time"))
  ),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
