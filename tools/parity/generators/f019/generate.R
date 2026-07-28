#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f019/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f019")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids_t <- 1:12
ids_c <- 13:24
d <- rbind(
  data.frame(id = rep(ids_t, each = 2),
             time = rep(1:2, times = length(ids_t)),
             g = 2),
  data.frame(id = rep(ids_c, each = 2),
             time = rep(1:2, times = length(ids_c)),
             g = 0)
)
d$rowid <- seq_len(nrow(d))
d$keep <- 1L
d$y <- with(d, ifelse(g == 2,
                      0.12 * id + 0.7 * time + 1.0 * (time == 2),
                      -0.08 * id + 0.3 * time + 0.02 * id * (time == 2)))

d$keep[d$id %in% c(2, 14)] <- 0L
d$y[d$id %in% c(3, 15)] <- NA_real_

mask_reason <- function(row) {
  if (!isTRUE(row[["keep"]] == 1L)) return("if_false")
  if (is.na(row[["y"]])) return("missing_y")
  ""
}
drop_reason <- apply(d, 1, mask_reason)
included <- drop_reason == ""
sample_mask <- data.frame(
  rowid = d$rowid,
  id = d$id,
  time = d$time,
  group = d$g,
  included = included,
  drop_reason = drop_reason,
  cell_membership = ifelse(included, "analysis", "")
)

write.csv(d[, c("rowid", "id", "time", "g", "y", "keep")],
          file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")
write.csv(sample_mask, file.path(fixture, "expected/r/sample-mask.csv"),
          row.names = FALSE, na = "")

analysis_data <- subset(d, keep == 1L)
out <- suppressWarnings(att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = analysis_data,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "varying"
))

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
  sample_n = sum(included),
  inffunc_col = seq_along(out$att)
)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F019",
  fixture_family = "sample-missingness-subset",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("EXACT", "TOL001"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = 6)),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f019/generate.R", path = "tools/parity/generators/f019/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/sample-mask.csv", schema = "sample-mask"),
    list(path = "expected/r/attgt.csv", schema = "attgt")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/sample-mask.csv", expected = "expected/r/sample-mask.csv", tolerance_id = "EXACT", key_columns = c("rowid")),
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("group", "time"))
  ),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
