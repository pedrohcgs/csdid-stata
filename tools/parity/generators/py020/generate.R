# PY020: R oracle for the review-fix scenarios, including factor covariates
# (Stata i.cat_code == R factor(cat_code)) and a seeded clustered bootstrap.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/py020/inputs"; rows <- list()
rp <- read.csv(file.path(IN,"review-panel.csv"));    names(rp)<-tolower(names(rp))
cp <- read.csv(file.path(IN,"clustered-panel.csv")); names(cp)<-tolower(names(cp))
add <- function(tag,r) rows[[tag]] <<-
  data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
add("factor_reg_panel", q(att_gt(yname="y",tname="year",idname="id",gname="group",
    xformla=~factor(cat_code), data=rp, est_method="reg", bstrap=FALSE, cband=FALSE)))
add("nox_reg_panel", q(att_gt(yname="y",tname="year",idname="id",gname="group",
    data=rp, est_method="reg", bstrap=FALSE, cband=FALSE)))
add("factor_reg_rcs", q(att_gt(yname="y",tname="year",gname="group", panel=FALSE,
    xformla=~factor(cat_code), data=rp, est_method="reg", bstrap=FALSE, cband=FALSE)))
add("factor_z_dr_panel", q(att_gt(yname="y",tname="year",idname="id",gname="group",
    xformla=~factor(cat_code)+z, data=rp, est_method="dr", bstrap=FALSE, cband=FALSE)))
set.seed(202620)
add("clustered_boot31", q(att_gt(yname="y",tname="year",idname="id",gname="group",
    data=cp, est_method="reg", bstrap=TRUE, biters=31, cband=FALSE, clustervars="cluster")))
out <- do.call(rbind, rows)
write.csv(out,"tests/fixtures/parity/py020/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("PY020 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
