#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f014/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f014")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:36
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 12, 3, ifelse(d$id <= 24, 4, 0))
d$cl <- 1 + ((d$id - 1) %% 4)
d$x1 <- 0.35 * d$time + 0.20 * sin(0.7 * d$id) + 0.10 * (d$id %% 3 == 0)
d$x2 <- 0.20 * d$time + 0.25 * cos(0.5 * d$id) - 0.08 * (d$id %% 4 == 0)
d$y0 <- 1.0 + 0.55 * d$time + 0.35 * d$x1 - 0.15 * d$x2 + 0.05 * cos(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.9 + 0.12 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

seed <- 20250622L
biters <- 399L
set.seed(seed)
mp_boot <- att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  bstrap = TRUE,
  biters = biters,
  cband = TRUE,
  est_method = "reg",
  base_period = "varying"
)
mp_analytic <- att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "varying"
)

point_crit <- qnorm(1 - mp_boot$alp / 2)
boot <- data.frame(
  group = mp_boot$group,
  time = mp_boot$t,
  event_time = mp_boot$t - mp_boot$group,
  att = mp_boot$att,
  se_boot_r = mp_boot$se,
  se_analytic = mp_analytic$se,
  crit_val_r = as.numeric(mp_boot$c),
  ci_low_r = mp_boot$att - as.numeric(mp_boot$c) * mp_boot$se,
  ci_high_r = mp_boot$att + as.numeric(mp_boot$c) * mp_boot$se,
  point_crit_val = point_crit,
  point_ci_low_r = mp_boot$att - point_crit * mp_boot$se,
  point_ci_high_r = mp_boot$att + point_crit * mp_boot$se,
  bstrap = TRUE,
  cband = TRUE,
  biters = biters,
  seed = seed,
  draw_distribution = "BMisc multiplier_bootstrap rademacher multipliers",
  exact_draw_parity = "raw-draw-export-not-in-public-fixture",
  stringsAsFactors = FALSE
)
write.csv(boot, file.path(fixture, "expected/r/bootstrap-attgt.csv"), row.names = FALSE, na = "")

cluster_seed <- 20250623L
cluster_biters <- 199L
set.seed(cluster_seed)
mp_cluster_boot <- att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  bstrap = TRUE,
  biters = cluster_biters,
  cband = TRUE,
  clustervars = "cl",
  est_method = "reg",
  base_period = "varying"
)
mp_cluster_analytic <- att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  bstrap = FALSE,
  cband = FALSE,
  clustervars = "cl",
  est_method = "reg",
  base_period = "varying"
)

cluster_boot <- data.frame(
  group = mp_cluster_boot$group,
  time = mp_cluster_boot$t,
  event_time = mp_cluster_boot$t - mp_cluster_boot$group,
  att = mp_cluster_boot$att,
  se_boot_r = mp_cluster_boot$se,
  se_analytic = mp_cluster_analytic$se,
  crit_val_r = as.numeric(mp_cluster_boot$c),
  bstrap = TRUE,
  cband = TRUE,
  biters = cluster_biters,
  seed = cluster_seed,
  clustervar = "cl",
  n_clusters = length(unique(d$cl)),
  draw_distribution = "BMisc multiplier_bootstrap rademacher multipliers over cluster-summed influence functions",
  exact_draw_parity = "raw-draw-export-not-in-public-fixture",
  stringsAsFactors = FALSE
)
write.csv(cluster_boot, file.path(fixture, "expected/r/bootstrap-cluster-attgt.csv"), row.names = FALSE, na = "")

events <- data.frame(
  event_key = c("invalid_reps"),
  return_code = c(198),
  event_type = "error",
  offending_option = c("wboot(reps(0))"),
  message_normalized = c(
    "wboot() reps() must be a positive integer"
  ),
  stringsAsFactors = FALSE
)
write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F014",
  fixture_family = "bootstrap-and-simultaneous-bands",
  normative_source = "R did 2.5.1 multiplier bootstrap",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D013"),
  tolerance_ids = c("TOL003", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f014/generate.R", path = "tools/parity/generators/f014/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(
    seed = seed,
    biters = biters,
    distribution = "BMisc multiplier_bootstrap rademacher multipliers",
    exact_draw_parity = FALSE,
    reason = "Stata implementation now mirrors BMisc/R's seeded rademacher draw stream for the public seed path; stochastic SEs remain smoke-checked for this fixture.",
    cluster_seed = cluster_seed,
    cluster_biters = cluster_biters
  ),
  expected_outputs = list(
    list(path = "expected/r/bootstrap-attgt.csv", schema = "bootstrap-attgt"),
    list(path = "expected/r/bootstrap-cluster-attgt.csv", schema = "bootstrap-cluster-attgt"),
    list(path = "expected/r/events.csv", schema = "error-warning-events-csv"),
    list(path = "expected/r/events.json", schema = "error-warning-events")
  ),
  comparison_plan = list(
    list(actual = "Stata e(boot_attgt) metadata and deterministic baseline", expected = "expected/r/bootstrap-attgt.csv", tolerance_id = "TOL003", key_columns = c("group", "time")),
    list(actual = "Stata clustered e(boot_attgt) metadata and deterministic baseline", expected = "expected/r/bootstrap-cluster-attgt.csv", tolerance_id = "TOL003", key_columns = c("group", "time")),
    list(actual = "Stata captured validation events", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = list(
    list(
      scope = "seeded_multiplier_draw_stream",
      reason = "The public seed path now mirrors BMisc/R's rademacher draw stream, while F014 remains a smoke fixture for stochastic bootstrap SEs rather than a full raw-draw export fixture.",
      accepted_behavior = "Stata must match deterministic ATT(g,t), analytical SEs, clustered analytical SEs, metadata, critical-value ordering, confidence-interval algebra, and the F035 seeded BMisc/R multiplier-stream probe."
    )
  ),
  scope_note = "Approved-divergence ATT(g,t) multiplier-bootstrap smoke for one balanced-panel method(reg) design, with both unclustered and clustered cluster-summed influence-function paths. Stata implements the same influence-function accumulation/scaling and records seed, reps, distribution, cluster, and cband metadata; F035 guards the exact seeded BMisc/R rademacher multiplier stream. PY005/PY015 cover inherited Python clustered bootstrap smoke, RT017 covers inherited R ATT(g,t) cluster-sum bootstrap stress, and aggregation bootstrap plus inherited RT018 postprocess stress remain tracked separately."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
