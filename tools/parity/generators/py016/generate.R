# PY016: R oracle for the not-yet-treated control scenario.
# The inherited test checked structural facts about which cohorts appear in
# e(group_prob) and e(unit_group), but never compared an estimate to R.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/py016/inputs/notyettreated.csv")
r <- q(att_gt(yname="y", tname="year", idname="id", gname="group", data=d,
              est_method="dr", control_group="notyettreated",
              bstrap=FALSE, cband=FALSE))
out <- data.frame(group=r$group, time=r$t, att=r$att, se=r$se)
write.csv(out, "tests/fixtures/parity/py016/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY016 oracle: %d cells\n", nrow(out)))
