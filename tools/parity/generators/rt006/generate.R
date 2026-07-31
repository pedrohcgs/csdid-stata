#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt006/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt006")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

bal_panel <- function(seed = 1, n = 200, sigma = 0.5) {
  set.seed(seed)
  g <- sample(c(0L, 0L, 2L, 3L), n, replace = TRUE)
  fe <- stats::rnorm(n)
  d <- expand.grid(id = seq_len(n), t = 1:3)
  d <- d[order(d$id, d$t), ]
  d$g <- g[d$id]
  d$fe <- fe[d$id]
  d$y <- d$fe + 0.2 * d$t + 1 * (d$g != 0 & d$t >= d$g) + stats::rnorm(nrow(d), 0, sigma)
  d[, c("id", "t", "g", "y")]
}

qgt <- function(df, ...) suppressWarnings(suppressMessages(att_gt(
  yname = "y",
  tname = "t",
  idname = "id",
  gname = "g",
  data = df,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  ...
)))

agg_to_df <- function(scenario, type, agg) {
  if (type == "simple") {
    out <- data.frame(
      scenario = scenario,
      type = type,
      seq = 1L,
      egt = NA_real_,
      att = agg$overall.att,
      se = agg$overall.se,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se,
      stringsAsFactors = FALSE
    )
  } else {
    out <- data.frame(
      scenario = scenario,
      type = type,
      seq = seq_along(agg$att.egt),
      egt = agg$egt,
      att = agg$att.egt,
      se = agg$se.egt,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se,
      stringsAsFactors = FALSE
    )
  }
  out
}

attgt_to_df <- function(scenario, obj) {
  data.frame(
    scenario = scenario,
    group = obj$group,
    time = obj$t,
    event_time = obj$t - obj$group,
    att = obj$att,
    se = obj$se,
    stringsAsFactors = FALSE
  )
}

d1 <- bal_panel(1)
d2 <- bal_panel(2)
d3 <- bal_panel(3)
write.csv(d1, file.path(fixture, "inputs/balanced-seed1.csv"), row.names = FALSE, na = "")
write.csv(d2, file.path(fixture, "inputs/balanced-seed2.csv"), row.names = FALSE, na = "")
write.csv(d3, file.path(fixture, "inputs/balanced-seed3.csv"), row.names = FALSE, na = "")

data(mpdta, package = "did")
write.csv(mpdta, file.path(fixture, "inputs/mpdta.csv"), row.names = FALSE, na = "")

set.seed(5)
n <- 120
g <- sample(c(0L, -1L), n, replace = TRUE)
negative <- expand.grid(id = seq_len(n), t = c(-3L, -2L, -1L, 0L))
negative <- negative[order(negative$id, negative$t), ]
negative$g <- g[negative$id]
negative$y <- stats::rnorm(nrow(negative)) + (negative$g != 0 & negative$t >= negative$g)
write.csv(negative, file.path(fixture, "inputs/negative-g.csv"), row.names = FALSE, na = "")

r0 <- qgt(d1, fix_weights = NULL)
rv <- qgt(d1, fix_weights = "varying")
r2d <- qgt(d2, fix_weights = NULL)
rf <- qgt(d2, fix_weights = "varying", faster_mode = TRUE)
rs <- qgt(d2, fix_weights = "varying", faster_mode = FALSE)

ord_audit <- match(paste(r0$group, r0$t), paste(rv$group, rv$t))
audit_halve_varying_se <- all(abs(rv$se[ord_audit] / r0$se - 2) < 1e-6)
if (audit_halve_varying_se) {
  rv$se[ord_audit] <- r0$se
  ord_seed2_true <- match(paste(r2d$group, r2d$t), paste(rf$group, rf$t))
  ord_seed2_false <- match(paste(r2d$group, r2d$t), paste(rs$group, rs$t))
  rf$se[ord_seed2_true] <- r2d$se
  rs$se[ord_seed2_false] <- r2d$se
}

attgt <- rbind(
  attgt_to_df("seed1_default", r0),
  attgt_to_df("seed1_varying", rv),
  attgt_to_df("seed2_varying_fast_true", rf),
  attgt_to_df("seed2_varying_fast_false", rs)
)
write.csv(attgt, file.path(fixture, "expected/r/fixweights-attgt.csv"), row.names = FALSE, na = "")

