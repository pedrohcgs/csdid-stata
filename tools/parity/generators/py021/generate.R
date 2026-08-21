# PY021: R oracle for the simulation-parity scenarios.
#
# This fixture used to consume expected/r/ref_sim.csv verbatim from the Python
# csdid package (csdid/test_csdid/r_ref/sim/ref_sim.csv). That artifact was
# generated elsewhere, against did 2.5.0, in an environment this repository
# cannot reconstruct -- so the numbers compared against were neither
# attributable to a did version verified here nor reproducible here.
#
# It is now generated locally, from the input datasets frozen in this fixture,
# against the same did the rest of the suite is pinned to. The recipe is the
# upstream one (r_ref/generate_sim_reference.R): six simulated panels x
# {nevertreated, notyettreated} x {dr, reg}, xformla = ~X, analytical SEs.
suppressMessages(library(did))

IN  <- "tests/fixtures/parity/py021/inputs"
OUT <- "tests/fixtures/parity/py021/expected/r"
DATASETS <- c("tp2_const", "tp4_const", "tp4_dyn", "tp5_dyn", "tp8_dyn", "tp10_const")

rows <- list()
for (nm in DATASETS) {
  d <- read.csv(file.path(IN, paste0(nm, ".csv")))
  for (cg in c("nevertreated", "notyettreated")) {
    for (em in c("dr", "reg")) {
      out <- tryCatch(
        suppressWarnings(suppressMessages(
          att_gt(yname = "Y", tname = "period", idname = "id", gname = "G",
                 xformla = ~X, data = d, control_group = cg, est_method = em,
                 bstrap = FALSE, cband = FALSE))),
        error = function(e) NULL)
      if (is.null(out)) { cat("  skip", nm, cg, em, "\n"); next }
      rows[[paste(nm, cg, em)]] <- data.frame(
        dataset = nm, control = cg, est = em,
        group = out$group, t = out$t, att = out$att, se = out$se)
    }
  }
}

ref <- do.call(rbind, rows)
# Match the upstream column order and row order so the fixture diff is readable.
ref <- ref[order(match(ref$dataset, DATASETS), ref$control, ref$est,
                 ref$group, ref$t), ]
write.csv(ref, file.path(OUT, "ref_sim.csv"), row.names = FALSE)
cat(sprintf("PY021 oracle: %d rows across %d scenarios (did %s)\n",
            nrow(ref), nrow(unique(ref[, c("dataset", "control", "est")])),
            as.character(packageVersion("did"))))
