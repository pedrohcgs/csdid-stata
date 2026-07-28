#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f024/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f024")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids_t <- 1:10
ids_c <- 11:20
d <- rbind(
  data.frame(id = rep(ids_t, each = 2),
             time = rep(1:2, times = length(ids_t)),
             g = 2,
             y = rep(c(0, 1), times = length(ids_t))),
  data.frame(id = rep(ids_c, each = 2),
             time = rep(1:2, times = length(ids_c)),
             g = 0,
             y = rep(c(0, 0), times = length(ids_c)))
)
ddup <- rbind(d, d[d$id == d$id[1] & d$time == 2, ])

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")
write.csv(ddup, file.path(fixture, "inputs/duplicate-input.csv"), row.names = FALSE, na = "")

err <- tryCatch(
  att_gt(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    data = ddup,
    panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = "reg",
    base_period = "varying"
  ),
  error = function(e) conditionMessage(e)
)
writeLines(jsonlite::toJSON(list(
  events = list(list(
    event_type = "error",
    event_key = "duplicate_id_time",
    offending_option = "ivar/time",
    message_normalized = err
  ))
), auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F024",
  fixture_family = "duplicate-unit-time",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("EXACT"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/duplicate-input.csv", rows = nrow(ddup), columns = ncol(ddup))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f024/generate.R", path = "tools/parity/generators/f024/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/r/events.json", schema = "events")),
  comparison_plan = list(list(actual = "expected/new-stata/events.json", expected = "expected/r/events.json", tolerance_id = "EXACT", key_columns = c("event_key"))),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
