#!/usr/bin/env Rscript
# RT084/D029: genuine raw R and distinctly supplied period-normalized R data.
farg<-grep("^--file=",commandArgs(FALSE),value=TRUE)
script_path<-if(length(farg))sub("^--file=","",farg[1L])else"tools/parity/generators/rt084/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root<-normalizePath(file.path(dirname(script_path),"../../../.."),mustWork=TRUE)
fx<-file.path(root,"tests/fixtures/parity/rt084")
for(sub in c("expected/r/raw-input","expected/r/period-normalized-input-diagnostic","expected/contract/stata","metadata"))dir.create(file.path(fx,sub),recursive=TRUE,showWarnings=FALSE)
sha<-function(path)digest::digest(file=path,algo="sha256")
column_hash<-function(d)vapply(d,function(z)digest::digest(writeBin(as.double(z),raw(),size=8,endian="little"),algo="sha256",serialize=FALSE),"")
lock<-jsonlite::read_json(file.path(fx,"inputs/input-lock.json"),simplifyVector=TRUE)
outputs<-list()
write17<-function(z,name){
 z<-as.data.frame(z);quoted<-which(vapply(z,is.character,logical(1)))
 for(j in seq_along(z))if(is.numeric(z[[j]]))z[[j]]<-ifelse(is.na(z[[j]]),"",sprintf("%.17g",z[[j]]))
 path<-file.path(fx,name);dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
 write.csv(z,path,row.names=FALSE,quote=quoted,na="")
 outputs[[length(outputs)+1L]]<<-list(path=name,sha256=sha(path),rows=nrow(z),columns=ncol(z),schema=if(startsWith(name,"expected/contract"))"approved-Stata-contract"else"genuine-R-output")
}
write_json<-function(z,name){
 path<-file.path(fx,name);dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
 jsonlite::write_json(z,path,pretty=TRUE,auto_unbox=TRUE,na="null",null="null",digits=NA)
 outputs[[length(outputs)+1L]]<<-list(path=name,sha256=sha(path),schema=if(startsWith(name,"expected/contract"))"approved-Stata-contract"else"R-reference-provenance")
}
wide<-function(z,scenario,reference,type="cells",unit=seq_len(nrow(z))){
 z<-as.matrix(z);stopifnot(ncol(z)<=20L)
 if(ncol(z)<20L)z<-cbind(z,matrix(NA_real_,nrow(z),20L-ncol(z)))
 colnames(z)<-paste0("v",1:20);data.frame(scenario,reference,type,unit,z)
}
call_record<-function(expr){
 warnings<-messages<-character()
 value<-withCallingHandlers(expr,warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")},message=function(m){messages<<-c(messages,conditionMessage(m));invokeRestart("muffleMessage")})
 list(value=value,warnings=warnings,messages=messages)
}
raw_data<-normalized_data<-factors<-list()
for(case in names(lock$cases)){
 input<-lock$cases[[case]];path<-file.path(fx,input$file);stopifnot(sha(path)==input$sha256)
 d<-foreign::read.dta(path,convert.factors=FALSE)
 stopifnot(nrow(d)==640L,identical(names(d),input$columns),!anyDuplicated(d[c("id","time")]),identical(unname(column_hash(d)),unname(input$column_double_sha256)))
 if(case=="first_subnormal")stopifnot(all(d$w[d$time==1L]>0),all(d$w[d$time==1L]<.Machine$double.xmin),all(d$w[d$time>1L]>=.5))
 raw_data[[case]]<-d;n<-d;divisors<-list()
 for(period in sort(unique(d$time))){
  keep<-d$time==period;first<-max(d$w[keep]);relative<-d$w[keep]/first;second<-mean(relative)
  stopifnot(is.finite(first),first>0,is.finite(second),second>0)
  n$w[keep]<-relative/second
  divisors[[length(divisors)+1L]]<-list(period=period,first_divisor_17g=sprintf("%.17g",first),first_divisor_hex=sprintf("%a",first),second_divisor_17g=sprintf("%.17g",second),second_divisor_hex=sprintf("%a",second),normalized_mean=mean(n$w[keep]))
 }
 stopifnot(identical(column_hash(d)[names(d)!="w"],column_hash(n)[names(n)!="w"]))
 normalized_data[[case]]<-n;factors[[case]]<-divisors
 write17(n,paste0("expected/r/period-normalized-input-diagnostic/DISTINCT-input-",case,".csv"))
}
specs<-list()
for(bootstrap in 0:1)for(case in c("ordinary","first_subnormal"))for(method in c("reg","dr","ipw"))specs[[length(specs)+1L]]<-data.frame(scenario=paste(case,method,bootstrap,sep="-"),case,method,bootstrap)
specs<-do.call(rbind,specs);write17(specs,"expected/contract/stata/scenarios.csv")
tables<-list();calls<-list()
for(reference in c("raw-input","period-normalized-input-diagnostic")){
 cells<-ifs<-aggs<-aggifs<-criticals<-diagnostics<-list();calls[[reference]]<-list()
 for(i in seq_len(nrow(specs))){
  s<-specs[i,];d<-if(reference=="raw-input")raw_data[[s$case]]else normalized_data[[s$case]]
  set.seed(20261030)
  fc<-call_record(did::att_gt(yname="y",tname="time",idname="id",gname="g",data=d,xformla=~x,weightsname="w",est_method=s$method,panel=TRUE,allow_unbalanced_panel=FALSE,fix_weights=NULL,control_group="notyettreated",base_period="universal",bstrap=as.logical(s$bootstrap),cband=as.logical(s$bootstrap),biters=99L,faster_mode=TRUE))
  f<-fc$value;keys<-sort(unique(d$id));ord<-match(as.character(keys),rownames(f$inffunc));stopifnot(!anyNA(ord))
  cells[[i]]<-data.frame(scenario=s$scenario,reference,group=f$group,time=f$t,att=f$att,se=f$se)
  ifs[[i]]<-wide(as.matrix(f$inffunc)[ord,,drop=FALSE],s$scenario,reference,unit=keys)
  diagnostics[[i]]<-data.frame(scenario=s$scenario,reference,crit=f$c,wald=if(is.null(f$W))NA_real_ else as.numeric(f$W),pvalue=if(is.null(f$Wpval))NA_real_ else f$Wpval)
  calls[[reference]][[s$scenario]]<-list(supplied_input_is_original_raw=reference=="raw-input",original_raw_sha256=sha(file.path(fx,lock$cases[[s$case]]$file)),original_raw_column_double_sha256=column_hash(raw_data[[s$case]]),supplied_input_column_double_sha256=column_hash(d),normalization_factors=if(reference=="raw-input")NULL else factors[[s$case]],warnings=fc$warnings,messages=fc$messages,aggregations=list())
  for(type in c("dynamic","group","calendar","simple")){
   ac<-call_record(did::aggte(f,type=type,cband=as.logical(s$bootstrap)));a<-ac$value
   if(type=="simple"){
    tab<-matrix(c(NA_real_,a$overall.att,a$overall.se,a$overall.att,a$overall.se),1L)
    ai<-cbind(a$inf.function$simple.att,a$inf.function$simple.att);crit<-qnorm(.975)
   }else{
    tab<-cbind(a$egt,a$att.egt,a$se.egt,a$overall.att,a$overall.se)
    ai<-switch(type,dynamic=cbind(a$inf.function$dynamic.inf.func.e,a$inf.function$dynamic.inf.func),group=cbind(a$inf.function$selective.inf.func.g,a$inf.function$selective.inf.func),calendar=cbind(a$inf.function$calendar.inf.func.t,a$inf.function$calendar.inf.func));crit<-a$crit.val.egt
   }
   aggs[[length(aggs)+1L]]<-wide(tab,s$scenario,reference,type)
   aggifs[[length(aggifs)+1L]]<-wide(as.matrix(ai)[ord,,drop=FALSE],s$scenario,reference,type,keys)
   criticals[[length(criticals)+1L]]<-data.frame(scenario=s$scenario,reference,type,crit)
   calls[[reference]][[s$scenario]]$aggregations[[type]]<-list(warnings=ac$warnings,messages=ac$messages)
  }
  cat("RT084 R",reference,s$scenario,"complete\n")
 }
 tables[[reference]]<-lapply(c("cells","ifs","aggs","aggifs","criticals","diagnostics"),function(name)do.call(rbind,get(name)))
 names(tables[[reference]])<-c("cells","ifs","aggs","aggifs","criticals","diagnostics")
 for(name in names(tables[[reference]]))write17(tables[[reference]][[name]],paste0("expected/r/",reference,"/",name,".csv"))
 write_json(list(reference_label=reference,supplied_input_is_original_raw=reference=="raw-input",input_transformation=if(reference=="raw-input")"none"else"DISTINCT INPUT: within each period w/max(w), then /mean(w/max(w))",options=list(panel=TRUE,allow_unbalanced_panel=FALSE,fix_weights=NULL,control_group="notyettreated",base_period="universal",faster_mode=TRUE,xformla="~x"),calls=calls[[reference]]),paste0("expected/r/",reference,"/reference-metadata.json"))
}
# Only the explicitly approved boundary uses the distinct-input reference.
for(name in names(tables[["raw-input"]])){
 a<-tables[["raw-input"]][[name]];b<-tables[["period-normalized-input-diagnostic"]][[name]]
 chosen<-rbind(a[startsWith(a$scenario,"ordinary-"),],b[startsWith(b$scenario,"first_subnormal-"),])
 write17(chosen,paste0("expected/contract/stata/",name,".csv"))
}
div<-data.frame(divergence_id="RT084-DIV001",decision_ref="D029",status="approved-divergence",owner_decision="Stable relative-weight computation at the balanced-panel default single-period-weight subnormal boundary",scope="Balanced panel with the default single-period weight vector: preserve stable relative weight masses when R global normalization leaves selected period weights subnormal. Genuine raw R is retained separately; the explicit DISTINCT per-period-normalized R input supports the stable Stata contract. No RC or unbalanced-varying generalization.")
write17(div,"expected/contract/approved-divergence.csv");write_json(div,"expected/contract/approved-divergence.json")
notice_specs<-read.csv(file.path(fx,"inputs/notice-specs.csv"),stringsAsFactors=FALSE);notice_rows<-notice_calls<-list()
for(notice_case in notice_specs$notice_case){
 d<-raw_data$ordinary
 if(notice_case=="range_eps")d$w<-c(1,1+1e-8,1-1e-8,1)[match(d$time,1:4)]
 if(notice_case%in%c("balanced_away","first_treated"))d$w[d$id==1 & d$time==2]<-2*d$w[d$id==1 & d$time==2]
 if(notice_case=="balanced_away")d<-d[!(d$id==1 & d$time==4),]
 if(notice_case=="first_treated")d$g[d$id==1]<-1
 call<-call_record(did::att_gt(yname="y",tname="time",idname="id",gname="g",data=d,xformla=~x,weightsname="w",est_method="reg",panel=TRUE,allow_unbalanced_panel=FALSE,fix_weights=NULL,control_group="notyettreated",base_period="universal",bstrap=FALSE,cband=FALSE,faster_mode=TRUE))
 text<-c(call$warnings,call$messages);notice<-text[grepl("Time-varying weights detected.",text,fixed=TRUE)];stopifnot(length(notice)<=1L)
 body<-if(length(notice))sub(" Use the 'fix_weights'.*$","",gsub("[[:space:]]+"," ",trimws(notice)))else""
 notice_rows[[notice_case]]<-data.frame(notice_case,emit=as.integer(length(notice)),body)
 notice_calls[[notice_case]]<-list(input_transformation=notice_specs$transformation[match(notice_case,notice_specs$notice_case)],column_double_sha256=column_hash(d),warnings=call$warnings,messages=call$messages)
}
stopifnot(notice_rows$constant$emit==0L,all(vapply(notice_rows[-1],function(x)x$emit,integer(1))==1L))
write17(do.call(rbind,notice_rows),"expected/r/notice-cases.csv");write_json(notice_calls,"expected/r/notice-metadata.json")
reference<-jsonlite::read_json(file.path(root,"inst/spec/r-oracle-reference.json"))
inputs<-lapply(names(lock$cases),function(case){z<-lock$cases[[case]];list(case=case,path=z$file,sha256=z$sha256,rows=z$rows,columns=length(z$columns),column_double_sha256=z$column_double_sha256)})
for(name in c("inputs/input-lock.json","inputs/notice-specs.csv"))inputs[[length(inputs)+1L]]<-list(path=name,sha256=sha(file.path(fx,name)),schema="read-only-input-lock-or-witness")
manifest<-list(matrix_id="RT084",fixture_family="approved-stable-period-weight-scale-boundary",normative_source="Genuine did raw-input results and explicitly DISTINCT normalized-input diagnostic; D029 supplies only the approved Stata boundary contract.",source_commit=reference$did_commit,decision_refs="D029",tolerance_ids=c("EXACT","TOL001","TOL002"),inputs=inputs,generators=list(list(runtime="R",command="Rscript tools/parity/generators/rt084/generate.R",path="tools/parity/generators/rt084/generate.R",sha256=sha(script_path))),runtimes=list(list(name="R",version=as.character(getRversion()),package_versions=list(did=as.character(packageVersion("did")),DRDID=as.character(packageVersion("DRDID"))))),rng=list(kind="Mersenne-Twister",seed=20261030,biters=99,bootstrap_draws_exported=FALSE,bootstrap_comparison_scope="Fixed shared stream summaries: reported cell and aggregation SEs, critical values, Wald diagnostics and full influence functions; raw bootstrap draws are not exported or certified."),expected_outputs=outputs,comparison_plan=list(list(actual="Ordinary controls against raw R; approved balanced boundary against clearly distinct-input R contract: cell ATT/SE, all four aggregation point estimates/SE, critical values, Wald and p-value diagnostics, including actual analytical saved-RIF and fixed-shared-stream bootstrap summaries",expected="expected/contract/stata",tolerance_id="TOL001"),list(actual="Complete keyed cell and all-four-aggregation influence-function matrices",expected="expected/contract/stata",tolerance_id="TOL002"),list(actual="Full-screened normalized per-unit-range warning count and body",expected="expected/r/notice-cases.csv",tolerance_id="EXACT")),approved_divergence=list(status="approved-divergence",id="RT084-DIV001",decision_ref="D029",path="expected/contract/approved-divergence.csv"),scope_note="Original two locked Stata12 DTA inputs. Separate raw R and DISTINCT per-period-normalized R values are never substituted or relabeled. Twelve configurations cross REG/DR/IPW, ordinary/boundary and analytical/bootstrap99; runtime coverage is claimed only after actual Stata reader execution. Notice cases are not covered by the numerical exception.")
jsonlite::write_json(manifest,file.path(fx,"metadata/manifest.json"),pretty=TRUE,auto_unbox=TRUE,null="null")
cat("RT084 complete: raw references retained; D029 stable contract and separate R notices\n")
