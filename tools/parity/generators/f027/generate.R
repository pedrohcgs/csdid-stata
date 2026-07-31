#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f027/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f027")
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
aggs <- list(
  simple = aggte(mp, type = "simple", bstrap = FALSE, cband = FALSE),
  group = suppressWarnings(aggte(mp, type = "group", bstrap = FALSE, cband = FALSE)),
  calendar = suppressWarnings(aggte(mp, type = "calendar", bstrap = FALSE, cband = FALSE)),
  dynamic = suppressWarnings(aggte(mp, type = "dynamic", bstrap = FALSE, cband = FALSE))
)

z <- qnorm(1 - mp$alp / 2)
tidy_attgt <- data.frame(
  term = paste0("ATT(", mp$group, ",", mp$t, ")"),
  group = mp$group,
  time = mp$t,
  estimate = mp$att,
  std_error = mp$se,
  statistic = mp$att / mp$se,
  p_value = 2 * pnorm(-abs(mp$att / mp$se)),
  conf_low = mp$att - z * mp$se,
  conf_high = mp$att + z * mp$se,
  point_conf_low = mp$att - z * mp$se,
  point_conf_high = mp$att + z * mp$se
)

glance_attgt <- data.frame(
  nobs = mp$n,
  ngroup = mp$DIDparams$treated_groups_count,
  ntime = mp$DIDparams$time_periods_count,
  control_group = mp$DIDparams$control_group,
  est_method = mp$DIDparams$est_method
)

tidy_aggte <- function(agg) {
  za <- qnorm(1 - agg$DIDparams$alp / 2)
  if (agg$type == "simple") {
    return(data.frame(
      type = agg$type,
      term = "ATT(simple average)",
      estimate = agg$overall.att,
      std_error = agg$overall.se,
      statistic = agg$overall.att / agg$overall.se,
      p_value = 2 * pnorm(-abs(agg$overall.att / agg$overall.se)),
      conf_low = agg$overall.att - za * agg$overall.se,
      conf_high = agg$overall.att + za * agg$overall.se,
      point_conf_low = agg$overall.att - za * agg$overall.se,
      point_conf_high = agg$overall.att + za * agg$overall.se
    ))
  }
  if (agg$type == "dynamic") {
    return(data.frame(
      type = agg$type,
      term = paste0("ATT(", agg$egt, ")"),
      event_time = agg$egt,
      estimate = agg$att.egt,
      std_error = agg$se.egt,
      statistic = agg$att.egt / agg$se.egt,
      p_value = 2 * pnorm(-abs(agg$att.egt / agg$se.egt)),
      conf_low = agg$att.egt - agg$crit.val.egt * agg$se.egt,
      conf_high = agg$att.egt + agg$crit.val.egt * agg$se.egt,
      point_conf_low = agg$att.egt - za * agg$se.egt,
      point_conf_high = agg$att.egt + za * agg$se.egt
    ))
  }
  if (agg$type == "calendar") {
    return(data.frame(
      type = agg$type,
      time = agg$egt,
      term = paste0("ATT(", agg$egt, ")"),
      estimate = agg$att.egt,
      std_error = agg$se.egt,
      statistic = agg$att.egt / agg$se.egt,
      p_value = 2 * pnorm(-abs(agg$att.egt / agg$se.egt)),
      conf_low = agg$att.egt - agg$crit.val.egt * agg$se.egt,
      conf_high = agg$att.egt + agg$crit.val.egt * agg$se.egt,
      point_conf_low = agg$att.egt - za * agg$se.egt,
      point_conf_high = agg$att.egt + za * agg$se.egt
    ))
  }
  if (agg$type == "group") {
    return(data.frame(
      type = agg$type,
      term = c("ATT(Average)", paste0("ATT(", agg$egt, ")")),
      group = c("Average", as.character(agg$egt)),
      estimate = c(agg$overall.att, agg$att.egt),
      std_error = c(agg$overall.se, agg$se.egt),
      statistic = c(agg$overall.att, agg$att.egt) / c(agg$overall.se, agg$se.egt),
      p_value = 2 * pnorm(-abs(c(agg$overall.att, agg$att.egt) / c(agg$overall.se, agg$se.egt))),
      conf_low = c(agg$overall.att - za * agg$overall.se, agg$att.egt - agg$crit.val.egt * agg$se.egt),
      conf_high = c(agg$overall.att + za * agg$overall.se, agg$att.egt + agg$crit.val.egt * agg$se.egt),
      point_conf_low = c(agg$overall.att - za * agg$overall.se, agg$att.egt - za * agg$se.egt),
      point_conf_high = c(agg$overall.att + za * agg$overall.se, agg$att.egt + za * agg$se.egt)
    ))
  }
  stop("unsupported aggregation type: ", agg$type)
}

glance_aggte <- function(agg) {
  data.frame(
    type = agg$type,
    nobs = agg$DIDparams$id_count,
    ngroup = agg$DIDparams$treated_groups_count,
    ntime = agg$DIDparams$time_periods_count,
    control_group = agg$DIDparams$control_group,
    est_method = agg$DIDparams$est_method
  )
}

tidy_aggte_simple <- tidy_aggte(aggs$simple)
tidy_aggte_group <- tidy_aggte(aggs$group)
tidy_aggte_calendar <- tidy_aggte(aggs$calendar)
tidy_aggte_dynamic <- tidy_aggte(aggs$dynamic)

glance_aggte_simple <- glance_aggte(aggs$simple)
glance_aggte_group <- glance_aggte(aggs$group)
glance_aggte_calendar <- glance_aggte(aggs$calendar)
glance_aggte_dynamic <- glance_aggte(aggs$dynamic)

