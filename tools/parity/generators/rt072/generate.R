#!/usr/bin/env Rscript
# RT072: distinguish absent balanced support from an empty display window,
# including a single surviving cell on an irregular calendar.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt072/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
out <- file.path(root, "tests/fixtures/parity/rt072")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
exact <- function(v) ifelse(is.na(v), "", sprintf("%.17g", v))

data(mpdta, package = "did")
mp <- mpdta[mpdta$first.treat %in% c(0, 2004), c("countyreal", "year", "first.treat", "lemp")]
names(mp) <- c("id", "time", "g", "y")
per <- c(1, 1.5, 2.2)
dz <- expand.grid(k = seq_along(per), id = 1:60)[, c("id", "k")]
dz$time <- per[dz$k]
dz$g <- ifelse(dz$id <= 30, 0, 1.5)
dz$y <- ((dz$id * 7) %% 11) / 4 + dz$k + ((dz$id * dz$k) %% 5 - 2) / 8 +
  ifelse(dz$g > 0 & dz$time >= dz$g, 1, 0)
dz <- dz[!(dz$g == 1.5 & dz$time == 1.5), c("id", "time", "g", "y")]
datasets <- list(
  onecell = mp[mp$time %in% c(2003, 2004), ],
  twocell = mp[mp$time %in% c(2003, 2004, 2005), ],
  decimal = dz)

cases <- data.frame(
  case = c("onecell_balance1", "onecell_window12", "decimal_balance0_narm", "twocell_balance1"),
  data = c("onecell", "onecell", "decimal", "twocell"),
  balance_e = c(1, NA, 0, 1),
  min_e = c(-Inf, 1, -Inf, -Inf),
  max_e = c(Inf, 2, Inf, Inf),
  na_rm = c(FALSE, FALSE, TRUE, FALSE),
  stringsAsFactors = FALSE)

inputs <- list()
for (d in names(datasets)) {
  input <- file.path("inputs", paste0(d, ".csv"))
  e <- datasets[[d]]
  for (v in c("time", "g", "y")) e[[v]] <- exact(e[[v]])
  write.csv(e, file.path(out, input), row.names = FALSE, quote = FALSE)
  inputs[[length(inputs) + 1L]] <- list(path = input, sha256 = sha(file.path(out, input)), rows = nrow(e), columns = ncol(e))
}
rows <- list(); refusals <- list()
for (k in seq_len(nrow(cases))) {
  c <- cases[k, ]
  fit <- suppressWarnings(did::att_gt(yname = "y", tname = "time", idname = "id", gname = "g",
    data = datasets[[c$data]], allow_unbalanced_panel = (c$data == "decimal"),
    control_group = "nevertreated", base_period = "varying", est_method = "reg",
    bstrap = FALSE, cband = FALSE))
  ag <- tryCatch(did::aggte(fit, type = "dynamic",
      balance_e = if (is.na(c$balance_e)) NULL else c$balance_e,
      min_e = c$min_e, max_e = c$max_e, na.rm = c$na_rm, bstrap = FALSE, cband = FALSE),
    error = function(err) conditionMessage(err))
  if (is.character(ag)) {
    refusals[[length(refusals) + 1L]] <- data.frame(case = c$case, message = ag)
    next
  }
  rows[[length(rows) + 1L]] <- data.frame(case = c$case, egt = exact(ag$egt),
    att = exact(ag$att.egt), se = exact(ag$se.egt))
}
write.csv(do.call(rbind, rows), file.path(out, "expected/r/dynamic.csv"), row.names = FALSE, quote = FALSE)
write.csv(do.call(rbind, refusals), file.path(out, "expected/r/refusals.csv"), row.names = FALSE)
write.csv(cases, file.path(out, "inputs/cases.csv"), row.names = FALSE, na = "")
inputs[[length(inputs) + 1L]] <- list(path = "inputs/cases.csv", sha256 = sha(file.path(out, "inputs/cases.csv")), rows = nrow(cases), columns = ncol(cases))
outputs <- list(
  list(path = "expected/r/dynamic.csv", schema = "aggte-dynamic", sha256 = sha(file.path(out, "expected/r/dynamic.csv"))),
  list(path = "expected/r/refusals.csv", schema = "refusal-message", sha256 = sha(file.path(out, "expected/r/refusals.csv"))))
manifest <- list(matrix_id = "RT072", fixture_family = "r-dynamic-empty-window-one-cell",
  normative_source = "did compute.aggte.R:514-550 (complete original support, then display-window restriction)",
  source_commit = "48863b646e657f2aaa5cc9e9d2e7b9d764a6a44e", decision_refs = list(),
  tolerance_ids = c("EXACT", "TOL001"), inputs = inputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt072/generate.R", path = "tools/parity/generators/rt072/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = NULL, expected_outputs = outputs,
  comparison_plan = list(
    list(actual = "csdid_stats dynamic refuses with rc 498 and the matching support/window diagnosis on every case R stops on", expected = "expected/r/refusals.csv", tolerance_id = "EXACT", key_columns = c("case")),
    list(actual = "the control keeps R's event times, effects and standard errors", expected = "expected/r/dynamic.csv", tolerance_id = "TOL001", key_columns = c("case", "egt"))),
  approved_divergence = NULL,
  scope_note = "mpdta (did's own copy) cut to 2003-2004 and 2003-2005 with cohorts 0 and 2004 under base_period varying; a three-period decimal axis {1, 1.5, 2.2} with cohort 1.5 unobserved at 1.5 under bal(none) and dropmissing.")
jsonlite::write_json(manifest, file.path(out, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT072 written:", nrow(do.call(rbind, rows)), "rows,", length(refusals), "refusals.\n")
