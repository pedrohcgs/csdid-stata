#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f038/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f038")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

make_panel <- function(ids, times, groups, te_fun) {
  d <- expand.grid(id = ids, period = times)
  d <- d[order(d$id, d$period), ]
  d$g <- rep(groups, each = length(times))
  d$x <- rep(0.35 * sin(ids * 0.27) + 0.1 * (ids %% 3 == 0), each = length(times))
  d$y0 <- 1 + 0.25 * d$period + 0.25 * d$x + 0.03 * cos(d$id + d$period)
  d$te <- te_fun(d$g, d$period)
  d$y <- d$y0 + d$te
  d$y0 <- NULL
  d$te <- NULL
  d
}

ids <- 1:60
times <- 1:4
groups <- ifelse(ids <= 20, 3, ifelse(ids <= 40, 4, 0))
base <- make_panel(ids, times, groups, function(g, t) ifelse(g > 0 & t >= g, 0.8 + 0.1 * (t - g), 0))
base$t1 <- 1
write.csv(base, file.path(fixture, "inputs/t1.csv"), row.names = FALSE, na = "")

missing_cov <- base
missing_cov$x[1] <- NA_real_
write.csv(missing_cov, file.path(fixture, "inputs/missing-cov.csv"), row.names = FALSE, na = "")

ids_gap <- 1:90
times_gap <- c(1, 3, 4, 6)
groups_gap <- ifelse(ids_gap <= 18, 2, ifelse(ids_gap <= 36, 3, ifelse(ids_gap <= 54, 4, ifelse(ids_gap <= 72, 6, 0))))
gaps <- make_panel(ids_gap, times_gap, groups_gap, function(g, t) ifelse(g > 0 & t >= g, 0.6 + 0.2 * (t - g), 0))
write.csv(gaps, file.path(fixture, "inputs/fewer-periods.csv"), row.names = FALSE, na = "")

ids_zero <- 1:80
times_zero <- 6:10
groups_zero <- ifelse(ids_zero <= 20, 7, ifelse(ids_zero <= 40, 8, ifelse(ids_zero <= 60, 9, 10)))
zero_pre <- make_panel(ids_zero, times_zero, groups_zero, function(g, t) ifelse(g > 0 & t >= g, 1 + 0.1 * (t - g), 0))
zero_pre$y[zero_pre$period < zero_pre$g] <- 0
write.csv(zero_pre, file.path(fixture, "inputs/zero-pre.csv"), row.names = FALSE, na = "")

ids_ant <- 1:120
times_ant <- 1:5
groups_ant <- c(rep(0, 40), rep(4, 40), rep(6, 40))
anticipation <- make_panel(ids_ant, times_ant, groups_ant, function(g, t) ifelse(g > 0 & t >= g, 0.7, 0))
write.csv(anticipation, file.path(fixture, "inputs/anticipation.csv"), row.names = FALSE, na = "")

att_to_df <- function(scenario, out) {
  data.frame(
    scenario = scenario,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    inffunc_col = seq_along(out$att)
  )
}

agg_to_df <- function(scenario, type, agg) {
  if (type == "simple") {
    out <- data.frame(scenario = scenario, type = type, egt = NA_real_,
                      att = agg$overall.att, se = agg$overall.se,
                      overall_att = agg$overall.att, overall_se = agg$overall.se)
  } else {
    out <- data.frame(scenario = scenario, type = type, egt = agg$egt,
                      att = agg$att.egt, se = agg$se.egt,
                      overall_att = agg$overall.att, overall_se = agg$overall.se)
  }
  out$seq <- seq_len(nrow(out))
  out
}

att_rows <- list()
agg_rows <- list()

out_t1 <- suppressWarnings(att_gt(
  yname = "y", tname = "period", idname = "id", gname = "g", data = base,
  xformla = ~ 1, control_group = "notyettreated", est_method = "reg",
  bstrap = FALSE, cband = FALSE
))
att_rows[["t1"]] <- att_to_df("t1_column", out_t1)

# allow_unbalanced_panel = TRUE is the R route bal(none) maps to (the f072
# differential pinned the correspondence cell for cell): a covariate missing
# in one row costs that row, not the unit. The old oracle used the balanced
# default and agreed with csdid only while csdid over-dropped the unit.
out_missing <- suppressWarnings(att_gt(
  yname = "y", tname = "period", idname = "id", gname = "g", data = missing_cov,
  xformla = ~ x, control_group = "notyettreated", est_method = "reg",
  allow_unbalanced_panel = TRUE,
  bstrap = FALSE, cband = FALSE
))
att_rows[["missing"]] <- att_to_df("missing_covariate", out_missing)

