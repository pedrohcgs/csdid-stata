#!/usr/bin/env Rscript

# RT037 -- the band on an aggregation's OVERALL summary effect, under the one
# configuration no other fixture in this repo exercises: bstrap = TRUE with
# cband = TRUE, where the simultaneous critical value and the pointwise normal
# quantile are different numbers.
#
# Every other generator that emits an overall row (f003, f004, f005, f006,
# f012, f015, f016, f027, rt026) runs bstrap = FALSE, cband = FALSE. There the
# two critical values coincide, so those fixtures cannot see which one a port
# applied -- which is how a port could band the overall effect simultaneously
# and still match every fixture in the suite.
#
# WHAT IS COMPARED. Two things, at two strengths.
#
#   1. The RULE, which is draw-invariant: the overall row's half-width divided
#      by its standard error is qnorm(1 - alp/2) exactly, for every type, while
#      the per-effect rows use crit.val.egt, strictly larger under a
#      simultaneous band. This holds whatever the draws are.
#
#   2. The VALUES, exactly. csdid reproduces this package's multiplier draws
#      draw for draw from the same seed, so the overall effect, its standard
#      error, its limits and the per-effect critical value all agree to
#      machine precision -- measured, not assumed.
#
# Value parity is only meaningful at a matched STREAM POSITION. Each aggte()
# call consumes draws from the session stream, so the numbers below belong to
# the ORDER in which the aggregations are computed. This generator fixes that
# order once -- dynamic, group, calendar, simple -- and every recorded number,
# including the tidy export, is derived from those four objects and no others.
# A Stata run must issue the same four aggregations in the same order after a
# single seeded estimation to reproduce them.

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt037/generate.R"
# tools/parity/generators/<id> is four levels below the repository root; see
# the note in rt026's generator for what a wrong depth silently does here.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt037")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

data(mpdta, package = "did")
d <- mpdta
names(d)[names(d) == "first.treat"] <- "first_treat"
write.csv(d, file.path(fixture, "inputs/mpdta.csv"), row.names = FALSE, na = "")

set.seed(20200806)
mp <- att_gt(
  yname = "lemp",
  gname = "first_treat",
  idname = "countyreal",
  tname = "year",
  xformla = ~1,
  data = d,
  control_group = "notyettreated",
  base_period = "universal",
  est_method = "dr",
  bstrap = TRUE,
  cband = TRUE,
  biters = 1000
)

alp <- mp$DIDparams$alp
za <- qnorm(1 - alp / 2)

# THE SEQUENCE. Computed once, in this order, and nothing below calls aggte()
# again -- a second call would sit at a different position in the multiplier
# stream and produce different (equally valid) numbers, which is exactly the
# trap that makes bootstrap fixtures irreproducible.
agg_seq <- list()
for (ty in c("dynamic", "group", "calendar", "simple")) {
  agg_seq[[ty]] <- aggte(mp, type = ty, bstrap = TRUE, cband = TRUE)
}

# summary.AGGTEobj's overall block, reproduced exactly as R computes it
# (AGGTEobj.R: pointwise_cval <- qnorm(1-alp/2); then overall.att +/-
# pointwise_cval*overall.se, before any type branch).
overall_row <- function(type) {
  agg <- agg_seq[[type]]
  lo <- agg$overall.att - za * agg$overall.se
  hi <- agg$overall.att + za * agg$overall.se
  # crit.val.egt is NULL for type = "simple": there are no per-effect rows.
  egt_crit <- if (is.null(agg$crit.val.egt)) NA_real_ else agg$crit.val.egt
  data.frame(
    type = type,
    overall_att = agg$overall.att,
    overall_se = agg$overall.se,
    overall_conf_low = lo,
    overall_conf_high = hi,
    # the two draw-invariant facts this fixture exists to pin
    overall_implied_crit = (hi - lo) / 2 / agg$overall.se,
    egt_crit_val = egt_crit,
    pointwise_crit = za,
    egt_crit_exceeds_pointwise = !is.na(egt_crit) && egt_crit > za,
    stringsAsFactors = FALSE
  )
}

overall <- do.call(rbind, lapply(c("dynamic", "group", "calendar", "simple"), overall_row))
write.csv(overall, file.path(fixture, "expected/r/overall-band.csv"), row.names = FALSE, na = "")

