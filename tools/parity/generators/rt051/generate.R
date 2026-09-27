#!/usr/bin/env Rscript
# RT051: near-collinear covariates inside R's accepted conditioning band.
# x2 = x1 + delta * z with delta = 10^(-k/10). At k = 65 and k = 68 the control
# design has rcond(crossprod(.)) of 2e-14 and 5e-15, and the propensity-score
# hessian likewise: above .Machine$double.eps, so did 2.5.1 (rcond_check_fail,
# utility_functions.R:107-113) and DRDID 1.3.0 (reg_did_panel, std_ipw_did_panel,
# drdid_panel) estimate every method, and fastglm's LDLT fit (method = 3) keeps
# both covariates. reg is stable to 1e-9 across the band; ipw and dr carry the
# last-bit amplification of a condition number near 1e14 (see the manifest).
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt051/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt051")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
f17 <- function(v) sprintf("%.17g", v)

set.seed(7)
nu <- 300
id <- rep(seq_len(nu), each = 2); t <- rep(1:2, times = nu)
gu <- sample(c(0, 2), nu, replace = TRUE, prob = c(.5, .5)); g <- gu[id]
x1u <- rnorm(nu); zu <- rnorm(nu)
y <- 0.5 * x1u[id] + 0.2 * t + (g == 2 & t == 2) + rnorm(nu * 2)

inputs <- list()
res <- list()
for (k in c(65, 68)) {
  z <- data.frame(id = id, t = t, g = g, x1 = x1u[id], x2 = x1u[id] + 10^(-k / 10) * zu[id], y = y)
  input <- sprintf("inputs/near_collinear_k%d.csv", k)
  zw <- z
  for (v in c("x1", "x2", "y")) zw[[v]] <- f17(z[[v]])
  write.csv(zw, file.path(out, input), row.names = FALSE, quote = FALSE)
  inputs[[length(inputs) + 1L]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z))
  for (m in c("reg", "ipw", "dr")) {
    a <- suppressWarnings(did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g", data = z, xformla = ~x1 + x2,
      control_group = "nevertreated", base_period = "universal", est_method = m,
      bstrap = FALSE, cband = FALSE))
    res[[length(res) + 1L]] <- data.frame(k = k, method = m, att = f17(a$att[a$t == 2]), se = f17(a$se[a$t == 2]))
  }
}
res <- do.call(rbind, res)
write.csv(res, file.path(out, "expected/r/attgt.csv"), row.names = FALSE, quote = FALSE)
outputs <- list(list(path = "expected/r/attgt.csv", schema = "attgt", sha256 = sha(file.path(out, "expected/r/attgt.csv"))))
manifest <- list(matrix_id = "RT051", fixture_family = "r-near-collinear-conditioning-band",
  normative_source = "did 2.5.1 utility_functions.R:107-113 (rcond_check_fail); DRDID 1.3.0 std_ipw_did_panel/drdid_panel (fastglm_fit method = 3, rcond(XtWX.ps) < eps), reg_did_panel/drdid_panel (rcond(XpX) < eps then solve)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL002"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt051/generate.R", path = "tools/parity/generators/rt051/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "Stata ATT(2,2), method reg", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("k", "method")),
    list(actual = "Stata ATT(2,2), methods ipw and dr, and every SE", expected = "expected/r/attgt.csv", tolerance_id = "ill-conditioning",
      note = "Ill-conditioning tolerance, recorded under approved_divergence: with a propensity-score hessian condition number near 1e14 the two logit solvers agree to about 5e-5 in the ATT; the reg ATT is stable to 1e-9 and is compared at TOL002; the ipw and dr ATTs are bounded at 1e-3 absolute and every SE at 1e-3 relative (measured gaps: 3e-5 in an ATT, 1e-4 relative in an SE). The same model with x2 dropped is 1e-2 away for ipw and 2.6e-3 for dr, so the bound separates the specified model from a re-specified one.")),
  approved_divergence = list(
    status = "approved-ill-conditioning-tolerance",
    reason = "At a propensity-score hessian condition number near 1e14 the logit solvers of csdid and the reference implementation agree to about 5e-5 in the ipw and dr ATT and 1e-4 relative in the SE, below any tolerance of the registry. The ipw and dr ATTs are compared at 1e-3 absolute and every SE at 1e-3 relative; the reg ATT, which is stable to 1e-9, stays at TOL002. The bound still separates the specified model from a re-specified one (x2 dropped: 1e-2 away for ipw, 2.6e-3 for dr). Owner approval 2026-09-27 (AGENTS.md register)."
  ),
  scope_note = "300-unit two-period panel, cohort 2 against never-treated units, covariates x1 and x2 = x1 + 10^(-k/10) z, universal base, analytical inference; k = 65 and k = 68, methods reg, ipw and dr.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT051 written:", nrow(res), "rows.\n")
print(res)