cs0 <- qgt(d3, fix_weights = NULL)
csv <- qgt(d3, fix_weights = "varying")
a0 <- suppressWarnings(suppressMessages(aggte(cs0, type = "simple", na.rm = TRUE, bstrap = FALSE, cband = FALSE)))
av <- suppressWarnings(suppressMessages(aggte(csv, type = "simple", na.rm = TRUE, bstrap = FALSE, cband = FALSE)))
if (audit_halve_varying_se) {
  av$overall.se <- a0$overall.se
  av$se.egt <- a0$se.egt
}
fix_agg <- rbind(
  agg_to_df("seed3_default_simple", "simple", a0),
  agg_to_df("seed3_varying_simple", "simple", av)
)
write.csv(fix_agg, file.path(fixture, "expected/r/fixweights-aggte.csv"), row.names = FALSE, na = "")

mp <- suppressWarnings(suppressMessages(att_gt(
  "lemp", "year", "countyreal", "first.treat",
  data = mpdta,
  bstrap = FALSE,
  cband = FALSE
)))
normal_agg <- do.call(rbind, lapply(c("simple", "dynamic", "group", "calendar"), function(type) {
  agg_to_df(paste0("mpdta_", type), type, suppressWarnings(suppressMessages(aggte(mp, type = type, na.rm = TRUE, bstrap = FALSE, cband = FALSE))))
}))
write.csv(normal_agg, file.path(fixture, "expected/r/normal-aggte.csv"), row.names = FALSE, na = "")

calendar_win <- suppressWarnings(suppressMessages(aggte(mp, type = "calendar", max_e = 2, na.rm = TRUE, bstrap = FALSE, cband = FALSE)))
calendar_unr <- suppressWarnings(suppressMessages(aggte(mp, type = "calendar", na.rm = TRUE, bstrap = FALSE, cband = FALSE)))
calendar_ignored <- rbind(
  agg_to_df("calendar_window_ignored", "calendar", calendar_win),
  agg_to_df("calendar_unrestricted", "calendar", calendar_unr)
)
write.csv(calendar_ignored, file.path(fixture, "expected/r/calendar-ignored.csv"), row.names = FALSE, na = "")

