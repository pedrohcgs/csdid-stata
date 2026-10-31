#!/usr/bin/env Rscript
# RT079: common original event support and windows in calendar units.
args <- commandArgs(trailingOnly=FALSE)
farg <- grep("^--file=",args,value=TRUE)
script_path <- if(length(farg)) sub("^--file=","",farg[1L]) else "tools/parity/generators/rt079/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path),"../../../.."),mustWork=TRUE)
out <- file.path(root,"tests/fixtures/parity/rt079")
for(sub in c("inputs","expected/r","metadata")) dir.create(file.path(out,sub),recursive=TRUE,showWarnings=FALSE)
sha <- function(p) digest::digest(file=p,algo="sha256")
inputs <- outputs <- list()
write17 <- function(z,path,input=FALSE) {
  z <- as.data.frame(z)
  quoted <- which(vapply(z,is.character,logical(1)))
  for(j in seq_along(z)) if(is.numeric(z[[j]])) z[[j]] <- ifelse(is.na(z[[j]]),"",sprintf("%.17g",z[[j]]))
  write.csv(z,file.path(out,path),row.names=FALSE,quote=quoted,na="")
  check <- read.csv(file.path(out,path),check.names=FALSE,stringsAsFactors=FALSE)
  stopifnot(identical(dim(check),dim(z)),identical(names(check),names(z)))
  rec <- list(path=path,sha256=sha(file.path(out,path)),rows=nrow(z),columns=ncol(z))
  if(input) inputs[[length(inputs)+1L]] <<- rec else {rec$schema<-"rt079";outputs[[length(outputs)+1L]]<<-rec}
}
make <- function(periods,groups) {
  d <- expand.grid(time=periods,id=1:120)[,c("id","time")]
  d$g <- rep(groups,each=120/length(groups))[d$id]
  d$y <- .1*d$time+sin(d$id*.7)+cos(d$id*d$time*.2)/5+
    ifelse(d$g>0 & d$time>=d$g, .7+.2*d$g+.3*(d$time-d$g),0)
  d
}
data <- list(regular=make(1:5,c(0,2,3)),irregular=make(c(1,2,4,5),c(0,2,4)),
  sparse=make(c(1,3,5),c(0,3,5)),decimal=make(c(1,1.2,1.7,2.2,2.7,3.1),c(0,1.7,2.2,3.1)),
  offgrid=make(c(1,2,4,5),c(0,2.5,4)))
data$missing <- subset(data$regular,!(g==2 & time==3))
data$none <- subset(data$regular,!(g==2 & time==3) & !(g==3 & time==3))
data$vanished <- subset(data$regular,!(g==2 & time==3) & !(g==3 & time==4))
data$decimal_missing <- subset(data$decimal,!(g==1.7 & time %in% c(1.7,2.2)))
for(name in names(data)) write17(data[[name]],paste0("inputs/",name,".csv"),TRUE)
specs <- list()
add <- function(input,type,mine=-Inf,maxe=Inf,balance=-1,narm=TRUE) {
  specs[[length(specs)+1L]] <<- data.frame(input,type,mine,maxe,balance,narm=as.integer(narm))
}
for(input in names(data)) {
  for(maxe in c(0,1,2)) add(input,"dynamic",0,maxe,if(input=="sparse")2 else 1)
  for(type in c("simple","group")) for(window in list(c(-2,1),c(1,2),c(.4,1),c(20,21))) {
    add(input,type,window[1],window[2])
  }
}
add("regular","dynamic",0,1,10)
add("regular","group",0,2,1)
add("regular","simple",0,2,1)
specs <- do.call(rbind,specs); specs$scenario <- sprintf("s%03d",seq_len(nrow(specs)))
write17(specs,"inputs/scenarios.csv",TRUE)
fits <- lapply(data,function(d) suppressWarnings(suppressMessages(did::att_gt("y","time","id","g",data=d,
  est_method="reg",control_group="nevertreated",base_period="universal",allow_unbalanced_panel=TRUE,bstrap=FALSE,cband=FALSE))))
