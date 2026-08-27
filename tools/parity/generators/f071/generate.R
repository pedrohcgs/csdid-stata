#!/usr/bin/env Rscript
# F071: on a gapped calendar, max_e counts OBSERVED PERIODS for the simple
# and group aggregations, because R rank-recodes periods and cohorts
# (orig2t) before its keepers (compute.aggte.R:279, :335) -- while the
# dynamic path stays on raw calendar event time (eseq = originalt -
# originalgroup). csdid's raw-calendar keeper once kept one of two post
# cells R keeps (cold-audit round 4, F1).

suppressPackageStartupMessages(library(did))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f071/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f071")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)

d <- expand.grid(id = 1:40, time = c(1, 3, 5))
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 20, 3, 0)
d$y <- round(1 + 0.1 * d$time
             + ifelse(d$g > 0 & d$time >= d$g, 1 + 0.5 * (d$time - 3), 0)
             + 0.05 * ((d$id * 7 + d$time * 3) %% 11), 6)
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

r <- att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
            data = d, bstrap = FALSE, cband = FALSE)
rows <- list()
d2 <- expand.grid(id = 1:40, time = c(1, 3, 5))
d2 <- d2[order(d2$id, d2$time), ]
d2$g <- ifelse(d2$id <= 12, 3, ifelse(d2$id <= 24, 5, 0))
d2$y <- round(0.1 * d2$time
              + ifelse(d2$g > 0 & d2$time >= d2$g, 1 + 0.3 * (d2$time - d2$g), 0)
              + 0.05 * ((d2$id * 3 + d2$time) %% 7), 6)
write.csv(d2, file.path(fixture, "inputs/input-twocohort.csv"), row.names = FALSE, na = "")
r2 <- att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
             data = d2, control_group = "nevertreated", bstrap = FALSE, cband = FALSE)
rows2 <- list()
for (spec in list(list(tag = "tc_simple_maxe1", type = "simple", max_e = 1),
                  list(tag = "tc_group_maxe1", type = "group", max_e = 1))) {
  a <- aggte(r2, type = spec$type, max_e = spec$max_e, na.rm = TRUE)
  rows2[[spec$tag]] <- data.frame(tag = spec$tag,
                                  overall_att = a$overall.att,
                                  overall_se = a$overall.se)
}
write.csv(do.call(rbind, rows2), file.path(fixture, "expected/r/aggte-twocohort.csv"),
          row.names = FALSE, na = "")

for (spec in list(list(tag = "simple_maxe1", type = "simple", max_e = 1),
                  list(tag = "simple_open", type = "simple", max_e = Inf),
                  list(tag = "group_maxe1", type = "group", max_e = 1),
                  list(tag = "dynamic_maxe1", type = "dynamic", max_e = 1))) {
  a <- aggte(r, type = spec$type, max_e = spec$max_e)
  rows[[spec$tag]] <- data.frame(tag = spec$tag,
                                 overall_att = a$overall.att,
                                 overall_se = a$overall.se)
}
write.csv(do.call(rbind, rows), file.path(fixture, "expected/r/aggte-overall.csv"),
          row.names = FALSE, na = "")
