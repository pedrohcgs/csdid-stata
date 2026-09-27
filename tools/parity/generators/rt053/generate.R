#!/usr/bin/env Rscript
# RT053: a treated share inside did's knife-edge band, below the overlap cut.
# 4994 of 4999 units are treated: the share is 0.9989998000, within 1e-6 of
# 0.999, so overlap_check_fail() defers to a real fit (utility_functions.R:87-94)
# whose fitted value is the share, below 0.999: the overlap guard passes for
# ipw exactly as for dr. At DRDID's default trim.level the five comparison units
# (score about 0.999) are trimmed and the cell is NA; with trim.level = 1 DRDID
# estimates it.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt053/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt053")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
f17 <- function(v) ifelse(is.na(v), "", sprintf("%.17g", v))

nu <- 4999
gu <- c(rep(2, 4994), rep(0, 5))
id <- rep(seq_len(nu), each = 2); tt <- rep(1:2, nu)
z <- data.frame(id = id, t = tt, g = gu[id],
  y = ((id * 7) %% 11) / 4 + 0.3 * tt + ((id * tt) %% 5) / 8 + (gu[id] == 2 & tt == 2))
input <- "inputs/knife_edge_share.csv"
zw <- z
zw$y <- f17(z$y)
write.csv(zw, file.path(out, input), row.names = FALSE, quote = FALSE)
inputs <- list(list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z)))

guard <- did:::overlap_check_fail(matrix(1, nu, 1), as.numeric(gu == 2), TRUE)
stopifnot(!guard, abs(mean(gu == 2) - 0.999) < 1e-6, mean(gu == 2) < 0.999)
res <- list()
for (m in c("ipw", "dr")) {
  a <- suppressWarnings(did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g", data = z,
    est_method = m, control_group = "nevertreated", base_period = "universal", bstrap = FALSE, cband = FALSE))
  res[[length(res) + 1L]] <- data.frame(route = "att_gt", method = m, trim_level = 0.995,
    att = f17(a$att[a$t == 2]), overlap_check_fail = as.integer(guard))
}
w1 <- z[z$t == 2, ]; w0 <- z[z$t == 1, ]
for (m in c("ipw", "dr")) {
  f <- if (m == "ipw") DRDID::std_ipw_did_panel else DRDID::drdid_panel
  r <- f(y1 = w1$y, y0 = w0$y, D = as.numeric(w1$g == 2), covariates = NULL, trim.level = 1)
  res[[length(res) + 1L]] <- data.frame(route = "drdid", method = m, trim_level = 1,
    att = f17(r$ATT), overlap_check_fail = as.integer(guard))
}
res <- do.call(rbind, res)
write.csv(res, file.path(out, "expected/r/attgt.csv"), row.names = FALSE, quote = FALSE)
outputs <- list(list(path = "expected/r/attgt.csv", schema = "attgt", sha256 = sha(file.path(out, "expected/r/attgt.csv"))))
manifest <- list(matrix_id = "RT053", fixture_family = "r-overlap-knife-edge-no-covariates",
  normative_source = "did 2.5.1 utility_functions.R:87-94 (overlap_check_fail defers to a fit inside the 1e-6 band); DRDID 1.3.0 std_ipw_did_panel and drdid_panel (trim.level)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt053/generate.R", path = "tools/parity/generators/rt053/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "method(ipw) and method(dr) without covariates: the cell is not refused as an overlap violation; at the default trim it is missing, with pscoretrim(1) it equals DRDID at trim.level = 1", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("route", "method"))),
  approved_divergence = NULL,
  scope_note = "Two-period balanced panel of 4999 units, 4994 in cohort 2 and 5 never treated, no covariates, universal base, analytical inference. At the default trim csdid announces the empty comparison mass where DRDID returns NA silently (the registered no-effective-mass announcement).")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT053 written:", nrow(res), "rows.\n")
print(res)
