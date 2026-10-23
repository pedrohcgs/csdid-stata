#!/usr/bin/env Rscript
# RT076: strict physical GLM dimensions; square blocks remain estimable.
args <- commandArgs(trailingOnly = FALSE)
farg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(farg)) sub("^--file=", "", farg[1L]) else "tools/parity/generators/rt076/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt076")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(p) digest::digest(file = p, algo = "sha256")
fmt <- function(x) ifelse(is.na(x), "", sprintf("%.17g", x))
H <- cbind(1, rbind(c(-1,-1,-1), c(-1,1,1), c(1,-1,1), c(1,1,-1)))
inputs <- list(); specs <- list(); results <- list(); influences <- list(); warnings <- list()
add_case <- function(mode, block, count, weighting) {
  scenario <- paste(mode, block, count, weighting, sep = "_")
  nblocks <- if (mode == "rc") 4L else 2L
  counts <- rep(24L, nblocks); counts[block] <- count
  b <- rep(seq_len(nblocks), counts)
  j <- sequence(counts)
  X <- H[1L + (j - 1L) %% 4L, , drop = FALSE]
  # Keep the shortened block inside the other arm's covariate hull. The
  # physical k-1/k/k+1 boundary must not also create a separated PS model.
  X[b == block, 2:4] <- X[b == block, 2:4, drop = FALSE] / 2
  D <- if (mode == "rc") as.numeric(b > 2L) else as.numeric(b == 2L)
  post <- if (mode == "rc") as.numeric(b %% 2L == 0L) else rep(1, length(b))
  w <- switch(weighting, unit = rep(1, length(b)), varying = 0.5 + (j %% 5L) / 3,
              zero = 0.5 + (j %% 5L) / 3)
  if (weighting == "zero") w[which(b == block)[1L]] <- 0
  y0 <- 1 + X[,2] / 3 - X[,3] / 5 + sin(seq_along(b) * 1.7) / 7
  dy <- 0.3 + D + X[,4] / 4 + cos(seq_along(b) * 0.7) / 5
  y1 <- y0 + dy
  y <- y0 + post * dy
  z <- data.frame(id = seq_along(b), d = D, post = post, y = y, y0 = y0,
                  y1 = y1, w = w, x1 = X[,2], x2 = X[,3], x3 = X[,4])
  path <- paste0("inputs/", scenario, ".csv")
  zw <- z; for (v in names(z)) zw[[v]] <- fmt(z[[v]])
  write.csv(zw, file.path(out, path), row.names = FALSE, quote = FALSE)
  inputs[[length(inputs)+1L]] <<- list(path = path, sha256 = sha(file.path(out,path)), rows = nrow(z), columns = ncol(z))
  for (method in c("reg", "dr", "ipw")) {
    name <- paste0(if (method == "dr") "drdid" else if (method == "ipw") "std_ipw_did" else "reg_did", "_", if (mode == "rc") "rc" else "panel")
    f <- getExportedValue("DRDID", name)
    a <- tryCatch(suppressWarnings(if (mode == "rc") f(y, post, D, X, w, inffunc = TRUE)
                                  else f(y1, y0, D, X, w, inffunc = TRUE)), error = function(e) conditionMessage(e))
    # csdid kernels also enforce did's outer feasibility checks. A finite
    # standalone DRDID result is not a finite did target after those refuse.
    overlap_fail <- method %in% c("dr", "ipw") && suppressWarnings(did:::overlap_check_fail(X, D, FALSE))
    rank_fail <- !overlap_fail && method %in% c("dr", "reg") && did:::rcond_check_fail(X, D, FALSE)
    if (overlap_fail) a <- "did preliminary overlap condition violated"
    else if (rank_fail) a <- "did preliminary control design is singular"
    error <- if (is.character(a)) a else ""
    good <- !is.character(a) && is.finite(a$ATT) && all(is.finite(a$att.inf.func))
    # did's preliminary pooled-control rcond guard still has priority.
    pooled_pass <- rcond(crossprod(X[D == 0, , drop = FALSE])) >= .Machine$double.eps
    physical <- count < ncol(X) && ((method == "dr" && (mode == "rc" || block == 1L)) || (method == "reg" && (mode == "panel" && block == 1L || mode == "rc" && block <= 2L)))
    status7 <- physical && pooled_pass && !overlap_fail
    specs[[length(specs)+1L]] <<- data.frame(scenario, mode, block, count, weighting, method,
       n = nrow(z), physical = as.integer(status7), good = as.integer(good))
    results[[length(results)+1L]] <<- data.frame(scenario, method, att = fmt(if (good) a$ATT else NA_real_),
       se = fmt(if (good) a$se else NA_real_), error = error)
    if (good) influences[[length(influences)+1L]] <<- data.frame(scenario, method, id = seq_len(nrow(z)), value = fmt(as.vector(a$att.inf.func)))
    # The actual did wrapper is exercised in both routes for every RC shape.
    if (mode == "rc") for (fast in c(FALSE, TRUE)) {
      dd <- data.frame(id = z$id, t = post + 1L, g = 2L * D, y = y, w = w, X[, -1L])
      names(dd)[6:8] <- c("x1", "x2", "x3")
      msgs <- character()
      aa <- tryCatch(withCallingHandlers(did::att_gt(yname="y", tname="t", idname="id", gname="g", data=dd,
          panel=FALSE, weightsname="w", xformla=~x1+x2+x3, control_group="nevertreated", base_period="universal",
          est_method=method, bstrap=FALSE, cband=FALSE, faster_mode=fast), warning=function(e) {
            msgs <<- c(msgs, conditionMessage(e)); invokeRestart("muffleWarning")
          }), error=function(e) conditionMessage(e))
      wanted <- msgs[grepl("fewer observations than covariates", msgs, fixed=TRUE)]
      if (status7) stopifnot(length(wanted)==1L)
      if (length(wanted)) warnings[[length(warnings)+1L]] <<- data.frame(scenario, method, faster_mode=as.integer(fast), message=wanted)
    }
  }
}
for (mode in c("rc", "panel")) for (block in seq_len(if (mode=="rc") 4L else 2L))
  for (count in 3:5) for (weighting in c("unit", "varying", "zero")) add_case(mode, block, count, weighting)
