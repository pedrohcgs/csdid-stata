#!/usr/bin/env Rscript
# RT082: a backend-dependent Gram-conditioning refusal boundary.
args <- commandArgs(FALSE)
farg <- grep("^--file=",args,value=TRUE)
script_path <- if(length(farg)) sub("^--file=","",farg[1L]) else "tools/parity/generators/rt082/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path),"../../../.."),mustWork=TRUE)
out <- file.path(root,"tests/fixtures/parity/rt082")
for(sub in c("inputs","expected/r","expected/contract","metadata")) dir.create(file.path(out,sub),recursive=TRUE,showWarnings=FALSE)
sha <- function(p) digest::digest(file=p,algo="sha256")
write17 <- function(d,path) {
 for(j in seq_along(d)) if(is.numeric(d[[j]])) d[[j]] <- ifelse(is.na(d[[j]]),"",sprintf("%.17g",d[[j]]))
 write.csv(d,file.path(out,path),row.names=FALSE,quote=TRUE,na="")
 stopifnot(nrow(read.csv(file.path(out,path)))==nrow(d))
}
x <- c(2,-3,-2,5,8,3,2,0,-6,6,8,-4,-6,-6)
z <- c(-7,-4,-6,3,2,-5,-3,2,3,4,6,5,-5,5)
X <- cbind(1,x,x+z*2^-25); n<-nrow(X)
d <- expand.grid(id=seq_len(2*n),t=1:2);d<-d[order(d$id,d$t),]
d$g<-ifelse(d$id>n,2,0);d$a<-rep(X[,2],each=2,length.out=nrow(d));d$b<-rep(X[,3],each=2,length.out=nrow(d))
d$y<-round((.1*d$id+sin(d$id)/7+(d$t==2)*(.2+(d$g==2)*(1+d$a/10)+cos(d$id)/20))*8192)/8192
 d$w<-1;d$rowid<-seq_len(nrow(d));rownames(d)<-NULL
write17(d,"inputs/panel.csv")
stopifnot(identical(unname(as.matrix(read.csv(file.path(out,"inputs/panel.csv")))) ,unname(as.matrix(d))))
backend_original <- getOption("matprod")
blas <- unname(extSoftVersion()["BLAS"])
results <- influences <- grams <- list()
run <- function() {
 on.exit(options(matprod=backend_original))
 for(backend in c("default","internal")) {
  options(matprod=backend)
  gram <- crossprod(X*1,X)/(2*n)
  grams[[backend]] <<- data.frame(backend,row=rep(1:3,3),column=rep(1:3,each=3),value=as.vector(gram),rcond=rcond(gram),epsilon=.Machine$double.eps)
  for(panel in c(TRUE,FALSE)) for(weighted in c(FALSE,TRUE)) for(fast in c(TRUE,FALSE)) {
   warnings<-character()
   a<-list(yname="y",tname="t",idname=if(panel)"id" else"rowid",gname="g",data=d,xformla=~a+b,panel=panel,control_group="nevertreated",est_method="reg",base_period="varying",bstrap=FALSE,cband=FALSE,faster_mode=fast)
   if(weighted)a$weightsname<-"w"
   f<-tryCatch(withCallingHandlers(do.call(did::att_gt,a),warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")}),error=conditionMessage)
   tag<-paste(backend,if(panel)"panel" else"rc",as.integer(weighted),as.integer(fast),sep="_")
   bad<-is.character(f)
   results[[tag]] <<- data.frame(scenario=tag,backend,route=if(panel)"panel" else"rc",weighted=as.integer(weighted),faster=as.integer(fast),att=if(bad)NA_real_ else f$att[1],se=if(bad)NA_real_ else f$se[1],missing_att=as.integer(bad || is.na(f$att[1])),error=if(bad)f else"",warnings=paste(warnings,collapse=" | "),blas)
   if(!bad){inf<-as.matrix(f$inffunc);influences[[tag]]<<-data.frame(scenario=tag,unit=seq_len(nrow(inf)),value=inf[,1])}
  }
 }
}
run()
write17(do.call(rbind,results),"expected/r/results.csv")
write17(do.call(rbind,influences),"expected/r/inffunc.csv")
write17(do.call(rbind,grams),"expected/r/grams.csv")
div <- data.frame(divergence_id="RT082-DIV001",source_tests="did weighted control-Gram conditioning at machine epsilon",reason="Matrix-product backend rounding can put the same nearly collinear design on opposite sides of the existing machine-epsilon conditioning guard. Preserve csdid's visible conservative missing cell; do not widen the guard or return a backend-selected finite estimate.",accepted_behavior="Every Stata panel/RC, auto/nofast, omitted/explicit-unit-weight call warns by group and period and returns missing ATT/SE/IF. The actual R default/internal backend estimates and warnings are recorded separately, without assuming every BLAS accepts.")
write.csv(div,file.path(out,"expected/contract/approved-divergence.csv"),row.names=FALSE)
jsonlite::write_json(div,file.path(out,"expected/contract/approved-divergence.json"),dataframe="rows",pretty=TRUE,auto_unbox=TRUE)
paths <- c("expected/r/results.csv","expected/r/inffunc.csv","expected/r/grams.csv","expected/contract/approved-divergence.csv","expected/contract/approved-divergence.json")
manifest <- list(matrix_id="RT082",fixture_family="r-conditioning-backend-boundary",normative_source="did 2.5.1.904 utility_functions.R rcond_check_fail; backend-dependent conditioning cutoff",source_commit="48863b646e657f2aaa5cc9e9d2e7b9d764a6a44e",decision_refs=character(),tolerance_ids="EXACT",inputs=list(list(path="inputs/panel.csv",sha256=sha(file.path(out,"inputs/panel.csv")),rows=nrow(d),columns=ncol(d))),generators=list(list(runtime="R",command="Rscript tools/parity/generators/rt082/generate.R",path="tools/parity/generators/rt082/generate.R",sha256=sha(script_path))),runtimes=list(list(name="R",version=as.character(getRversion()),package_versions=list(did=as.character(packageVersion("did")),DRDID=as.character(packageVersion("DRDID")),fastglm=as.character(packageVersion("fastglm"))),BLAS=blas)),rng=NULL,expected_outputs=lapply(paths,function(p)list(path=p,schema=if(grepl("contract",p))"approved-divergence" else"keyed-reference",sha256=sha(file.path(out,p)))),comparison_plan=list(list(actual="Visible Stata conditioning refusal, missing ATT/SE/IF, and genuine R backend results",expected=paths,tolerance_id="EXACT")),approved_divergence=list(status="approved-divergence",path="expected/contract/approved-divergence.csv"),scope_note="One exact-roundtripping 28-unit/two-period regression design at the existing reciprocal-condition-number cutoff; 16 genuine R fits cross panel/RC, omitted/unit weights, fast/slow, default/internal matrix products. Default BLAS identity and its observed verdict are recorded, not assumed. No tolerance or estimator is changed.")
jsonlite::write_json(manifest,file.path(out,"metadata/manifest.json"),pretty=TRUE,auto_unbox=TRUE,null="null")
cat("RT082: 16 backend-specific R fits; visible conditioning-refusal contract\n")
