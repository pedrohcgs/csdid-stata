# RT028: R oracle for the user-bug-fix regressions that estimate.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/rt028/inputs"; rows <- list()
add <- function(tag,file,tn,gn,xf,...) {
  d <- read.csv(file.path(IN,file)); names(d)<-tolower(names(d))
  args <- list(yname="y", tname=tn, idname="id", gname=gn, data=d, bstrap=FALSE, cband=FALSE, ...)
  if (!is.null(xf)) args$xformla <- xf
  r <- tryCatch(q(do.call(att_gt,args)), error=function(e) NULL)
  if (is.null(r)) { cat("  skip",tag,"\n"); return(invisible()) }
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
}
add("fewer_periods","fewer-periods.csv","period","g",~x, est_method="dr")
for (bp in c("varying","universal"))
  add(paste0("zero_pre_",bp),"zero-pre.csv","period","g",NULL,
      control_group="notyettreated", base_period=bp)
for (a in c(0,2))
  add(paste0("anticipation_",a),"anticipation.csv","time","group",NULL, anticipation=a)
out <- do.call(rbind, rows)
write.csv(out,"tests/fixtures/parity/rt028/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("RT028 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
