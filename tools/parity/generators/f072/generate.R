#!/usr/bin/env Rscript
# F072: a covariate missing in ONE row must cost exactly that row under the
# unbalanced routes, not the whole unit. R's allowed-unbalanced path keeps
# complete-case rows and lets per-2x2 availability decide; the balanced path
# drops the now-incomplete unit. csdid's whole-unit covariate markout once
# ran BEFORE the balance-mode dispatch, so bal(pair)/bal(none) silently lost
# the unit's clean rows (cold-audit round 6, F1: ATT(2,2) 1.0 vs R's
# 1.1666667 on this design).

suppressPackageStartupMessages(library(did))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f072/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f072")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)

d <- expand.grid(id = 1:60, time = 1:3)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 30, 2, 0)
d$x <- d$id %% 2
d$y <- round(0.1 * d$time + ifelse(d$g == 2 & d$time >= 2, 1, 0)
             + 0.02 * (d$id %% 7) + 0.03 * (d$id %% 2) * d$time, 6)
d$y[d$id == 1 & d$time == 2] <- d$y[d$id == 1 & d$time == 2] + 5
d$x[d$id == 1 & d$time == 3] <- NA
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

rows <- list()
for (ub in c(FALSE, TRUE)) {
  r <- att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
              xformla = ~x, data = d, est_method = "reg",
              control_group = "nevertreated", panel = TRUE,
              allow_unbalanced_panel = ub, bstrap = FALSE, cband = FALSE)
  tag <- ifelse(ub, "unbalanced", "balanced")
  rows[[tag]] <- data.frame(tag = tag, group = r$group, time = r$t,
                            att = r$att, se = r$se)
}
write.csv(do.call(rbind, rows), file.path(fixture, "expected/r/attgt.csv"),
          row.names = FALSE, na = "")
