# RT021: R oracle for the not-yet-treated runs across the three methods.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/rt021/inputs/output-methods.csv"); names(d)<-tolower(names(d))
rows <- list()
for (m in c("dr","ipw","reg")) {
  r <- q(att_gt(yname="y",tname="period",idname="id",gname="g",xformla=~x,data=d,
                est_method=m,control_group="notyettreated",bstrap=FALSE,cband=FALSE))
  rows[[m]] <- data.frame(scenario=m, group=r$group, time=r$t, att=r$att, se=r$se)
}
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/rt021/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("RT021 oracle: %d rows\n", nrow(out)))
