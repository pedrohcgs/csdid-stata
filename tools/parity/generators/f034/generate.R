#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f034/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f034")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/new-stata"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:36
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 12, 3, ifelse(d$id <= 24, 4, 0))
d$x1 <- 0.35 * d$time + 0.20 * sin(0.7 * d$id) + 0.10 * (d$id %% 3 == 0)
d$x2 <- 0.20 * d$time + 0.25 * cos(0.5 * d$id) - 0.08 * (d$id %% 4 == 0)
d$y0 <- 1.0 + 0.55 * d$time + 0.35 * d$x1 - 0.15 * d$x2 + 0.05 * cos(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.9 + 0.12 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

scenario_specs <- list(
  panel_reg = list(panel = TRUE, method = "reg"),
  rc_reg = list(panel = FALSE, method = "reg")
)

summarize_inffunc <- function(scenario, out) {
  inf <- as.matrix(out$inffunc)
  sumsq <- colSums(inf^2)
  data.frame(
    scenario = scenario,
    group = out$group,
    time = out$t,
    event_time = out$t - out$group,
    inffunc_col = seq_along(out$att),
    n_rows = nrow(inf),
    sum = colSums(inf),
    sumsq = sumsq,
    min = apply(inf, 2, min),
    max = apply(inf, 2, max),
    nonzero_count = colSums(abs(inf) > 1e-12),
    se_from_if = sqrt(sumsq) / nrow(inf)
  )
}

summary_rows <- list()
for (scenario in names(scenario_specs)) {
  spec <- scenario_specs[[scenario]]
  call_args <- list(
    yname = "y",
    tname = "time",
    gname = "g",
    data = d,
    panel = spec$panel,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = spec$method,
    base_period = "varying"
  )
  if (spec$panel) call_args$idname <- "id"
  out <- do.call(att_gt, call_args)
  summary_rows[[scenario]] <- summarize_inffunc(scenario, out)
}
inffunc_summary <- do.call(rbind, summary_rows)
write.csv(inffunc_summary, file.path(fixture, "expected/r/rif-summary.csv"), row.names = FALSE, na = "")

artifact_schema <- list(
  matrix_id = "F034",
  fixture_family = "saved-rif-artifacts",
  wide_rif_dataset = list(
    required_variables = c("rif_row", "id", "group", paste0("rif", 1:6)),
    required_characteristics = c(
      "csdid_artifact",
      "csdid_cmdline",
      "csdid_panel_mode",
      "csdid_control_group",
      "csdid_base_period",
      "csdid_method",
      "csdid_N",
      "csdid_N_units",
      "csdid_N_attgt",
      "csdid_N_groups",
      "csdid_N_time",
      "csdid_anticipation",
      "csdid_level"
    ),
    required_rif_characteristics = c("csdid_attgt"),
    rif_column_labels = "RIF group=<group> time=<time> event_time=<event_time>"
  ),
  scope_note = "Partial saverif() artifact schema, numeric RIF summary parity, and csdid_stats reload parity for panel and true repeated-cross-section no-covariate reg scenarios. Full postestimation artifact workflows remain incomplete."
)
writeLines(
  jsonlite::toJSON(artifact_schema, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/saverif-schema.json")
)

divergence <- data.frame(
  divergence_id = "F034-DIV001",
  surface = "stata-saverif-artifact-extension",
  reason = "R did exposes MP objects and influence-function matrices in R memory, while Stata needs a durable saverif() dataset and csdid_stats using reload workflow. The saved-RIF file format is therefore a Stata extension rather than an R object surface.",
  accepted_behavior = "The saved RIF dataset must preserve R influence-function summaries, required Stata schema/characteristics, no-replace protection, and simple/group/calendar/dynamic csdid_stats reload parity for panel and repeated-cross-section command results.",
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

manifest <- list(
  matrix_id = "F034",
  fixture_family = "saved-rif-artifacts",
  normative_source = "R did 2.5.1 influence functions plus retained Stata saverif() artifact contract",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D014"),
  tolerance_ids = c("TOL002", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f034/generate.R", path = "tools/parity/generators/f034/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/rif-summary.csv", schema = "inffunc-summary"),
    list(path = "expected/new-stata/saverif-schema.json", schema = "saved-rif-artifact"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence")
  ),
  comparison_plan = list(
    list(actual = "saved Stata RIF summary", expected = "expected/r/rif-summary.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time", "inffunc_col")),
    list(actual = "saved Stata RIF dataset schema", expected = "expected/new-stata/saverif-schema.json", tolerance_id = "EXACT", key_columns = c("variable", "characteristic"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "Approved-divergence saverif() artifact schema, numeric RIF summary parity, and csdid_stats reload parity for panel and true repeated-cross-section no-covariate reg scenarios. F034-DIV001 records that persisted RIF datasets are a Stata extension that must preserve R influence-function content rather than byte-match an R object format."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
