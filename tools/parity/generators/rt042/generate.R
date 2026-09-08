#!/usr/bin/env Rscript
# RT042: a failed ATT grid still has a settled estimation sample.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt042/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt042")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
d <- expand.grid(t = 1:2, id = 1:20)
d <- d[order(d$id, d$t), ]
d$g <- ifelse(d$id <= 10, 2, 0)
d$x <- as.numeric(d$g > 0)
d$y <- d$id / 10 + d$t + 2 * (d$g > 0 & d$t == 2)
specs <- data.frame(scenario = c("varying", "universal", "screened"),
                    base = c("varying", "universal", "varying"))
cells <- samples <- inputs <- list()
for (k in seq_len(nrow(specs))) {
  s <- specs[k, ]; z <- d
  if (s$scenario == "screened") z$y[z$id == 15 & z$t == 2] <- NA_real_
  input <- file.path("inputs", paste0(s$scenario, ".csv"))
  write.csv(z, file.path(out, input), row.names = FALSE, na = "")
  fit_data <- if (s$scenario == "screened") z[z$id > 2, ] else z
  a <- suppressWarnings(did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
    xformla = ~ x, data = fit_data, est_method = "reg", control_group = "nevertreated",
    base_period = s$base, bstrap = FALSE, cband = FALSE))
  settled <- as.data.frame(a$DIDparams$data)
  samples[[k]] <- data.frame(scenario = s$scenario, id = z$id, t = z$t,
    used = as.integer(paste(z$id, z$t) %in% paste(settled$id, settled$t)))
  cells[[k]] <- data.frame(scenario = s$scenario, group = a$group, time = a$t,
    att = a$att, se = a$se, sample_n = nrow(settled), n_units = a$n)
  stopifnot(sum(samples[[k]]$used) == nrow(settled))
  inputs[[k]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z))
}
write.csv(do.call(rbind, cells), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(do.call(rbind, samples), file.path(out, "expected/r/sample.csv"), row.names = FALSE)
manifest <- list(matrix_id = "RT042", fixture_family = "r-empty-coefficient-sample",
  normative_source = "did 2.5.1 att_gt and its settled DIDparams$data; singular control covariate design",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = "EXACT", inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt042/generate.R",
    path = "tools/parity/generators/rt042/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()),
    package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL,
  expected_outputs = lapply(c("attgt.csv", "sample.csv"), function(nm) list(path = paste0("expected/r/", nm),
    schema = if (nm == "attgt.csv") "attgt" else "estimation-sample", sha256 = sha(file.path(out, "expected/r", nm)))),
  comparison_plan = list(
    list(actual = "Every Stata ATT/SE missing pattern and sample count", expected = "expected/r/attgt.csv", tolerance_id = "EXACT", key_columns = c("scenario", "group", "time")),
    list(actual = "Every Stata e(sample) marker", expected = "expected/r/sample.csv", tolerance_id = "EXACT", key_columns = c("scenario", "id", "t"))),
  approved_divergence = NULL,
  scope_note = "A singular control design leaves no postable coefficient; universal normalization also cannot be posted. The sample marker still identifies settled data, including if-screening and full balancing after a missing outcome.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT042 written:", nrow(do.call(rbind, cells)), "cells and", nrow(do.call(rbind, samples)), "sample markers.\n")
