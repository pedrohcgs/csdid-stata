#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f023/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f023")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:48
times <- c(2000, 2002, 2005, 2007)
gmap <- c(rep(2005, 16), rep(2007, 16), rep(0, 16))
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- rep(gmap, each = length(times))
time_idx <- match(d$time, times)
g_idx <- match(d$g, times)
id_eff <- (d$id %% 7) * 0.11
time_eff <- time_idx * 0.4
treat <- ifelse(d$g > 0 & d$time >= d$g,
                0.8 + 0.2 * (time_idx - g_idx) + 0.03 * g_idx,
                0)
d$y <- id_eff + time_eff + treat + 0.02 * d$id * (d$time == 2007)

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

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
  base_period = "varying"
)

attgt <- data.frame(
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
  est_method = out$DIDparams$est_method,
  panel_mode = "panel",
  sample_n = nrow(d),
  inffunc_col = seq_along(out$att)
)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F023",
  fixture_family = "irregular-time-gaps",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D010", "D011"),
  tolerance_ids = c("TOL001", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f023/generate.R", path = "tools/parity/generators/f023/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/r/attgt.csv", schema = "attgt")),
  comparison_plan = list(list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("group", "time"))),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
