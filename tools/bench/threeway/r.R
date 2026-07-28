suppressMessages(library(did))
OUT <- "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
tm <- function(f, reps=3) {
  t <- numeric(reps); res <- NULL
  for (i in seq_len(reps)) t[i] <- system.time(res <- f())[["elapsed"]]
  list(sec=min(t), med=median(t), n=length(res$att), sumatt=sum(res$att, na.rm=TRUE))
}
unb <- read.csv(file.path(OUT,"unbalanced.csv")); rcs <- read.csv(file.path(OUT,"rcs.csv"))
q <- function(e) suppressWarnings(suppressMessages(e))
jobs <- list(
 unb_dr_analytical = function() q(att_gt(yname="y",tname="time",idname="id",gname="g",xformla=~x1+x2,
   weightsname="wt",data=unb,est_method="dr",bstrap=FALSE,cband=FALSE,allow_unbalanced_panel=TRUE)),
 unb_dr_bootstrap = function() q(att_gt(yname="y",tname="time",idname="id",gname="g",xformla=~x1+x2,
   weightsname="wt",data=unb,est_method="dr",bstrap=TRUE,biters=1000,cband=TRUE,allow_unbalanced_panel=TRUE)),
 rcs_dr_analytical = function() q(att_gt(yname="y",tname="time",gname="g",xformla=~x1+x2,
   weightsname="wt",data=rcs,est_method="dr",bstrap=FALSE,cband=FALSE,panel=FALSE)),
 rcs_dr_bootstrap = function() q(att_gt(yname="y",tname="time",gname="g",xformla=~x1+x2,
   weightsname="wt",data=rcs,est_method="dr",bstrap=TRUE,biters=1000,cband=TRUE,panel=FALSE)))
sink(file.path(OUT,"r-times.csv"))
cat("engine,scenario,sec_min,sec_med,ncells,sumatt\n")
for (k in names(jobs)) {
  r <- tm(jobs[[k]], 5)
  cat(sprintf("R,%s,%.4f,%.4f,%d,%.10g\n", k, r$sec, r$med, r$n, r$sumatt))
}
sink()
cat(readLines(file.path(OUT,"r-times.csv")), sep="\n")
