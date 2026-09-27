#!/usr/bin/env Rscript
# RT052: DRDID's own rcond guards on the outcome-regression designs.
# did 2.5.1 tests rcond(crossprod(.)) of the pooled, unweighted control design
# (rcond_check_fail). DRDID 1.3.0 then tests rcond(XpX) < .Machine$double.eps
# on the design it actually inverts: the weighted control XpX in reg_did_panel
# and drdid_panel, and each period's block in reg_did_rc and drdid_rc (control
# pre, control post, then treated pre and post in drdid_rc). A block or a
# weighting can fail while the pooled design passes, and R then reports NA.
#   rc_spre1 / rc_spre3: repeated cross sections, x = 1e4 + s z in the pre
#     period and 1e4 + 100 z in the post period. s = 1 fails the pre block
#     (rcond about 9e-17); s = 3 passes it (7e-16) and every method estimates.
#   panel_weighted: iweights of 1 and 1e-6 put the weighted control XpX at
#     rcond about 1e-16 while the unweighted design is at 7e-13.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt052/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt052")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
f17 <- function(v) ifelse(is.na(v), "", sprintf("%.17g", v))
inputs <- list()
write_input <- function(z, name, cols) {
  zw <- z
  for (v in cols) zw[[v]] <- f17(z[[v]])
  path <- file.path("inputs", name)
  write.csv(zw, file.path(out, path), row.names = FALSE, quote = FALSE)
  inputs[[length(inputs) + 1L]] <<- list(path = path, sha256 = sha(file.path(out, path)), rows = nrow(z), columns = ncol(z))
}
res <- list()
run <- function(scenario, z, method, ...) {
  msg <- ""
  a <- withCallingHandlers(did::att_gt(yname = "y", tname = "t", gname = "g", data = z, xformla = ~x,
      est_method = method, control_group = "nevertreated", base_period = "universal",
      bstrap = FALSE, cband = FALSE, ...),
    warning = function(w) {
      m <- conditionMessage(w)
      if (grepl("design matrix", m, fixed = TRUE)) msg <<- sub("^.*: (The [^.]*singular)\\..*$", "\\1", m)
      invokeRestart("muffleWarning")
    })
  res[[length(res) + 1L]] <<- data.frame(scenario = scenario, method = method,
    att = f17(a$att[a$t == 2]), se = f17(a$se[a$t == 2]), r_reason = msg)
}

set.seed(4)
n <- 600
t <- rep(c(1, 2), each = n / 2)
g <- ifelse(runif(n) < 0.5, 2, 0)
for (s_pre in c(1, 3)) {
  zz <- rnorm(n)
  x <- 1e4 + ifelse(t == 1, s_pre, 100) * zz
  y <- 1 + 0.01 * (x - 1e4) + (g == 2 & t == 2) + rnorm(n)
  z <- data.frame(y = y, x = x, t = t, g = g)
  write_input(z, sprintf("rc_spre%d.csv", s_pre), c("y", "x"))
  z <- read.csv(file.path(out, "inputs", sprintf("rc_spre%d.csv", s_pre)))
  for (m in c("reg", "dr", "ipw")) run(sprintf("rc_spre%d", s_pre), z, m, idname = NULL, panel = FALSE)
}

set.seed(5)
nu <- 400
id <- rep(seq_len(nu), each = 2); t <- rep(1:2, times = nu)
gu <- ifelse(runif(nu) < 0.5, 2, 0)
heavy <- runif(nu) < 0.5
zu <- rnorm(nu)
xu <- 1e4 + ifelse(heavy, 1, 100) * zu
wu <- ifelse(heavy, 1, 1e-6)
z <- data.frame(id = id, t = t, g = gu[id], x = xu[id], w = wu[id],
  y = 0.01 * (xu[id] - 1e4) + 0.2 * t + (gu[id] == 2 & t == 2) + rnorm(2 * nu))
write_input(z, "panel_weighted.csv", c("x", "w", "y"))
z <- read.csv(file.path(out, "inputs", "panel_weighted.csv"))
for (m in c("reg", "dr")) run("panel_weighted", z, m, idname = "id", weightsname = "w")

res <- do.call(rbind, res)
write.csv(res, file.path(out, "expected/r/attgt.csv"), row.names = FALSE, quote = FALSE, na = "")
outputs <- list(list(path = "expected/r/attgt.csv", schema = "attgt", sha256 = sha(file.path(out, "expected/r/attgt.csv"))))
manifest <- list(matrix_id = "RT052", fixture_family = "r-regression-design-rcond-guards",
  normative_source = "DRDID 1.3.0 reg_did_panel and drdid_panel (rcond(XpX) < eps, XpX weighted), reg_did_rc and drdid_rc (rcond of each pre/post block < eps); did 2.5.1 compute.att_gt.R:678/944 (the stop becomes an NA cell with a warning)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL002"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt052/generate.R", path = "tools/parity/generators/rt052/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "Stata ATT(2,2) and SE where R estimates; a missing cell where R reports NA", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "method")),
    list(actual = "the refusal names R's reason (r_reason)", expected = "expected/r/attgt.csv", tolerance_id = "EXACT", key_columns = c("scenario", "method"))),
  approved_divergence = NULL,
  scope_note = "Repeated cross sections (600 rows, one covariate) at two pre-period scales, reg, dr and ipw; a two-period weighted panel (400 units) with reg and dr. Cohort 2 against never-treated units, universal base, analytical inference.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT052 written:", nrow(res), "rows.\n")
print(res)
