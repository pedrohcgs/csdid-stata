#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f047/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f047")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/new-stata"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

make_panel <- function(seed, scenario, unbalanced = FALSE) {
  set.seed(seed)
  ids <- seq_len(64)
  times <- 1:5
  cohorts <- rep(c(0, 3, 4, 5), each = 16)
  x1_unit <- rnorm(length(ids))
  x2_unit <- runif(length(ids), min = -0.8, max = 0.8)
  alpha <- rnorm(length(ids), sd = 0.35)

  d <- expand.grid(id = ids, time = times)
  d <- d[order(d$id, d$time), ]
  d$g <- rep(cohorts, each = length(times))
  d$x1 <- rep(x1_unit, each = length(times)) + 0.05 * d$time
  d$x2 <- rep(x2_unit, each = length(times)) - 0.03 * d$time
  d$w <- 0.75 + ((d$id + 2 * d$time) %% 7) / 10
  eps <- rnorm(nrow(d), sd = 0.20)
  treated <- d$g > 0 & d$time >= d$g
  d$y <- rep(alpha, each = length(times)) +
    0.25 * d$time + 0.40 * d$x1 - 0.20 * d$x2 +
    0.04 * d$x1 * d$time + eps +
    ifelse(treated, 0.65 + 0.11 * (d$time - d$g) + 0.025 * d$g, 0)
  d$scenario <- scenario
  if (unbalanced) {
    keep <- !((d$id %% 11 == 0 & d$time == 2) |
              (d$id %% 13 == 0 & d$time == 5) |
              (d$id %% 17 == 0 & d$time == 3))
    d <- d[keep, ]
  }
  d$rowid <- seq_len(nrow(d))
  d[, c("scenario", "rowid", "id", "time", "g", "y", "x1", "x2", "w")]
}

scenario_specs <- list(
  rand_101_panel_dr_never_varying_cov_w = list(
    seed = 101L,
    method = "dr",
    control_group = "nevertreated",
    base_period = "varying",
    panel = TRUE,
    stata_ivar = TRUE,
    expected_panel_mode = "panel",
    covariates = "numeric",
    weighted = TRUE,
    agg_types = c("simple", "dynamic"),
    unbalanced = FALSE
  ),
  rand_202_panel_ipw_notyet_universal_nocov = list(
    seed = 202L,
    method = "ipw",
    control_group = "notyettreated",
    base_period = "universal",
    panel = TRUE,
    stata_ivar = TRUE,
    expected_panel_mode = "panel",
    covariates = "none",
    weighted = FALSE,
    agg_types = c("simple", "dynamic"),
    unbalanced = FALSE
  ),
  rand_303_rc_reg_never_varying_cov_w = list(
    seed = 303L,
    method = "reg",
    control_group = "nevertreated",
    base_period = "varying",
    panel = FALSE,
    stata_ivar = FALSE,
    expected_panel_mode = "repeated-cross-section",
    covariates = "numeric",
    weighted = TRUE,
    agg_types = c("simple", "dynamic"),
    unbalanced = FALSE
  ),
  rand_404_unbalanced_default_dr_never_varying_cov_w = list(
    seed = 404L,
    method = "dr",
    control_group = "nevertreated",
    base_period = "varying",
    panel = TRUE,
    stata_ivar = TRUE,
    expected_panel_mode = "allow_unbalanced",
    covariates = "numeric",
    weighted = TRUE,
    agg_types = c("simple", "dynamic"),
    unbalanced = TRUE
  ),
  rand_505_rc_ipw_notyet_universal_cov = list(
    seed = 505L,
    method = "ipw",
    control_group = "notyettreated",
    base_period = "universal",
    panel = FALSE,
    stata_ivar = FALSE,
    expected_panel_mode = "repeated-cross-section",
    covariates = "numeric",
    weighted = FALSE,
    agg_types = c("simple", "dynamic"),
    unbalanced = FALSE
  )
)