results <- statuses <- influences <- list()
for(i in seq_len(nrow(specs))) {
  s <- specs[i,]; f <- fits[[s$input]]
  a <- list(MP=f,type=s$type,min_e=s$mine,max_e=s$maxe,na.rm=as.logical(s$narm),bstrap=FALSE,cband=FALSE)
  if(s$balance>=0) a$balance_e <- s$balance
  messages <- character()
  ag <- tryCatch(withCallingHandlers(do.call(did::aggte,a),warning=function(e){messages<<-c(messages,conditionMessage(e));invokeRestart("muffleWarning")}),error=function(e)conditionMessage(e))
  error <- if(is.character(ag)) ag else ""
  statuses[[i]] <- data.frame(scenario=s$scenario,refused=as.integer(nzchar(error)),ignored=as.integer(any(grepl("balance_e.*ignored",messages))),message=error)
  if(nzchar(error)) next
  if(s$type=="simple") {
    tab <- data.frame(event=NA_real_,att=ag$overall.att,se=ag$overall.se,overall=ag$overall.att,overall_se=ag$overall.se)
    ai <- cbind(ag$inf.function$simple.att,ag$inf.function$simple.att)
  } else {
    tab <- data.frame(event=ag$egt,att=ag$att.egt,se=ag$se.egt,overall=ag$overall.att,overall_se=ag$overall.se)
    ai <- if(s$type=="dynamic") cbind(ag$inf.function$dynamic.inf.func.e,ag$inf.function$dynamic.inf.func) else cbind(ag$inf.function$selective.inf.func.g,ag$inf.function$selective.inf.func)
  }
  results[[length(results)+1L]] <- cbind(scenario=s$scenario,tab)
  ai <- as.matrix(ai); keys <- sort(unique(data[[s$input]]$id))
  ord <- match(as.character(keys),rownames(f$inffunc)); stopifnot(!anyNA(ord));ai<-ai[ord,,drop=FALSE]
  if(ncol(ai)<10) ai<-cbind(ai,matrix(NA_real_,nrow(ai),10-ncol(ai)))
  colnames(ai)<-paste0("v",seq_len(ncol(ai)))
  influences[[length(influences)+1L]]<-data.frame(scenario=s$scenario,unit=keys,ai)
}
write17(do.call(rbind,results),"expected/r/aggregates.csv")
write17(do.call(rbind,statuses),"expected/r/status.csv")
write17(do.call(rbind,influences),"expected/r/inffunc.csv")
manifest <- list(matrix_id="RT079",fixture_family="r-upstream-aggregation-support",normative_source="did compute.aggte.R:165-168,316,386-405,514-550",
  source_commit="4bed75ef731cba2e6d4a28205111b311f892fab1",decision_refs=list(),tolerance_ids=c("EXACT","TOL001","TOL002"),inputs=inputs,
  generators=list(list(runtime="R",command="Rscript tools/parity/generators/rt079/generate.R",path="tools/parity/generators/rt079/generate.R",sha256=sha(script_path))),
  runtimes=list(list(name="R",version=as.character(getRversion()),package_versions=list(did=as.character(packageVersion("did")),DRDID=as.character(packageVersion("DRDID"))))),rng=NULL,expected_outputs=outputs,
  comparison_plan=list(list(actual="all dynamic/simple/group aggregate cells and IFs or named window/support refusals",expected="expected/r",tolerance_id="TOL002",key_columns=c("scenario","event","unit"))),
  approved_divergence=NULL,scope_note="102 cases: regular, irregular, sparse, decimal and off-grid calendars; one missing cohort-event cell, no complete cohort, an event time missing for all cohorts, and decimal missing cells. Balancing requires the original eligible-cohort union of observed post-treatment event times before display limits. Both window bounds are measured in calendar units for every aggregation.")
jsonlite::write_json(manifest,file.path(out,"metadata/manifest.json"),pretty=TRUE,auto_unbox=TRUE,null="null")
cat("RT079 written:",nrow(specs),"aggregation cases\n")
