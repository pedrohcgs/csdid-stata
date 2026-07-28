# PY009: R oracle for the full 24-cell grid the fast/nofast test sweeps --
# panel x repeated cross sections, never/not-yet-treated controls, three
# methods, varying/universal base periods. The inherited test proved only that
# fast equals nofast, which is self-consistency: both could be wrong together.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/py009/inputs/sim-fast.csv"); names(d)<-tolower(names(d))
rows <- list()
for (pn in c("panel","rcs"))
 for (cg in c("nevertreated","notyettreated"))
  for (m in c("dr","reg","ipw"))
   for (bp in c("varying","universal")) {
     tag <- paste(pn,cg,m,bp,sep="_")
     a <- if (pn=="panel")
        q(att_gt(yname="y",tname="period",idname="id",gname="g",xformla=~x,data=d,
                 est_method=m,control_group=cg,base_period=bp,bstrap=FALSE,cband=FALSE))
      else
        q(att_gt(yname="y",tname="period",gname="g",xformla=~x,data=d,panel=FALSE,
                 est_method=m,control_group=cg,base_period=bp,bstrap=FALSE,cband=FALSE))
     rows[[tag]] <- data.frame(scenario=tag, group=a$group, time=a$t, att=a$att, se=a$se)
   }
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py009/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY009 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
