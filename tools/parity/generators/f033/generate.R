#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(DRDID))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f033/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f033")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:48
base <- data.frame(id = ids)
base$g <- ifelse(base$id <= 24, 2, 0)
base$x1_unit <- sin(base$id * 0.37) + 0.10 * (base$id %% 4)
base$x2_unit <- cos(base$id * 0.23) - 0.05 * (base$id %% 5)
base$w_unit <- 1 + 0.04 * (base$id %% 7)

d <- do.call(rbind, lapply(1:2, function(tt) transform(base, time = tt)))
d <- d[order(d$id, d$time), ]
d$x1 <- d$x1_unit + 0.20 * (d$time == 2)
d$x2 <- d$x2_unit - 0.15 * (d$time == 2)
d$y0 <- 1 + 0.55 * d$time + 0.45 * d$x1 - 0.25 * d$x2 + 0.03 * cos(d$id + d$time)
d$te <- ifelse(d$g == 2 & d$time == 2, 0.90 + 0.08 * d$x1_unit - 0.05 * d$x2_unit, 0)
d$y <- d$y0 + d$te
d$w <- d$w_unit
d <- d[, c("id", "time", "g", "y", "x1", "x2", "w")]
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

wide <- reshape(d, idvar = "id", timevar = "time", direction = "wide")
wide <- wide[order(wide$id), ]
D_panel <- as.numeric(wide$g.1 == 2)
D_rc <- as.numeric(d$g == 2)
post_rc <- as.numeric(d$time == 2)

panel_functions <- c(dr = "drdid_panel", reg = "reg_did_panel", ipw = "std_ipw_did_panel")
rc_functions <- c(dr = "drdid_rc", reg = "reg_did_rc", ipw = "std_ipw_did_rc")
scenarios <- list(
  panel_intercept = list(
    panel = TRUE,
    covariates = "intercept",
    weights = TRUE,
    X = matrix(1, nrow = nrow(wide), ncol = 1),
    trim_level = 0.995,
    methods = names(panel_functions)
  ),
  panel_intercept_unweighted = list(
    panel = TRUE,
    covariates = "intercept",
    weights = FALSE,
    X = matrix(1, nrow = nrow(wide), ncol = 1),
    trim_level = 0.995,
    methods = names(panel_functions)
  ),
  panel_covariates = list(
    panel = TRUE,
    covariates = "x1_x2",
    weights = TRUE,
    X = cbind(Intercept = 1, x1 = wide$x1.1, x2 = wide$x2.1),
    trim_level = 0.995,
    methods = names(panel_functions)
  ),
  panel_covariates_unweighted = list(
    panel = TRUE,
    covariates = "x1_x2",
    weights = FALSE,
    X = cbind(Intercept = 1, x1 = wide$x1.1, x2 = wide$x2.1),
    trim_level = 0.995,
    methods = names(panel_functions)
  ),
  panel_covariates_trim07 = list(
    panel = TRUE,
    covariates = "x1_x2",
    weights = TRUE,
    X = cbind(Intercept = 1, x1 = wide$x1.1, x2 = wide$x2.1),
    trim_level = 0.700,
    methods = c("dr", "ipw")
  ),
  rc_intercept = list(
    panel = FALSE,
    covariates = "intercept",
    weights = TRUE,
    X = matrix(1, nrow = nrow(d), ncol = 1),
    trim_level = 0.995,
    methods = names(panel_functions)
  ),
  rc_intercept_unweighted = list(
    panel = FALSE,
    covariates = "intercept",
    weights = FALSE,
    X = matrix(1, nrow = nrow(d), ncol = 1),
    trim_level = 0.995,
    methods = names(panel_functions)
  ),
  rc_covariates = list(
    panel = FALSE,
    covariates = "x1_x2",
    weights = TRUE,
    X = cbind(Intercept = 1, x1 = d$x1, x2 = d$x2),
    trim_level = 0.995,
    methods = names(panel_functions)
  ),
  rc_covariates_unweighted = list(
    panel = FALSE,
    covariates = "x1_x2",
    weights = FALSE,
    X = cbind(Intercept = 1, x1 = d$x1, x2 = d$x2),
    trim_level = 0.995,
    methods = names(panel_functions)
  ),
  rc_covariates_trim07 = list(
    panel = FALSE,
    covariates = "x1_x2",
    weights = TRUE,
    X = cbind(Intercept = 1, x1 = d$x1, x2 = d$x2),
    trim_level = 0.700,
    methods = c("dr", "ipw")
  )
)

rows <- list()
for (scenario in names(scenarios)) {
  spec <- scenarios[[scenario]]
  for (method in spec$methods) {
    if (spec$panel) {
      fn <- get(panel_functions[[method]], asNamespace("DRDID"))
      call_args <- list(
        y1 = wide$y.2,
        y0 = wide$y.1,
        D = D_panel,
        covariates = spec$X,
        boot = FALSE,
        inffunc = TRUE
      )
      if (spec$weights) call_args$i.weights <- wide$w.1
      if (method != "reg") call_args$trim.level <- spec$trim_level
      out <- do.call(fn, call_args)
      nobs <- length(D_panel)
      panel_mode <- "panel"
      direct_function <- panel_functions[[method]]
    } else {
      fn <- get(rc_functions[[method]], asNamespace("DRDID"))
      call_args <- list(
        y = d$y,
        post = post_rc,
        D = D_rc,
        covariates = spec$X,
        boot = FALSE,
        inffunc = TRUE
      )
      if (spec$weights) call_args$i.weights <- d$w
      if (method != "reg") call_args$trim.level <- spec$trim_level
      out <- do.call(fn, call_args)
      nobs <- length(D_rc)
      panel_mode <- "repeated-cross-section"
      direct_function <- rc_functions[[method]]
    }

    rows[[length(rows) + 1]] <- data.frame(
      scenario = scenario,
      panel_mode = panel_mode,
      covariates = spec$covariates,
      method = method,
      direct_function = direct_function,
      weight_var = ifelse(spec$weights, "w", "none"),
      pscoretrim = spec$trim_level,
      group = 2,
      time = 2,
      event_time = 0,
      att = out$ATT,
      se = out$se,
      nobs = nobs,
      stringsAsFactors = FALSE
    )
  }
}
direct_grid <- do.call(rbind, rows)
write.csv(direct_grid, file.path(fixture, "expected/r/drdid-direct-grid.csv"), row.names = FALSE, na = "")

