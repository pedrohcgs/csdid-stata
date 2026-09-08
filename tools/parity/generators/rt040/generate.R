#!/usr/bin/env Rscript
# RT040: R fixes its cohort grid/control availability before full balancing.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt040/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt040")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
scenarios <- list()
add <- function(shape, base, control = "notyettreated", defaults = FALSE, weighted = FALSE, anticipation = 0L) {
  name <- paste(shape, base, if (control == "nevertreated") "never" else if (defaults) "default" else if (weighted) "weighted" else "notyet", sep = "_")
  covariate <- shape %in% c("covariate_missing", "treated_covariate_missing", "dead_first", "anticipation")
  options <- if (defaults) "" else paste("bal(full)", if (control == "nevertreated") "nevertreated" else "notyet", paste0("base_period(", base, ")"))
  if (weighted) options <- paste(options, "cluster(cl)")
  if (anticipation > 0) options <- paste(options, paste0("anticipation(", anticipation, ")"))
  refused <- shape %in% c("treated_removed", "all_treated_removed", "treated_covariate_missing", "never_treated_removed", "never_latest_removed", "effective_never_treated_removed", "no_never_treated_removed")
  scenarios[[length(scenarios) + 1L]] <<- data.frame(scenario = name, shape, base, control, defaults, weighted, anticipation, covariate, refused, stata_options = options)
}
for (shape in c("row_absent", "covariate_missing", "latest_removed", "treated_removed", "all_treated_removed", "effective_never", "dead_first", "early_shift")) {
  for (base in c("varying", "universal")) add(shape, base)
}
for (shape in c("row_absent", "covariate_missing")) {
  add(shape, "universal", defaults = TRUE)
  add(shape, "varying", weighted = TRUE)
  for (base in c("varying", "universal")) add(shape, base, control = "nevertreated")
}
for (base in c("varying", "universal")) add("anticipation", base, anticipation = 1L)
for (shape in c("treated_removed", "all_treated_removed")) for (base in c("varying", "universal")) add(shape, base, control = "nevertreated")
for (shape in c("treated_covariate_missing", "never_treated_removed", "never_latest_removed", "effective_never_treated_removed", "no_never_treated_removed")) {
  for (control in c("notyettreated", "nevertreated")) for (base in c("varying", "universal")) add(shape, base, control)
}
for (shape in c("first_period_removed", "surviving_fold", "common_dead_period")) for (base in c("varying", "universal")) add(shape, base)
for (control in c("notyettreated", "nevertreated")) for (base in c("varying", "universal")) add("cutoff_only_cohort", base, control)
scenarios <- do.call(rbind, scenarios)
make_data <- function(shape) {
  periods <- if (shape %in% c("row_absent", "covariate_missing")) 4L else 5L
  cohorts <- switch(shape, cutoff_only_cohort = c(2, 3, 4), first_period_removed = c(1, 0, 3, 4), surviving_fold = c(3, 3, 4, 5), latest_removed = c(3, 3, 4, 5), effective_never = c(6, 3, 4, 5), dead_first = c(0, 3, 4, 5), early_shift = c(1, 0, 3, 4, 5), anticipation = c(0, 3, 4, 5), c(0, 2, 3, 4))
  d <- expand.grid(id = seq_len(10L * length(cohorts)), time = seq_len(periods))
  d$g <- rep(cohorts, each = 10L)[d$id]
  d$x <- ((d$id^2 + 3 * d$time) %% 17) / 16
  d$y <- d$id * d$time / 64 + ((d$id * d$time) %% 11) / 8 + (d$g > 0 & d$time >= d$g) / 2
  d$w <- 1 + (d$id %% 3) / 4
  d$cl <- 1 + d$id %% 8
  if (shape == "row_absent") d <- d[!(d$g == 0 & d$time == 1), ]
  if (shape %in% c("covariate_missing", "anticipation")) d$x[d$g == 0 & d$time == 1] <- NA_real_
  if (shape == "latest_removed") d <- d[!(d$g == 5 & d$time == 2), ]
  if (shape == "treated_removed") d <- d[!(d$g == 2 & d$time == 3), ]
  if (shape == "all_treated_removed") d <- d[!(d$g > 0 & d$time == 3), ]
  if (shape == "effective_never") d <- d[!(d$g == 6 & d$time == 2), ]
  if (shape == "dead_first") d$x[d$time == 1 | (d$g == 0 & d$time == 2)] <- NA_real_
  if (shape == "early_shift") d <- d[(d$g == 1 & d$time == 1) | (d$g != 1 & d$time > 1 & !(d$g == 0 & d$time == 2)), ]
  if (shape == "treated_covariate_missing") d$x[d$g == 2 & d$time == 3] <- NA_real_
  if (shape == "never_treated_removed") d <- d[!(d$g %in% c(0, 2) & d$time == 2), ]
  if (shape == "never_latest_removed") d <- d[!(d$g %in% c(0, 4) & d$time == 2), ]
  if (shape == "effective_never_treated_removed") {
    d$g[d$g == 0] <- 6
    d <- d[!(d$g %in% c(6, 2) & d$time == 2), ]
  }
  if (shape == "no_never_treated_removed") d <- d[d$g != 0 & !(d$g == 2 & d$time == 2), ]
  if (shape == "first_period_removed") d <- d[!(d$g == 1 & d$time == 2), ]
  if (shape == "cutoff_only_cohort") d <- d[!(d$g == 3 & d$time < 4), ]
  if (shape == "common_dead_period") d <- d[d$time != 2, ]
  if (shape == "surviving_fold") d <- d[(d$time %in% c(1, 2) & !(d$g == 5 & d$time == 2)) | (d$g == 5 & d$time == 5), ]
  d <- d[order(d$id, d$time), ]; rownames(d) <- NULL
  d
}
attout <- ifout <- sampleout <- metaout <- aggout <- statusout <- fastout <- inputs <- list()
one <- function(x) if (length(x)) as.numeric(x[[1]]) else NA_real_
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]; d <- make_data(s$shape)
  input <- file.path("inputs", paste0(s$scenario, ".csv"))
  write.csv(d, file.path(out, input), row.names = FALSE, na = "")
  inputs[[k]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(d), columns = ncol(d))
  # Approved D6.7 is precisely the never-treated case: csdid applies the
  # reference fallback on its balanced sample. Not-yet-treated uses raw data.
  approved_fallback <- s$control == "nevertreated" && s$shape %in% c("row_absent", "covariate_missing")
  q <- if (approved_fallback) d[d$g != 0, ] else d
  run <- function(fast = NULL) {
    call <- list(yname = "y", tname = "time", gname = "g", idname = "id", data = q,
      xformla = if (s$covariate) ~x else ~1, weightsname = if (s$weighted) "w" else NULL,
      clustervars = if (s$weighted) "cl" else NULL, panel = TRUE, allow_unbalanced_panel = FALSE,
      control_group = s$control, base_period = s$base, anticipation = s$anticipation,
      est_method = "reg", bstrap = FALSE, cband = FALSE)
    if (!is.null(fast)) call$faster_mode <- fast
    suppressWarnings(do.call(did::att_gt, call))
  }
  a <- tryCatch(run(), error = function(e) e)
  failed <- inherits(a, "error")
  stopifnot(identical(failed, s$refused))
  fastout[[k]] <- data.frame(scenario = s$scenario, failed = as.integer(failed),
    message = if (failed) conditionMessage(a) else "", approved_fallback = as.integer(approved_fallback))
  if (failed) {
    stopifnot(grepl("not found in cohort_vec", conditionMessage(a), fixed = TRUE))
    next
  }
  slow <- run(FALSE)
  stopifnot(identical(a$group, slow$group), identical(a$t, slow$t), identical(is.na(a$att), is.na(slow$att)), identical(is.na(a$se), is.na(slow$se)))
  stopifnot(all(abs(a$att - slow$att) <= 1e-10 + 1e-10 * abs(a$att), na.rm = TRUE), all(abs(a$se - slow$se) <= 1e-10 + 1e-10 * abs(a$se), na.rm = TRUE))
  inf <- as.matrix(a$inffunc)
  ids <- unique(a$DIDparams$data[[a$DIDparams$idname]])
  stopifnot(length(ids) == nrow(inf), !anyDuplicated(ids))
  inf <- inf[order(ids), , drop = FALSE]
  used <- a$DIDparams$data[, c("id", "time")]
  used <- as.data.frame(used)[order(used$id, used$time), ]
  attout[[k]] <- data.frame(scenario = s$scenario, group = a$group, time = a$t, att = a$att, se = a$se)
  ifout[[k]] <- data.frame(scenario = s$scenario, unit_index = rep(seq_len(nrow(inf)), ncol(inf)), group = rep(a$group, each = nrow(inf)), time = rep(a$t, each = nrow(inf)), value = as.vector(inf))
  sampleout[[k]] <- data.frame(scenario = s$scenario, used)
  metaout[[k]] <- data.frame(scenario = s$scenario, n_obs = nrow(used), n_units = a$n, n_time = length(unique(used$time)), n_cells = length(a$att), wald = one(a$W), wald_pval = one(a$Wpval))
  for (type in c("simple", "group", "calendar", "dynamic")) for (na_rm in c(FALSE, TRUE)) {
    agg <- tryCatch(suppressWarnings(did::aggte(a, type = type, na.rm = na_rm, bstrap = FALSE, cband = FALSE)), error = function(e) e)
    failed <- inherits(agg, "error")
    statusout[[length(statusout) + 1L]] <- data.frame(scenario = s$scenario, type, na_rm = as.integer(na_rm), failed = as.integer(failed), message = if (failed) conditionMessage(agg) else "")
    if (!failed) {
      n <- if (type == "simple") 1L else length(agg$att.egt)
      aggout[[length(aggout) + 1L]] <- data.frame(scenario = s$scenario, type, na_rm = as.integer(na_rm), seq = seq_len(n), egt = if (type == "simple") NA_real_ else agg$egt, att = if (type == "simple") agg$overall.att else agg$att.egt, se = if (type == "simple") agg$overall.se else agg$se.egt, overall_att = agg$overall.att, overall_se = agg$overall.se)
    }
  }
}
unlink(file.path(out, "expected/r/reference_fast_status.csv"))
outputs <- list(attgt = attout, inffunc = ifout, sample = sampleout, meta = metaout, aggte = aggout, aggregation_status = statusout, estimation_status = fastout)
for (nm in names(outputs)) write.csv(do.call(rbind, outputs[[nm]]), file.path(out, "expected/r", paste0(nm, ".csv")), row.names = FALSE, na = "")
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE, na = "")
inputs[[length(inputs) + 1L]] <- list(path = "inputs/scenarios.csv", sha256 = sha(file.path(out, "inputs/scenarios.csv")), rows = nrow(scenarios), columns = ncol(scenarios))
expected <- lapply(names(outputs), function(nm) list(path = paste0("expected/r/", nm, ".csv"), schema = nm, rows = nrow(do.call(rbind, outputs[[nm]])), sha256 = sha(file.path(out, "expected/r", paste0(nm, ".csv")))))
manifest <- list(matrix_id = "RT040", fixture_family = "r-grid-before-full-balance",
  normative_source = "did 2.5.1 pre_process_did.R and pre_process_did2.R: row complete cases, fixed cohort/control grid, then whole-unit balancing",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = c("D026", "approved divergence 6.7"), tolerance_ids = c("EXACT", "TOL001", "TOL002"),
  inputs = inputs, expected_outputs = expected,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt040/generate.R", path = "tools/parity/generators/rt040/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))), rng = NULL,
  comparison_plan = list(list(actual = "Every ATT/SE, unit IF, estimation-sample key, and sample dimension", expected = c("attgt.csv", "inffunc.csv", "sample.csv", "meta.csv"), tolerance_ids = c("EXACT", "TOL001", "TOL002")), list(actual = "All four aggregation types with and without dropmissing: verdicts and every effect/overall ATT/SE", expected = c("aggregation_status.csv", "aggte.csv"), tolerance_ids = c("EXACT", "TOL001", "TOL002"))),
  scope_note = "Normative results and refusals are from the default did 2.5.1 call. Successful grids are cross-checked against its slow path; no slow-only grid is substituted for a default refusal. Coverage includes comparison-unit removal, actual eligible treated-cohort loss under both comparison groups, excluded first-period/latest/future groups, surviving cohorts beyond a shortened horizon, dead periods, anticipation, weights/clustering and defaults. The four declared never-only fallback witnesses use the approved balanced-sample reference. Estimation refusal assertions are recorded in estimation_status.csv.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT040:", nrow(scenarios), "scenarios;", paste(vapply(outputs, function(x) nrow(do.call(rbind, x)), integer(1)), collapse = ", "), "rows in", paste(names(outputs), collapse = ", "), "\n")
