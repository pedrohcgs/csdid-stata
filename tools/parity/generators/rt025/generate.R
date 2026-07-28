# RT025: R oracle for the slow-path/precompute scenarios. The inherited test
# compares the two internal paths to each other, which both being wrong also
# satisfies, and checks row-order invariance.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/rt025/inputs"; rows <- list()
add <- function(tag,file,xf,panel,...) {
  d <- read.csv(file.path(IN,file)); names(d)<-tolower(names(d))
  args <- list(yname="y", tname="time", gname="g", data=d, bstrap=FALSE, cband=FALSE, ...)
  if (panel) args$idname <- "id" else args$panel <- FALSE
  if (!is.null(xf)) args$xformla <- xf
  r <- tryCatch(q(do.call(att_gt, args)), error=function(e) NULL)
  if (is.null(r)) { cat("  skip",tag,"\n"); return(invisible()) }
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
}
add("rcs_dr",        "input.csv",            ~x1, FALSE, est_method="dr")
add("unbal_dr",      "input-unbalanced.csv", ~x1, TRUE,  est_method="dr", allow_unbalanced_panel=TRUE)
add("panel_reg",     "input.csv",            NULL, TRUE, est_method="reg")
add("shuffled_reg",  "input-shuffled.csv",   NULL, TRUE, est_method="reg")
out <- do.call(rbind, rows)
write.csv(out,"tests/fixtures/parity/rt025/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("RT025 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
