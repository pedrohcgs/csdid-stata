# RT008: R oracle for the influence function itself.
#
# att_gt returns the influence function on the MP object, so this can be
# compared directly rather than only through the standard errors it implies.
# That is the stronger check: the IF drives every SE, every aggregation, and
# the multiplier bootstrap, so pinning it pins all of them at the source.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/rt008/inputs/input.csv"); names(d) <- tolower(names(d))
OUT <- "tests/fixtures/parity/rt008/expected/r"

attrows <- list(); ifrows <- list()
for (m in c("dr","reg","ipw")) {
  r <- q(att_gt(yname="y", tname="year", idname="id", gname="group", xformla=~x,
                data=d, est_method=m, bstrap=FALSE, cband=FALSE))
  attrows[[m]] <- data.frame(scenario=m, group=r$group, time=r$t, att=r$att, se=r$se)
  M <- as.matrix(r$inffunc)
  # unit order in R's inffunc follows the sorted unit id
  ids <- sort(unique(d$id))
  for (j in seq_len(ncol(M)))
    ifrows[[paste(m,j)]] <- data.frame(scenario=m, cell=j, id=ids, psi=M[, j])
}
write.csv(do.call(rbind, attrows), file.path(OUT,"attgt.csv"), row.names=FALSE, na="")
inf <- do.call(rbind, ifrows)
write.csv(inf, file.path(OUT,"inffunc.csv"), row.names=FALSE, na="")
cat(sprintf("RT008 oracle: %d attgt rows, %d influence-function entries\n",
            nrow(do.call(rbind, attrows)), nrow(inf)))
