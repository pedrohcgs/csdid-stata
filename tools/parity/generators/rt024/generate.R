# RT024: R oracle for the estimable robustness-guard designs. Several inputs
# exist to trigger refusals (duplicate rows, negative weights); those stay
# behavioral. The ones that estimate are pinned here.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/rt024/inputs"; rows <- list()
add <- function(tag,file,...) {
  d <- read.csv(file.path(IN,file)); names(d)<-tolower(names(d))
  r <- tryCatch(q(att_gt(yname="y",tname="period",idname="id",gname="g",xformla=~x,
                         data=d,est_method="dr",bstrap=FALSE,cband=FALSE,...)),
                error=function(e) NULL)
  if (is.null(r)) { cat("  skip",tag,"\n"); return(invisible()) }
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
}
add("positive_weights","positive-weights.csv", weightsname="wgt")
add("fractional_unbalanced","fractional-unbalanced.csv", allow_unbalanced_panel=TRUE)
out <- do.call(rbind, rows)
write.csv(out,"tests/fixtures/parity/rt024/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("RT024 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
