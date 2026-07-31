# PY005: R oracle for the seeded multiplier bootstrap, clustered and not.
# Valid only because csdid reproduces R's random-number stream draw for draw;
# verified at max |dSE| 5.8e-16 before this oracle was written. Seeds and
# iteration counts mirror the Stata calls exactly.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/py005/inputs/clustered-data.csv"); names(d)<-tolower(names(d))
rows <- list()
run <- function(tag, biters, seed, clus=NULL) {
  set.seed(seed)
  r <- q(att_gt(yname="y", tname="year", idname="id", gname="group", data=d,
                est_method="dr", bstrap=TRUE, biters=biters, cband=FALSE,
                clustervars=clus))
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
}
run("boot200_cluster",     200, 20250501, "cluster")
run("boot500_iid",         500, 20250502, NULL)
run("boot500_cluster",     500, 20250502, "cluster")
run("boot500_iid_b",       500, 20250503, NULL)
run("boot500_unitcluster", 500, 20250503, "unit_cluster")
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py005/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY005 oracle: %d rows across %d bootstrap scenarios\n", nrow(out), length(unique(out$scenario))))
