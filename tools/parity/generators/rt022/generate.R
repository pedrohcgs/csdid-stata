# RT022: R oracle for the overlap-guard design.
#
# The inherited test counts how many "overlap condition violated" warnings fire.
# That checks the guard triggers, not that it triggers on the SAME cells R
# refuses. Exporting R's ATT table for this design pins both: which cells come
# back missing (refused) and the values of the ones that survive.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/rt022/inputs/overlap-cache.csv"); names(d)<-tolower(names(d))
r <- q(att_gt(yname="y", tname="period", idname="id", gname="g", xformla=~xsep,
              data=d, est_method="dr", bstrap=FALSE, cband=FALSE))
out <- data.frame(scenario="overlap_dr", group=r$group, time=r$t, att=r$att, se=r$se)
write.csv(out, "tests/fixtures/parity/rt022/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("RT022 oracle: %d cells, %d refused (missing att)\n",
            nrow(out), sum(is.na(out$att))))
