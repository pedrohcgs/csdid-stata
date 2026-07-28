# PY001: R oracle for the aggregation suite -- ATT(g,t) for the three methods
# plus every aggregation variant the Stata test exercises.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/py001/inputs/aggte-data.csv"); names(d) <- tolower(names(d))
OUT <- "tests/fixtures/parity/py001/expected/r"
rows <- list()
for (m in c("dr","reg","ipw")) {
  r <- q(att_gt(yname="y", tname="period", idname="id", gname="g", xformla=~x,
                data=d, est_method=m, bstrap=FALSE, cband=FALSE))
  rows[[m]] <- data.frame(scenario=m, group=r$group, time=r$t, att=r$att, se=r$se)
}
write.csv(do.call(rbind, rows), file.path(OUT,"attgt.csv"), row.names=FALSE, na="")

base <- q(att_gt(yname="y", tname="period", idname="id", gname="g", xformla=~x,
                 data=d, est_method="dr", bstrap=FALSE, cband=FALSE))
spec <- list(list(tag="simple",type="simple",args=list()),
             list(tag="group",type="group",args=list()),
             list(tag="calendar",type="calendar",args=list()),
             list(tag="dynamic",type="dynamic",args=list()),
             list(tag="dynamic_min_e_m1",type="dynamic",args=list(min_e=-1)),
             list(tag="dynamic_max_e_1",type="dynamic",args=list(max_e=1)),
             list(tag="dynamic_min_m1_max_1",type="dynamic",args=list(min_e=-1,max_e=1)),
             list(tag="dynamic_balance_e_1",type="dynamic",args=list(balance_e=1)))
ov <- do.call(rbind, lapply(spec, function(s) {
  a <- do.call(aggte, c(list(base, type=s$type, na.rm=TRUE), s$args))
  data.frame(spec=s$tag, overall_att=a$overall.att, overall_se=a$overall.se)}))
write.csv(ov, file.path(OUT,"aggte-overall.csv"), row.names=FALSE, na="")
cat(sprintf("PY001 oracle: %d attgt rows, %d aggregations\n",
            nrow(do.call(rbind, rows)), nrow(ov)))
