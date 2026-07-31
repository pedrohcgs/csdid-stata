# RT010: R oracle for the edge-case designs -- single treated unit, two periods,
# no never-treated group, non-consecutive time and cohort codes, balanced and
# unbalanced, a single post period. These are exactly the shapes where an
# implementation is most likely to differ, and none was compared against R.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN <- "tests/fixtures/parity/rt010/inputs"
rows <- list()
try_add <- function(tag, file, ...) {
  d <- read.csv(file.path(IN, file)); names(d) <- tolower(names(d))
  r <- tryCatch(q(att_gt(yname="y", tname="period", idname="id", gname="g",
                         data=d, bstrap=FALSE, cband=FALSE, ...)),
                error=function(e) NULL)
  if (is.null(r)) { cat("  skip", tag, "- R refused\n"); return(invisible()) }
  rows[[tag]] <<- data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)
}
try_add("single_treated",        "single_treated.csv")
try_add("two_period_universal",  "two_period.csv", base_period="universal")
try_add("no_never_notyet",       "no_never.csv", control_group="notyettreated")
try_add("nonconsecutive_time",   "nonconsecutive_time.csv")
try_add("nonconsecutive_group",  "nonconsecutive_group.csv")
try_add("balanced_allow",        "balanced_allow.csv")
try_add("unbalanced_allow",      "unbalanced_allow.csv", allow_unbalanced_panel=TRUE)
try_add("single_post",           "single_post.csv")
out <- do.call(rbind, rows)
write.csv(out, "tests/fixtures/parity/rt010/expected/r/attgt.csv", row.names=FALSE, na="")
cat(sprintf("RT010 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
