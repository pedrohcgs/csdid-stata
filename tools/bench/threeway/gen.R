# Shared fixtures for the three-way benchmark: legacy csdid vs csdid 2.0.0 vs R did.
# One dataset per shape, written once, so all three engines see identical bytes.
set.seed(20260727)
OUT <- "/private/tmp/claude-501/-Users-pedrosantanna-Documents-csdid/5c90ee0a-2bf3-41a2-94bb-d485f9545c83/scratchpad/threeway"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---- unbalanced panel: 6,000 units x 6 periods, ~18% of unit-periods missing
n <- 6000L; TT <- 6L
x1 <- rnorm(n); x2 <- rnorm(n)
g  <- sample(c(0L, 2002L, 2003L, 2004L), n, replace = TRUE)
wt <- 0.4 + runif(n) * 3
pan <- do.call(rbind, lapply(1:TT, function(k)
  data.frame(id = 1:n, time = 1999L + k, g = g, x1 = x1, x2 = x2, wt = wt,
             cl = (1:n) %% 60L,
             y = 0.3 * x1 - 0.2 * x2 + 0.6 * ((g > 0) & (1999 + k >= g)) + rnorm(n))))
pan <- pan[order(pan$id, pan$time), ]
keep <- !( (pan$id %% 7 == 0 & pan$time <= 2001) | (pan$id %% 11 == 3 & pan$time == 2003) )
unb <- pan[keep, ]
write.csv(unb, file.path(OUT, "unbalanced.csv"), row.names = FALSE)

# ---- repeated cross sections: same size, but each row an independent draw
m <- nrow(unb)
rcs <- data.frame(
  id   = 1:m,
  time = sample(2000:2005, m, replace = TRUE),
  g    = sample(c(0L, 2002L, 2003L, 2004L), m, replace = TRUE),
  x1   = rnorm(m), x2 = rnorm(m),
  wt   = 0.4 + runif(m) * 3,
  cl   = (1:m) %% 60L)
rcs$y <- 0.3 * rcs$x1 - 0.2 * rcs$x2 + 0.6 * ((rcs$g > 0) & (rcs$time >= rcs$g)) + rnorm(m)
write.csv(rcs, file.path(OUT, "rcs.csv"), row.names = FALSE)

cat(sprintf("unbalanced: %d rows, %d units, %d periods\n", nrow(unb), length(unique(unb$id)), TT))
cat(sprintf("rcs       : %d rows (repeated cross sections)\n", nrow(rcs)))
