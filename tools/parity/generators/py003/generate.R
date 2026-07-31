# PY003: R oracle for the att_gt suite's estimating scenarios.
#
# The largest inherited suite, and the one whose numeric assertions were
# weakest: DGP-implied targets with loose tolerances, plus fast-versus-nofast
# self-consistency. The fix_weights block is the most valuable piece, because
# fix_weights has a direct R counterpart and nothing compared it.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/py003/inputs"; rows <- list()
add <- function(tag,r) { if (is.null(r)) { cat("  skip",tag,"\n"); return(invisible()) }
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se) }
G <- function(...) tryCatch(q(att_gt(...)), error=function(e) NULL)

sim <- read.csv(file.path(IN,"sim-data.csv"));            names(sim)<-tolower(names(sim))
fw  <- read.csv(file.path(IN,"fixweights.csv"));          names(fw)<-tolower(names(fw))
fc  <- read.csv(file.path(IN,"fixweights-constant.csv")); names(fc)<-tolower(names(fc))
fu  <- read.csv(file.path(IN,"fixweights-unbalanced.csv"));names(fu)<-tolower(names(fu))

# core grid: method x panel/rcs x covariates x control group
for (m in c("dr","reg","ipw")) {
  add(paste0("panel_x_",m),  G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
      data=sim,est_method=m,bstrap=FALSE,cband=FALSE))
  add(paste0("panel_nox_",m),G(yname="y",tname="period",idname="id",gname="g",
      data=sim,est_method=m,bstrap=FALSE,cband=FALSE))
  add(paste0("rcs_x_",m),    G(yname="y",tname="period",gname="g",xformla=~x,panel=FALSE,
      data=sim,est_method=m,bstrap=FALSE,cband=FALSE))
  add(paste0("notyet_",m),   G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
      data=sim,est_method=m,control_group="notyettreated",bstrap=FALSE,cband=FALSE))
}
add("cluster_dr", G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
    data=sim,est_method="dr",clustervars="cluster",bstrap=FALSE,cband=FALSE))
add("weighted_notyet_reg", G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
    data=fw,est_method="reg",weightsname="wt",control_group="notyettreated",
    bstrap=FALSE,cband=FALSE))

# fix_weights: the block with a direct R counterpart and no prior comparison
for (f in c("varying","base_period","first_period"))
  add(paste0("fixw_",f), G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
      data=fw,est_method="reg",weightsname="wt",fix_weights=f,bstrap=FALSE,cband=FALSE))
add("fixw_unset", G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
    data=fw,est_method="reg",weightsname="wt",bstrap=FALSE,cband=FALSE))
for (f in c("varying","base_period","first_period"))
  add(paste0("fixconst_",f), G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
      data=fc,est_method="reg",weightsname="wt",fix_weights=f,bstrap=FALSE,cband=FALSE))
add("fixw_base_notyet", G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
    data=fw,est_method="reg",weightsname="wt",fix_weights="base_period",
    control_group="notyettreated",bstrap=FALSE,cband=FALSE))
add("fixw_rcs_varying", G(yname="y",tname="period",gname="g",xformla=~x,panel=FALSE,
    data=fw,est_method="reg",weightsname="wt",fix_weights="varying",bstrap=FALSE,cband=FALSE))
add("fixunbal_first", G(yname="y",tname="period",idname="id",gname="g",xformla=~x,
    data=fu,est_method="reg",weightsname="wt",fix_weights="first_period",
    allow_unbalanced_panel=TRUE,bstrap=FALSE,cband=FALSE))
out <- do.call(rbind, rows)
write.csv(out,"tests/fixtures/parity/py003/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("PY003 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