write.csv(tidy_attgt, file.path(fixture, "expected/r/tidy-attgt.csv"), row.names = FALSE, na = "")
write.csv(glance_attgt, file.path(fixture, "expected/r/glance-attgt.csv"), row.names = FALSE, na = "")
write.csv(tidy_aggte_simple, file.path(fixture, "expected/r/tidy-aggte-simple.csv"), row.names = FALSE, na = "")
write.csv(glance_aggte_simple, file.path(fixture, "expected/r/glance-aggte-simple.csv"), row.names = FALSE, na = "")
write.csv(tidy_aggte_group, file.path(fixture, "expected/r/tidy-aggte-group.csv"), row.names = FALSE, na = "")
write.csv(glance_aggte_group, file.path(fixture, "expected/r/glance-aggte-group.csv"), row.names = FALSE, na = "")
write.csv(tidy_aggte_calendar, file.path(fixture, "expected/r/tidy-aggte-calendar.csv"), row.names = FALSE, na = "")
write.csv(glance_aggte_calendar, file.path(fixture, "expected/r/glance-aggte-calendar.csv"), row.names = FALSE, na = "")
write.csv(tidy_aggte_dynamic, file.path(fixture, "expected/r/tidy-aggte-dynamic.csv"), row.names = FALSE, na = "")
write.csv(glance_aggte_dynamic, file.path(fixture, "expected/r/glance-aggte-dynamic.csv"), row.names = FALSE, na = "")

schema <- list(
  matrix_id = "F027",
  fixture_family = "exportable-tables",
  tables = list(
    tidy_attgt = names(tidy_attgt),
    glance_attgt = names(glance_attgt),
    tidy_aggte_simple = names(tidy_aggte_simple),
    glance_aggte_simple = names(glance_aggte_simple),
    tidy_aggte_group = names(tidy_aggte_group),
    glance_aggte_group = names(glance_aggte_group),
    tidy_aggte_calendar = names(tidy_aggte_calendar),
    glance_aggte_calendar = names(glance_aggte_calendar),
    tidy_aggte_dynamic = names(tidy_aggte_dynamic),
    glance_aggte_dynamic = names(glance_aggte_dynamic)
  ),
  scope_note = "Partial tidy/glance table export for ATT(g,t) and simple, group, calendar, and dynamic aggregation. Inherited R/Python tidy/glance tests and richer table exporters remain incomplete."
)
writeLines(
  jsonlite::toJSON(schema, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/export-schema.json")
)

manifest <- list(
  matrix_id = "F027",
  fixture_family = "exportable-tables",
  normative_source = "R did 2.5.1 tidy/glance formulas",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D014"),
  tolerance_ids = c("EXACT", "TOL002"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f027/generate.R", path = "tools/parity/generators/f027/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/tidy-attgt.csv", schema = "tidy-attgt"),
    list(path = "expected/r/glance-attgt.csv", schema = "glance-attgt"),
    list(path = "expected/r/tidy-aggte-simple.csv", schema = "tidy-aggte-simple"),
    list(path = "expected/r/glance-aggte-simple.csv", schema = "glance-aggte-simple"),
    list(path = "expected/r/tidy-aggte-group.csv", schema = "tidy-aggte-group"),
    list(path = "expected/r/glance-aggte-group.csv", schema = "glance-aggte-group"),
    list(path = "expected/r/tidy-aggte-calendar.csv", schema = "tidy-aggte-calendar"),
    list(path = "expected/r/glance-aggte-calendar.csv", schema = "glance-aggte-calendar"),
    list(path = "expected/r/tidy-aggte-dynamic.csv", schema = "tidy-aggte-dynamic"),
    list(path = "expected/r/glance-aggte-dynamic.csv", schema = "glance-aggte-dynamic"),
    list(path = "expected/new-stata/export-schema.json", schema = "exportable-table-schema")
  ),
  comparison_plan = list(
    list(actual = "Stata csdid_estat tidy ATT(g,t)", expected = "expected/r/tidy-attgt.csv", tolerance_id = "TOL002", key_columns = c("term", "group", "time")),
    list(actual = "Stata csdid_estat glance ATT(g,t)", expected = "expected/r/glance-attgt.csv", tolerance_id = "EXACT", key_columns = c("row")),
    list(actual = "Stata csdid_estat tidy simple aggte", expected = "expected/r/tidy-aggte-simple.csv", tolerance_id = "TOL002", key_columns = c("type", "term")),
    list(actual = "Stata csdid_estat glance simple aggte", expected = "expected/r/glance-aggte-simple.csv", tolerance_id = "EXACT", key_columns = c("type")),
    list(actual = "Stata csdid_estat tidy group aggte", expected = "expected/r/tidy-aggte-group.csv", tolerance_id = "TOL002", key_columns = c("type", "term", "group")),
    list(actual = "Stata csdid_estat glance group aggte", expected = "expected/r/glance-aggte-group.csv", tolerance_id = "EXACT", key_columns = c("type")),
    list(actual = "Stata csdid_estat tidy calendar aggte", expected = "expected/r/tidy-aggte-calendar.csv", tolerance_id = "TOL002", key_columns = c("type", "term", "time")),
    list(actual = "Stata csdid_estat glance calendar aggte", expected = "expected/r/glance-aggte-calendar.csv", tolerance_id = "EXACT", key_columns = c("type")),
    list(actual = "Stata csdid_estat tidy dynamic aggte", expected = "expected/r/tidy-aggte-dynamic.csv", tolerance_id = "TOL002", key_columns = c("type", "term", "event_time")),
    list(actual = "Stata csdid_estat glance dynamic aggte", expected = "expected/r/glance-aggte-dynamic.csv", tolerance_id = "EXACT", key_columns = c("type"))
  ),
  approved_divergence = NULL,
  scope_note = schema$scope_note
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
