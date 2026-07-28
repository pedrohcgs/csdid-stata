# PY017: R oracle for the parametric grids. The inherited assertions were
# "at least one ATT is finite" and "at least one SE is positive", which almost
# any implementation satisfies.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/py017/inputs"
pd <- read.csv(file.path(IN,"panel-data.csv"));        names(pd) <- tolower(names(pd))
ad <- read.csv(file.path(IN,"anticipation-data.csv")); names(ad) <- tolower(names(ad))
rows <- list()
fit <- function(tag, d, m, cg, bp, panel, ant) {
  a <- if (panel)
      q(att_gt(yname="y",tname="period",idname="id",gname="g",xformla=~x,data=d,
               est_method=m,control_group=cg,base_period=bp,anticipation=ant,
               bstrap=FALSE,cband=FALSE))
    else
      q(att_gt(yname="y",tname="period",gname="g",xformla=~x,data=d,panel=FALSE,
               est_method=m,control_group=cg,base_period=bp,anticipation=ant,
               bstrap=FALSE,cband=FALSE))
  rows[[tag]] <<- data.frame(scenario=tag, group=a$group, time=a$t, att=a$att, se=a$se)
}
# grid 1: method x control x base, on the panel design
for (m in c("dr","reg","ipw")) for (cg in c("nevertreated","notyettreated")) for (bp in c("varying","universal"))
  fit(paste("g1",m,cg,bp,sep="_"), pd, m, cg, bp, TRUE, 0)
# grid 2: method x panel/rcs
for (m in c("dr","reg","ipw")) for (pn in c(1,0))
  fit(paste("g2",m,ifelse(pn==1,"panel","rcs"),sep="_"), pd, m, "nevertreated", "varying", pn==1, 0)
# grid 3: anticipation x method
for (ant in c(0,1,2)) for (m in c("dr","reg","ipw"))
  fit(paste("g3",m,ant,sep="_"), ad, m, "nevertreated", "varying", TRUE, ant)
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py017/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY017 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
