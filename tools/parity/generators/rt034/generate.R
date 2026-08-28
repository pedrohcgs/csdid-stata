#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt034/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt034")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

# type(group) + na.rm on an off-grid calendar. Periods {1,3,5,9} and cohort
# dates {2,4,7} share no value, so every rank in compute.aggte's recode grid
# depends on WHICH cohorts survive the na.rm screen: R's grid is the original
# tlist joined with the SURVIVING glist (compute.aggte.R:239 with glist as it
# stands after :164/:195), and for type="group" the survival screen runs on
# RAW calendar values with max_e before any recode (:177). Witness 2 needs no
# missing cells at all: with max_e = 1, cohort 7 has no cell inside
# [7, 8] and leaves glist, which moves every later rank. Witness 1 removes
# cohort 4's t = 5 rows, so its only cell inside [4, 6] is missing and the
# cohort leaves under na.rm while cohorts 2 and 7 survive.
set.seed(20260827)
periods <- c(1, 3, 5, 9)
cohorts <- c(0, 2, 4, 7)
n_per <- 40
id <- rep(seq_len(n_per * length(cohorts)), each = length(periods))
g  <- rep(rep(cohorts, each = n_per), each = length(periods))
tt <- rep(periods, times = n_per * length(cohorts))
y  <- 1 + 0.1 * tt + 0.5 * (g > 0 & tt >= g) + rnorm(length(id), sd = 0.3)
d  <- data.frame(id = id, t = tt, g = g, y = y)
d1 <- d[!(d$g == 4 & d$t == 5), ]
write.csv(d, file.path(fixture, "inputs/offgrid-balanced.csv"), row.names = FALSE, na = "")
write.csv(d1, file.path(fixture, "inputs/offgrid-gap.csv"), row.names = FALSE, na = "")

run_group <- function(dat, unbal, max_e) {
  fit <- att_gt(
    yname = "y", tname = "t", idname = "id", gname = "g", data = dat,
    control_group = "notyettreated", est_method = "reg",
    bstrap = FALSE, cband = FALSE, allow_unbalanced_panel = unbal
  )
  suppressWarnings(suppressMessages(
    aggte(fit, type = "group", max_e = max_e, na.rm = TRUE,
          bstrap = FALSE, cband = FALSE)
  ))
}

a2 <- run_group(d, FALSE, 1)
a1 <- run_group(d1, TRUE, 2)

export_group <- function(ag, witness, max_e, path_frag) {
  write.csv(
    data.frame(
      witness = witness, max_e = max_e,
      egt = ag$egt, att = ag$att.egt, se = ag$se.egt,
      overall_att = ag$overall.att, overall_se = ag$overall.se
    ),
    file.path(fixture, path_frag), row.names = FALSE, na = "."
  )
}
export_group(a2, "balanced", 1, "expected/r/group-balanced-maxe1.csv")
export_group(a1, "gap", 2, "expected/r/group-gap-maxe2.csv")

manifest <- list(
  matrix_id = "RT034",
  fixture_family = "group-narm-offgrid-cohorts",
  normative_source = "R did 2.5.1 compute.aggte: under na.rm the type='group' cohort screen runs on raw calendar values with max_e before the rank recode, and the recode grid is the original tlist joined with the surviving glist",
  generators = list(list(
    runtime = "R",
    command = "Rscript tools/parity/generators/rt034/generate.R",
    path = "tools/parity/generators/rt034/generate.R"
  )),
  inputs = list(
    list(path = "inputs/offgrid-balanced.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/offgrid-gap.csv", rows = nrow(d1), columns = ncol(d1))
  ),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."))),
  consumers = list("tests/stata/r/test-group-grid-narm.do")
)
write_json(manifest, file.path(fixture, "metadata/manifest.json"),
           auto_unbox = TRUE, pretty = TRUE)

cat("rt034 fixtures written:", fixture, "\n")
print(data.frame(egt = a2$egt, att = a2$att.egt, se = a2$se.egt))
print(data.frame(egt = a1$egt, att = a1$att.egt, se = a1$se.egt))
