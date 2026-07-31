# RT031: inherit R did tests/testthat/test_sim_data_2_groups.R
#
# Upstream asserts an INVARIANCE: with only two groups (one treated cohort plus
# never-treated), never-treated and not-yet-treated controls coincide, so all
# four combinations of control group x base period must agree, and att[2] must
# recover the true effect of 3. Upstream checks that against loose tolerances
# (.1 against truth, .0001 across specifications). We inherit the scenario but
# compare Stata against R's own numbers, which is the stronger claim.
suppressMessages(library(did))
set.seed(20241017)
n <- 5000
p3_true <- exp(0.5); denominator <- 1 + p3_true
p3_true <- p3_true / denominator
g <- as.numeric(runif(n) <= p3_true); g <- ifelse(g == 1, 3, 0)
nu <- rnorm(n, mean = g, sd = 1)
index_trend <- 1; att_rand <- rnorm(n, mean = 3, sd = 1)
Yt1_ginf <- index_trend + nu + rnorm(n); Yt2_ginf <- 2*index_trend + nu + rnorm(n)
Yt3_ginf <- 3*index_trend + nu + rnorm(n); Yt4_ginf <- 4*index_trend + nu + rnorm(n)
Yt1_g3 <- index_trend + nu + rnorm(n);     Yt2_g3 <- 2*index_trend + nu + rnorm(n)
Yt3_g3 <- att_rand + 3*index_trend + nu + rnorm(n)
Yt4_g3 <- 1.5*att_rand + 4*index_trend + nu + rnorm(n)
y1 <- (g==3)*Yt1_g3 + (g==0)*Yt1_ginf; y2 <- (g==3)*Yt2_g3 + (g==0)*Yt2_ginf
y3 <- (g==3)*Yt3_g3 + (g==0)*Yt3_ginf; y4 <- (g==3)*Yt4_g3 + (g==0)*Yt4_ginf
wide <- data.frame(id = 1:n, g = g, y1, y2, y3, y4)
long <- do.call(rbind, lapply(1:4, function(k)
  data.frame(id = wide$id, g = wide$g, t = k, y = wide[[paste0("y", k)]])))
long <- long[order(long$id, long$t), ]

# run from the repository root
OUT <- "tests/fixtures/parity/rt031"
write.csv(long, file.path(OUT, "inputs", "two-groups.csv"), row.names = FALSE)

spec <- list(
  list(tag="nt_varying",   ctrl="nevertreated",   bp="varying"),
  list(tag="nt_universal", ctrl="nevertreated",   bp="universal"),
  list(tag="nyt_varying",  ctrl="notyettreated",  bp="varying"),
  list(tag="nyt_universal",ctrl="notyettreated",  bp="universal"))
rows <- do.call(rbind, lapply(spec, function(s) {
  r <- suppressWarnings(suppressMessages(att_gt(
    yname="y", tname="t", idname="id", gname="g", data=long,
    est_method="reg", control_group=s$ctrl, base_period=s$bp,
    bstrap=FALSE, cband=FALSE)))
  data.frame(spec=s$tag, group=r$group, time=r$t, att=r$att, se=r$se)
}))
# NA is written empty so Stata imports the column as numeric-with-missing;
# the universal base period contributes a reference cell with att 0 and no SE.
write.csv(rows, file.path(OUT, "expected", "r", "attgt.csv"), row.names = FALSE, na = "")
cat(sprintf("RT031: %d rows across %d specifications\n", nrow(rows), length(spec)))
