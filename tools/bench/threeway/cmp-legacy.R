OUT <- "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid-stata-porting/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
suppressMessages(library(did)); q <- function(e) suppressWarnings(suppressMessages(e))
unb <- read.csv(file.path(OUT,"unbalanced.csv")); rcs <- read.csv(file.path(OUT,"rcs.csv"))
R1 <- q(att_gt(yname="y",tname="time",idname="id",gname="g",xformla=~x1+x2,weightsname="wt",
        data=unb,est_method="dr",bstrap=FALSE,cband=FALSE,allow_unbalanced_panel=TRUE))
R2 <- q(att_gt(yname="y",tname="time",gname="g",xformla=~x1+x2,weightsname="wt",
        data=rcs,est_method="dr",bstrap=FALSE,cband=FALSE,panel=FALSE))
rr <- rbind(data.frame(fixture="unb",g=R1$group,t=R1$t,att_r=R1$att,se_r=R1$se),
            data.frame(fixture="rcs",g=R2$group,t=R2$t,att_r=R2$att,se_r=R2$se))
for (eng in c("candidate","legacy")) {
  st <- read.csv(file.path(OUT, paste0(eng,"-attgt.csv"))); st$fixture <- trimws(st$fixture)
  m <- merge(rr, st, by=c("fixture","g","t"))
  for (f in c("unb","rcs")) {
    s <- m[m$fixture==f,]
    if (!nrow(s)) { cat(sprintf("%-9s %s: NO MATCHED CELLS\n", eng, f)); next }
    cat(sprintf("%-9s %s: %2d/15 cells | max|dATT|=%.3e maxrel=%.3e | max|dSE|=%.3e maxrel=%.3e\n",
        eng, f, nrow(s), max(abs(s$att-s$att_r)), max(abs(s$att-s$att_r)/pmax(abs(s$att_r),1e-12)),
        max(abs(s$se-s$se_r)), max(abs(s$se-s$se_r)/pmax(abs(s$se_r),1e-12))))
  }
}
