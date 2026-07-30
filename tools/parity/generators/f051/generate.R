#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f051/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f051")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:60
times <- 1:5
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 20, 3L, ifelse(d$id <= 40, 4L, 0L))
d$x1 <- sin(0.17 * d$id) + 0.12 * d$time
d$x2 <- cos(0.13 * d$id) - 0.08 * d$time
d$y <- with(
  d,
  0.25 * time + 0.18 * x1 - 0.11 * x2 + 0.015 * (id %% 9) +
    ifelse(g > 0 & time >= g, 0.85 + 0.07 * (time - g), 0)
)
write.csv(d, file.path(fixture, "inputs/default-panel.csv"), row.names = FALSE, na = "")

set.seed(20260707)
out <- att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = TRUE,
  cband = TRUE,
  biters = 1000,
  est_method = "dr",
  base_period = "varying"
)

attgt <- data.frame(
  group = out$group,
  time = out$t,
  event_time = out$t - out$group,
  att = out$att,
  se = out$se,
  control_group = out$DIDparams$control_group,
  base_period = out$DIDparams$base_period,
  est_method = out$DIDparams$est_method,
  panel_mode = "panel",
  stringsAsFactors = FALSE
)
write.csv(attgt, file.path(fixture, "expected/r/default-attgt.csv"), row.names = FALSE, na = "")

