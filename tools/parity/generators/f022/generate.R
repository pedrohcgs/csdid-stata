#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f022/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f022")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids_t <- 1:12
ids_future <- 13:24
times <- 1:4
d <- rbind(
  data.frame(id = rep(ids_t, each = length(times)),
             time = rep(times, times = length(ids_t)),
             g = 3),
  data.frame(id = rep(ids_future, each = length(times)),
             time = rep(times, times = length(ids_future)),
             g = 5)
)
d$y <- with(d, ifelse(
  g == 3,
  0.1 * id + 0.35 * time + 0.8 * (time >= 3) + 0.15 * pmax(time - 3, 0),
  -0.05 * id + 0.2 * time + 0.015 * id * (time == 4)
))

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

d_negative <- d
d_negative$g[d_negative$id <= 4] <- -1
write.csv(d_negative, file.path(fixture, "inputs/negative-g.csv"), row.names = FALSE, na = "")

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
  anticipation = 0
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

sample_mask <- data.frame(
  rowid = seq_len(nrow(d)),
  id = d$id,
  time = d$time,
  group = ifelse(d$g > max(d$time), 0, d$g),
  included = TRUE,
  drop_reason = "",
  cell_membership = ifelse(d$g > max(d$time), "future_as_never", "analysis")
)
write.csv(sample_mask, file.path(fixture, "expected/r/sample-mask.csv"), row.names = FALSE, na = "")

events <- data.frame(
  event_key = "negative_gvar",
  return_code = 198,
  event_type = "error",
  offending_option = "gvar(g)",
  message_normalized = "gvar() negative values are not supported; gvar() must be 0 for never-treated units and 1 or more for treated cohorts. Shift the cohort and time axes so both start at 1 (for example, replace g = g - min_period + 1 for treated units and t = t - min_period + 1); a monotone relabelling of the periods leaves the estimates unchanged.",
  stringsAsFactors = FALSE
)
write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F022",
  fixture_family = "treatment-timing-encodings",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D010"),
  tolerance_ids = c("EXACT", "TOL001"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/negative-g.csv", rows = nrow(d_negative), columns = ncol(d_negative))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f022/generate.R", path = "tools/parity/generators/f022/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/sample-mask.csv", schema = "sample-mask"),
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/events.csv", schema = "error-warning-events-csv"),
    list(path = "expected/r/events.json", schema = "error-warning-events")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/sample-mask.csv", expected = "expected/r/sample-mask.csv", tolerance_id = "EXACT", key_columns = c("rowid")),
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("group", "time")),
    list(actual = "Stata captured validation events", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = NULL,
  scope_note = "Treatment timing encoding fixture covers future-treated cohorts beyond max(time) as never-treated, ATT/SE parity for that recoding, and explicit negative gvar rejection matching R did 2.5.1 audit behavior."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
