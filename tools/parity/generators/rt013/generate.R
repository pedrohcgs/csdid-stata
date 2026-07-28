#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt013/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt013")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

set.seed(20260401)
sp <- did::reset.sim(time.periods = 4, n = 300)
d <- did::build_sim_dataset(sp)
names(d) <- tolower(names(d))
write.csv(d, file.path(fixture, "inputs/sim-ggdid.csv"), row.names = FALSE, na = "")

mp <- suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  xformla = ~ x,
  data = d,
  tname = "period",
  idname = "id",
  gname = "g",
  est_method = "dr",
  bstrap = FALSE
)))

agg_dyn <- suppressWarnings(aggte(mp, type = "dynamic", bstrap = FALSE, cband = FALSE))
agg_grp <- suppressWarnings(aggte(mp, type = "group", bstrap = FALSE, cband = FALSE))
agg_cal <- suppressWarnings(aggte(mp, type = "calendar", bstrap = FALSE, cband = FALSE))
agg_sim <- suppressWarnings(aggte(mp, type = "simple", bstrap = FALSE, cband = FALSE))

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

first_group <- sort(unique(mp$group))[1]
plot_attgt_all <- plot_attgt(mp)
plot_attgt_first <- plot_attgt(mp, groups = first_group)
plot_aggte_dynamic <- plot_aggte(agg_dyn)
plot_aggte_group <- plot_aggte(agg_grp)
plot_aggte_calendar <- plot_aggte(agg_cal)

write.csv(plot_attgt_all, file.path(fixture, "expected/r/plot-data-attgt.csv"), row.names = FALSE, na = "")
write.csv(plot_attgt_first, file.path(fixture, "expected/r/plot-data-attgt-first-group.csv"), row.names = FALSE, na = "")
write.csv(plot_aggte_dynamic, file.path(fixture, "expected/r/plot-data-aggte-dynamic.csv"), row.names = FALSE, na = "")
write.csv(plot_aggte_group, file.path(fixture, "expected/r/plot-data-aggte-group.csv"), row.names = FALSE, na = "")
write.csv(plot_aggte_calendar, file.path(fixture, "expected/r/plot-data-aggte-calendar.csv"), row.names = FALSE, na = "")

events <- data.frame(
  event_key = c("invalid_group_warning", "simple_aggregation_error", "unsupported_graph_style_option"),
  return_code = c(0, 498, 198),
  message_normalized = c(
    "Some of the specified groups do not exist in the data. Reporting all available groups.",
    "Plot method not available for this type of aggregation",
    "unsupported option(s)"
  ),
  stringsAsFactors = FALSE
)
write.csv(events, file.path(fixture, "expected/contract/events.csv"), row.names = FALSE)
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/events.json"))

mapped_tests <- data.frame(
  source_file = "tests/testthat/test-ggdid.R",
  source_sha256 = "5752409812175f8f659750b50d2f57844bc78a0715beb6be98ade666f44838e3",
  source_test = c(
    "ggdid.MP returns a ggplot object",
    "ggdid.MP accepts group parameter",
    "ggdid.MP warns for non-existent group values",
    "ggdid works for type = dynamic",
    "ggdid works for type = group",
    "ggdid works for type = calendar",
    "ggdid errors for type = simple",
    "splot works for group-type and renders without deprecation warnings"
  ),
  mapped_scenario = c(
    "attgt_plot_data",
    "attgt_first_group_plot_data",
    "attgt_invalid_group_warning_all_groups",
    "aggte_dynamic_plot_data",
    "aggte_group_plot_data",
    "aggte_calendar_plot_data",
    "aggte_simple_rejected",
    "aggte_group_plot_data_no_error"
  ),
  assertion_family = c(
    "ggplot object creation mapped to Stata plot-data file creation",
    "group argument mapped to Stata group() plot-data filter",
    "R warning mapped to Stata informational diagnostic and all-group plot data",
    "dynamic AGGTE plot object mapped to dynamic plot-data export",
    "group AGGTE plot object mapped to group plot-data export",
    "calendar AGGTE plot object mapped to calendar plot-data export",
    "simple AGGTE plot error mapped to Stata simple aggregation rejection",
    "ggplot build/no-warning smoke mapped to successful group plot-data export"
  ),
  coverage_status = "mapped",
  divergence_id = "",
  stringsAsFactors = FALSE
)

