# PY006: R oracle for the influence function, compared value by value.
# att_gt exports the influence function on the MP object, so the check does not
# have to stop at its shape.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/py006/inputs/sample-data.csv"); names(d) <- tolower(names(d))
OUT <- "tests/fixtures/parity/py006/expected/r"
attrows <- list(); ifrows <- list()
for (m in c("dr","reg","ipw")) {
  r <- q(att_gt(yname="y", tname="year", idname="id", gname="group",
                data=d, est_method=m, bstrap=FALSE, cband=FALSE))
  attrows[[m]] <- data.frame(scenario=m, group=r$group, time=r$t, att=r$att, se=r$se)
  M <- as.matrix(r$inffunc); ids <- sort(unique(d$id))
  for (j in seq_len(ncol(M)))
    ifrows[[paste(m,j)]] <- data.frame(scenario=m, cell=j, id=ids, psi=M[, j])
}
write.csv(do.call(rbind, attrows), file.path(OUT,"attgt.csv"), row.names=FALSE, na="")
inf <- do.call(rbind, ifrows)
write.csv(inf, file.path(OUT,"inffunc.csv"), row.names=FALSE, na="")
cat(sprintf("PY006 oracle: %d influence-function entries\n", nrow(inf)))
