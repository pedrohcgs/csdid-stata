# RT004: R oracle for the always-treated-invariance designs. The inherited test
# checks that rescaling one cohort's outcome leaves other cohorts' ATT
# unchanged -- an invariance, which is self-referential. This pins the base
# runs against R.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/rt004/inputs"; rows <- list()
add <- function(tag,file,...) {
  d <- read.csv(file.path(IN,file)); names(d)<-tolower(names(d))
  r <- tryCatch(q(att_gt(yname="y",tname="t",idname="uid",gname="g",data=d,
                         bstrap=FALSE,cband=FALSE,...)), error=function(e) NULL)
  if (is.null(r)) { cat("  skip",tag,"\n"); return(invisible()) }
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
}
for (m in c("dr","reg","ipw")) {
  add(paste0("p1_",m), "p1.csv", est_method=m)
  add(paste0("structural_",m), "structural.csv", est_method=m)
}
add("structural_notyet_dr","structural.csv", est_method="dr", control_group="notyettreated")
add("fastslow_dr","fastslow.csv", est_method="dr")
out <- do.call(rbind, rows)
write.csv(out,"tests/fixtures/parity/rt004/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("RT004 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
