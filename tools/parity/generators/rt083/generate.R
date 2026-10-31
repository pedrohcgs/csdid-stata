#!/usr/bin/env Rscript
# RT083: sampling-weight units cannot change aggregation ratio derivatives.
farg <- grep("^--file=", commandArgs(FALSE), value=TRUE)
script_path <- if(length(farg)) sub("^--file=", "", farg[1L]) else "tools/parity/generators/rt083/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."),mustWork=TRUE)
out <- file.path(root,"tests/fixtures/parity/rt083")
for(sub in c("inputs","expected/r","expected/contract","metadata")) dir.create(file.path(out,sub),recursive=TRUE,showWarnings=FALSE)
sha <- function(p) digest::digest(file=p,algo="sha256")
inputs <- outputs <- list()
write17 <- function(z,path,input=FALSE,schema="rt083") {
  z <- as.data.frame(z); dimz <- dim(z)
  quoted <- which(vapply(z,is.character,logical(1)))
  for(j in seq_along(z)) if(is.numeric(z[[j]])) z[[j]] <- ifelse(is.na(z[[j]]),"",sprintf("%.17g",z[[j]]))
  write.csv(z,file.path(out,path),row.names=FALSE,quote=quoted,na="")
  check <- read.csv(file.path(out,path),check.names=FALSE,stringsAsFactors=FALSE)
  stopifnot(identical(dim(check),dimz),identical(names(check),names(z)))
  rec <- list(path=path,sha256=sha(file.path(out,path)),rows=dimz[1],columns=dimz[2])
  if(input) inputs[[length(inputs)+1L]] <<- rec else {rec$schema<-schema;outputs[[length(outputs)+1L]]<<-rec}
}
matrix_rows <- function(z,scenario,type="cells",keys=NULL) {
  z <- as.matrix(z);stopifnot(ncol(z)<=20L)
  if(ncol(z)<20L) z<-cbind(z,matrix(NA_real_,nrow(z),20L-ncol(z)))
  colnames(z)<-paste0("v",seq_len(ncol(z)))
  data.frame(scenario,type,unit=if(is.null(keys))seq_len(nrow(z))else keys,z)
}
old_wif <- function(keepers,pg,w,G,group) {
  Spg <- sum(pg[keepers])
  centered <- sapply(keepers,function(k)w*1*BMisc::TorF(G==group[k])-pg[k])
  centered/Spg-rowSums(centered)%*%t(pg[keepers]/Spg^2)
}
scales <- c(1,1e-200,1e-160,1e160,1e200,1e307)
G <- rep(c(0,2,3,4),each=4);w<-c(0,seq_len(15)/10);group<-c(2,2,3,3,4);keep<-c(1,3,4,5)
membership <- outer(G,group[keep],`==`)*1;counts<-rowSums(membership)
total <- sum(w*counts);shares<-colSums(w*membership)/total
derivative <- length(G)*w*(membership-counts%o%shares)/total
h<-1e-5
finite_difference <- t(vapply(seq_along(G),function(i){
  perturb<-function(delta){mass<-w;mass[i]<-mass[i]*(1+delta);colSums(mass*membership)/sum(mass*counts)}
  (perturb(h)-perturb(-h))/(h/(length(G)+h)+h/(length(G)-h))
},numeric(length(keep))))
stopifnot(max(abs(finite_difference-derivative))<1e-8)
write17(data.frame(unit=seq_along(G),G,w),"inputs/ratio-units.csv",TRUE)
write17(data.frame(cell=seq_along(group),group,keep=as.integer(seq_along(group)%in%keep)),"inputs/ratio-cells.csv",TRUE)
colnames(derivative)<-paste0("d",1:4);colnames(finite_difference)<-paste0("fd",1:4)
write17(data.frame(unit=seq_along(G),derivative,finite_difference),"expected/r/ratio-derivatives.csv")
for(i in seq_along(scales)) {
  ww<-w*scales[i];pg<-vapply(group,function(g)mean(ww*(G==g)),0)
  actual<-did:::wif(keep,pg,ww,G,group)
  stopifnot(all(is.finite(actual)),max(abs(actual-derivative))<1e-12)
  write17(data.frame(unit=seq_along(G),actual),sprintf("expected/r/ratio-%d.csv",i))
}
ordinary_G<-rep(c(0,2,3),4);ordinary_group<-c(2,2,3)
write17(data.frame(unit=seq_along(ordinary_G),G=ordinary_G,w=seq_along(ordinary_G)),"inputs/ordinary-units.csv",TRUE)
for(i in seq_along(c(1e-100,1,1e100))) {
  ww<-seq_along(ordinary_G)*c(1e-100,1,1e100)[i]
  pg<-vapply(ordinary_group,function(g)mean(ww*(ordinary_G==g)),0)
  actual<-did:::wif(1:3,pg,ww,ordinary_G,ordinary_group)
  stopifnot(identical(actual,old_wif(1:3,pg,ww,ordinary_G,ordinary_group)))
  write17(data.frame(unit=seq_along(ordinary_G),actual),sprintf("expected/r/ordinary-%d.csv",i))
}
for(i in 1:3) {
  pg<-list(c(0,0,0),c(Inf,1,1),c(-1,-1,2))[[i]]
  actual<-did:::wif(1:3,pg,rep(1,length(ordinary_G)),ordinary_G,ordinary_group)
  stopifnot(identical(actual,old_wif(1:3,pg,rep(1,length(ordinary_G)),ordinary_G,ordinary_group)))
  actual[!is.finite(actual)]<-NA_real_
  write17(data.frame(unit=seq_along(ordinary_G),actual),sprintf("expected/r/invalid-%d.csv",i))
}
overflow_G<-rep(c(0,2,3),each=8);overflow_group<-rep(c(2,3),40)
overflow_pg<-rep(1/3,80)
stopifnot(is.infinite(sum(overflow_pg*1e307)))
overflow<-did:::wif(1:80,overflow_pg*1e307,rep(1e307,24),overflow_G,overflow_group)
stopifnot(all(is.finite(overflow)),max(abs(overflow-did:::wif(1:80,overflow_pg,rep(1,24),overflow_G,overflow_group)))<1e-12)
write17(data.frame(unit=seq_along(overflow_G),G=overflow_G),"inputs/overflow-units.csv",TRUE)
write17(data.frame(unit=seq_along(overflow_G),overflow),"expected/r/repeated-mass-overflow.csv")

