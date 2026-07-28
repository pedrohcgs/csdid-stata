set.seed(20260727)
OUT <- "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid-stata-porting/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
# balanced panel matched to the unbalanced fixture's ROW count (33,740 ~ 5623x6)
n <- 5623L; TT <- 6L
x1 <- rnorm(n); x2 <- rnorm(n); g <- sample(c(0L,2002L,2003L,2004L), n, replace=TRUE)
wt <- 0.4 + runif(n)*3
bal <- do.call(rbind, lapply(1:TT, function(k)
  data.frame(id=1:n, time=1999L+k, g=g, x1=x1, x2=x2, wt=wt, cl=(1:n)%%60L,
             y=0.3*x1-0.2*x2+0.6*((g>0)&(1999+k>=g))+rnorm(n))))
bal <- bal[order(bal$id,bal$time),]
write.csv(bal, file.path(OUT,"balanced.csv"), row.names=FALSE)
cat(sprintf("balanced: %d rows, %d units, %d periods\n", nrow(bal), n, TT))
