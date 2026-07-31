#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f029/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f029")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:24
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 8, 3, ifelse(d$id <= 16, 4, 0))
d$x1 <- 0.25 * d$time + 0.10 * sin(d$id)
d$w <- 1 + 0.05 * (d$id %% 5)
d$y0 <- 1 + 0.45 * d$time + 0.20 * d$x1 + 0.03 * cos(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.7 + 0.10 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

neg <- d
neg$w[1] <- -1
write.csv(neg, file.path(fixture, "inputs/negative-weight.csv"), row.names = FALSE, na = "")

dup <- rbind(d, d[1, ])
write.csv(dup, file.path(fixture, "inputs/duplicate-input.csv"), row.names = FALSE, na = "")

empty <- d
empty$y <- NA_real_
write.csv(empty, file.path(fixture, "inputs/empty-after-markout.csv"), row.names = FALSE, na = "")

events <- data.frame(
  event_key = c(
    "invalid_method",
    "invalid_base_period",
    "invalid_fix_weights",
    "fix_weights_requires_panel",
    "negative_anticipation",
    "negative_iweight",
    "duplicate_unit_time",
    "unsupported_option",
    "csdid_stats_no_prior",
    "csdid_stats_invalid_type",
    "csdid_estat_no_prior",
    "csdid_estat_tidy_requires_saving",
    "csdid_plot_requires_saving",
    "csdid_plot_simple_unavailable",
    "no_observations"
  ),
  return_code = c(198, 198, 198, 198, 198, 198, 459, 198, 301, 198, 301, 198, 198, 498, 2000),
  event_type = "error",
  offending_option = c(
    "method(bad)",
    "base_period(Universal)",
    "fix_weights(bad)",
    "fix_weights(first_period)",
    "anticipation(-1)",
    "iweight",
    "ivar-time",
    "foo",
    "prior-results",
    "type(bad)",
    "prior-results",
    "tidy",
    "saving()",
    "type(simple)",
    "sample"
  ),
  message_normalized = c(
    "method() must be one of dr, reg, or ipw",
    "baseperiod() must be varying or universal",
    "fixweights() must be one of varying, base, or first",
    "fixweights(first) requires ivar(); repeated cross-section fixed-weight modes are unsupported",
    "anticipation() must be nonnegative",
    "iweights must be nonnegative",
    "The value of ivar() must be unique within time(). Some units are observed more than once in a period.",
    "unsupported option(s): foo",
    "csdid_stats requires prior csdid results or a saved RIF file",
    "type() must be one of simple, group, dynamic/event, or calendar",
    "csdid_estat requires prior csdid results",
    "tidy requires saving(filename)",
    "csdid_plot requires saving(filename). To export plot data, run: csdid_plot, saving(filename) replace",
    "Plot method not available for this type of aggregation",
    "no observations"
  ),
  stringsAsFactors = FALSE
)

write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F029",
  fixture_family = "validation-events",
  normative_source = "R did 2.5.1 validation/error semantics plus Stata command-surface mapping",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D008", "D014", "D015"),
  tolerance_ids = c("EXACT"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/negative-weight.csv", rows = nrow(neg), columns = ncol(neg)),
    list(path = "inputs/duplicate-input.csv", rows = nrow(dup), columns = ncol(dup)),
    list(path = "inputs/empty-after-markout.csv", rows = nrow(empty), columns = ncol(empty))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f029/generate.R", path = "tools/parity/generators/f029/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/events.json", schema = "error-warning-events"),
    list(path = "expected/r/events.csv", schema = "error-warning-events-csv")
  ),
  comparison_plan = list(
    list(actual = "Stata captured validation events", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = NULL,
  scope_note = "Partial validation-event fixture for current csdid/csdid_stats/csdid_estat/csdid_plot command surfaces. Full inherited R/Python error suites remain RT011/PY008."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
