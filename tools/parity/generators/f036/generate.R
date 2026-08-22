#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f036/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f036")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/new-stata"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:36
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 12, 3, ifelse(d$id <= 24, 4, 0))
d$x1 <- 0.15 * d$time + 0.10 * sin(d$id)
d$x2 <- 0.10 * d$time + 0.08 * cos(d$id)
d$w <- 1 + 0.05 * (d$id %% 4)
d$y0 <- 0.9 + 0.35 * d$time + 0.20 * d$x1 - 0.10 * d$x2 + 0.02 * (d$id %% 5)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.7 + 0.08 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

inventory <- data.frame(
  surface = c(
    "csdid", "csdid", "csdid", "csdid", "csdid", "csdid", "csdid",
    "csdid", "csdid", "csdid", "csdid", "csdid", "csdid", "csdid",
    "csdid", "csdid", "csdid", "csdid", "csdid", "csdid_stats", "csdid_estat", "csdid_plot"
  ),
  option = c(
    "ivar/time/gvar", "omitted ivar", "notyet", "method(dripw)",
    "method(stdipw)", "asinr", "bal()/balance()", "long/long2",
    "dryrun", "agg()", "pscoretrim()", "from()/window()", "wboot aliases",
    "cluster()", "id()", "notyettreated/nevertreated", "vce(cluster)", "wboot shorthand",
    "saverif()", "min_e/max_e/balance_e/na_rm",
    "tidy/glance saving replace", "saving/group"
  ),
  target_classification = c(
    "retain", "retain", "retain", "soft-deprecated alias",
    "soft-deprecated alias", "accepted no-op warning", "soft-deprecated alias",
    "deprecated universal-base event-study alias", "unsupported-by-design",
    "retain event wrapper; defer other types to csdid_stats", "retain",
    "postestimation window mapping", "retain as R-compatible aliases",
    "retain analytical; bootstrap later", "Stata-style alias", "Stata-style aliases",
    "Stata-style alias", "Stata-style alias", "retain", "retain", "retain", "retain"
  ),
  current_behavior = c(
    "accepted", "accepted", "accepted", "accepted maps to dr",
    "accepted maps to ipw", "accepted warning", "accepted warning",
    "accepted warning", "explicit error", "agg(event) accepted; other types error",
    "accepted with validation", "unsupported option error",
    "partial F035 support", "partial F015/F016 support", "accepted as ivar()",
    "accepted and conflict-checked", "accepted as cluster()", "accepted as wboot(reps()/seed()/rseed())",
    "partial F034 support", "partial F025/F051 support", "partial F027/F051 support", "partial F028 support"
  ),
  evidence = c(
    "F001-F002/F030", "F018", "F008", "F010/F036",
    "F010/F036", "F017/F036", "F017/F036", "F017/F036/JEL",
    "F036", "F025/F036/JEL", "F033/F036", "F036", "F035/F036",
    "F015/F016", "F051", "F051", "F051", "F035/F051", "F034",
    "F025/F036/F051", "F027/F036/F051", "F028/F036"
  ),
  stringsAsFactors = FALSE
)
write.csv(inventory, file.path(fixture, "expected/new-stata/option-inventory.csv"), row.names = FALSE, na = "")
writeLines(
  jsonlite::toJSON(inventory, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/option-inventory.json")
)

events <- data.frame(
  event_key = c(
    "dryrun_rejected",
    "agg_not_yet",
    "pscoretrim_invalid",
    "from_unsupported",
    "estat_style_unsupported",
    "plot_style_unsupported"
  ),
  return_code = c(198, 198, 198, 198, 198, 198),
  event_type = "error",
  offending_option = c(
    "dryrun",
    "agg(simple)",
    "pscoretrim(1)",
    "from(-1)",
    "csdid_estat tidy style(foo)",
    "csdid_plot style(foo)"
  ),
  message_normalized = c(
    "dryrun is an internal legacy option and is unsupported",
    "agg() immediate aggregation currently supports only event/dynamic; run csdid_stats for simple, group, or calendar aggregation",
    "pscoretrim() must be between 0 and 1",
    "unsupported option(s): from(-1)",
    "unsupported option(s): style(foo)",
    "unsupported option(s): style(foo)"
  ),
  stringsAsFactors = FALSE
)
write.csv(events, file.path(fixture, "expected/new-stata/events.csv"), row.names = FALSE, na = "")
writeLines(
  jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/events.json")
)

divergence <- data.frame(
  divergence_id = "F036-DIV001",
  surface = "legacy-stata-option-surface",
  reason = "Some legacy Stata convenience options have no R did 2.5.1 analogue or are intentionally routed through newer postestimation commands. They are frozen as retained, soft-deprecated, explicitly rejected, or not-yet wrapper behavior rather than implemented as silent legacy behavior.",
  accepted_behavior = "The option inventory must classify all current csdid/csdid_stats/csdid_estat/csdid_plot surfaces, preserve retained R-compatible options, warn for soft-deprecated aliases, and return explicit diagnostics for unsupported legacy or styling options.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "F036",
  fixture_family = "legacy-option-inventory",
  normative_source = "Legacy Stata option inventory with R did 2.5.1 as behavioral oracle",
  source_commit = "fdbae25521a941314af8d84ec0c93fb0596daa8e",
  decision_refs = c("D008", "D009"),
  tolerance_ids = c("EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f036/generate.R", path = "tools/parity/generators/f036/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/new-stata/option-inventory.csv", schema = "option-inventory-csv"),
    list(path = "expected/new-stata/option-inventory.json", schema = "option-inventory"),
    list(path = "expected/new-stata/events.csv", schema = "error-warning-events-csv"),
    list(path = "expected/new-stata/events.json", schema = "error-warning-events"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "Stata accepted/rejected option behavior", expected = "expected/new-stata/option-inventory.csv", tolerance_id = "EXACT", key_columns = c("surface", "option")),
    list(actual = "Stata captured validation events", expected = "expected/new-stata/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "Approved-divergence F036 executable inventory for the current csdid/csdid_stats/csdid_estat/csdid_plot option surface. Accepted core options, pscoretrim(), soft-deprecated aliases, Stata-style id()/vce()/control/bootstrap aliases, the agg(event) compatibility wrapper, postestimation aggregation aliases, and explicit diagnostics for unsupported legacy/convenience/styling options are checked. F036-DIV001 records legacy Stata option surfaces that are classified rather than silently reimplemented."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
