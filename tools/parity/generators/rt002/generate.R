# RT002: R oracle for the aggregation scenarios the Stata test exercises.
# The inherited test asserted only that an aggregate lay within 0.5 of 1.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN  <- "tests/fixtures/parity/rt002/inputs"
OUT <- "tests/fixtures/parity/rt002/expected/r"
d <- read.csv(list.files(IN, pattern="\\.csv$", full.names=TRUE)[1])

base <- q(att_gt(yname="y", tname="period", idname="id", gname="g", xformla=~x,
                 data=d, est_method="dr", bstrap=FALSE, cband=FALSE))

# overall summaries, including the windowed and balanced dynamic variants
spec <- list(
  list(tag="simple",              type="simple",   args=list()),
  list(tag="group",               type="group",    args=list()),
  list(tag="calendar",            type="calendar", args=list()),
  list(tag="dynamic",             type="dynamic",  args=list()),
  list(tag="dynamic_min_e_m1",    type="dynamic",  args=list(min_e=-1)),
  list(tag="dynamic_max_e_1",     type="dynamic",  args=list(max_e=1)),
  list(tag="dynamic_min_m1_max_1",type="dynamic",  args=list(min_e=-1, max_e=1)),
  list(tag="dynamic_balance_e_1", type="dynamic",  args=list(balance_e=1)))

overall <- do.call(rbind, lapply(spec, function(s) {
  a <- do.call(aggte, c(list(base, type=s$type, na.rm=TRUE), s$args))
  data.frame(spec=s$tag, overall_att=a$overall.att, overall_se=a$overall.se)
}))
write.csv(overall, file.path(OUT, "aggte-overall.csv"), row.names=FALSE, na="")

# per-cell aggregation values, which is where a windowing bug would show
cells <- do.call(rbind, lapply(spec, function(s) {
  a <- do.call(aggte, c(list(base, type=s$type, na.rm=TRUE), s$args))
  if (is.null(a$egt)) return(NULL)
  data.frame(spec=s$tag, egt=a$egt, att=a$att.egt, se=a$se.egt)
}))
write.csv(cells, file.path(OUT, "aggte-cells.csv"), row.names=FALSE, na="")
cat(sprintf("RT002 oracle: %d overall rows, %d cell rows\n", nrow(overall), nrow(cells)))