contract <- list(
  matrix_id = "F051",
  fixture_family = "release-productization-defaults",
  csdid_defaults = list(
    method = "dr",
    control_group = "nevertreated",
    base_period = "varying",
    panel_mode_with_ivar = "panel",
    anticipation = 0,
    level = 95,
    pscoretrim = 0.995,
    bstrap = TRUE,
    cband = TRUE,
    biters = 1000,
    fast_mode = "auto",
    performance_mode = "auto",
    store_all = FALSE
  ),
  postestimation_defaults = list(
    csdid_stats_type = "group",
    csdid_estat_event_aggregation = "dynamic",
    csdid_plot_requires_saving = TRUE,
    csdid_plot_plot_data_surface = c("attgt", "aggte_dynamic", "aggte_group", "aggte_calendar")
  ),
  stata_style_aliases = list(
    csdid = list(
      baseperiod = "base_period",
      universal = "base_period(universal)",
      varying = "base_period(varying)",
      id = "ivar",
      notyettreated = "notyet",
      nevertreated = "default control_group",
      "vce(cluster clustvar)" = "cluster(clustvar)",
      "wboot reps(#) seed(#)" = "wboot(reps(#) seed(#))",
      fixweights = "fix_weights",
      "fixweights(base)" = "fix_weights(base_period)",
      "fixweights(first)" = "fix_weights(first_period)",
      balance = "bal",
      unbalanced = "bal(none)",
      allowunbalanced = "bal(none)",
      storeall = "store_all"
    ),
    postestimation = list(
      estat_event = "csdid_estat event",
      estat_dynamic = "csdid_stats dynamic",
      "estat simple/group/calendar" = "csdid_stats simple/group/calendar",
      event = "dynamic",
      window = "min_e/max_e",
      balance = "balance_e",
      dropmissing = "na_rm"
    )
  ),
  diagnostics = list(
    csdid_plot_requires_saving = "csdid_plot requires saving(filename). To export plot data, run: csdid_plot, saving(filename) replace",
    unsupported_estat_subcommand = "supported subcommands are attgt, event, dynamic, simple, group, calendar, tidy, and glance"
  )
)
writeLines(
  jsonlite::toJSON(contract, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/contract/default-surface.json")
)

# ---------------------------------------------------------------------------
# Approved divergences: the two omitted-option defaults that deliberately
# differ from R did 2.5.1.
#
# These are the only places where csdid's *numbers* differ from the reference
# implementation for the same command, and they differ only because the
# omitted-option default resolves elsewhere; state either option explicitly
# and csdid and R agree to machine precision. They are divergences from Stata
# csdid Version 1.82 as well, which shares R's two defaults, so they are
# recorded here rather than buried in a migration note.
#
# Every other approved divergence in this repository is about surface --
# an R internal with no public Stata command, an R language feature with no
# Stata analogue, a deliberately omitted option. These two are the behavioural
# ones.
# ---------------------------------------------------------------------------
divergences <- data.frame(
  divergence_id = c("F051-DIV001", "F051-DIV002"),
  source_tests = c(
    "R did 2.5.1 att_gt() default base_period = \"varying\"",
    "R did 2.5.1 att_gt() default control_group = \"nevertreated\""
  ),
  reason = c(
    paste(
      "csdid defaults to base_period(universal); R did and Stata csdid Version 1.82",
      "both default to varying. Universal is the layout an event-study plot assumes,",
      "and event studies are how these results are almost always presented.",
      "Post-treatment ATT(g,t) are identical under either choice; the pre-treatment",
      "cells differ, and universal additionally reports the g-1 normalisation row.",
      "base_period(varying) reproduces R exactly."
    ),
    paste(
      "csdid defaults to not-yet-treated controls; R did and Stata csdid Version 1.82",
      "both default to never-treated. Not-yet-treated uses more of the data, usually",
      "gives tighter standard errors, and does not require a never-treated group to",
      "exist or to be large enough to trust -- it is also the remedy R's own",
      "too-small-never-treated refusal recommends. nevertreated reproduces R exactly."
    )
  ),
  accepted_behavior = c(
    paste(
      "F051 pins e(base_period) == universal when the option is omitted and asserts",
      "that base_period(varying) matches the R oracle; the whole test suite pins the",
      "R-matching value explicitly wherever it compares against an R fixture."
    ),
    paste(
      "F051 pins e(control_group) == notyettreated when the option is omitted and",
      "asserts that nevertreated matches the R oracle; F008 estimates both arms and",
      "compares each against its own R oracle."
    )
  ),
  divergence_kind = c("behavioral-default", "behavioral-default"),
  stringsAsFactors = FALSE
)
write.csv(divergences, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(
  jsonlite::toJSON(divergences, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/contract/approved-divergence.json")
)

manifest <- list(
  matrix_id = "F051",
  fixture_family = "release-productization-defaults",
  normative_source = "R did 2.5.1 point-estimate defaults plus frozen Stata release UX contract",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D003", "D008", "D009", "D016"),
  tolerance_ids = c("TOL001", "EXACT"),
  inputs = list(list(path = "inputs/default-panel.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f051/generate.R", path = "tools/parity/generators/f051/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/default-attgt.csv", schema = "attgt"),
    list(path = "expected/contract/default-surface.json", schema = "release-default-surface"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "Stata omitted-option ATT(g,t)", expected = "expected/r/default-attgt.csv", tolerance_id = "TOL001", key_columns = c("group", "time")),
    list(actual = "Stata stored-result defaults and diagnostics", expected = "expected/contract/default-surface.json", tolerance_id = "EXACT", key_columns = c("setting"))
  ),
  approved_divergence = list(path = "expected/contract/approved-divergence.csv", ids = divergences$divergence_id),
  scope_note = "Release-productization fixture binding omitted-option defaults, explicit default-equivalent calls, Stata-style aliases including bare universal/varying base-period aliases, id(), notyettreated/nevertreated, vce(cluster), bootstrap shorthand, optimized default computation/storage metadata, storeall full-storage compatibility, csdid_stats default/event aggregation aliases, estat/csdid_estat event and aggregation replay, csdid_plot saving() plot-data handoff, and user-facing diagnostics. Omitted inference follows R did 2.5.1 bootstrap/cband/1000 defaults; the fixture uses set.seed(20260707) only to make bootstrap SE evidence deterministic. Numerical point estimates remain R did 2.5.1-oracle; storage and Stata UX details are governed by the frozen Stata release contract."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
