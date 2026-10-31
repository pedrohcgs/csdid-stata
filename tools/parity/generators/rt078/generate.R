#!/usr/bin/env Rscript
# RT078: outcome units, anticipation-window inference and bootstrap support.
args <- commandArgs(trailingOnly = FALSE)
farg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(farg)) sub("^--file=", "", farg[1L]) else "tools/parity/generators/rt078/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt078")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(p) digest::digest(file = p, algo = "sha256")
inputs <- outputs <- list()
write17 <- function(z, path, input = FALSE) {
  z <- as.data.frame(z)
  quoted <- which(vapply(z,is.character,logical(1)))
  for (j in seq_along(z)) if (is.numeric(z[[j]])) z[[j]] <- ifelse(is.na(z[[j]]), "", sprintf("%.17g", z[[j]]))
  write.csv(z, file.path(out, path), row.names = FALSE, quote = quoted, na = "")
  check <- read.csv(file.path(out,path),check.names=FALSE,stringsAsFactors=FALSE)
  stopifnot(identical(dim(check),dim(z)),identical(names(check),names(z)))
  record <- list(path=path, sha256=sha(file.path(out,path)), rows=nrow(z), columns=ncol(z))
  if (input) inputs[[length(inputs)+1L]] <<- record else {
    record$schema <- "rt078"; outputs[[length(outputs)+1L]] <<- record
  }
}
matrix_rows <- function(z, scenario, type = "cells", keys = NULL) {
  z <- as.matrix(z)
  stopifnot(ncol(z)<=20L)
  if(ncol(z)<20L) z <- cbind(z,matrix(NA_real_,nrow(z),20L-ncol(z)))
  colnames(z) <- paste0("v",seq_len(ncol(z)))
  data.frame(scenario=scenario,type=type,unit=if(is.null(keys))seq_len(nrow(z)) else keys,z)
}
data <- expand.grid(time=c(1,2,3,4,6,7,8),id=seq_len(120L))[,c("id","time")]
data$g <- rep(c(0,4,7),each=40L)[data$id]
data$cl <- ifelse(data$id<=3,1L,1L+ceiling((data$id-3)/5))
data$y <- sin(data$id*.47) + .2*data$time + cos(data$id*data$time*.31) / 4 +
  ifelse(data$g>0 & data$time>=data$g-1, .5+.15*(data$time-data$g), 0)
write17(data,"inputs/panel.csv",TRUE)
rc <- data; rc$id <- seq_len(nrow(rc)); rc$cl <- ifelse(rc$id<=3,1L,1L+ceiling((rc$id-3)/7))
write17(rc,"inputs/rc.csv",TRUE)
specs <- expand.grid(route=c("panel","rc"),method=c("reg","dr","ipw"),
  base=c("varying","universal"),anticipation=c(0L,1L),scale=c(1,1e-8,1e-100),
  bootstrap=c(0L,1L),KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE)
