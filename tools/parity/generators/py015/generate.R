# PY015: R oracle for the CLUSTERED MULTIPLIER BOOTSTRAP.
#
# Bootstrap standard errors are comparable to R only because csdid reproduces
# R's random-number stream draw for draw. That was verified before writing this
# oracle: a seeded clustered bootstrap at 499 iterations agreed with R to
# max |dATT| 2.2e-15 and max |dSE| 5.8e-16. The seeds and iteration counts below
# mirror the Stata test exactly, because a bootstrap SE is only reproducible for
# the same seed and count.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/py015/inputs"
rows <- list()
run <- function(tag, file, biters, seed) {
  d <- read.csv(file.path(IN, file)); names(d) <- tolower(names(d))
  set.seed(seed)
  r <- q(att_gt(yname="y", tname="t", idname="id", gname="g", data=d,
                est_method="reg", bstrap=TRUE, biters=biters, cband=FALSE,
                clustervars="cl"))
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
}
run("unbalanced_399", "clustered-unbalanced.csv", 399, 20251501)
run("balanced_399",   "clustered-balanced.csv",   399, 20251502)
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py015/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY015 oracle: %d rows across %d clustered-bootstrap scenarios\n",
            nrow(out), length(unique(out$scenario))))