# Total propensity-design dimensions are a separate IPW boundary: did's
# unweighted overlap check precedes DRDID's strict physical-design refusal.
wide_specs <- list(); wide_warnings <- list(); wide_attgt <- list()
for (mode in c("rc", "panel")) for (kind in c("pass", "fail")) for (weighting in c("unit", "varying", "zero")) {
  scenario <- paste("wide", mode, kind, weighting, sep="_")
  if (mode == "rc") {
    z <- data.frame(id=1:8, t=rep(c(1,2,1,2),each=2), g=rep(c(3,3,2,2),each=2), y=1:8)
    xx <- rep(c(-1,1),4)
  } else {
    z <- data.frame(id=rep(1:4,each=2),t=rep(1:2,4),g=rep(c(3,3,2,2),each=2),y=1:8)
    xx <- rep(c(-1,1,-1,1),each=2)
  }
  if (kind == "fail") xx <- as.numeric(z$g == 2)
  for (j in 1:8) z[[paste0("x",j)]] <- j * xx
  z$w <- if (weighting == "unit") rep(1,nrow(z)) else exp(z$id/13)
  if (weighting == "zero") z$w[z$id==1] <- 0
  input <- paste0("inputs/",scenario,".csv")
  zw <- z; for (name in names(z)) zw[[name]] <- fmt(z[[name]])
  write.csv(zw,file.path(out,input),row.names=FALSE,quote=FALSE)
  inputs[[length(inputs)+1L]] <- list(path=input,sha256=sha(file.path(out,input)),rows=nrow(z),columns=ncol(z))
  zz <- if (mode == "rc") z else z[z$t==1,]
  X <- model.matrix(~x1+x2+x3+x4+x5+x6+x7+x8,zz)
  overlap <- suppressWarnings(did:::overlap_check_fail(X,as.numeric(zz$g==2),FALSE))
  stopifnot(identical(overlap,kind=="fail"),nrow(X)<ncol(X))
  wide_specs[[length(wide_specs)+1L]] <- data.frame(scenario,mode,kind,weighting,n=nrow(X),k=ncol(X),want_status=if(overlap)1L else 7L)
  cell_messages <- character()
  for (fast in c(FALSE,TRUE)) {
    msgs <- character()
    a <- withCallingHandlers(did::att_gt(yname="y",tname="t",idname="id",gname="g",data=z,
      panel=mode=="panel",xformla=~x1+x2+x3+x4+x5+x6+x7+x8,weightsname="w",
      control_group="notyettreated",est_method="ipw",base_period="universal",bstrap=FALSE,cband=FALSE,
      faster_mode=fast),warning=function(e){msgs<<-c(msgs,conditionMessage(e));invokeRestart("muffleWarning")})
    msg <- msgs[grepl("overlap condition violated|Error computing internal 2x2",msgs)]
    stopifnot(length(msg)==1L,all(is.na(a$att[a$t==2])))
    if (overlap) stopifnot(grepl("overlap condition violated",msg,fixed=TRUE))
    else stopifnot(grepl("fewer observations than covariates",msg,fixed=TRUE))
    cell_messages <- c(cell_messages,msg)
    wide_warnings[[length(wide_warnings)+1L]] <- data.frame(scenario,faster_mode=as.integer(fast),message=msg)
    wide_attgt[[length(wide_attgt)+1L]] <- data.frame(scenario,faster_mode=as.integer(fast),group=a$group,time=a$t,att=fmt(a$att),se=fmt(a$se))
  }
  stopifnot(identical(cell_messages[1L],cell_messages[2L]))
}
wide_specs <- do.call(rbind,wide_specs)
write.csv(wide_specs,file.path(out,"inputs/wide-scenarios.csv"),row.names=FALSE,quote=FALSE)
inputs[[length(inputs)+1L]] <- list(path="inputs/wide-scenarios.csv",sha256=sha(file.path(out,"inputs/wide-scenarios.csv")),rows=nrow(wide_specs),columns=ncol(wide_specs))
write.csv(do.call(rbind,wide_warnings),file.path(out,"expected/r/wide-warnings.csv"),row.names=FALSE)
write.csv(do.call(rbind,wide_attgt),file.path(out,"expected/r/wide-attgt.csv"),row.names=FALSE,quote=FALSE)

