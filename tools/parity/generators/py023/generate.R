# PY023: R oracle for the Python-map user-bug-fix regressions.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/py023/inputs"; rows <- list()
add <- function(tag,r) { if (is.null(r)) { cat("  skip",tag,"\n"); return(invisible()) }
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se) }
mp <- read.csv(file.path(IN,"mpdta.csv")); names(mp)<-tolower(gsub("\\.","",names(mp)))
add("mpdta_reg_notyet", tryCatch(q(att_gt(yname="lemp",tname="year",idname="countyreal",
    gname="firsttreat", data=mp, est_method="reg", control_group="notyettreated",
    bstrap=FALSE,cband=FALSE)), error=function(e) NULL))
add("mpdta_reg_notyet_x", tryCatch(q(att_gt(yname="lemp",tname="year",idname="countyreal",
    gname="firsttreat", xformla=~lpop, data=mp, est_method="reg",
    control_group="notyettreated", bstrap=FALSE,cband=FALSE)), error=function(e) NULL))
fp <- read.csv(file.path(IN,"fewer_periods.csv")); names(fp)<-tolower(names(fp))
add("fewer_periods", tryCatch(q(att_gt(yname="y",tname="period",idname="id",gname="g",
    xformla=~x, data=fp, est_method="dr", bstrap=FALSE,cband=FALSE)), error=function(e) NULL))
zp <- read.csv(file.path(IN,"zero_pretreat.csv")); names(zp)<-tolower(names(zp))
for (bp in c("varying","universal"))
  add(paste0("zero_pre_",bp), tryCatch(q(att_gt(yname="y",tname="period",idname="id",gname="g",
      data=zp, control_group="notyettreated", base_period=bp, bstrap=FALSE,cband=FALSE)),
      error=function(e) NULL))
an <- read.csv(file.path(IN,"anticipation.csv")); names(an)<-tolower(names(an))
for (a in c(0,2))
  add(paste0("anticipation_",a), tryCatch(q(att_gt(yname="y",tname="time",idname="id",
      gname="group", data=an, anticipation=a, bstrap=FALSE,cband=FALSE)), error=function(e) NULL))
out <- do.call(rbind, rows)
write.csv(out,"tests/fixtures/parity/py023/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("PY023 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