set.seed(20261027)
n<-160L
units<-data.frame(id=seq_len(n),g=rep(c(0,2,3,4),each=n/4),x=rnorm(n),a=rnorm(n),w=.5+(seq_len(n)%%7)/10)
panel<-merge(units,data.frame(time=1:4))
panel$y<-panel$a+.2*panel$time+.1*panel$x*panel$time+
  (panel$g>0 & panel$time>=panel$g)*(.5+.2*panel$g)*(panel$time-panel$g+1)+.1*rnorm(nrow(panel))
panel<-panel[order(panel$id,panel$time),c("id","time","g","x","w","y")];rownames(panel)<-NULL
rc<-panel;rc$id<-seq_len(nrow(rc))
write17(panel,"inputs/panel.csv",TRUE);write17(rc,"inputs/rc.csv",TRUE)
unbalanced<-subset(panel,!(id%%7==0 & time==2))
unbalanced$w<-unbalanced$w*(1+.05*unbalanced$time+.03*(unbalanced$id%%3))
write17(unbalanced,"inputs/unbalanced.csv",TRUE)
data<-list(panel=panel,rc=rc,unbalanced=unbalanced)
for(route in names(data)) {
 tiny<-data[[route]];tiny$w<-tiny$w*1e-320
 write17(tiny,paste0("inputs/",route,"-subnormal.csv"),TRUE)
}
public_scales<-c(scales,1e-320)
specs<-expand.grid(route=c("panel","rc"),method=c("dr","ipw","reg"),bootstrap=c(0L,1L),scale=public_scales,KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE)
specs<-rbind(specs,data.frame(route="unbalanced",method="reg",bootstrap=0L,scale=c(1,1e-320)))
specs$subnormal<-as.integer(specs$scale<.Machine$double.xmin)
specs$scenario<-sprintf("s%03d",seq_len(nrow(specs)))
write17(specs,"inputs/scenarios.csv",TRUE)
cells<-ifs<-aggs<-aggifs<-criticals<-diagnostics<-list()
for(i in seq_len(nrow(specs))) {
 s<-specs[i,];d<-data[[s$route]]
 if(s$subnormal)d<-read.csv(file.path(out,paste0("inputs/",s$route,"-subnormal.csv")))else d$w<-d$w*s$scale
 a<-list(yname="y",tname="time",idname="id",gname="g",data=d,panel=s$route!="rc",xformla=~x,
   weightsname="w",est_method=s$method,control_group="notyettreated",base_period="universal",
   bstrap=as.logical(s$bootstrap),cband=as.logical(s$bootstrap),biters=99L)
 if(s$route=="unbalanced") {a$allow_unbalanced_panel<-TRUE;a$fix_weights<-"varying"}
 set.seed(20261029)
 f<-suppressWarnings(suppressMessages(do.call(did::att_gt,a)))
 # The upstream regression crosses both source implementations. Row identities
 # align the full influence functions instead of assuming their storage order.
 rng_after_fit<-.Random.seed
 a$faster_mode<-FALSE;a$bstrap<-FALSE;a$cband<-FALSE
 slow<-suppressWarnings(suppressMessages(do.call(did::att_gt,a)))
 stopifnot(max(abs(f$att-slow$att),na.rm=TRUE)<1e-9)
 if(!s$bootstrap)stopifnot(max(abs(f$se-slow$se),na.rm=TRUE)<1e-9)
 keys<-sort(unique(d$id));ord<-match(as.character(keys),rownames(f$inffunc));sloword<-match(as.character(keys),rownames(slow$inffunc))
 stopifnot(!anyNA(ord),!anyNA(sloword),max(abs(as.matrix(f$inffunc)[ord,]-as.matrix(slow$inffunc)[sloword,]),na.rm=TRUE)<1e-9)
 cells[[i]]<-data.frame(scenario=s$scenario,group=f$group,time=f$t,att=f$att,se=f$se)
 ifs[[i]]<-matrix_rows(as.matrix(f$inffunc)[ord,,drop=FALSE],s$scenario,keys=keys)
 diagnostics[[i]]<-data.frame(scenario=s$scenario,crit=f$c,wald=if(is.null(f$W))NA_real_ else as.numeric(f$W),pvalue=if(is.null(f$Wpval))NA_real_ else f$Wpval)
 # The second reference fit must not advance the stream chained to f.
 .Random.seed<-rng_after_fit
 for(type in c("dynamic","group","calendar","simple")) {
  ag<-suppressWarnings(did::aggte(f,type=type,cband=as.logical(s$bootstrap)))
  if(type=="simple") {tab<-matrix(c(NA_real_,ag$overall.att,ag$overall.se,ag$overall.att,ag$overall.se),1);ai<-cbind(ag$inf.function$simple.att,ag$inf.function$simple.att);crit<-qnorm(.975)}
  else {tab<-cbind(ag$egt,ag$att.egt,ag$se.egt,ag$overall.att,ag$overall.se);ai<-switch(type,dynamic=cbind(ag$inf.function$dynamic.inf.func.e,ag$inf.function$dynamic.inf.func),group=cbind(ag$inf.function$selective.inf.func.g,ag$inf.function$selective.inf.func),calendar=cbind(ag$inf.function$calendar.inf.func.t,ag$inf.function$calendar.inf.func));crit<-ag$crit.val.egt}
  stopifnot(is.finite(ag$overall.se),ag$overall.se>0)
  aggs[[length(aggs)+1L]]<-matrix_rows(tab,s$scenario,type)
  aggifs[[length(aggifs)+1L]]<-matrix_rows(as.matrix(ai)[ord,,drop=FALSE],s$scenario,type,keys)
  criticals[[length(criticals)+1L]]<-data.frame(scenario=s$scenario,type,crit)
 }
}
for(name in c("cells","ifs","aggs","aggifs","criticals","diagnostics"))write17(do.call(rbind,get(name)),paste0("expected/r/",name,".csv"))
# Forty-three selected post-treatment cells repeat cohort masses until their
# sum exceeds Stata's finite numeric range, although each mass is finite.
repeated<-expand.grid(time=1:40,id=1:120)
repeated$g<-ifelse(repeated$id<=40,0,ifelse(repeated$id<=80,2,3));repeated$basew<-1
repeated$y<-.01*repeated$time+sin(repeated$id*.7)+.1*(repeated$g>0 & repeated$time>=repeated$g)+.01*cos(repeated$id*repeated$time)
write17(repeated,"inputs/repeated-public.csv",TRUE)
repeated_cells<-repeated_agg<-repeated_if<-list()
for(periods in c(23L,40L))for(scale in c(1,1e307)) {
 dd<-subset(repeated,time<=periods);dd$w<-dd$basew*scale;huge<-as.integer(scale>1)
 a<-list(yname="y",tname="time",idname="id",gname="g",data=dd,weightsname="w",est_method="reg",
  control_group="nevertreated",base_period="universal",bstrap=FALSE,cband=FALSE)
 f<-suppressWarnings(suppressMessages(do.call(did::att_gt,a)))
 ag<-did::aggte(f,type="simple",bstrap=FALSE,cband=FALSE)
 if(periods==23L) {
  a$faster_mode<-FALSE
  slow<-suppressWarnings(suppressMessages(do.call(did::att_gt,a)))
  slow_ag<-did::aggte(slow,type="simple",bstrap=FALSE,cband=FALSE)
  stopifnot(abs(ag$overall.att-slow_ag$overall.att)<1e-12,abs(ag$overall.se-slow_ag$overall.se)<1e-12)
 }
 stopifnot(is.finite(ag$overall.se),ag$overall.se>0)
 repeated_cells[[length(repeated_cells)+1L]]<-data.frame(periods,huge,group=f$group,time=f$t,att=f$att,se=f$se)
 repeated_agg[[length(repeated_agg)+1L]]<-data.frame(periods,huge,att=ag$overall.att,se=ag$overall.se)
 ord<-match(as.character(1:120),rownames(f$inffunc));stopifnot(!anyNA(ord))
 repeated_if[[length(repeated_if)+1L]]<-data.frame(periods,huge,unit=1:120,value=ag$inf.function$simple.att[ord])
}
write17(do.call(rbind,repeated_cells),"expected/r/repeated-public-cells.csv")
write17(do.call(rbind,repeated_agg),"expected/r/repeated-public-aggregate.csv")
write17(do.call(rbind,repeated_if),"expected/r/repeated-public-inffunc.csv")
upstream<-Sys.getenv("CSDID_DID_UPSTREAM");sf<-"tests/testthat/test-aggregation-weight-scale.R"
titles<-c("weight influence functions match ratio derivatives at extreme scales","weight influence functions preserve ordinary arithmetic and invalid inputs","weight influence functions handle overflow of repeated selected masses","all public aggregations preserve full influence functions across weight scales")
map<-data.frame(source_file=sf,source_sha256=sha(file.path(upstream,sf)),source_test=titles,
 mapped_scenario="tests/stata/r/test-aggregation-weight-scale.do",
 assertion_family=c("RT083 compares complete weight-ratio influence functions and independent finite-difference derivatives at six weight scales.","RT083 preserves ordinary-scale arithmetic and all-missing invalid-input results.","RT083 checks complete finite influence matrices when repeated cohort masses overflow their raw sum.","RT083 compares full cell and aggregate influence functions, estimates, analytical/seeded-bootstrap inference and analytical saved-RIF roundtrips for panel/RC and all three estimators."),coverage_status="mapped",divergence_id="")