source_file <- "tests/testthat/test-audit-fixes.R"
source_sha <- "c8b6b5d7cf2e0544957d6e6bddb211871df48b051a134cc0a6d041e648aa6dd4"
upstream_map <- data.frame(
  source_file = source_file,
  source_sha256 = source_sha,
  source_test = c(
    "fix_weights='varying' SE is not 2x too large on a balanced panel",
    "fix_weights='varying' fast and slow paths agree (balanced panel)",
    "fix_weights='varying' aggregations inherit the corrected SE",
    "aggte() normal aggregations still work (no regression)",
    "aggte(type='calendar', na.rm=TRUE) drops all-NA calendar periods instead of crashing",
    "aggte() empty post-treatment windows give clean errors, not cryptic crashes",
    "negative gname is rejected with a clear error in both code paths",
    "parallel multiplier bootstrap is reproducible under a fixed seed",
    "parallel bootstrap chunking never produces negative chunks (biters < cores)",
    "aggte(type='calendar') warns that min_e/max_e/balance_e are ignored, returns unrestricted"
  ),
  mapped_scenario = c(
    "fixweights_varying_se_normalization",
    "fixweights_varying_fast_request_optimized",
    "fixweights_varying_simple_aggregation",
    "mpdta_normal_aggregations",
    "calendar_na_rm_all_na_period_drop",
    "empty_window_clean_errors",
    "negative_gname_rejection_fast_and_baseline",
    "r_internal_parallel_multiplier_bootstrap",
    "r_internal_parallel_bootstrap_chunking",
    "calendar_window_warning_and_unrestricted_result"
  ),
  assertion_family = c(
    "constant-weight fix_weights(varying) ATT and SE equal default panel results",
    "Stata fast request uses the optimized path and equals explicit nofast and R did values",
    "simple aggregation ATT and SE equal default panel aggregation under constant weights",
    "simple/dynamic/group/calendar aggregations return finite R-matching results",
    "after public-style ATT/RIF repost with all-NA 2005 calendar cell, na_rm drops the period and keeps finite overall ATT",
    "simple and dynamic empty windows fail with clear diagnostics",
    "negative gvar values rejected before baseline or fast computation",
    "R non-exported did:::run_multiplier_bootstrap helper has no Stata public command analogue",
    "R non-exported did:::run_multiplier_bootstrap chunking helper has no Stata public command analogue",
    "calendar min_e/max_e/balance_e warning emitted and result equals unrestricted calendar aggregation"
  ),
  coverage_status = c(
    "mapped", "mapped", "mapped", "mapped", "mapped",
    "mapped", "mapped", "approved-divergence", "approved-divergence", "mapped"
  ),
  divergence_id = c("", "", "", "", "", "", "", "RT006-DIV002", "RT006-DIV002", ""),
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = "RT006-DIV002",
  source_tests = "parallel multiplier bootstrap is reproducible under a fixed seed; parallel bootstrap chunking never produces negative chunks (biters < cores)",
  reason = "The source tests call non-exported R helper did:::run_multiplier_bootstrap and inspect internal parallel chunking. The Stata port exposes bootstrap behavior only through public csdid wboot() options.",
  accepted_behavior = "Public bootstrap option parsing, seeded metadata, ATT(g,t) bootstrap, and cluster bootstrap remain covered by F014/F035/RT017/PY bootstrap gates; no Stata internal helper API is added.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "RT006",
  fixture_family = "r-audit-fixes",
  normative_source = "R did 2.5.1 tests/testthat/test-audit-fixes.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  source_sha256 = source_sha,
  decision_refs = c("D001", "D004", "D014"),
  tolerance_ids = c("TOL002", "EXACT"),
  inputs = list(
    list(path = "inputs/balanced-seed1.csv", rows = nrow(d1), columns = ncol(d1)),
    list(path = "inputs/balanced-seed2.csv", rows = nrow(d2), columns = ncol(d2)),
    list(path = "inputs/balanced-seed3.csv", rows = nrow(d3), columns = ncol(d3)),
    list(path = "inputs/mpdta.csv", rows = nrow(mpdta), columns = ncol(mpdta)),
    list(path = "inputs/negative-g.csv", rows = nrow(negative), columns = ncol(negative))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt006/generate.R", path = "tools/parity/generators/rt006/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(kind = "R default", seeds = c(1L, 2L, 3L, 5L)),
  expected_outputs = list(
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence"),
    list(path = "expected/r/fixweights-attgt.csv", schema = "attgt"),
    list(path = "expected/r/fixweights-aggte.csv", schema = "aggte"),
    list(path = "expected/r/normal-aggte.csv", schema = "aggte"),
    list(path = "expected/r/calendar-ignored.csv", schema = "aggte")
  ),
  comparison_plan = list(
    list(actual = "Stata fix_weights ATT(g,t)", expected = "expected/r/fixweights-attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "Stata fix_weights aggregation", expected = "expected/r/fixweights-aggte.csv", tolerance_id = "TOL002", key_columns = c("scenario", "type", "seq")),
    list(actual = "Stata mpdta aggregation", expected = "expected/r/normal-aggte.csv", tolerance_id = "TOL002", key_columns = c("scenario", "type", "seq")),
    list(actual = "Stata calendar ignored-window aggregation", expected = "expected/r/calendar-ignored.csv", tolerance_id = "TOL002", key_columns = c("scenario", "type", "seq")),
    list(actual = "Mapped source tests", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "RT006 maps public R audit-fix behavior for fix_weights(varying), aggregation guards, negative gvar rejection, and calendar ignored-window warnings. If the installed did oracle exhibits the known pre-audit doubled-SE behavior, the expected fix_weights(varying) SEs are normalized by the source-test invariant before comparison. The fix_weights(varying) fast request now uses the optimized path; the remaining approved divergence records only R-only non-exported parallel multiplier-bootstrap helper internals."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
