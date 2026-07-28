#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f017/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f017")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:15
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 5, 3, ifelse(d$id <= 10, 4, 0))
d$y0 <- 1 + 0.40 * d$time + 0.08 * d$id + 0.03 * sin(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.55 + 0.08 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
d <- d[!(d$id == 2 & d$time == 2), ]
d <- d[!(d$id == 7 & d$time == 3), ]
d <- d[!(d$id == 14 & d$time == 4), ]

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

balance_message <- "csdid legacy compatibility: bal()/balance() are soft-deprecated; use allowunbalanced or omit the option. Legacy balancing modes no longer drop units; this run uses R-compatible allowunbalanced handling"
long_message <- "warning: long/long2 are legacy event-study aliases slated for removal; do not use them in new code. Specify baseperiod(universal) explicitly for legacy event-study layout"
asinr_message <- "csdid legacy compatibility: asinr is accepted as a no-op; R-compatible not-yet selection is governed by notyet"

events <- data.frame(
  event_key = c(
    "legacy_bal_full",
    "legacy_balance_full",
    "legacy_bal_unbal",
    "legacy_long",
    "legacy_long2",
    "legacy_asinr_noop"
  ),
  return_code = c(0, 0, 0, 0, 0, 0),
  event_type = c("warning", "warning", "warning", "warning", "warning", "warning"),
  offending_option = c(
    "bal(full)",
    "balance(full)",
    "bal(unbal)",
    "long",
    "long2",
    "asinr"
  ),
  message_normalized = c(
    balance_message,
    balance_message,
    balance_message,
    long_message,
    long_message,
    asinr_message
  ),
  stringsAsFactors = FALSE
)

write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F017",
  fixture_family = "legacy-balance-compatibility",
  normative_source = "D003/D008 conformance contract; legacy Stata 1.82 behavior is rejected for v1 defaults",
  source_commit = "fdbae25521a941314af8d84ec0c93fb0596daa8e",
  decision_refs = c("D003", "D008"),
  tolerance_ids = c("EXACT"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f017/generate.R", path = "tools/parity/generators/f017/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/events.json", schema = "error-warning-events"),
    list(path = "expected/r/events.csv", schema = "error-warning-events-csv")
  ),
  comparison_plan = list(
    list(actual = "Stata captured legacy balance/default events", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = list(
    status = "soft-deprecated-alias",
    reason = "Old pair-balanced/full-balanced unbalanced-panel behavior is not retained in v1; bal()/balance() are accepted only as warning aliases for the R-compatible allow_unbalanced default."
  ),
  scope_note = "F017 accepts legacy bal()/balance() unbalanced-panel modes with a soft-deprecation warning, verifies that they match the default allowunbalanced ATT(g,t) path, keeps long/long2 as strongly deprecated aliases that use baseperiod(universal) when baseperiod() is omitted, and verifies asinr as a no-op warning."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
