# PY012: R oracle for the inference scenarios (panel and repeated cross
# sections x three methods, analytical). The inherited test compared against
# DGP-implied targets with loose tolerances, never against R.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/py012/inputs/inference-data.csv")
names(d) <- tolower(names(d))
rows <- list()
add <- function(tag,r) rows[[length(rows)+1]] <<-
  data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
for (m in c("dr","reg","ipw")) {
  add(paste0("panel_",m), q(att_gt(yname="y", tname="period", idname="id", gname="g",
      xformla=~x, data=d, est_method=m, bstrap=FALSE, cband=FALSE)))
  add(paste0("rcs_",m), q(att_gt(yname="y", tname="period", gname="g",
      xformla=~x, data=d, est_method=m, panel=FALSE, bstrap=FALSE, cband=FALSE)))
}
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py012/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY012 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
