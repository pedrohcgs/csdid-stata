# F045: R oracle for the legacy-default surface -- the defaults csdid resolves
# when options are omitted, on balanced and unbalanced weighted designs.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/f045/inputs"; rows <- list()
b <- read.csv(file.path(IN,"balanced.csv"));   names(b)<-tolower(names(b))
u <- read.csv(file.path(IN,"unbalanced.csv")); names(u)<-tolower(names(u))
add <- function(tag,r) rows[[tag]] <<-
  data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
add("default_dr_balanced", q(att_gt(yname="y",tname="time",idname="id",gname="g",
    xformla=~x1+x2, weightsname="w", data=b, est_method="dr", bstrap=FALSE, cband=FALSE)))
add("explicit_dr_varying", q(att_gt(yname="y",tname="time",idname="id",gname="g",
    xformla=~x1+x2, weightsname="w", data=b, est_method="dr", base_period="varying",
    bstrap=FALSE, cband=FALSE)))
add("rcs_default", q(att_gt(yname="y",tname="time",gname="g", panel=FALSE,
    xformla=~x1+x2, weightsname="w", data=b, est_method="dr", bstrap=FALSE, cband=FALSE)))
add("ipw_balanced", q(att_gt(yname="y",tname="time",idname="id",gname="g",
    xformla=~x1+x2, weightsname="w", data=b, est_method="ipw", bstrap=FALSE, cband=FALSE)))
add("unbalanced_default", q(att_gt(yname="y",tname="time",idname="id",gname="g",
    xformla=~x1+x2, weightsname="w", data=u, est_method="dr",
    allow_unbalanced_panel=TRUE, bstrap=FALSE, cband=FALSE)))
out <- do.call(rbind, rows)
write.csv(out,"tests/fixtures/parity/f045/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("F045 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
