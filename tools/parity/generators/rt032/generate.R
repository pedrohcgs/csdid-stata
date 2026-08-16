#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt032/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt032")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

# mpdta with the 2005 rows of the 2006 cohort removed: that cohort's universal
# base period is absent, so its ATT(g,t) cells cannot be estimated while every
# other cohort's cells can. Healthy cells must keep their standard errors.
mpdta <- read.csv(file.path(root, "examples/data/mpdta.csv"))
gap <- mpdta[!(mpdta$year == 2005 & mpdta$first_treat == 2006), ]
drop2006 <- mpdta[mpdta$first_treat != 2006, ]
write.csv(gap, file.path(fixture, "inputs/mpdta-gap.csv"), row.names = FALSE, na = "")
write.csv(drop2006, file.path(fixture, "inputs/mpdta-drop2006.csv"), row.names = FALSE, na = "")

run_rcs_analytical <- function(d) {
  att_gt(
    yname = "lemp", tname = "year", idname = "countyreal", gname = "first_treat",
    data = d, panel = FALSE, control_group = "notyettreated",
    base_period = "universal", est_method = "dr", bstrap = FALSE, cband = FALSE
  )
}

export_attgt <- function(out, path) {
  write.csv(
    data.frame(group = out$group, time = out$t, att = out$att, se = out$se),
    path, row.names = FALSE, na = "."
  )
}

res_gap <- run_rcs_analytical(gap)
export_attgt(res_gap, file.path(fixture, "expected/r/attgt-gap-rcs-analytical.csv"))

res_drop <- run_rcs_analytical(drop2006)
export_attgt(res_drop, file.path(fixture, "expected/r/attgt-drop-rcs-analytical.csv"))

summary_json <- list(
  did_version = as.character(packageVersion("did")),
  gap = list(
    n = res_gap$n,
    wald_stat = if (is.null(res_gap$W)) NA else as.numeric(res_gap$W),
    wald_pvalue = if (is.null(res_gap$Wpval)) NA else as.numeric(res_gap$Wpval),
    n_missing_att = sum(is.na(res_gap$att)),
    n_missing_se = sum(is.na(res_gap$se))
  ),
  drop2006 = list(
    n = res_drop$n,
    wald_stat = if (is.null(res_drop$W)) NA else as.numeric(res_drop$W),
    wald_pvalue = if (is.null(res_drop$Wpval)) NA else as.numeric(res_drop$Wpval),
    n_missing_att = sum(is.na(res_drop$att)),
    n_missing_se = sum(is.na(res_drop$se))
  )
)
write_json(summary_json, file.path(fixture, "expected/r/summary.json"),
           auto_unbox = TRUE, digits = 15, na = "null")

manifest <- list(
  matrix_id = "RT032",
  fixture_family = "missing-cell-inference",
  normative_source = "R did 2.5.1: a (g,t) cell whose 2x2 estimation fails carries NA att/se without contaminating any other cell's inference",
  generators = list(list(
    runtime = "R",
    command = "Rscript tools/parity/generators/rt032/generate.R",
    path = "tools/parity/generators/rt032/generate.R"
  )),
  inputs = list(
    list(path = "inputs/mpdta-gap.csv", rows = nrow(gap), columns = ncol(gap)),
    list(path = "inputs/mpdta-drop2006.csv", rows = nrow(drop2006), columns = ncol(drop2006))
  ),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."))),
  consumers = list("tests/stata/r/test-missing-cell-se.do")
)
write_json(manifest, file.path(fixture, "metadata/manifest.json"),
           auto_unbox = TRUE, pretty = TRUE)

cat("rt032 fixtures written:", fixture, "\n")
cat("gap rows:", nrow(gap), " drop2006 rows:", nrow(drop2006), "\n")
print(data.frame(group = res_gap$group, time = res_gap$t, att = res_gap$att, se = res_gap$se))
cat("gap wald p:", if (is.null(res_gap$Wpval)) NA else res_gap$Wpval, "\n")