# Unequal clusters are exercised alongside the i.i.d. route.
specs$cluster <- as.integer(specs$method=="reg" & specs$anticipation==1L)
specs$scenario <- sprintf("s%03d",seq_len(nrow(specs)))
write17(specs,"inputs/scenarios.csv",TRUE)
diagnostics <- cell_rows <- if_rows <- agg_rows <- agg_if_rows <- crit_rows <- list()
for (i in seq_len(nrow(specs))) {
  s <- specs[i,]; d <- if(s$route=="panel") data else rc
  d$y <- d$y*s$scale
  a <- list(yname="y",tname="time",idname="id",gname="g",data=d,panel=s$route=="panel",
    control_group="notyettreated",base_period=s$base,anticipation=s$anticipation,
    est_method=s$method,bstrap=as.logical(s$bootstrap),cband=as.logical(s$bootstrap),biters=199L)
  if(s$cluster) a$clustervars <- "cl"
  set.seed(20261026)
  fit <- suppressWarnings(suppressMessages(do.call(did::att_gt,a)))
  cell_rows[[i]] <- data.frame(scenario=s$scenario,group=fit$group,time=fit$t,att=fit$att,se=fit$se)
  inf <- as.matrix(fit$inffunc)
  keys <- sort(unique(d$id)); ord <- match(as.character(keys),rownames(inf))
  stopifnot(!anyNA(ord)); inf <- inf[ord,,drop=FALSE]
  if_rows[[i]] <- matrix_rows(inf,s$scenario,keys=keys)
  diagnostics[[i]] <- data.frame(scenario=s$scenario,crit=fit$c,cband=as.integer(fit$DIDparams$cband),
    wald=if(is.null(fit$W)) NA_real_ else as.numeric(fit$W),pvalue=if(is.null(fit$Wpval)) NA_real_ else fit$Wpval)
  for(type in c("dynamic","group","calendar","simple")) {
    ag <- suppressWarnings(did::aggte(fit,type=type))
    if(type=="simple") {
      tab <- matrix(c(NA_real_,ag$overall.att,ag$overall.se,ag$overall.att,ag$overall.se),1)
      aif <- cbind(ag$inf.function$simple.att,ag$inf.function$simple.att)
      crit <- qnorm(.975)
    } else {
      tab <- cbind(ag$egt,ag$att.egt,ag$se.egt,ag$overall.att,ag$overall.se)
      aif <- switch(type,dynamic=cbind(ag$inf.function$dynamic.inf.func.e,ag$inf.function$dynamic.inf.func),
        group=cbind(ag$inf.function$selective.inf.func.g,ag$inf.function$selective.inf.func),
        calendar=cbind(ag$inf.function$calendar.inf.func.t,ag$inf.function$calendar.inf.func))
      crit <- ag$crit.val.egt
    }
    agg_rows[[length(agg_rows)+1L]] <- matrix_rows(tab,s$scenario,type)
    agg_if_rows[[length(agg_if_rows)+1L]] <- matrix_rows(aif[ord,,drop=FALSE],s$scenario,type)
    crit_rows[[length(crit_rows)+1L]] <- data.frame(scenario=s$scenario,type=type,crit=crit)
  }
}
write17(do.call(rbind,diagnostics),"expected/r/diagnostics.csv")
write17(do.call(rbind,cell_rows),"expected/r/cells.csv")
write17(do.call(rbind,if_rows),"expected/r/inffunc.csv")
write17(do.call(rbind,agg_rows),"expected/r/aggregates.csv")
write17(do.call(rbind,agg_if_rows),"expected/r/agg-inffunc.csv")
write17(do.call(rbind,crit_rows),"expected/r/criticals.csv")
two_period <- list()
for(route in c("panel","rc")) {
  d <- subset(if(route=="panel")data else rc,time %in% c(1,2))
  d$g <- ifelse(d$g==4,2,0)
  set.seed(20261026)
  f <- suppressWarnings(did::att_gt("y","time","id","g",data=d,panel=route=="panel",
    est_method="reg",base_period="universal",control_group="notyettreated",biters=199L))
  stopifnot(!f$DIDparams$cband,identical(f$c,qnorm(.975)))
  two_period[[route]] <- data.frame(route,group=f$group,time=f$t,att=f$att,se=f$se,crit=f$c,cband=as.integer(f$DIDparams$cband))
}
write17(do.call(rbind,two_period),"expected/r/two-period.csv")
for(base in c("varying","universal")) {
  fit <- function(d) suppressWarnings(did::att_gt("y","time","id","g",data=d,anticipation=1L,
    base_period=base,control_group="notyettreated",est_method="reg",bstrap=FALSE,cband=FALSE))
  f <- fit(data); changed <- data;changed$y[changed$g==4 & changed$time==3] <- changed$y[changed$g==4 & changed$time==3]+9
  g <- fit(changed)
  delta <- 9*(f$group==4 & f$t==3)
  stopifnot(max(abs(g$att-f$att-delta))<1e-10,abs(g$W-f$W)<1e-8)
}
# Tiny scales must survive even when squaring the draws underflows. Attestation
# comes from the public fits above; these target mboot's exact support rule.
b <- c(-2,-1,0,1,2)
sigma <- (b[ceiling(.75*length(b))]-b[ceiling(.25*length(b))])/(qnorm(.75)-qnorm(.25))
write17(data.frame(scale=c(1,1e-8,1e-200),sigma=sigma*c(1,1e-8,1e-200)),"expected/r/tiny-sigma.csv")
boundary <- local({
  draws <- cbind(c(4e307,2e-308,3e-308,4e-308,5e-308),c(1e100,-2,-1,0,1))
  dp <- list(idname="id",tname="time",clustervars=NULL,biters=5L,alp=.05,panel=TRUE,
    true_repeated_cross_sections=FALSE,allow_unbalanced_panel=FALSE)
  ns <- asNamespace("did"); name <- "run_multiplier_bootstrap"; old <- get(name,ns)
  unlockBinding(name,ns); assign(name,function(...)draws/sqrt(5),ns);lockBinding(name,ns)
  on.exit({unlockBinding(name,ns);assign(name,old,ns);lockBinding(name,ns)})
  # Feed controlled finite draws through the actual authenticated summary.
  # One studentized entry overflows; R must omit that entire sup-t draw.
  did::mboot(matrix(1,5,2),dp,return_V=FALSE)
})
write17(data.frame(v1=boundary$bres[,1],v2=boundary$bres[,2]),"inputs/overflow-draws.csv",TRUE)
write17(data.frame(crit=as.numeric(boundary$crit.val)),"expected/r/overflow-crit.csv")
mpdta <- read.csv(file.path(root,"examples/data/mpdta.csv"))
mpdta$lemp <- mpdta$lemp*3e-5
set.seed(1)
mpfit <- suppressWarnings(did::att_gt("lemp","year","countyreal","first_treat",data=mpdta,
  control_group="notyettreated",base_period="universal",bstrap=TRUE,cband=TRUE,biters=1000L))
