#!/usr/bin/env Rscript
# RT077: supported weighted designs and normalized RC outcome support.
args <- commandArgs(trailingOnly = FALSE)
farg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(farg)) sub("^--file=", "", farg[1L]) else "tools/parity/generators/rt077/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt077")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(p) digest::digest(file = p, algo = "sha256")
fmt <- function(x) ifelse(is.na(x), "", sprintf("%.17g", x))
write_exact <- function(z, path) {
  for (n in names(z)) if (is.numeric(z[[n]])) z[[n]] <- fmt(z[[n]])
  write.csv(z, file.path(out, path), row.names = FALSE, quote = FALSE)
}
inputs <- list(); specs <- list(); cells <- list(); influences <- list(); warnings <- list()
for (route in c("panel", "rc", "unbalanced", "varying")) {
  for (method in c("reg", "dr", "ipw")) for (kind in c("zero", "ordinary", "tiny", "unweighted", "nearrank")) {
    if (kind == "tiny" && method != "reg") next
    scenario <- paste(route, method, kind, sep = "_")
    z <- expand.grid(t = 1:5, id = 1:120)
    z$g <- ifelse(z$id <= 60, 0, ifelse(z$id <= 90, 3, 4))
    z$x <- sin(z$id * 1.37) + cos(z$id * .71) / 3
    z$w <- 1 + (z$id %% 5) / 7
    z$y <- sin(z$id * .9) + z$t * (.2 + .3 * z$x) +
      sin(z$id * 1.7 + z$t * .8) / 5 + ifelse(z$g > 0 & z$t >= z$g, 1 + .2 * (z$t-z$g), 0)
    if (route == "unbalanced") z <- z[!(z$id %% 13 == 0 & z$t == 5), ]
    if (kind %in% c("zero", "tiny")) {
      extra <- data.frame(t=1:5, id=121, g=if (method == "reg") 0 else 3,
        x=if (method == "reg") 1e12 else 1000,
        w=if (kind == "zero") 0 else 1e-24, y=0)
      z <- rbind(z, extra[, names(z)])
    }
    if (kind == "nearrank") z$x <- z$x * 1e7
    weighted <- as.integer(!kind %in% c("unweighted", "nearrank"))
    if (route == "rc") z$id <- seq_len(nrow(z))
    input <- paste0("inputs/", scenario, ".csv")
    write_exact(z, input)
    inputs[[length(inputs)+1L]] <- list(path=input, sha256=sha(file.path(out,input)),rows=nrow(z),columns=ncol(z))
    for (fast in c(FALSE, TRUE)) {
      msgs <- character()
      fit <- withCallingHandlers(suppressMessages(did::att_gt(yname="y",tname="t",gname="g",idname="id",
        data=z,xformla=~x,weightsname=if (weighted) "w" else NULL,control_group="nevertreated",base_period="universal",
        panel=route!="rc",allow_unbalanced_panel=route=="unbalanced",
        fix_weights=if (route=="varying") "varying" else NULL,
        est_method=method,faster_mode=fast,bstrap=FALSE,cband=FALSE)),
        warning=function(e) { msgs <<- c(msgs,conditionMessage(e)); invokeRestart("muffleWarning") })
      stopifnot(all(is.finite(fit$att)))
      key <- data.frame(scenario,fast=as.integer(fast),group=fit$group,time=fit$t,att=fit$att,se=fit$se)
      cells[[length(cells)+1L]] <- key
      fi <- as.matrix(fit$inffunc)
      influences[[length(influences)+1L]] <- data.frame(scenario,fast=as.integer(fast),
        unit=rep(as.numeric(rownames(fi)),ncol(fi)),group=rep(fit$group,each=nrow(fi)),
        time=rep(fit$t,each=nrow(fi)),value=as.vector(fi))
      if (length(msgs)) warnings[[length(warnings)+1L]] <- data.frame(scenario,fast=as.integer(fast),message=msgs)
    }
    specs[[length(specs)+1L]] <- data.frame(scenario,route,method,kind,weighted)
  }
}
write.csv(do.call(rbind,specs),file.path(out,"inputs/scenarios.csv"),row.names=FALSE,quote=FALSE)
inputs[[length(inputs)+1L]] <- list(path="inputs/scenarios.csv",sha256=sha(file.path(out,"inputs/scenarios.csv")),rows=length(specs),columns=5)
write_exact(do.call(rbind,cells),"expected/r/attgt.csv")
write_exact(do.call(rbind,influences),"expected/r/inffunc.csv")
write.csv(if(length(warnings)) do.call(rbind,warnings) else data.frame(scenario=character(),fast=integer(),message=character()),
  file.path(out,"expected/r/warnings.csv"),row.names=FALSE)

