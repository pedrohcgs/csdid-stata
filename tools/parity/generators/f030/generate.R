#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f030/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f030")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:36
times <- 1:4
d <- expand.grid(panel_id = ids, period_time = times)
d <- d[order(d$panel_id, d$period_time), ]
d$first_treat <- ifelse(d$panel_id <= 12, 3, ifelse(d$panel_id <= 24, 4, 0))
d$cluster_num <- ((d$panel_id - 1) %% 6) + 1
d$control_alpha <- 0.18 * d$period_time + 0.12 * sin(0.3 * d$panel_id)
d$control_beta <- 0.22 * cos(0.5 * d$panel_id) - 0.04 * d$period_time
d$outcome_y <- 1.1 + 0.42 * d$period_time + 0.25 * d$control_alpha -
  0.15 * d$control_beta + ifelse(d$first_treat > 0 & d$period_time >= d$first_treat,
                                  0.75 + 0.08 * (d$period_time - d$first_treat), 0) +
  0.03 * cos(d$panel_id + d$period_time)
d <- d[, c("panel_id", "period_time", "first_treat", "cluster_num",
           "control_alpha", "control_beta", "outcome_y")]
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

internal_names <- d
names(internal_names)[names(internal_names) == "panel_id"] <- "idname"
names(internal_names)[names(internal_names) == "period_time"] <- "tname"
names(internal_names)[names(internal_names) == "first_treat"] <- "gname"
internal_names$t1 <- 1
write.csv(internal_names, file.path(fixture, "inputs/internal-names.csv"), row.names = FALSE, na = "")

group_time_names <- d
names(group_time_names)[names(group_time_names) == "panel_id"] <- "unit"
names(group_time_names)[names(group_time_names) == "period_time"] <- "time"
names(group_time_names)[names(group_time_names) == "first_treat"] <- "group"
write.csv(group_time_names, file.path(fixture, "inputs/group-time-names.csv"), row.names = FALSE, na = "")

output_names <- d
names(output_names)[names(output_names) == "panel_id"] <- "id"
names(output_names)[names(output_names) == "period_time"] <- "time"
names(output_names)[names(output_names) == "first_treat"] <- "group"
output_names$att <- output_names$control_alpha
output_names$se <- output_names$control_beta
output_names$event_time <- output_names$control_alpha * output_names$control_beta
output_names$overall_att <- sin(0.11 * output_names$id) + 0.07 * output_names$time
output_names$overall_se <- cos(0.13 * output_names$id) - 0.05 * output_names$time
output_names$estimate <- output_names$att - output_names$se
output_names$std_error <- output_names$overall_att + 0.20 * output_names$overall_se
write.csv(output_names, file.path(fixture, "inputs/output-names.csv"), row.names = FALSE, na = "")

attgt_rows <- function(out, scenario, method) {
  data.frame(
    scenario = scenario,
    method = method,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    att = out$att,
    se = out$se,
    control_group = out$DIDparams$control_group,
    base_period = out$DIDparams$base_period,
    est_method = out$DIDparams$est_method,
    panel_mode = "panel",
    stringsAsFactors = FALSE
  )
}

output_formula <- ~ att + se + event_time + overall_att

out <- att_gt(
  yname = "outcome_y",
  tname = "period_time",
  idname = "panel_id",
  gname = "first_treat",
  xformla = ~ control_alpha + control_beta,
  data = d,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "varying"
)

out_internal <- att_gt(
  yname = "outcome_y",
  tname = "tname",
  idname = "idname",
  gname = "gname",
  xformla = ~ control_alpha + control_beta,
  data = internal_names,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "varying"
)

name_collision <- attgt_rows(out_internal, "internal_names_with_t1", "reg")
for (m in c("dr", "reg", "ipw")) {
  out_gt <- att_gt(
    yname = "outcome_y",
    tname = "time",
    idname = "unit",
    gname = "group",
    xformla = ~ 1,
    data = group_time_names,
    panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = m,
    base_period = "varying"
  )
  name_collision <- rbind(name_collision, attgt_rows(out_gt, "group_time_unit_names", m))
}
for (m in c("dr", "reg", "ipw")) {
  out_output <- att_gt(
    yname = "outcome_y",
    tname = "time",
    idname = "id",
    gname = "group",
    xformla = output_formula,
    data = output_names,
    panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = m,
    base_period = "varying"
  )
  name_collision <- rbind(name_collision, attgt_rows(out_output, "output_name_covariates", m))
}

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
  panel_mode = "panel",
  sample_n = nrow(d),
  inffunc_col = seq_along(out$att)
)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(name_collision, file.path(fixture, "expected/r/name-collision-attgt.csv"), row.names = FALSE, na = "")

events <- data.frame(
  event_key = c("string_outcome", "string_covariate", "string_ivar", "string_time", "string_gvar", "string_cluster"),
  return_code = c(109, 109, 198, 198, 198, 198),
  event_type = "error",
  offending_option = c("outcome_y", "control_alpha", "ivar(sid)", "time(tstr)", "gvar(gstr)", "cluster(clstr)"),
  message_normalized = c(
    "outcome variable must be numeric",
    "covariates must be numeric Stata variables; encode string covariates before using factor-variable notation",
    "ivar() must be a numeric variable; encode or destring a string identifier first",
    "time() must be numeric",
    "gvar() must be numeric",
    "cluster() must be numeric"
  ),
  stringsAsFactors = FALSE
)
write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F030",
  fixture_family = "data-types-and-names",
  normative_source = "R did 2.5.1 validation plus Stata command-surface mapping",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D010"),
  tolerance_ids = c("EXACT", "TOL001"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/internal-names.csv", rows = nrow(internal_names), columns = ncol(internal_names)),
    list(path = "inputs/group-time-names.csv", rows = nrow(group_time_names), columns = ncol(group_time_names)),
    list(path = "inputs/output-names.csv", rows = nrow(output_names), columns = ncol(output_names))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f030/generate.R", path = "tools/parity/generators/f030/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/name-collision-attgt.csv", schema = "attgt-with-scenario"),
    list(path = "expected/r/events.csv", schema = "error-warning-events-csv"),
    list(path = "expected/r/events.json", schema = "error-warning-events")
  ),
  comparison_plan = list(
    list(actual = "Stata ATT(g,t) with non-default variable names and numeric storage classes", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("group", "time")),
    list(actual = "Stata ATT(g,t) when user variables collide with internal names and output names", expected = "expected/r/name-collision-attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "method", "group", "time")),
    list(actual = "Stata captured data-type validation events", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = NULL,
  scope_note = "F030 data-type and name fixture for numeric id/time/gvar storage classes, non-default variable names, numeric controls, e() name preservation, user variables named idname/tname/gname with a harmless t1 column, user variables named group/time/unit across dr/reg/ipw, output-name covariates named att/se/event_time/overall_att across dr/reg/ipw, and explicit string outcome/covariate/ivar/time/gvar/cluster rejection. Broader inherited name-normalization stress remains tracked by RT/PY rows."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