alt_rows <- list()
add_alt <- function(scenario, method, alternative_function, alt_out) {
  target <- direct_grid[direct_grid$scenario == scenario & direct_grid$method == method, ]
  alt_rows[[length(alt_rows) + 1]] <<- data.frame(
    scenario = scenario,
    panel_mode = target$panel_mode,
    covariates = target$covariates,
    method = method,
    target_function = target$direct_function,
    alternative_function = alternative_function,
    group = target$group,
    time = target$time,
    event_time = target$event_time,
    target_att = target$att,
    target_se = target$se,
    alternative_att = alt_out$ATT,
    alternative_se = alt_out$se,
    abs_delta_att = abs(target$att - alt_out$ATT),
    abs_delta_se = abs(target$se - alt_out$se),
    stringsAsFactors = FALSE
  )
}

add_alt(
  "panel_covariates", "dr", "drdid_imp_panel",
  DRDID::drdid_imp_panel(
    y1 = wide$y.2,
    y0 = wide$y.1,
    D = D_panel,
    covariates = scenarios$panel_covariates$X,
    i.weights = wide$w.1,
    boot = FALSE,
    inffunc = TRUE
  )
)
add_alt(
  "panel_covariates", "ipw", "ipw_did_panel",
  DRDID::ipw_did_panel(
    y1 = wide$y.2,
    y0 = wide$y.1,
    D = D_panel,
    covariates = scenarios$panel_covariates$X,
    i.weights = wide$w.1,
    boot = FALSE,
    inffunc = TRUE
  )
)
add_alt(
  "rc_covariates", "dr", "drdid_imp_rc",
  DRDID::drdid_imp_rc(
    y = d$y,
    post = post_rc,
    D = D_rc,
    covariates = scenarios$rc_covariates$X,
    i.weights = d$w,
    boot = FALSE,
    inffunc = TRUE
  )
)
add_alt(
  "rc_covariates", "dr", "drdid_rc1",
  DRDID::drdid_rc1(
    y = d$y,
    post = post_rc,
    D = D_rc,
    covariates = scenarios$rc_covariates$X,
    i.weights = d$w,
    boot = FALSE,
    inffunc = TRUE
  )
)
add_alt(
  "rc_covariates", "dr", "drdid_imp_rc1",
  DRDID::drdid_imp_rc1(
    y = d$y,
    post = post_rc,
    D = D_rc,
    covariates = scenarios$rc_covariates$X,
    i.weights = d$w,
    boot = FALSE,
    inffunc = TRUE
  )
)
add_alt(
  "rc_covariates", "ipw", "ipw_did_rc",
  DRDID::ipw_did_rc(
    y = d$y,
    post = post_rc,
    D = D_rc,
    covariates = scenarios$rc_covariates$X,
    i.weights = d$w,
    boot = FALSE,
    inffunc = TRUE
  )
)
alternative_grid <- do.call(rbind, alt_rows)
write.csv(alternative_grid, file.path(fixture, "expected/r/drdid-alternative-grid.csv"), row.names = FALSE, na = "")

divergence <- data.frame(
  divergence_id = "F033-DIV001",
  surface = "raw-drdid-api-internals",
  reason = "The Stata port exposes csdid command behavior, not a raw DRDID function API. The fixture verifies the R did 2.5.1 target DRDID functions and diagnostic alternatives for the public ATT(g,t) boundary; broader raw DRDID failure-propagation and bootstrap internals are covered through command-level validation/bootstrap gates rather than a separate public Stata callback surface.",
  accepted_behavior = "Stata must match the R did target 2x2 functions for weighted/unweighted panel and repeated-cross-section dr/reg/ipw cells, pscoretrim(.7), and must not silently switch to improved DRDID, RC1, or unnormalized-IPW alternatives.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "F033",
  fixture_family = "drdid-boundary",
  normative_source = "R DRDID 1.3.0 as used by R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("TOL001"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f033/generate.R", path = "tools/parity/generators/f033/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/drdid-direct-grid.csv", schema = "drdid-direct-grid"),
    list(path = "expected/r/drdid-alternative-grid.csv", schema = "drdid-alternative-diagnostic-grid"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "Stata csdid single 2x2 ATT(g,t)", expected = "expected/r/drdid-direct-grid.csv", tolerance_id = "TOL001", key_columns = c("scenario", "method", "group", "time")),
    list(actual = "Stata csdid function-boundary diagnostic", expected = "expected/r/drdid-alternative-grid.csv", tolerance_id = "TOL001", key_columns = c("scenario", "method", "alternative_function", "group", "time"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "Approved-divergence direct DRDID-boundary fixture for one two-period design covering weighted and unweighted panel/repeated-cross-section, intercept/covariate, dr/reg/ipw normalized-IPW cells, nondefault pscoretrim(.7) trimming for weighted covariate DR/IPW cells, and diagnostic contrasts that prove Stata matches the R did target DRDID functions rather than improved DRDID, RC1, or unnormalized IPW alternatives. Raw DRDID helper internals that are not public Stata command surfaces are recorded in F033-DIV001."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
