#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f021/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f021")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids_first <- 1:8
ids_later <- 9:20
ids_never <- 21:32
times <- 2:4
d <- rbind(
  data.frame(id = rep(ids_first, each = length(times)),
             time = rep(times, times = length(ids_first)),
             g = 2),
  data.frame(id = rep(ids_later, each = length(times)),
             time = rep(times, times = length(ids_later)),
             g = 3),
  data.frame(id = rep(ids_never, each = length(times)),
             time = rep(times, times = length(ids_never)),
             g = 0)
)
d$rowid <- seq_len(nrow(d))
d$y <- with(d, ifelse(
  g == 2,
  0.08 * id + 0.25 * time + 0.4 * (time >= 2),
  ifelse(g == 3,
         0.1 * id + 0.3 * time + 0.75 * (time >= 3) + 0.1 * (time == 4),
         -0.05 * id + 0.2 * time + 0.015 * id * (time == 4))
))

write.csv(d[, c("rowid", "id", "time", "g", "y")],
          file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

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
  sample_n = sum(!(d$g <= min(d$time) & d$g != 0)),
  inffunc_col = seq_along(out$att)
)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")

sample_mask <- data.frame(
  rowid = d$rowid,
  id = d$id,
  time = d$time,
  group = d$g,
  included = !(d$g <= min(d$time) & d$g != 0),
  drop_reason = ifelse(d$g <= min(d$time) & d$g != 0, "first_period_treated", ""),
  cell_membership = ifelse(d$g <= min(d$time) & d$g != 0, "", "analysis")
)
write.csv(sample_mask, file.path(fixture, "expected/r/sample-mask.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F021",
  fixture_family = "first-period-treated",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D010"),
  tolerance_ids = c("EXACT", "TOL001"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = 5)),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f021/generate.R", path = "tools/parity/generators/f021/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/sample-mask.csv", schema = "sample-mask"),
    list(path = "expected/r/attgt.csv", schema = "attgt")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/sample-mask.csv", expected = "expected/r/sample-mask.csv", tolerance_id = "EXACT", key_columns = c("rowid")),
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("group", "time"))
  ),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