write17(data.frame(group=mpfit$group,time=mpfit$t,att=mpfit$att,se=mpfit$se,crit=mpfit$c),"expected/r/mpdta-small.csv")
cluster_probes <- data.frame(id=1:4,cl=c(1,1,2,2),
  missing=c(1,NA_real_,3,3),overflow=c(1e200,1e200,1,1),healthy=c(1,2,3,4),zero=0)
write17(cluster_probes,"inputs/cluster-probes.csv",TRUE)
cluster_dp <- list(bstrap=FALSE,alp=.05,cband=FALSE,cluster_vector=cluster_probes$cl,
  clustervars="cl",idname="id")
cluster_expected <- data.frame(case=c("missing","overflow","healthy","zero"),
  se=vapply(cluster_probes[c("missing","overflow","healthy","zero")],
    function(x)did:::getSE(x,cluster_dp),0))
stopifnot(all(is.na(cluster_expected$se[c(1,2,4)])),is.finite(cluster_expected$se[3]))
write17(cluster_expected,"expected/r/cluster-se.csv")
manifest <- list(matrix_id="RT078",fixture_family="r-upstream-inference-units",
  normative_source="did att_gt.R:600-750; mboot.R:143-196; anticipation-window and outcome-unit regressions",
  source_commit="4bed75ef731cba2e6d4a28205111b311f892fab1",decision_refs=list(),tolerance_ids=c("EXACT","TOL001","TOL002"),inputs=inputs,
  generators=list(list(runtime="R",command="Rscript tools/parity/generators/rt078/generate.R",path="tools/parity/generators/rt078/generate.R",sha256=sha(script_path))),
  runtimes=list(list(name="R",version=as.character(getRversion()),package_versions=list(did=as.character(packageVersion("did")),DRDID=as.character(packageVersion("DRDID"))))),
  rng=list(kind="Mersenne-Twister",seed=20261026,biters=199),expected_outputs=outputs,
  comparison_plan=list(list(actual="every ATT/SE/IF, Wald and critical value and all four aggregate tables and IFs after dividing by outcome scale",expected="expected/r",tolerance_id="TOL002",key_columns=c("scenario","group","time"))),
  approved_divergence=NULL,scope_note="144 configurations cross panel/RC, all three estimators, both base conventions, anticipation 0/1, analytical/bootstrap, outcome scales 1/1e-8/1e-100, and unequal clusters. Irregular calendar isolates the actual universal base. Direct IQR checks retain representable 1e-200 scales even when squared draws underflow.")
jsonlite::write_json(manifest,file.path(out,"metadata/manifest.json"),pretty=TRUE,auto_unbox=TRUE,null="null")
cat("RT078 written:",nrow(specs),"inference configurations\n")
