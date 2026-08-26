#!/usr/bin/env Rscript
# F073: a time axis in epoch seconds estimates exactly as any other axis.
# The coefficient NAMES fall back to att_# (Stata's 32-character limit),
# but every number matches R, which never names coefficients at all.
suppressPackageStartupMessages(library(did))
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f073/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)
fixture <- file.path(root, "tests/fixtures/parity/f073")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
T0 <- 1700172800; T1 <- 1700259200; T2 <- 1700345600
d <- expand.grid(id = 1:30, time = c(T0, T1, T2))
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 15, T1, 0)
d$y <- round(0.1 * (d$time - T0) / 86400 + ifelse(d$g > 0 & d$time >= d$g, 1.25, 0)
             + 0.03 * (d$id %% 6), 6)
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")
r <- att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
            data = d, control_group = "nevertreated", bstrap = FALSE, cband = FALSE)
write.csv(data.frame(group = r$group, time = r$t, att = r$att, se = r$se),
          file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")
