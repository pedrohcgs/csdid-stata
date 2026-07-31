# RT012: R oracle for the fast/nofast scenarios. The inherited test proves the
# two kernels agree with each other, which both being wrong would also satisfy.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/rt012/inputs"
d  <- read.csv(file.path(IN,"input.csv"));            names(d)  <- tolower(names(d))
du <- read.csv(file.path(IN,"input-unbalanced.csv")); names(du) <- tolower(names(du))
rows <- list()
add <- function(tag,r) rows[[tag]] <<-
  data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
add("dr_panel", q(att_gt(yname="y",tname="period",idname="id",gname="g",xformla=~x,
    data=d, est_method="dr", bstrap=FALSE, cband=FALSE)))
add("dr_notyet_universal", q(att_gt(yname="y",tname="period",idname="id",gname="g",xformla=~x,
    data=d, est_method="dr", control_group="notyettreated", base_period="universal",
    bstrap=FALSE, cband=FALSE)))
add("ipw_rcs_varying", q(att_gt(yname="y",tname="period",gname="g",xformla=~x,
    data=d, panel=FALSE, est_method="ipw", base_period="varying", bstrap=FALSE, cband=FALSE)))
add("reg_unbal_notyet", q(att_gt(yname="y",tname="period",idname="id",gname="g",xformla=~x,
    data=du, est_method="reg", control_group="notyettreated",
    allow_unbalanced_panel=TRUE, bstrap=FALSE, cband=FALSE)))
add("reg_nox", q(att_gt(yname="y",tname="period",idname="id",gname="g",
    data=d, est_method="reg", bstrap=FALSE, cband=FALSE)))
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/rt012/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("RT012 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
