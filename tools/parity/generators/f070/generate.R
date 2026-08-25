#!/usr/bin/env Rscript
# F070: a factor level emptied AFTER sample reduction must not poison the
# design. Two scenarios, each of which once made every substantive ATT(g,t)
# silently missing in csdid while R estimated real numbers (cold-audit F1):
#   missbase  -- the base region's units carry a missing covariate in every
#                row, so covariate markout removes the whole level;
#   balempty  -- the base region's units are observed in only two of four
#                periods, so the balanced-panel drop removes the whole level.
# R builds its model matrix on the already-reduced data, so the emptied level
# never becomes a column; csdid now rebuilds its factor expansion on the
# final estimation sample the same way.

suppressPackageStartupMessages(library(did))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f070/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f070")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)

make_panel <- function(scenario) {
  d <- expand.grid(id = 1:60, time = 1:4)
  d <- d[order(d$id, d$time), ]
  d$region <- 1 + (d$id %% 3)
  d$g <- ifelse(d$id %% 4 == 0, 0, ifelse(d$id %% 2 == 0, 3, 4))
  d$x1 <- round(0.3 * d$time + 0.1 * (d$id %% 5), 6)
  d$y <- round(1 + 0.2 * d$time + ifelse(d$g > 0 & d$time >= d$g, 1.5, 0)
               + 0.3 * sin(3 * d$id + 2 * d$time), 6)
  if (scenario == "missbase") {
    d$x1[d$region == 1] <- NA
  } else {
    d <- d[!(d$region == 1 & d$time > 2), ]
  }
  d
}

for (scenario in c("missbase", "balempty")) {
  d <- make_panel(scenario)
  write.csv(d, file.path(fixture, sprintf("inputs/input-%s.csv", scenario)),
            row.names = FALSE, na = "")
  r <- att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
              xformla = ~x1 + factor(region), data = d, est_method = "dr",
              control_group = "notyettreated", base_period = "varying",
              bstrap = FALSE, cband = FALSE)
  out <- data.frame(scenario = scenario, group = r$group, time = r$t,
                    att = r$att, se = r$se)
  write.csv(out, file.path(fixture, sprintf("expected/r/attgt-%s.csv", scenario)),
            row.names = FALSE, na = "")
}
cat("f070 fixtures written\n")