# The tidy surface states the same rule a second way: on the Average row of a
# group aggregation, and on the single row of a simple aggregation, conf_* and
# point_conf_* are the SAME expression, so they are equal even under a
# simultaneous band. tidy.AGGTEobj builds the vectors as c(overall, per-effect).
agg_group <- agg_seq[["group"]]
tidy_group <- data.frame(
  type = "group",
  term = c("ATT(Average)", paste0("ATT(", agg_group$egt, ")")),
  group = c("Average", as.character(agg_group$egt)),
  estimate = c(agg_group$overall.att, agg_group$att.egt),
  std_error = c(agg_group$overall.se, agg_group$se.egt),
  conf_low = c(agg_group$overall.att - za * agg_group$overall.se,
               agg_group$att.egt - agg_group$crit.val.egt * agg_group$se.egt),
  conf_high = c(agg_group$overall.att + za * agg_group$overall.se,
                agg_group$att.egt + agg_group$crit.val.egt * agg_group$se.egt),
  point_conf_low = c(agg_group$overall.att - za * agg_group$overall.se,
                     agg_group$att.egt - za * agg_group$se.egt),
  point_conf_high = c(agg_group$overall.att + za * agg_group$overall.se,
                      agg_group$att.egt + za * agg_group$se.egt),
  stringsAsFactors = FALSE
)
tidy_group$conf_equals_point <- abs(tidy_group$conf_low - tidy_group$point_conf_low) < 1e-12 &
  abs(tidy_group$conf_high - tidy_group$point_conf_high) < 1e-12
write.csv(tidy_group, file.path(fixture, "expected/r/tidy-aggte-group-bootstrap.csv"), row.names = FALSE, na = "")

# The rule itself, as three assertions a port must satisfy. These are the rows
# a Stata test reads; the numeric files above are provenance.
rule <- data.frame(
  rule_id = c("overall-is-pointwise", "egt-is-simultaneous", "tidy-average-pairs-agree"),
  statement = c(
    "The overall summary effect's half-width divided by its standard error equals qnorm(1-alp/2), for every aggregation type, under bstrap=TRUE and cband=TRUE.",
    "The per-effect rows' critical value (crit.val.egt) is strictly greater than qnorm(1-alp/2) when a simultaneous band was computed.",
    "In the tidy group export, the ATT(Average) row has conf_low/conf_high equal to point_conf_low/point_conf_high, while the per-cohort rows do not."
  ),
  holds_in_r = c(
    all(abs(overall$overall_implied_crit - za) < 1e-12),
    all(overall$egt_crit_exceeds_pointwise[!is.na(overall$egt_crit_val)]),
    tidy_group$conf_equals_point[1] && !any(tidy_group$conf_equals_point[-1])
  ),
  pointwise_crit = za,
  stringsAsFactors = FALSE
)
write.csv(rule, file.path(fixture, "expected/r/overall-band-rule.csv"), row.names = FALSE, na = "")

stopifnot(all(rule$holds_in_r))

manifest <- list(
  matrix_id = "RT037",
  fixture_family = "r-aggregation-band",
  normative_source = "R did 2.5.1 R/AGGTEobj.R (summary.AGGTEobj overall block) and R/tidy.R",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  tolerance_ids = c("EXACT", "TOL002"),
  inputs = list(list(path = "inputs/mpdta.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt037/generate.R", path = "tools/parity/generators/rt037/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = 20200806, kind = RNGkind()),
  aggregation_sequence = c("dynamic", "group", "calendar", "simple"),
  expected_outputs = list(
    list(path = "expected/r/overall-band.csv", schema = "overall-band"),
    list(path = "expected/r/overall-band-rule.csv", schema = "overall-band-rule"),
    list(path = "expected/r/tidy-aggte-group-bootstrap.csv", schema = "tidy-aggte-group")
  ),
  comparison_plan = list(
    list(actual = "Stata r(table) overall column implied critical value", expected = "expected/r/overall-band-rule.csv", tolerance_id = "EXACT", key_columns = c("rule_id")),
    list(actual = "Stata estat tidy group Average row", expected = "expected/r/tidy-aggte-group-bootstrap.csv", tolerance_id = "EXACT", key_columns = c("type", "term"))
  ),
  approved_divergence = NULL,
  scope_note = paste(
    "RT037 pins the critical value applied to an aggregation's overall summary effect under bstrap = TRUE and cband = TRUE,",
    "the configuration in which the simultaneous and pointwise critical values differ.",
    "csdid reproduces this package's multiplier draws draw for draw from the same seed, so the comparison is by VALUE as well as by rule,",
    "but only at a matched stream position: the recorded numbers belong to the aggregation order dynamic, group, calendar, simple,",
    "issued once after a single seeded estimation. A different order is equally valid R and will not reproduce these numbers.",
    "Every other generator emitting an overall row runs bstrap = FALSE and cband = FALSE, where the two critical values coincide."
  )
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))

cat("rt037 written; pointwise crit =", za, "\n")
print(overall[, c("type", "overall_implied_crit", "egt_crit_val")])
