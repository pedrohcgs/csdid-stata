#!/usr/bin/env Rscript
# RT060: which empty-cell warnings R raises. A cell whose treated cohort, or
# whose comparison group, has no row in EITHER of its two periods fails R's
# valid_did_cohort check and is skipped in silence (compute.att_gt2.R:463-468);
# the four corner warnings belong only to cells that pass it
# (compute.att_gt2.R:267-284). Cohort 4 is absent in periods 1 and 3 -- its
# universal base -- so cell (4,1) is empty in both periods (silent) while
# (4,2) and (4,4) are empty only in the base (warned).
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt060/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt060")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")

z <- expand.grid(i = 1:12, t = 1:4, g = c(0, 3, 4))
z$id <- z$i + 12 * match(z$g, c(0, 3, 4))
z$y <- (z$i %% 5) / 4 + 0.5 * z$t + ifelse(z$g > 0 & z$t >= z$g, 1 + (z$t - z$g) / 2, 0) +
  ((z$i * z$t) %% 7 - 3) / 8
z <- z[!(z$g == 4 & z$t %in% c(1, 3)), c("id", "t", "g", "y")]
z <- z[order(z$id, z$t), ]
rownames(z) <- NULL
write.csv(z, file.path(out, "inputs/cohort4-gaps.csv"), row.names = FALSE)

scenarios <- data.frame(scenario = c("rcs", "unbalanced"), panel = c(FALSE, TRUE), stringsAsFactors = FALSE)
warn_rows <- list(); att_rows <- list()
for (k in seq_len(nrow(scenarios))) {
  s <- scenarios[k, ]
  w <- character(0)
  a <- withCallingHandlers(did::att_gt(
      yname = "y", tname = "t", gname = "g", idname = if (s$panel) "id" else NULL, data = z,
      panel = s$panel, allow_unbalanced_panel = s$panel, control_group = "notyettreated",
      base_period = "universal", est_method = "reg", bstrap = FALSE, cband = FALSE),
    warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
  corner <- w[grepl("^No units in group|^No available control units", w)]
  tab <- if (length(corner)) as.data.frame(table(message = corner), stringsAsFactors = FALSE) else
    data.frame(message = character(0), Freq = integer(0))
  if (nrow(tab)) warn_rows[[k]] <- data.frame(scenario = s$scenario, message = tab$message, count = tab$Freq)
  att_rows[[k]] <- data.frame(scenario = s$scenario, group = a$group, time = a$t, att = a$att, se = a$se)
}
write.csv(do.call(rbind, warn_rows), file.path(out, "expected/r/warnings.csv"), row.names = FALSE)
write.csv(do.call(rbind, att_rows), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(scenarios, file.path(out, "inputs/scenarios.csv"), row.names = FALSE)
inputs <- lapply(c("inputs/cohort4-gaps.csv", "inputs/scenarios.csv"), function(p)
  list(path = p, sha256 = sha(file.path(out, p))))
outputs <- lapply(c("warnings.csv", "attgt.csv"), function(nm)
  list(path = paste0("expected/r/", nm), schema = if (nm == "attgt.csv") "attgt" else "warning-counts",
       sha256 = sha(file.path(out, "expected/r", nm))))
manifest <- list(matrix_id = "RT060", fixture_family = "r-empty-cell-warnings",
  normative_source = "did 2.5.1 compute.att_gt2.R:463-468 (valid_did_cohort: a cell with no treated or no comparison unit in either period returns NULL silently) and :267-284 (the four corner warnings)",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt060/generate.R", path = "tools/parity/generators/rt060/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "count of each corner warning csdid prints", expected = "expected/r/warnings.csv", tolerance_id = "EXACT", key_columns = c("scenario", "message")),
    list(actual = "Stata ATT(g,t) and standard errors", expected = "expected/r/attgt.csv", tolerance_id = "TOL001", key_columns = c("scenario", "group", "time"))),
  approved_divergence = NULL,
  scope_note = "Repeated cross sections and an unbalanced panel with one cohort absent from two periods, one of them its universal base.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT060 written\n")
