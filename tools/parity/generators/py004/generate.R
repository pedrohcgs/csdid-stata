# PY004: R oracle for the clustered ANALYTICAL scenarios across methods and
# both panel and repeated-cross-section layouts.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
rows <- list()
add <- function(tag,r) rows[[length(rows)+1]] <<-
  data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
d404 <- read.csv("tests/fixtures/parity/py004/inputs/clustered-shocks-404.csv")
d606 <- read.csv("tests/fixtures/parity/py004/inputs/clustered-shocks-606.csv")
d707 <- read.csv("tests/fixtures/parity/py004/inputs/clustered-shocks-707.csv")
add("p404_iid_reg", q(att_gt(yname="y", tname="t", idname="id", gname="g",
    data=d404, est_method="reg", bstrap=FALSE, cband=FALSE)))
add("p404_cluster_reg", q(att_gt(yname="y", tname="t", idname="id", gname="g",
    data=d404, est_method="reg", clustervars="cl", bstrap=FALSE, cband=FALSE)))
add("rcs606_cluster_reg", q(att_gt(yname="y", tname="t", gname="g", data=d606,
    est_method="reg", panel=FALSE, clustervars="cl", bstrap=FALSE, cband=FALSE)))
for (m in c("dr","reg","ipw")) {
  add(paste0("p606_cluster_",m), q(att_gt(yname="y", tname="t", idname="id", gname="g",
      data=d606, est_method=m, clustervars="cl", bstrap=FALSE, cband=FALSE)))
  add(paste0("p707_cluster_",m), q(att_gt(yname="y", tname="t", idname="id", gname="g",
      data=d707, est_method=m, clustervars="cl", bstrap=FALSE, cband=FALSE)))
}
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py004/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY004 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
