#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f025/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f025")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:48
times <- 1:4
gmap <- c(rep(3, 16), rep(4, 16), rep(0, 16))
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- rep(gmap, each = length(times))
id_eff <- (d$id %% 7) * 0.11
time_eff <- d$time * 0.4
treat <- ifelse(d$g > 0 & d$time >= d$g,
                0.8 + 0.2 * (d$time - d$g) + 0.03 * d$g,
                0)
d$y <- id_eff + time_eff + treat + 0.02 * d$id * (d$time == 4)

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

mp <- att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  base_period = "varying"
)

agg_to_df <- function(scenario, agg) {
  if (is.null(agg$egt)) {
    return(data.frame(
      scenario = scenario,
      egt = NA_real_,
      att = agg$overall.att,
      se = agg$overall.se,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se,
      type = agg$type
    ))
  }
  data.frame(
    scenario = scenario,
    egt = agg$egt,
    att = agg$att.egt,
    se = agg$se.egt,
    overall_att = agg$overall.att,
    overall_se = agg$overall.se,
    type = agg$type
  )
}

mp_dynamic_na <- mp
mp_dynamic_na$att[1] <- NA_real_
mp_dynamic_na$inffunc[, 1] <- NA_real_

mp_group_na <- mp
g_first <- sort(unique(mp_group_na$group))[1]
group_na <- which(mp_group_na$group == g_first & mp_group_na$t == g_first)
mp_group_na$att[group_na] <- NA_real_
mp_group_na$inffunc[, group_na] <- NA_real_

expected <- rbind(
  agg_to_df("dynamic_window", suppressWarnings(aggte(mp, type = "dynamic", min_e = -1, max_e = 0, bstrap = FALSE, cband = FALSE))),
  agg_to_df("dynamic_balance", suppressWarnings(aggte(mp, type = "dynamic", balance_e = 1, bstrap = FALSE, cband = FALSE))),
  agg_to_df("simple_maxe", suppressWarnings(aggte(mp, type = "simple", max_e = 0, bstrap = FALSE, cband = FALSE))),
  agg_to_df("group_maxe", suppressWarnings(aggte(mp, type = "group", max_e = 0, bstrap = FALSE, cband = FALSE))),
  agg_to_df("calendar_ignored", suppressWarnings(aggte(mp, type = "calendar", min_e = -1, max_e = 0, balance_e = 1, bstrap = FALSE, cband = FALSE))),
  agg_to_df("dynamic_na_rm", suppressWarnings(aggte(mp_dynamic_na, type = "dynamic", na.rm = TRUE, bstrap = FALSE, cband = FALSE))),
  agg_to_df("group_na_rm_maxe", suppressWarnings(aggte(mp_group_na, type = "group", max_e = 0, na.rm = TRUE, bstrap = FALSE, cband = FALSE)))
)
write.csv(expected, file.path(fixture, "expected/r/aggte-windows.csv"), row.names = FALSE, na = "")

events <- list(
  list(
    scenario = "dynamic_missing_default",
    action = "aggte dynamic after injected missing ATT with na.rm FALSE",
    expected_error_key = "Missing values",
    expected_rc = NA
  )
)
writeLines(jsonlite::toJSON(events, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F025",
  fixture_family = "aggte-window-options",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001"),
  tolerance_ids = c("TOL001", "EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f025/generate.R", path = "tools/parity/generators/f025/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/aggte-windows.csv", schema = "aggte-window-options"),
    list(path = "expected/r/events.json", schema = "events")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/aggte-windows.csv", expected = "expected/r/aggte-windows.csv", tolerance_id = "TOL001", key_columns = c("scenario", "seq")),
    list(actual = "expected/new-stata/events.json", expected = "expected/r/events.json", tolerance_id = "EXACT", key_columns = c("scenario"))
  ),
  approved_divergence = NULL
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