divergent_tests <- data.frame(
  source_file = "tests/testthat/test-ggdid.R",
  source_sha256 = "5752409812175f8f659750b50d2f57844bc78a0715beb6be98ade666f44838e3",
  source_test = c(
    "ggdid.MP accepts custom labels",
    "ggdid.AGGTEobj accepts custom labels and theme settings",
    "ggdid.AGGTEobj works with theming=FALSE",
    "ggdid.AGGTEobj works with ref_line=NULL"
  ),
  mapped_scenario = "graph-styling-options",
  assertion_family = "R ggplot label/theme/ref_line options are rendered-graph styling controls outside Stata plot-data parity",
  coverage_status = "approved-divergence",
  divergence_id = "RT013-DIV001",
  stringsAsFactors = FALSE
)

upstream_map <- rbind(mapped_tests, divergent_tests)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE)
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = "RT013-DIV001",
  source_tests = paste(divergent_tests$source_test, collapse = "; "),
  reason = "The clean-room Stata surface currently freezes numerical plot data through csdid_plot, saving(); R ggplot label, theme, and reference-line controls are rendered-graph styling, not statistical output.",
  accepted_behavior = "Stata rejects unsupported graph styling options with a diagnostic while preserving plot-data parity for ATT(g,t) and dynamic/group/calendar aggregation outputs.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE)
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "RT013",
  fixture_family = "r-ggdid-plot-data",
  normative_source = "R did 2.5.1 tests/testthat/test-ggdid.R",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D004", "D015"),
  tolerance_ids = c("TOL005", "EXACT"),
  inputs = list(list(path = "inputs/sim-ggdid.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt013/generate.R", path = "tools/parity/generators/rt013/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 20260401, compact_simulation = "did::reset.sim(time.periods = 4, n = 300)"),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence"),
    list(path = "expected/contract/events.csv", schema = "error-warning-events"),
    list(path = "expected/contract/events.json", schema = "error-warning-events"),
    list(path = "expected/r/plot-data-attgt.csv", schema = "plot-data"),
    list(path = "expected/r/plot-data-attgt-first-group.csv", schema = "plot-data"),
    list(path = "expected/r/plot-data-aggte-dynamic.csv", schema = "plot-data"),
    list(path = "expected/r/plot-data-aggte-group.csv", schema = "plot-data"),
    list(path = "expected/r/plot-data-aggte-calendar.csv", schema = "plot-data")
  ),
  comparison_plan = list(
    list(actual = "Stata csdid_plot ATT(g,t)", expected = "expected/r/plot-data-attgt.csv", tolerance_id = "TOL005", key_columns = c("plot_type", "group", "time")),
    list(actual = "Stata csdid_plot ATT(g,t) first group", expected = "expected/r/plot-data-attgt-first-group.csv", tolerance_id = "TOL005", key_columns = c("plot_type", "group", "time")),
    list(actual = "Stata csdid_plot dynamic/group/calendar aggregation", expected = "expected/r/plot-data-aggte-*.csv", tolerance_id = "TOL005", key_columns = c("plot_type", "x")),
    list(actual = "Stata diagnostics for invalid group/simple/style options", expected = "expected/contract/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = list(
    status = "approved-divergence",
    path = "expected/contract/approved-divergence.csv",
    reason = "Rendered graph label/theme/ref_line controls are outside the frozen Stata plot-data contract."
  ),
  scope_note = "RT013 maps R did test-ggdid.R public plotting assertions to Stata csdid_plot plot-data exports for ATT(g,t), group filtering, invalid-group diagnostics, dynamic/group/calendar aggregation, and simple-aggregation rejection. Approved divergence covers R ggplot rendered-label/theme/ref_line controls because the Stata surface freezes numerical plot data and rejects unsupported graph styling options."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
