#!/usr/bin/env Rscript

# F052 -- rcs: declaring repeated cross sections on data that carries an
# identifier.
#
# The fixture deliberately uses a *balanced panel with a real, meaningful id*.
# That is what makes the test discriminating: the same file can legitimately be
# read either way, so a run that ignored the rcs option would still produce a
# well-formed answer. Unit-specific intercepts are baked into the DGP so the
# panel reading and the repeated-cross-section reading do not coincide -- the
# panel differences out the unit effect and the cross-section reading does not.
# Both oracles are written, and the test asserts csdid matches panel=FALSE and
# differs from panel=TRUE. Without the second oracle the test could pass on a
# build where rcs did nothing at all.

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f052/generate.R"
# tools/parity/generators/<id> is four levels below the repository root.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f052")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

# 45 units (15 per cohort) observed in all of periods 1..4: a genuine balanced
# panel. alpha is the unit effect that separates the two readings.
cohorts <- c(3, 4, 0)
units <- do.call(rbind, lapply(seq_along(cohorts), function(j) {
  data.frame(id = (j - 1) * 15 + 1:15, g = cohorts[j])
}))
units$alpha <- 0.35 * ((units$id * 7) %% 11) - 1.4

d <- do.call(rbind, lapply(1:4, function(t) {
  treat <- ifelse(units$g > 0 & t >= units$g, 0.6 + 0.15 * (t - units$g) + 0.05 * units$g, 0)
  data.frame(
    id = units$id,
    time = t,
    g = units$g,
    # Deterministic idiosyncratic term. A purely additive DGP leaves the panel
    # reading with zero residual variance, so its standard errors come back
    # missing and there is nothing to compare. This varies with both id and
    # time, which gives both readings a nonzero residual, and it uses no RNG so
    # the fixture regenerates byte-for-byte without a recorded seed.
    y = units$alpha + 0.3 * t + 0.02 * units$g + treat +
      0.23 * sin(1.7 * units$id + 2.9 * t)
  )
}))
d <- d[order(d$id, d$time), ]
rownames(d) <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

run <- function(is_panel) {
  att_gt(
    yname = "y",
    tname = "time",
    idname = "id",
    gname = "g",
    data = d,
    panel = is_panel,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = "reg",
    base_period = "varying"
  )
}

emit <- function(out, mode, path) {
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
    panel_mode = mode,
    sample_n = nrow(d),
    inffunc_col = seq_along(out$att)
  )
  write.csv(attgt, file.path(fixture, path), row.names = FALSE, na = "")
  attgt
}

rcs_out <- emit(run(FALSE), "repeated-cross-section", "expected/r/attgt.csv")
pan_out <- emit(run(TRUE), "panel", "expected/r/attgt-panel.csv")

# Fail loudly at generation time if the fixture is not discriminating: if the
# two readings agreed, the test built on it would prove nothing about rcs.
se_gap <- max(abs(rcs_out$se - pan_out$se))
if (!(se_gap > 1e-6)) {
  stop(sprintf("F052 fixture is not discriminating: panel and rcs standard errors agree to %g", se_gap))
}
cat(sprintf("F052: %d cells, panel-vs-rcs max SE gap %.6g\n", nrow(rcs_out), se_gap))

manifest <- list(
  matrix_id = "F052",
  fixture_family = "declared-repeated-cross-sections",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("TOL001", "TOL002", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f052/generate.R", path = "tools/parity/generators/f052/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/attgt-panel.csv", schema = "attgt")
  ),
  comparison_plan = list(list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("group", "time"))),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
