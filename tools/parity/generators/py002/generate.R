# PY002: R oracle for the clustered ANALYTICAL scenario.
# The inherited test asserted that clustered SEs were positive and differed from
# iid SEs, never that they equalled R's.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/py002/inputs/clustered-data.csv")
rows <- list()
add <- function(tag,r) rows[[length(rows)+1]] <<-
  data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
add("iid_dr", q(att_gt(yname="y", tname="year", idname="id", gname="group",
    data=d, est_method="dr", bstrap=FALSE, cband=FALSE)))
add("cluster_dr", q(att_gt(yname="y", tname="year", idname="id", gname="group",
    data=d, est_method="dr", clustervars="cluster", bstrap=FALSE, cband=FALSE)))
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py002/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY002 oracle: %d rows\n", nrow(out)))
