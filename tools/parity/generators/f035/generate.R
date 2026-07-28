# F035: R oracle for the seeded wild-bootstrap spellings. The test proves the
# four option spellings agree with each other; this pins the value against R.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
d <- read.csv("tests/fixtures/parity/f035/inputs/input.csv"); names(d)<-tolower(names(d))
set.seed(12345)
r <- q(att_gt(yname="y",tname="time",idname="id",gname="g",data=d,est_method="reg",
              bstrap=TRUE,biters=31,cband=TRUE))
out <- data.frame(scenario="wboot31_seed12345", group=r$group, time=r$t, att=r$att, se=r$se)
write.csv(out,"tests/fixtures/parity/f035/expected/r/attgt.csv",row.names=FALSE,na="")
cat(sprintf("F035 oracle: %d cells\n", nrow(out)))
