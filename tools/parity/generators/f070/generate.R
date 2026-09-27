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

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f070/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))

suppressPackageStartupMessages(library(did))

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
# Two later reductions made by the estimation itself, after the rebuild once
# ran: the units (rows) treated at or before the first period plus
# anticipation, and, with no never-treated units, the periods from the latest
# cohort's date on. A factor level held only there once blanked every cell.
#   fpt / fptbase  -- region 4 (a non-base level) or region 0 (the base) only
#                     among units treated in the first period;
#   antic          -- region 4 only among cohort-2 units, which anticipation(1)
#                     makes first-period treated;
#   trim           -- no never-treated units; region 4 only in period 4, which
#                     the fallback removes (time-varying on the panel).
# Each on the panel (_p) and on repeated cross sections (_r).
make_late <- function(shape, panel) {
  d <- expand.grid(id = 1:80, time = 1:4)
  d <- d[order(d$id, d$time), ]
  d$region <- 1 + (d$id %% 3)
  d$g <- ifelse(d$id %% 4 == 0, 0, ifelse(d$id %% 2 == 0, 3, 4))
  first <- d$id > 68
  if (shape %in% c("fpt", "fptbase")) d$g[first] <- 1
  if (shape == "antic") d$g[first] <- 2
  if (shape %in% c("fpt", "antic")) d$region[first] <- 4
  if (shape == "fptbase") d$region[first] <- 0
  if (shape == "trim") {
    d$g[d$g == 0] <- 2
    d$region[d$time == 4 & d$id %% 5 == 0] <- 4
  }
  d$x1 <- round(0.3 * d$time + 0.1 * (d$id %% 5), 6)
  d$y <- round(1 + 0.2 * d$time + ifelse(d$g > 0 & d$time >= d$g, 1.5, 0)
               + 0.25 * d$region + 0.3 * sin(3 * d$id + 2 * d$time), 6)
  if (!panel) d$id <- seq_len(nrow(d))
  d
}
late <- expand.grid(shape = c("fpt", "fptbase", "antic", "trim"), panel = c(TRUE, FALSE),
                    stringsAsFactors = FALSE)
late$scenario <- paste0(late$shape, ifelse(late$panel, "_p", "_r"))
late$anticipation <- ifelse(late$shape == "antic", 1L, 0L)
late$control <- "nevertreated"
for (k in seq_len(nrow(late))) {
  s <- late[k, ]
  d <- make_late(s$shape, s$panel)
  write.csv(d, file.path(fixture, sprintf("inputs/input-%s.csv", s$scenario)),
            row.names = FALSE, na = "")
  r <- suppressWarnings(att_gt(yname = "y", tname = "time", idname = if (s$panel) "id" else NULL,
              gname = "g", xformla = ~x1 + factor(region), data = d, panel = s$panel,
              est_method = "dr", control_group = s$control, base_period = "varying",
              anticipation = s$anticipation, bstrap = FALSE, cband = FALSE))
  stopifnot(all(!is.na(r$att)))
  out <- data.frame(scenario = s$scenario, group = r$group, time = r$t,
                    att = r$att, se = r$se)
  write.csv(out, file.path(fixture, sprintf("expected/r/attgt-%s.csv", s$scenario)),
            row.names = FALSE, na = "")
}
write.csv(late[, c("scenario", "shape", "panel", "anticipation", "control")],
          file.path(fixture, "inputs/scenarios-late.csv"), row.names = FALSE)
cat("f070 fixtures written\n")
