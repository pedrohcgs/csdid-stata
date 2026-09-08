#!/usr/bin/env Rscript
# RT041: REG panel/RC and DR panel outcome coefficients use pivoted QR.
# Exactly affine dyadic outcomes expose normal-equation rounding; ordinary
# noisy outcomes check nondegenerate IFs, clustering and weight routes.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt041/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt041")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
scenarios <- data.frame(
  scenario = c("affine_panel_reg", "affine_panel_reg_weighted", "affine_panel_dr", "affine_panel_dr_weighted",
               "affine_rc_reg", "affine_rc_reg_weighted", "regular_panel_reg", "regular_panel_dr",
               "regular_rc_reg", "regular_unbalanced_reg", "regular_balanced_reg_varying"),
  method = c("reg", "reg", "dr", "dr", "reg", "reg", "reg", "dr", "reg", "reg", "reg"),
  panel = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE, TRUE),
  unbalanced = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE),
  weighted = c(FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
  cluster = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE),
  regular = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE),
  denom = c(8192, 8192, 32768, 8192, 8192, 8192, 8192, 8192, 8192, 8192, 8192),
  fix_weights = c("", "", "", "", "", "", "", "", "", "", "varying"),
  stringsAsFactors = FALSE)
attout <- list(); ifout <- list(); inputs <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  z <- expand.grid(i = 1:20, time = seq_len(if (s$panel) 3 else 2), g = c(0, 2))
  z$id <- z$i + 20 * (z$g == 2)
  z$cl <- 1 + (z$id %% 8)
  z$x1 <- 20 + z$i / 32 + z$g / 8
  z$x2 <- z$x1 + (((z$i + z$g)^2 %% 17) - 8) / s$denom
  z$y <- 3 + z$i / 16 + (z$time - 1) * (1 + z$x1 / 4 - z$x2 / 8) + 2 * (z$g == 2 & z$time >= 2)
  if (!s$panel) {
    z$x1 <- z$x1 + z$time / 64
    z$x2 <- z$x1 + (((z$i + z$g + 3 * z$time)^2 %% 17) - 8) / s$denom
    z$y <- 3 + z$x1 / 4 - z$x2 / 8 + (z$g == 2) * (1 + 2 * (z$time == 2))
  }
  if (s$regular) {
    z$x1 <- (z$id %% 13) / 8 - 3 / 4
    z$x2 <- ((z$id^2 %% 17) - 8) / 16
    z$y <- 3 + z$x1 / 4 - z$x2 / 8 + (z$g == 2) * (1 + 2 * (z$time >= 2)) + ((z$id * z$time %% 11) - 5) / 8
  }
  z$w <- 1 + (z$i %% 3) / 4 + z$time / 32
  z <- z[order(z$id, z$time), c("id", "time", "g", "cl", "x1", "x2", "y", "w")]
  if (s$unbalanced) z <- z[!(z$id == 2 & z$time == 2) & !(z$id == 25 & z$time == 1), ]
  rownames(z) <- NULL
  input <- file.path("inputs", paste0(s$scenario, ".csv"))
  write.csv(z, file.path(out, input), row.names = FALSE)
  inputs[[k]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(z), columns = ncol(z))
  a <- suppressWarnings(did::att_gt(
    yname = "y", tname = "time", gname = "g", idname = if (s$panel) "id" else NULL,
    data = z, xformla = ~x1 + x2, panel = s$panel, allow_unbalanced_panel = s$unbalanced,
    weightsname = if (s$weighted) "w" else NULL, clustervars = if (s$cluster) "cl" else NULL,
    control_group = "nevertreated", base_period = "universal", est_method = s$method,
    fix_weights = if (nzchar(s$fix_weights)) s$fix_weights else NULL,
    bstrap = FALSE, cband = FALSE))
  inf <- as.matrix(a$inffunc)
  inf_ids <- unique(a$DIDparams$data[[a$DIDparams$idname]])
  stopifnot(length(inf_ids) == nrow(inf), !anyDuplicated(inf_ids))
  inf <- inf[order(inf_ids), , drop = FALSE]
  attout[[k]] <- data.frame(scenario = s$scenario, group = a$group, time = a$t,
    event_time = a$t - a$group, att = a$att, se = a$se, crit_val = qnorm(.975),
    ci_low = a$att - qnorm(.975) * a$se, ci_high = a$att + qnorm(.975) * a$se,
    control_group = "nevertreated", base_period = "universal", est_method = s$method,
    panel_mode = if (!s$panel) "rcs" else if (s$unbalanced) "unbalanced" else "panel",
    sample_n = nrow(z), inffunc_col = seq_along(a$att), n_units = a$n)
  ifout[[k]] <- data.frame(scenario = s$scenario, unit_index = rep(seq_len(nrow(inf)), ncol(inf)),
    group = rep(a$group, each = nrow(inf)), time = rep(a$t, each = nrow(inf)), value = as.vector(inf))
}
write.csv(do.call(rbind, attout), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(do.call(rbind, ifout), file.path(out, "expected/r/inffunc.csv"), row.names = FALSE, na = "")
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE)
inputs[[length(inputs) + 1L]] <- list(path = "inputs/scenarios.csv", sha256 = sha(file.path(out, "inputs/scenarios.csv")), rows = nrow(scenarios), columns = ncol(scenarios))
outputs <- lapply(c("attgt.csv", "inffunc.csv"), function(nm) list(path = paste0("expected/r/", nm), schema = if (nm == "attgt.csv") "attgt" else "full-influence-function", sha256 = sha(file.path(out, "expected/r", nm))))
manifest <- list(matrix_id = "RT041", fixture_family = "r-outcome-qr",
  normative_source = "did 2.5.1 compute.att_gt.R; DRDID 1.3.0 reg_did_panel, reg_did_rc, drdid_panel and fastglm_fit: Gaussian outcome fits use method=0 (column-pivoted QR)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001", "TOL002"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt041/generate.R", path = "tools/parity/generators/rt041/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID")), fastglm = as.character(packageVersion("fastglm"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "Stata full ATT(g,t), standard errors and sample dimensions", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "group", "time")),
    list(actual = "Every Stata unit influence-function entry", expected = "expected/r/inffunc.csv", tolerance_id = "TOL002", key_columns = c("scenario", "unit_index", "group", "time"))),
  approved_divergence = NULL,
  scope_note = "Six affine cases qualify three distinct coefficient kernels, weighted and unweighted; five ordinary cases cover nondegenerate influence functions, clustering, unbalanced panels, and varying weights. Three-period panels exercise DR cache reuse. All cells and full IF entries are compared without conditioning-specific tolerance.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT041 written:", nrow(do.call(rbind, attout)), "cells and", nrow(do.call(rbind, ifout)), "IF entries.\n")
