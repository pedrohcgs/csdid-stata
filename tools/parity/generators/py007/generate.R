# PY007: R oracle for the Python-map edge cases, across methods where the test
# sweeps them.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/py007/inputs"
rows <- list()
add <- function(tag, file, ...) {
  d <- read.csv(file.path(IN,file)); names(d) <- tolower(names(d))
  r <- tryCatch(q(att_gt(yname="y",tname="period",idname="id",gname="g",data=d,
                         bstrap=FALSE,cband=FALSE,...)), error=function(e) NULL)
  if (is.null(r)) { cat("  skip", tag, "\n"); return(invisible()) }
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
}
for (m in c("dr","reg","ipw")) {
  add(paste0("single_group_",m),        "single_group.csv", est_method=m)
  add(paste0("two_period_univ_",m),     "two_period.csv", est_method=m, base_period="universal")
  add(paste0("nonconsec_time_",m),      "nonconsecutive_time.csv", est_method=m)
  add(paste0("nonconsec_group_",m),     "nonconsecutive_group.csv", est_method=m)
}
add("no_never_notyet", "no_never.csv", control_group="notyettreated")
add("sim_data",        "sim_data.csv")
add("unbalanced",      "unbalanced.csv", allow_unbalanced_panel=TRUE)
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/py007/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("PY007 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
