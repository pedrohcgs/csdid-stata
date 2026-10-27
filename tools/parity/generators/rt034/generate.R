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

# Group windows use original calendar units. With periods {1,3,5,9}
# and cohorts {2,4,7}, max_e=1 removes cohort 7 because [7,8] contains
# no observed cell. Removing cohort 4's t=5 observations makes its only
# cell in [4,6] unavailable; na.rm then removes that cohort at max_e=2.
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
  normative_source = "R did 2.5.1.904 compute.aggte: type='group' applies min_e/max_e in original calendar units; under na.rm cohorts with no surviving post-treatment cell inside the window are excluded",
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