agg_to_df <- function(scenario, type, agg) {
  if (type == "simple") {
    out <- data.frame(
      scenario = scenario,
      agg_type = type,
      egt = NA_real_,
      att = agg$overall.att,
      se = agg$overall.se,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  } else {
    out <- data.frame(
      scenario = scenario,
      agg_type = type,
      egt = agg$egt,
      att = agg$att.egt,
      se = agg$se.egt,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  }
  out$seq <- seq_len(nrow(out))
  out
}

att_rows <- list()
agg_rows <- list()
scenario_rows <- list()
input_rows <- list()

for (scenario in names(scenario_specs)) {
  spec <- scenario_specs[[scenario]]
  d <- make_panel(spec$seed, scenario, unbalanced = spec$unbalanced)
  input_name <- paste0(scenario, ".csv")
  write.csv(d, file.path(fixture, "inputs", input_name), row.names = FALSE, na = "")
  input_rows[[scenario]] <- d

  call_args <- list(
    yname = "y",
    tname = "time",
    gname = "g",
    data = d,
    panel = spec$panel,
    control_group = spec$control_group,
    bstrap = FALSE,
    cband = FALSE,
    est_method = spec$method,
    base_period = spec$base_period
  )
  if (spec$panel) call_args$idname <- "id"
  if (spec$panel && spec$unbalanced) call_args$allow_unbalanced_panel <- TRUE
  if (spec$covariates == "numeric") call_args$xformla <- ~ x1 + x2
  if (spec$weighted) call_args$weightsname <- "w"

  mp <- suppressWarnings(do.call(att_gt, call_args))
  att_rows[[scenario]] <- data.frame(
    scenario = scenario,
    method = spec$method,
    control_group = spec$control_group,
    base_period = spec$base_period,
    panel_mode = spec$expected_panel_mode,
    covariates = spec$covariates,
    weighted = as.integer(spec$weighted),
    group = mp$group,
    time = mp$t,
    event_time = mp$t - mp$group,
    att = mp$att,
    se = mp$se,
    inffunc_col = seq_along(mp$att),
    stringsAsFactors = FALSE
  )

  for (agg_type in spec$agg_types) {
    agg <- suppressWarnings(aggte(mp, type = agg_type, bstrap = FALSE, cband = FALSE, na.rm = TRUE))
    agg_rows[[paste(scenario, agg_type, sep = "::")]] <- agg_to_df(scenario, agg_type, agg)
  }

  scenario_rows[[scenario]] <- data.frame(
    scenario = scenario,
    input_file = input_name,
    seed = spec$seed,
    method = spec$method,
    control_group = spec$control_group,
    base_period = spec$base_period,
    r_panel = spec$panel,
    stata_ivar = spec$stata_ivar,
    expected_panel_mode = spec$expected_panel_mode,
    covariates = spec$covariates,
    weighted = as.integer(spec$weighted),
    unbalanced = spec$unbalanced,
    n_obs = nrow(d),
    n_units = length(unique(d$id)),
    stringsAsFactors = FALSE
  )
}

attgt <- do.call(rbind, att_rows)
aggte <- do.call(rbind, agg_rows)
scenarios <- do.call(rbind, scenario_rows)
all_inputs <- do.call(rbind, input_rows)

write.csv(all_inputs, file.path(fixture, "inputs/all-inputs.csv"), row.names = FALSE, na = "")
write.csv(scenarios, file.path(fixture, "expected/r/scenarios.csv"), row.names = FALSE, na = "")
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(aggte, file.path(fixture, "expected/r/aggte.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F047",
  fixture_family = "seeded-randomized-differential",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D003"),
  tolerance_ids = c("TOL002"),
  inputs = c(
    list(list(path = "inputs/all-inputs.csv", rows = nrow(all_inputs), columns = ncol(all_inputs))),
    lapply(names(scenario_specs), function(scenario) {
      list(path = paste0("inputs/", scenario, ".csv"), rows = nrow(input_rows[[scenario]]), columns = ncol(input_rows[[scenario]]))
    })
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f047/generate.R", path = "tools/parity/generators/f047/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(seed = unname(vapply(scenario_specs, `[[`, integer(1), "seed")), kind = "Mersenne-Twister", draws = "scenario-local generated panels", distribution = "normal and uniform"),
  expected_outputs = list(
    list(path = "expected/r/scenarios.csv", schema = "randomized-scenarios"),
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/aggte.csv", schema = "aggte")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "expected/new-stata/aggte.csv", expected = "expected/r/aggte.csv", tolerance_id = "TOL002", key_columns = c("scenario", "agg_type", "seq"))
  ),
  approved_divergence = NULL,
  scope_note = "Seeded small-panel randomized differential gate across balanced panel, true repeated-cross-section, and unbalanced-ivar-default-to-RC paths; dr/reg/ipw; nevertreated/notyettreated controls; varying/universal base periods; covariate/no-covariate and weighted/unweighted cells. The gate compares ATT(g,t) and simple/dynamic aggregation to R did 2.5.1 under TOL002. It is a release smoke differential test, not a replacement for exhaustive inherited R/Python suites."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