write.csv(map,file.path(out,"expected/contract/upstream-test-map.csv"),row.names=FALSE)
jsonlite::write_json(map,file.path(out,"expected/contract/upstream-test-map.json"),pretty=TRUE,dataframe="rows",auto_unbox=TRUE)
for(path in c("expected/contract/upstream-test-map.csv","expected/contract/upstream-test-map.json"))outputs[[length(outputs)+1L]]<-list(path=path,schema="source-test-map",sha256=sha(file.path(out,path)))
reference<-jsonlite::read_json(file.path(root,"inst/spec/r-oracle-reference.json"))
manifest<-list(matrix_id="RT083",fixture_family="r-aggregation-weight-scale",normative_source="did wif.R; PR280 test-aggregation-weight-scale.R",source_commit=reference$did_commit,decision_refs=list(),tolerance_ids=c("EXACT","TOL001","TOL002","TOL003"),inputs=inputs,
 generators=list(list(runtime="R",command="Rscript tools/parity/generators/rt083/generate.R",path="tools/parity/generators/rt083/generate.R",sha256=sha(script_path))),
 runtimes=list(list(name="R",version=as.character(getRversion()),package_versions=list(did=as.character(packageVersion("did")),DRDID=as.character(packageVersion("DRDID"))))),rng=list(kind="Mersenne-Twister",seed=20261029,biters=99),expected_outputs=outputs,
 comparison_plan=list(list(actual="Full weight/cell/aggregate IFs, ATT/SE, critical values and pretests on direct and saved analytical routes and direct seeded bootstrap",expected="expected/r",tolerance_id="TOL002",key_columns=c("scenario","type","unit"))),approved_divergence=NULL,
 scope_note="All four PR280 source tests inherited. Seven public scales include 1e-320, 1e-200, 1e-160, 1, 1e160, 1e200 and 1e307. 84 public fits cross panel/RC, dr/ipw/reg and analytical/bootstrap; two additional unbalanced varying-weight REG fits guard subnormal per-unit means. Every such fit compares all four aggregation types and complete influence functions. Subnormal raw weights are serialized once and supplied directly to both consumers. A test helper reconstructs balanced legacy raw-unit weight fields before the unchanged production writer signs them, separately exercising valid older saved-RIF files. This does not recover row-level precision absent from older unbalanced artifacts. Two separate 120-unit panels with 23/40 periods compare direct and saved simple aggregation at scales 1/1e307 when 43/77 selected cohort masses overflow the raw sum. The 23-period reference agrees in both R implementations; the 40-period reference follows R default fast mode because its slow mode overflows raw cohort sums. Saved-RIF aggregation retains its documented analytical inference. Direct ratio derivatives, ordinary arithmetic, invalid masses, and 80 repeated selected masses cover the numerical fallback boundaries.")
jsonlite::write_json(manifest,file.path(out,"metadata/manifest.json"),pretty=TRUE,auto_unbox=TRUE,null="null")
cat("RT083: 90 public configurations, all four aggregations, complete influence functions and four inherited source blocks\n")