# Necessary support boundaries are observed directly without entering native
# nuisance fitting: underflow, the smallest subnormal, zero and square blocks.
guard_inputs <- list(); guard_expected <- list()
for (small in c("control","treated")) for (power in c(-100,-76,-75,0,1000)) {
  for (rescale in c(1,2^-900)) for (k in 1:2) {
    scenario <- paste("support",small,power,if(rescale==1)"large" else "scaled",k,sep="_")
    D <- c(0,0,1,1); post <- c(0,1,0,1)
    w <- if (small=="treated") c(2^1000,2^1000,2^power,2^power) else c(2^power,2^power,2^1000,2^1000)
    w <- w*rescale
    dat <- data.frame(scenario,id=1:4,d=D,post,w,k)
    guard_inputs[[length(guard_inputs)+1L]] <- dat
    guard_expected[[length(guard_expected)+1L]] <- data.frame(scenario,
      dr=as.integer(did:::rc_outcome_has_too_few_obs(D,post,w,k,TRUE)),
      reg=as.integer(did:::rc_outcome_has_too_few_obs(D,post,w,k,FALSE)))
  }
}
write_exact(do.call(rbind,guard_inputs),"inputs/support.csv")
inputs[[length(inputs)+1L]] <- list(path="inputs/support.csv",sha256=sha(file.path(out,"inputs/support.csv")),rows=nrow(do.call(rbind,guard_inputs)),columns=6)
write.csv(do.call(rbind,guard_expected),file.path(out,"expected/r/support.csv"),row.names=FALSE,quote=FALSE)

outputs <- lapply(c("attgt.csv","inffunc.csv","warnings.csv","support.csv"),function(n)
  list(path=paste0("expected/r/",n),schema="rt077",sha256=sha(file.path(out,"expected/r",n))))
manifest <- list(matrix_id="RT077",fixture_family="r-weighted-feasibility-support",
  normative_source="did utility_functions.R overlap_check_fail, rcond_check_fail, rc_outcome_has_too_few_obs; compute.att_gt2.R normalized RC support precedence",
  source_commit="4bed75ef731cba2e6d4a28205111b311f892fab1",decision_refs=list(),tolerance_ids=c("EXACT","TOL001","TOL002"),inputs=inputs,
  generators=list(list(runtime="R",command="Rscript tools/parity/generators/rt077/generate.R",path="tools/parity/generators/rt077/generate.R",sha256=sha(script_path))),
  runtimes=list(list(name="R",version=as.character(getRversion()),package_versions=list(did=as.character(packageVersion("did")),DRDID=as.character(packageVersion("DRDID"))))),rng=NULL,
  expected_outputs=outputs,comparison_plan=list(
    list(actual="every public ATT/SE and unit-level influence function on weighted panel, RC, unbalanced and varying-weight routes",expected="expected/r/attgt.csv and inffunc.csv",tolerance_id="TOL002",key_columns=c("scenario","fast","group","time","unit")),
    list(actual="exact normalized support decisions including square and subnormal boundaries",expected="expected/r/support.csv",tolerance_id="EXACT",key_columns="scenario")),
  approved_divergence=NULL,scope_note="52 deterministic designs, each in both R compute modes, plus 40 normalized support boundaries. The 28 weighted designs cover zero-weight extreme covariates and tiny positive control weights; 24 unweighted designs cover ordinary and large-column-scale near-rank designs with no user weights. All public estimates and every unit-level influence-function entry are compared, alongside weighted numerical-rank rejection and normalized support checks in the Stata test.")
jsonlite::write_json(manifest,file.path(out,"metadata/manifest.json"),pretty=TRUE,auto_unbox=TRUE,null="null")
cat("RT077 written:",length(specs),"public designs;",nrow(do.call(rbind,cells)),"cells;",nrow(do.call(rbind,guard_expected)),"support boundaries.\n")
