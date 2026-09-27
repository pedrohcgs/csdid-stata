#!/usr/bin/env Rscript
# RT062: the words R prints when it declines the Wald pre-test on a singular
# covariance matrix (att_gt.R:670-675). Repeated cross sections over four
# periods, cohorts 3 and 4 in every period and never-treated rows only in
# periods 3 and 4: under not-yet-treated controls and a varying base period the
# two pre-treatment cells, (3,2) and (4,2), are each other's comparison, so
# their estimates are exact negatives and the pre-test covariance is singular.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt062/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt062")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

z <- rbind(expand.grid(i = 1:5, t = 1:4, g = c(3, 4)), expand.grid(i = 1:5, t = 3:4, g = 0))
z$id <- seq_len(nrow(z))
z$y <- round(sin(1.7 * z$id + z$t) + 0.5 * z$t + ifelse(z$g > 0 & z$t >= z$g, 1, 0), 6)
z <- z[order(z$t, z$g, z$i), c("id", "t", "g", "y")]
rownames(z) <- NULL
write.csv(z, file.path(out, "inputs/singular-pretest.csv"), row.names = FALSE)

w <- character(0)
a <- withCallingHandlers(did::att_gt(
    yname = "y", tname = "t", gname = "g", data = z, panel = FALSE,
    control_group = "notyettreated", base_period = "varying", est_method = "reg",
    bstrap = FALSE, cband = FALSE),
  warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
wald <- w[grepl("^Not returning pre-test Wald", w)]
stopifnot(length(wald) == 1, is.null(a$W))
write.csv(data.frame(message = wald), file.path(out, "expected/r/warnings.csv"), row.names = FALSE)
inputs <- lapply("inputs/singular-pretest.csv", function(p) list(path = p, sha256 = sha(file.path(out, p))))
outputs <- list(list(path = "expected/r/warnings.csv", schema = "warning-text",
  sha256 = sha(file.path(out, "expected/r/warnings.csv"))))
manifest <- list(matrix_id = "RT062", fixture_family = "r-wald-pretest-warning",
  normative_source = "did 2.5.1 att_gt.R:670-675 (the Wald pre-test is not returned when the pre-treatment covariance is singular, with this warning)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt062/generate.R", path = "tools/parity/generators/rt062/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "the Wald pre-test warning line csdid prints", expected = "expected/r/warnings.csv", tolerance_id = "EXACT", key_columns = c("message"))),
  approved_divergence = NULL,
  scope_note = "Repeated cross sections whose two pre-treatment cells are each other's comparison, so the pre-test covariance is singular.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT062 written\n")
