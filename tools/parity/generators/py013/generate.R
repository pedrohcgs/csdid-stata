# PY013: R oracle for the integration scenarios (three methods analytical, plus
# not-yet-treated controls).
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/py013/inputs/panel-data.csv"); names(d)<-tolower(names(d))
rows <- list()
for (m in c("dr","reg","ipw")) {
  r <- q(att_gt(yname="y", tname="year", idname="id", gname="group", data=d,
                est_method=m, bstrap=FALSE, cband=FALSE))
  rows[[m]] <- data.frame(scenario=m, group=r$group, time=r$t, att=r$att, se=r$se)
}
r <- q(att_gt(yname="y", tname="year", idname="id", gname="group", data=d,
              est_method="dr", control_group="notyettreated", bstrap=FALSE, cband=FALSE))
rows[["notyet_dr"]] <- data.frame(scenario="notyet_dr", group=r$group, time=r$t, att=r$att, se=r$se)
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py013/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY013 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