for (em in c("dr", "reg", "ipw")) {
  out_gap <- suppressWarnings(att_gt(
    yname = "y", tname = "period", idname = "id", gname = "g", data = gaps,
    xformla = ~ x, est_method = em, bstrap = FALSE, cband = FALSE
  ))
  scenario <- paste0("fewer_periods__", em)
  att_rows[[scenario]] <- att_to_df(scenario, out_gap)
  for (type in c("dynamic", "group", "calendar")) {
    agg_rows[[paste(scenario, type, sep = "__")]] <- agg_to_df(
      scenario, type, suppressWarnings(aggte(out_gap, type = type, bstrap = FALSE, cband = FALSE, na.rm = TRUE))
    )
  }
}

for (bp in c("universal", "varying")) {
  out_zero <- suppressWarnings(att_gt(
    yname = "y", tname = "period", idname = "id", gname = "g", data = zero_pre,
    control_group = "notyettreated", base_period = bp,
    bstrap = FALSE, cband = FALSE
  ))
  att_rows[[paste0("zero_", bp)]] <- att_to_df(paste0("zero_pre__", bp), out_zero)
}

for (ant in c(0L, 2L)) {
  out_ant <- suppressWarnings(att_gt(
    yname = "y", tname = "period", idname = "id", gname = "g", data = anticipation,
    anticipation = ant, control_group = "nevertreated",
    bstrap = FALSE, cband = FALSE
  ))
  att_rows[[paste0("anticipation_", ant)]] <- att_to_df(paste0("anticipation__", ant), out_ant)
}

attgt <- do.call(rbind, att_rows)
aggte <- do.call(rbind, agg_rows)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(aggte, file.path(fixture, "expected/r/aggte.csv"), row.names = FALSE, na = "")

events <- data.frame(
  event_key = "missing_formula_variable",
  return_code = 111,
  event_type = "error",
  offending_option = "x variable not in dataset",
  message_normalized = "variable x_missing not found",
  stringsAsFactors = FALSE
)
write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

divergence <- data.frame(
  divergence_id = "F038-DIV001",
  surface = "inherited-user-bug-residuals",
  reason = "F038 freezes a compact R-anchored user-regression feature set. mpdta-specific regressions, repeated-cross-section small-group DRDID callback branches, Python review-fix bootstrap internals, and full inherited user-bug file mapping are covered by RT028, PY020, and PY023 dedicated gates rather than duplicated in this feature row.",
  accepted_behavior = "Stata must match R did 2.5.1 for the frozen harmless-column, missing-covariate, fewer-periods, zero-pre, missing-variable, and anticipation user-regression scenarios; deeper inherited file coverage remains enforced by the dedicated RT/PY rows.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "F038",
  fixture_family = "python-user-bug-regressions",
  normative_source = "R did test-user_bug_fixes.R and Python csdid test_user_bug_fixes.py",
  source_commit = "48f8fa1d991d14a0739c359fd16477e2497c4c6f5385b2b92ec698389ec3f6fc",
  decision_refs = c("D001", "D004"),
  tolerance_ids = c("TOL002", "EXACT"),
  inputs = list(
    list(path = "inputs/t1.csv", rows = nrow(base), columns = ncol(base)),
    list(path = "inputs/missing-cov.csv", rows = nrow(missing_cov), columns = ncol(missing_cov)),
    list(path = "inputs/fewer-periods.csv", rows = nrow(gaps), columns = ncol(gaps)),
    list(path = "inputs/zero-pre.csv", rows = nrow(zero_pre), columns = ncol(zero_pre)),
    list(path = "inputs/anticipation.csv", rows = nrow(anticipation), columns = ncol(anticipation))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f038/generate.R", path = "tools/parity/generators/f038/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/aggte.csv", schema = "aggte"),
    list(path = "expected/r/events.csv", schema = "error-warning-events-csv"),
    list(path = "expected/r/events.json", schema = "error-warning-events"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "expected/new-stata/aggte.csv", expected = "expected/r/aggte.csv", tolerance_id = "TOL002", key_columns = c("scenario", "type", "seq")),
    list(actual = "Stata captured validation events", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "Approved-divergence F038/PY023 user-regression evidence for harmless t1 columns, missing-covariate complete-case panel unit dropping, fewer observed periods than treatment groups with aggregations, zero pre-treatment outcomes, missing formula variables, and anticipation-window treatment-group coercion. F038-DIV001 records inherited user-bug residuals covered by RT028, PY020, and PY023 dedicated gates rather than duplicated here."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
