#!/usr/bin/env Rscript

# F053 -- saving() on every estat subcommand.
#
# This fixture pins a Stata surface contract, not a numerical one: the claim is
# that every estat subcommand writes the result it computed when given
# saving(). There is no R counterpart, because R has no estat and no saving() --
# the reference implementation returns objects and the user writes them out
# with R's own tools. So this generator writes the input panel and the contract
# itself, and no R oracle.
#
# The panel is deliberately ordinary: four periods, two treated cohorts and a
# never-treated group, large enough that every aggregation (event, dynamic,
# simple, group, calendar) has something to report. If any aggregation came
# back empty the test could pass by writing an empty file, so the generator
# refuses to write a panel that cannot support all five.

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f053/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f053")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

cohorts <- c(3, 4, 0)
units <- do.call(rbind, lapply(seq_along(cohorts), function(j) {
  data.frame(id = (j - 1) * 20 + 1:20, g = cohorts[j])
}))
units$alpha <- 0.3 * ((units$id * 5) %% 7) - 0.9

d <- do.call(rbind, lapply(1:4, function(t) {
  treat <- ifelse(units$g > 0 & t >= units$g, 0.5 + 0.2 * (t - units$g), 0)
  data.frame(
    id = units$id,
    time = t,
    g = units$g,
    y = units$alpha + 0.25 * t + treat + 0.19 * sin(2.3 * units$id + 1.7 * t)
  )
}))
d <- d[order(d$id, d$time), ]
rownames(d) <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

# Every aggregation must have something to report, or the test could pass by
# writing an empty file.
n_cohorts <- length(setdiff(cohorts, 0))
n_event   <- length(unique(unlist(lapply(setdiff(cohorts, 0), function(g) (1:4) - g))))
if (n_cohorts < 2 || n_event < 3) {
  stop("F053 panel cannot support every aggregation")
}

contract <- list(
  claim = paste(
    "saving(filename) on any estat subcommand writes the result that subcommand",
    "computed, as a Stata dataset. replace overwrites."
  ),
  subcommands = c("attgt", "event", "dynamic", "simple", "group", "calendar"),
  attgt_options = list(
    accepted = c("saving", "replace"),
    refused = c("post", "window", "level", "dropmissing"),
    refused_return_code = 198
  ),
  undocumented_but_supported = list(
    subcommands = c("tidy", "glance"),
    note = paste(
      "tidy and glance keep working and are not documented. They are borrowed",
      "from R's broom package, where the words carry meaning they do not carry",
      "in Stata. They are pinned against the new spellings so the two paths",
      "cannot drift apart."
    )
  ),
  prior_defect = paste(
    "saving() was parsed at the syntax line and then ignored on event, dynamic,",
    "simple, group and calendar, so `estat event, saving(f)' returned rc 0 and",
    "wrote no file; estat attgt refused it outright."
  ),
  panel = list(units = nrow(units), periods = 4L, cohorts = cohorts, rows = nrow(d))
)
writeLines(
  jsonlite::toJSON(contract, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/contract/export-surface.json")
)

manifest <- list(
  matrix_id = "F053",
  fixture_family = "results-export-surface",
  normative_source = "Stata postestimation conventions (owner-directed); no R counterpart",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D008"),
  tolerance_ids = c("EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f053/generate.R", path = "tools/parity/generators/f053/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/contract/export-surface.json", schema = "export-surface")),
  comparison_plan = list(list(actual = "Stata estat saving() output", expected = "expected/contract/export-surface.json", tolerance_id = "EXACT", key_columns = c("subcommand"))),
  approved_divergence = NULL,
  scope_note = "Stata-only surface contract: R has no estat and no saving(), so there is no oracle to compare against."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
cat(sprintf("F053: %d rows, %d units, %d event times\n", nrow(d), nrow(units), n_event))
