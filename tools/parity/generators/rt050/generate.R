#!/usr/bin/env Rscript
# RT050: the aggregation simultaneous band keeps a column whose bootstrap scale
# is positive but at or below sqrt(.Machine$double.eps)*10.
# mboot() drops a column only on its sum of squared draws (mboot.R:142) and
# divides by its IQR scale as it stands (mboot.R:158-180); only the ATT(g,t)
# band in att_gt() blanks a small scale (att_gt.R:707). Event time 2 here is
# supported by a two-unit cohort, and the never-treated outcome changes differ
# by about 1e-9, so on some seeds the band draws of that column put both
# quartiles inside a narrow cluster around zero: the scale is a few 1e-10, the
# column dominates the sup-t maximum, and compute.aggte warns that the critical
# value is very large (compute.aggte.R:528). Seed 2 is the ordinary case.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt050/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt050")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

rows <- list()
id <- 0
for (i in 1:40) { id <- id + 1; for (t in 1:5) rows[[length(rows) + 1]] <- c(id, t, 0, (i %% 7) / 4 + 0.5 * t + 1e-9 * ((i * t) %% 5)) }
for (i in 1:2)  { id <- id + 1; for (t in 1:5) rows[[length(rows) + 1]] <- c(id, t, 3, (i %% 3) / 4 + 0.5 * t + (t >= 3) * (1 + 0.3 * i) + ((i * t) %% 4) / 8) }
for (i in 1:30) { id <- id + 1; for (t in 1:5) rows[[length(rows) + 1]] <- c(id, t, 4, (i %% 5) / 4 + 0.5 * t + (t >= 4) * 1 + ((i * t) %% 7) / 10) }
z <- as.data.frame(do.call(rbind, rows))
names(z) <- c("id", "t", "g", "y")
input <- "inputs/small_scale_column.csv"
zw <- z
zw$y <- sprintf("%.17g", z$y)
write.csv(zw, file.path(out, input), row.names = FALSE, quote = FALSE)
inputs <- list(list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z)))

res <- list()
for (s in c(1, 2)) {
  set.seed(s)
  a <- suppressWarnings(did::att_gt(
    yname = "y", tname = "t", idname = "id", gname = "g", data = z,
    control_group = "nevertreated", base_period = "universal", est_method = "reg",
    bstrap = TRUE, biters = 1000, cband = TRUE))
  w <- character(0)
  e <- withCallingHandlers(did::aggte(a, type = "dynamic"),
    warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
  res[[length(res) + 1L]] <- data.frame(seed = s, type = "dynamic",
    crit_val = sprintf("%.17g", e$crit.val.egt),
    very_large_warning = as.integer(any(grepl("Simultaneous critical value is very large", w, fixed = TRUE))))
}
res <- do.call(rbind, res)
write.csv(res, file.path(out, "expected/r/aggte_crit.csv"), row.names = FALSE, quote = FALSE)
outputs <- list(list(path = "expected/r/aggte_crit.csv", schema = "aggte-crit", sha256 = sha(file.path(out, "expected/r/aggte_crit.csv"))))
manifest <- list(matrix_id = "RT050", fixture_family = "r-aggregation-band-small-scale",
  normative_source = "did 2.5.1 mboot.R:142 (ndg.dim on colSums(bres^2)), mboot.R:158-180 (bSigma unthresholded, is.finite filter), compute.aggte.R:514-530 (dynamic crit.val and very-large warning); contrast att_gt.R:707",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001", "TOL003"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt050/generate.R", path = "tools/parity/generators/rt050/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID")), BMisc = as.character(packageVersion("BMisc"))))),
  rng = list(kind = "Mersenne-Twister", seeds = c(1, 2), biters = 1000, distribution = "rademacher"),
  expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "csdid rseed(seed) reps(1000) then estat event: e(crit_val)", expected = "expected/r/aggte_crit.csv", tolerance_id = "TOL003",
      note = "Seed 1: the critical value is a ratio over a scale of a few 1e-10, which amplifies the ~1e-15 rounding of the draws to a relative 3e-6; TOL003 relative 5e-4 applies. Seed 2: ordinary scale, TOL001."),
    list(actual = "the very-large critical value warning", expected = "expected/r/aggte_crit.csv", tolerance_id = "EXACT", key_columns = c("seed", "type"))),
  approved_divergence = NULL,
  scope_note = "Balanced 5-period panel: 40 never-treated units, a 2-unit cohort 3 and a 30-unit cohort 4; method reg, never-treated controls, universal base, seeded multiplier bootstrap with 1000 draws. Both the accelerator and the Mata draws are compared.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT050 written:", nrow(res), "rows.\n")
print(res)
