#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f028/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f028")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/new-stata"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:36
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 12, 3, ifelse(d$id <= 24, 4, 0))
d$x1 <- 0.35 * d$time + 0.20 * sin(0.7 * d$id) + 0.10 * (d$id %% 3 == 0)
d$x2 <- 0.20 * d$time + 0.25 * cos(0.5 * d$id) - 0.08 * (d$id %% 4 == 0)
d$y0 <- 1.0 + 0.55 * d$time + 0.35 * d$x1 - 0.15 * d$x2 + 0.05 * cos(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.9 + 0.12 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

mp <- att_gt(
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

plot_attgt <- function(mp, groups = NULL) {
  out <- data.frame(
    plot_type = "attgt",
    series = ifelse(mp$t >= mp$group, "Post", "Pre"),
    x = mp$t,
    x_label = as.character(mp$t),
    estimate = mp$att,
    ci_low = mp$att - mp$c * mp$se,
    ci_high = mp$att + mp$c * mp$se,
    group = mp$group,
    time = mp$t,
    event_time = mp$t - mp$group
  )
  out$significant <- as.integer((out$ci_low > 0 & !is.na(out$ci_low)) | (out$ci_high < 0 & !is.na(out$ci_high)))
  if (!is.null(groups)) out <- out[out$group %in% groups, , drop = FALSE]
  out[order(out$group, out$time), ]
}

plot_aggte <- function(agg) {
  if (agg$type == "simple") stop("Plot method not available for this type of aggregation")
  crit <- if (is.null(agg$crit.val.egt)) qnorm(1 - agg$DIDparams$alp / 2) else agg$crit.val.egt
  out <- data.frame(
    plot_type = paste0("aggte_", agg$type),
    series = ifelse(agg$egt >= 0, "Post", "Pre"),
    x = agg$egt,
    x_label = as.character(agg$egt),
    estimate = agg$att.egt,
    ci_low = agg$att.egt - crit * agg$se.egt,
    ci_high = agg$att.egt + crit * agg$se.egt,
    group = NA_real_,
    time = NA_real_,
    event_time = NA_real_
  )
  if (agg$type == "dynamic") out$event_time <- agg$egt
  if (agg$type == "calendar") out$time <- agg$egt
  if (agg$type == "group") out$group <- agg$egt
  out$significant <- as.integer((out$ci_low > 0 & !is.na(out$ci_low)) | (out$ci_high < 0 & !is.na(out$ci_high)))
  out[order(out$x), ]
}

agg_dynamic <- suppressWarnings(aggte(mp, type = "dynamic", bstrap = FALSE, cband = FALSE))
agg_group <- suppressWarnings(aggte(mp, type = "group", bstrap = FALSE, cband = FALSE))
agg_calendar <- suppressWarnings(aggte(mp, type = "calendar", bstrap = FALSE, cband = FALSE))
agg_simple <- suppressWarnings(aggte(mp, type = "simple", bstrap = FALSE, cband = FALSE))

plot_attgt_all <- plot_attgt(mp)
plot_attgt_group3 <- plot_attgt(mp, groups = 3)
plot_aggte_dynamic <- plot_aggte(agg_dynamic)
plot_aggte_group <- plot_aggte(agg_group)
plot_aggte_calendar <- plot_aggte(agg_calendar)

write.csv(plot_attgt_all, file.path(fixture, "expected/r/plot-data-attgt.csv"), row.names = FALSE, na = "")
write.csv(plot_attgt_group3, file.path(fixture, "expected/r/plot-data-attgt-group3.csv"), row.names = FALSE, na = "")
write.csv(plot_aggte_dynamic, file.path(fixture, "expected/r/plot-data-aggte-dynamic.csv"), row.names = FALSE, na = "")
write.csv(plot_aggte_group, file.path(fixture, "expected/r/plot-data-aggte-group.csv"), row.names = FALSE, na = "")
write.csv(plot_aggte_calendar, file.path(fixture, "expected/r/plot-data-aggte-calendar.csv"), row.names = FALSE, na = "")

events <- list(
  list(
    return_code = 498,
    event_type = "error",
    event_key = "plot_simple_aggte_unavailable",
    offending_option = "type(simple)",
    message_normalized = "Plot method not available for this type of aggregation"
  )
)
writeLines(jsonlite::toJSON(events, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

schema <- list(
  matrix_id = "F028",
  fixture_family = "plot-data",
  plot_data_columns = names(plot_attgt_all),
  scope_note = "Partial plot-data fixture for ATT(g,t), ATT(g,t) group filtering, and dynamic/group/calendar aggregation plot data. Rendering, graph styling, inherited R/Python plotting tests, and JEL figures remain incomplete."
)
writeLines(jsonlite::toJSON(schema, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/new-stata/plot-schema.json"))

manifest <- list(
  matrix_id = "F028",
  fixture_family = "plot-data",
  normative_source = "R did 2.5.1 ggdid plot-data formulas",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D015"),
  tolerance_ids = c("TOL005", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f028/generate.R", path = "tools/parity/generators/f028/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/plot-data-attgt.csv", schema = "plot-data"),
    list(path = "expected/r/plot-data-attgt-group3.csv", schema = "plot-data"),
    list(path = "expected/r/plot-data-aggte-dynamic.csv", schema = "plot-data"),
    list(path = "expected/r/plot-data-aggte-group.csv", schema = "plot-data"),
    list(path = "expected/r/plot-data-aggte-calendar.csv", schema = "plot-data"),
    list(path = "expected/r/events.json", schema = "error-warning-events"),
    list(path = "expected/new-stata/plot-schema.json", schema = "plot-data-schema")
  ),
  comparison_plan = list(
    list(actual = "Stata csdid_plot ATT(g,t)", expected = "expected/r/plot-data-attgt.csv", tolerance_id = "TOL005", key_columns = c("plot_type", "group", "time")),
    list(actual = "Stata csdid_plot ATT(g,t) group 3", expected = "expected/r/plot-data-attgt-group3.csv", tolerance_id = "TOL005", key_columns = c("plot_type", "group", "time")),
    list(actual = "Stata csdid_plot dynamic aggregation", expected = "expected/r/plot-data-aggte-dynamic.csv", tolerance_id = "TOL005", key_columns = c("plot_type", "x")),
    list(actual = "Stata csdid_plot group aggregation", expected = "expected/r/plot-data-aggte-group.csv", tolerance_id = "TOL005", key_columns = c("plot_type", "x")),
    list(actual = "Stata csdid_plot calendar aggregation", expected = "expected/r/plot-data-aggte-calendar.csv", tolerance_id = "TOL005", key_columns = c("plot_type", "x")),
    list(actual = "Stata csdid_plot simple aggregation error", expected = "expected/r/events.json", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = NULL,
  scope_note = schema$scope_note
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
