#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f018/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f018")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

d <- do.call(rbind, lapply(1:4, function(t) {
  do.call(rbind, lapply(c(3, 4, 0), function(g) {
    k <- 1:12
    treat <- ifelse(g > 0 && t >= g, 0.6 + 0.15 * (t - g) + 0.05 * g, 0)
    data.frame(
      rowid = NA_integer_,
      time = t,
      g = g,
      k = k,
      y = 0.3 * t + 0.02 * g + 0.04 * k + 0.01 * k * t + treat
    )
  }))
}))
d$rowid <- seq_len(nrow(d))
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

out <- att_gt(
  yname = "y",
  tname = "time",
  gname = "g",
  data = d,
  panel = FALSE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "varying"
)

attgt <- data.frame(
  group = out$group,
  time = out$t,
  event_time = out$t - out$group,
  att = out$att,
  se = out$se,
  crit_val = NA_real_,
  ci_low = NA_real_,
  ci_high = NA_real_,
  control_group = out$DIDparams$control_group,
  base_period = out$DIDparams$base_period,
  est_method = out$DIDparams$est_method,
  panel_mode = "repeated-cross-section",
  sample_n = nrow(d),
  inffunc_col = seq_along(out$att)
)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F018",
  fixture_family = "true-repeated-cross-sections",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("TOL001", "TOL002", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f018/generate.R", path = "tools/parity/generators/f018/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/r/attgt.csv", schema = "attgt")),
  comparison_plan = list(list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("group", "time"))),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