specs <- do.call(rbind,specs); result <- do.call(rbind,results)
write.csv(specs, file.path(out,"inputs/scenarios.csv"), row.names=FALSE, quote=FALSE)
inputs[[length(inputs)+1L]] <- list(path="inputs/scenarios.csv",sha256=sha(file.path(out,"inputs/scenarios.csv")),rows=nrow(specs),columns=ncol(specs))
write.csv(result,file.path(out,"expected/r/fits.csv"),row.names=FALSE,na="")
write.csv(do.call(rbind,influences),file.path(out,"expected/r/inffunc.csv"),row.names=FALSE,quote=FALSE)
write.csv(do.call(rbind,warnings),file.path(out,"expected/r/warnings.csv"),row.names=FALSE)
outputs <- lapply(c("fits.csv","inffunc.csv","warnings.csv","wide-warnings.csv","wide-attgt.csv"),function(n)list(path=paste0("expected/r/",n),schema="rt076",sha256=sha(file.path(out,"expected/r",n))))
manifest <- list(matrix_id="RT076",fixture_family="r-undersized-glm-designs",
 normative_source="DRDID 1.4.0 fastglm_fit.R:19-21; did 2.5.1 compute.att_gt/compute.att_gt2 catch and report estimator errors",
 source_commit="eaac3b49cd225d0d7706c633858555a5f204e21e", decision_refs=list(),tolerance_ids=c("EXACT","TOL001","TOL002"),inputs=inputs,
 generators=list(list(runtime="R",command="Rscript tools/parity/generators/rt076/generate.R",path="tools/parity/generators/rt076/generate.R",sha256=sha(script_path))),
 runtimes=list(list(name="R",version=as.character(getRversion()),package_versions=list(did=as.character(packageVersion("did")),DRDID=as.character(packageVersion("DRDID"))))),rng=NULL,expected_outputs=outputs,
 comparison_plan=list(list(actual="all kernel ATT/SE/influence values or missing refusals after did preliminary feasibility guards",expected="expected/r/fits.csv and inffunc.csv",tolerance_id="TOL002",key_columns=c("scenario","method","id")),
 list(actual="12 wide IPW kernel/public refusals with overlap precedence and exact fast/slow warnings",expected="expected/r/wide-attgt.csv and wide-warnings.csv",tolerance_id="EXACT",key_columns=c("scenario","faster_mode","group","time")),
 list(actual="physical undersize status and exact caught warning",expected="expected/r/warnings.csv",tolerance_id="EXACT",key_columns=c("scenario","method"))),approved_divergence=NULL,
 scope_note="54 designs, 162 low-level method fits with did preliminary feasibility guards: every RC corner and both panel arms at k-1/k/k+1 rows for k=4, unit/nonuniform/one-zero weights. The shortened block has half-scale H4 covariates so the propensity model remains regular; square outcome designs retain full rank. Every RC shape also runs did's fast and slow route. Square designs stay admissible when full rank; zero weights count physically, with effective rank left to existing guards. Twelve total-design IPW cases cross panel/RC, overlap pass/fail and three weight types at n<k=9, matching both public did modes.")
jsonlite::write_json(manifest,file.path(out,"metadata/manifest.json"),pretty=TRUE,auto_unbox=TRUE,null="null")
cat("RT076 written:",nrow(specs),"fits;",sum(specs$physical),"explicit physical refusals;",sum(specs$good),"finite fits;",nrow(wide_specs),"wide IPW refusals.\n")
