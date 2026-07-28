#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt026/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt026")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

data(mpdta, package = "did")
d <- mpdta
names(d)[names(d) == "first.treat"] <- "first_treat"
write.csv(d, file.path(fixture, "inputs/mpdta.csv"), row.names = FALSE, na = "")

set.seed(1234)
mp <- att_gt(
  yname = "lemp",
  gname = "first_treat",
  idname = "countyreal",
  tname = "year",
  xformla = ~1,
  data = d,
  bstrap = FALSE,
  cband = FALSE
)

aggs <- list(
  dynamic = aggte(mp, type = "dynamic", bstrap = FALSE, cband = FALSE),
  group = aggte(mp, type = "group", bstrap = FALSE, cband = FALSE),
  calendar = aggte(mp, type = "calendar", bstrap = FALSE, cband = FALSE),
  simple = aggte(mp, type = "simple", bstrap = FALSE, cband = FALSE)
)

z <- qnorm(1 - mp$alp / 2)
tidy_attgt <- data.frame(
  term = paste0("ATT(", mp$group, ",", mp$t, ")"),
  group = mp$group,
  time = mp$t,
  estimate = mp$att,
  std_error = mp$se,
  statistic = mp$att / mp$se,
  p_value = 2 * (1 - pnorm(abs(mp$att / mp$se))),
  conf_low = mp$att - z * mp$se,
  conf_high = mp$att + z * mp$se,
  point_conf_low = mp$att - z * mp$se,
  point_conf_high = mp$att + z * mp$se
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
      p_value = 2 * (1 - pnorm(abs(agg$overall.att / agg$overall.se))),
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
      p_value = 2 * (1 - pnorm(abs(agg$att.egt / agg$se.egt))),
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
      p_value = 2 * (1 - pnorm(abs(c(agg$overall.att, agg$att.egt) / c(agg$overall.se, agg$se.egt)))),
      conf_low = c(agg$overall.att - za * agg$overall.se, agg$att.egt - agg$crit.val.egt * agg$se.egt),
      conf_high = c(agg$overall.att + za * agg$overall.se, agg$att.egt + agg$crit.val.egt * agg$se.egt),
      point_conf_low = c(agg$overall.att - za * agg$overall.se, agg$att.egt - za * agg$se.egt),
      point_conf_high = c(agg$overall.att + za * agg$overall.se, agg$att.egt + za * agg$se.egt)
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
      p_value = 2 * (1 - pnorm(abs(agg$att.egt / agg$se.egt))),
      conf_low = agg$att.egt - agg$crit.val.egt * agg$se.egt,
      conf_high = agg$att.egt + agg$crit.val.egt * agg$se.egt,
      point_conf_low = agg$att.egt - za * agg$se.egt,
      point_conf_high = agg$att.egt + za * agg$se.egt
    ))
  }
  stop("unsupported aggregation type: ", agg$type)
}

write.csv(tidy_attgt, file.path(fixture, "expected/r/tidy-attgt.csv"), row.names = FALSE, na = "")
for (nm in names(aggs)) {
  write.csv(tidy_aggte(aggs[[nm]]), file.path(fixture, paste0("expected/r/tidy-aggte-", nm, ".csv")), row.names = FALSE, na = "")
}

nobs_expected <- data.frame(
  object = c("MP", "dynamic", "group", "calendar", "simple"),
  nobs = c(mp$n, vapply(aggs, function(x) x$DIDparams$id_count, numeric(1))),
  stringsAsFactors = FALSE
)
write.csv(nobs_expected, file.path(fixture, "expected/r/nobs.csv"), row.names = FALSE, na = "")

upstream_map <- data.frame(
  source_file = "tests/testthat/test-tidy.R",
  source_sha256 = "534afcf046f23224e61af67b1362f232bdeae6ccc8b6904383224e64f80bc9b3",
  source_test = c(
    "tidy.MP returns expected columns",
    "tidy.MP statistic equals estimate / std.error",
    "tidy.MP p.value matches normal approximation",
    "tidy.MP p.value is between 0 and 1",
    "tidy.AGGTEobj (dynamic) returns expected columns",
    "tidy.AGGTEobj (group) returns expected columns",
    "tidy.AGGTEobj (calendar) returns expected columns",
    "tidy.AGGTEobj (simple) returns expected columns",
    "tidy.AGGTEobj statistic and p.value are consistent",
    # Upstream has three separate nobs tests; one merged row left all three
    # unclaimed by name, which the coverage gate reads as uncovered.
    "nobs.MP returns number of unique units",
    "nobs.AGGTEobj returns number of unique units",
    "nobs.MP and nobs.AGGTEobj agree"
  ),
  mapped_scenario = c(
    "tidy-attgt",
    "tidy-attgt",
    "tidy-attgt",
    "tidy-attgt",
    "tidy-aggte-dynamic",
    "tidy-aggte-group",
    "tidy-aggte-calendar",
    "tidy-aggte-simple",
    "tidy-aggte-all",
    "nobs",
    "nobs",
    "nobs"
  ),
  assertion_family = c(
    "expected Stata-normalized tidy columns",
    "statistic formula",
    "normal p-value formula",
    "p-value range",
    "expected Stata-normalized dynamic columns",
    "expected Stata-normalized group columns",
    "expected Stata-normalized calendar columns",
    "expected Stata-normalized simple columns",
    "statistic and p-value formulas for all aggregation types",
    "unique-unit nobs equality",
    "unique-unit nobs equality",
    "unique-unit nobs equality"
  ),
  coverage_status = "mapped",
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/contract/upstream-test-map.json"))

manifest <- list(
  matrix_id = "RT026",
  fixture_family = "r-tidy-output",
  normative_source = "R did 2.5.1 tests/testthat/test-tidy.R",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D004", "D014"),
  tolerance_ids = c("EXACT", "TOL002"),
  inputs = list(list(path = "inputs/mpdta.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt026/generate.R", path = "tools/parity/generators/rt026/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 1234),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/r/tidy-attgt.csv", schema = "tidy-attgt"),
    list(path = "expected/r/tidy-aggte-dynamic.csv", schema = "tidy-aggte-dynamic"),
    list(path = "expected/r/tidy-aggte-group.csv", schema = "tidy-aggte-group"),
    list(path = "expected/r/tidy-aggte-calendar.csv", schema = "tidy-aggte-calendar"),
    list(path = "expected/r/tidy-aggte-simple.csv", schema = "tidy-aggte-simple"),
    list(path = "expected/r/nobs.csv", schema = "nobs-output")
  ),
  comparison_plan = list(
    list(actual = "Stata tidy ATT(g,t)", expected = "expected/r/tidy-attgt.csv", tolerance_id = "TOL002", key_columns = c("term", "group", "time")),
    list(actual = "Stata tidy aggregation exports", expected = "expected/r/tidy-aggte-*.csv", tolerance_id = "TOL002", key_columns = c("type", "term")),
    list(actual = "Stata nobs metadata", expected = "expected/r/nobs.csv", tolerance_id = "EXACT", key_columns = c("object"))
  ),
  approved_divergence = NULL,
  scope_note = "RT026 maps all tidy/nobs tests in tests/testthat/test-tidy.R to Stata-normalized tidy export columns, statistic and p-value formulas, p-value bounds, and unique-unit nobs metadata for MP and simple/group/calendar/dynamic aggregation on mpdta."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
