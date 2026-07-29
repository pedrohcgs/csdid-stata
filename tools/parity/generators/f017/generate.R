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

# The bal() vocabulary is full / pair / none. Everything below is a deprecated
# spelling of one of those three, and each one announces itself and names its
# replacement -- a deprecation nobody is told about is not a deprecation.
# bal(pair) has no row here yet because the mode is not implemented; when it
# lands, balancepair joins this table.
dep_unbal      <- "csdid: bal(unbal) is deprecated; use bal(none)"
dep_all        <- "csdid: bal(all) is deprecated; use bal(full)"
dep_allowunbal <- "csdid: allowunbalanced is deprecated; use bal(none)"
dep_balanceall <- "csdid: balanceall is deprecated; use bal(full)"
long_message <- "warning: long/long2 are legacy event-study aliases slated for removal; do not use them in new code. Specify baseperiod(universal) explicitly for legacy layouts."
asinr_message <- "csdid legacy compatibility: asinr is accepted as a no-op; R-compatible not-yet selection is governed by notyet"

events <- data.frame(
  event_key = c(
    "legacy_bal_unbal",
    "legacy_bal_all",
    "legacy_allowunbalanced",
    "legacy_balanceall",
    "legacy_long",
    "legacy_long2",
    "legacy_asinr_noop"
  ),
  return_code = rep(0, 7),
  event_type = rep("warning", 7),
  offending_option = c(
    "bal(unbal)",
    "bal(all)",
    "allowunbalanced",
    "balanceall",
    "long",
    "long2",
    "asinr"
  ),
  message_normalized = c(
    dep_unbal,
    dep_all,
    dep_allowunbal,
    dep_balanceall,
    long_message,
    long_message,
    asinr_message
  ),
  # Which bal() mode each spelling resolves to. none and full are not the same
  # estimand on this deliberately unbalanced fixture, so the test can tell them
  # apart rather than merely checking that nothing errored.
  resolves_to = c("none", "full", "none", "full", NA, NA, NA),
  stringsAsFactors = FALSE
)

write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F017",
  fixture_family = "balance-vocabulary-and-legacy-spellings",
  normative_source = "D003/D008 conformance contract; bal() vocabulary is full/pair/none with deprecated spellings mapped onto it",
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
