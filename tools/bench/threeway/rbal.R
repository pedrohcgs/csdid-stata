suppressMessages(library(did))
OUT <- "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid-stata-porting/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
q <- function(e) suppressWarnings(suppressMessages(e))
tm <- function(f, reps=5) { t<-numeric(reps); for(i in 1:reps) t[i]<-system.time(f())[["elapsed"]]; min(t) }
bal <- read.csv(file.path(OUT,"balanced.csv")); unb <- read.csv(file.path(OUT,"unbalanced.csv"))
rcs <- read.csv(file.path(OUT,"rcs.csv"))
a <- tm(function() q(att_gt(yname="y",tname="time",idname="id",gname="g",xformla=~x1+x2,
      weightsname="wt",data=bal,est_method="dr",bstrap=FALSE,cband=FALSE)))
b <- tm(function() q(att_gt(yname="y",tname="time",idname="id",gname="g",xformla=~x1+x2,
      weightsname="wt",data=unb,est_method="dr",bstrap=FALSE,cband=FALSE,allow_unbalanced_panel=TRUE)))
cc <- tm(function() q(att_gt(yname="y",tname="time",gname="g",xformla=~x1+x2,
      weightsname="wt",data=rcs,est_method="dr",bstrap=FALSE,cband=FALSE,panel=FALSE)))
cat(sprintf("R balanced   : %.4f\nR unbalanced : %.4f  (%.2fx balanced)\nR rcs        : %.4f  (%.2fx balanced)\n",
    a, b, b/a, cc, cc/a))
