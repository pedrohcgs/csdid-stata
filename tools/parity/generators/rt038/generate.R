#!/usr/bin/env Rscript

# RT038 -- fix_weights() on an UNBALANCED panel, under method(reg) with no
# covariates, no weights, and a never-treated comparison group.
#
# WHY THIS CONFIGURATION. Setting fix_weights freezes each unit's weight at the
# base (or first) period and DROPS the units that period does not observe. This
# package applies that drop whenever fix_weights is set -- whether or not a
# weight variable was supplied -- because its internal .w defaults to 1 and the
# per-unit lookup still fails for a unit absent from the target period
# (R/compute.att_gt.R, the "not observed in" block).
#
# The port routed dr and ipw through its fitted path, which implements the
# lookup, but kept reg on a four-means closed form that does not. On this exact
# combination -- unbalanced, reg, no covariates, no weights, never-treated --
# the drop therefore did not happen: the port kept all six control units and
# reported att = .2099498 and .1269936 with NO warning, where this package
# drops the unit and reports .1201847 and .2589032 and warns twice. Adding any
# covariate, any weight, the not-yet-treated group, or switching to dr or ipw
# moved the run onto the fitted path and hid the divergence, which is why no
# existing fixture sees it.
#
# THE DESIGN is the smallest one that separates the two: three periods, one
# treated cohort at g = 3, six never-treated units, and exactly one
# never-treated unit absent at t = 2 -- the base period for every cell under a
# universal base. That single hole is what the drop is about.
#
# WHAT IS COMPARED. The full ATT(g,t) table by value, and the warning, which is
# the half a numeric fixture cannot see: a port that skips the drop still
# returns a complete, plausible table.

suppressPackageStartupMessages(library(did))

root <- Sys.getenv("CSDID_REPO", unset = normalizePath("."))
out_dir <- file.path(root, "tests", "fixtures", "parity", "rt038")

set.seed(70707)
n_units <- 12
periods <- 1:3
d <- expand.grid(id = 1:n_units, t = periods)
d$g <- ifelse(d$id <= 6, 0L, 3L)
d$y <- rnorm(nrow(d)) + 0.5 * (d$g == 3 & d$t >= 3) + 0.2 * d$t + 0.1 * d$id
# the one hole: a never-treated unit missing from the universal base period
d <- d[!(d$id == 1 & d$t == 2), ]
d <- d[order(d$id, d$t), ]
rownames(d) <- NULL

write.csv(d, file.path(out_dir, "inputs", "panel.csv"), row.names = FALSE)

warns <- character(0)
res <- withCallingHandlers(
  att_gt(yname = "y", tname = "t", idname = "id", gname = "g", data = d,
         control_group = "nevertreated", base_period = "universal",
         est_method = "reg", allow_unbalanced_panel = TRUE,
         bstrap = FALSE, cband = FALSE, fix_weights = "base_period"),
  warning = function(w) {
    warns <<- c(warns, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)

attgt <- data.frame(group = res$group, time = res$t, att = res$att, se = res$se)
write.csv(attgt, file.path(out_dir, "expected", "r", "attgt.csv"),
          row.names = FALSE, na = "")

# The warning is a compared channel, not decoration: it is the only signal that
# distinguishes "dropped the unit" from "silently kept it".
drop_warns <- grep("not observed in", warns, value = TRUE)
stopifnot(length(drop_warns) == 2L)
write.csv(data.frame(n_drop_warnings = length(drop_warns),
                     phrase = "not observed in base_period"),
          file.path(out_dir, "expected", "r", "warnings.csv"), row.names = FALSE)

# The claim this fixture exists to pin, computed rather than asserted: the run
# that drops the unit differs from the run that does not.
stopifnot(nrow(attgt) == 3L)
cat("RT038 written.\n")
print(attgt)
cat("warnings:\n"); print(drop_warns)
