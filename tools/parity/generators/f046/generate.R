#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f046/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f046")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/new-stata"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:36
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 12, 3, ifelse(d$id <= 24, 4, 0))
d$y0 <- 1.1 + 0.35 * d$time + 0.08 * sin(d$id) + 0.04 * (d$id %% 5)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.6 + 0.08 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

events <- data.frame(
  event_key = c(
    "method_dripw_warning",
    "method_stdipw_warning",
    "asinr_warning",
    "wboot_mammen_error"
  ),
  return_code = c(0, 0, 0, 498),
  event_type = c("warning", "warning", "warning", "error"),
  offending_option = c(
    "method(dripw)",
    "method(stdipw)",
    "asinr",
    "wboot(wbtype(mammen))"
  ),
  message_normalized = c(
    "csdid legacy compatibility: method(dripw) is soft-deprecated; using R-compatible method(dr)",
    "csdid legacy compatibility: method(stdipw) is soft-deprecated; using R-compatible method(ipw)",
    "csdid legacy compatibility: asinr is accepted as a no-op; R-compatible not-yet selection is governed by notyet",
    "wboot() currently supports only R-compatible rademacher multipliers"
  ),
  canonical_behavior = c(
    "method=dr",
    "method=ipw",
    "no-op",
    "unsupported multiplier"
  ),
  stringsAsFactors = FALSE
)
write.csv(events, file.path(fixture, "expected/new-stata/events.csv"), row.names = FALSE, na = "")
writeLines(
  jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/events.json")
)

migration <- data.frame(
  gate = c(
    "retained_alias",
    "retained_alias",
    "retained_alias",
    "retained_alias",
    "unsupported_alias",
    "retained_alias",
    "retained_alias",
    "unsupported_default",
    "default_contract",
    "empirical_contract"
  ),
  surface = c(
    "method(dripw)",
    "method(stdipw)",
    "asinr",
    "wboot(wtype(rademacher))",
    "wboot(wbtype(mammen))",
    "bal()/balance()",
    "long/long2",
    "dryrun",
    "unbalanced ivar()",
    "JEL-DiD"
  ),
  classification = c(
    "soft-deprecated-alias",
    "soft-deprecated-alias",
    "accepted-no-op-warning",
    "soft-deprecated-alias",
    "unsupported-by-design",
    "soft-deprecated-alias",
    "deprecated-universal-base-event-alias",
    "unsupported-by-design",
    "r-compatible-default",
    "release-blocking-replication"
  ),
  canonical_behavior = c(
    "method=dr",
    "method=ipw",
    "no-op; notyet governs not-yet controls",
    "boot_dist=rademacher;boot_dist_requested=rademacher",
    "exit 498; only rademacher multipliers are supported",
    "accept with warning; no-op mapped to D003 allow_unbalanced default",
    "accept with strong warning; use baseperiod(universal) when baseperiod() is omitted",
    "reject internal legacy option",
    "use repeated-cross-section computation path with panel standard-error accounting",
    "replicate all frozen table and figure artifacts before release"
  ),
  evidence = c(
    "F010;F045;F046",
    "F010;F045;F046",
    "F017;F045;F046",
    "F035;F046",
    "F035;F046",
    "F016;F017;F045",
    "F017;F045;F036;JEL",
    "F036;F045",
    "D003;F016;F045",
    "F040;F041;F042;F043;F044;JEL001-JEL018"
  ),
  document = "docs/legacy-migration-guide.md",
  stringsAsFactors = FALSE
)
write.csv(migration, file.path(fixture, "expected/new-stata/migration-checklist.csv"), row.names = FALSE, na = "")
writeLines(
  jsonlite::toJSON(migration, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/migration-checklist.json")
)

manifest <- list(
  matrix_id = "F046",
  fixture_family = "legacy-deprecation-warnings",
  normative_source = "Legacy Stata compatibility policy; R did 2.5.1 remains the behavioral oracle",
  source_commit = "fdbae25521a941314af8d84ec0c93fb0596daa8e",
  decision_refs = c("D008", "D009", "D013"),
  tolerance_ids = c("EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f046/generate.R", path = "tools/parity/generators/f046/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/new-stata/events.csv", schema = "error-warning-events-csv"),
    list(path = "expected/new-stata/events.json", schema = "error-warning-events"),
    list(path = "expected/new-stata/migration-checklist.csv", schema = "legacy-migration-checklist"),
    list(path = "expected/new-stata/migration-checklist.json", schema = "legacy-migration-checklist")
  ),
  comparison_plan = list(
    list(actual = "Stata captured deprecation warnings", expected = "expected/new-stata/events.csv", tolerance_id = "EXACT", key_columns = c("event_key")),
    list(actual = "Migration guide checklist", expected = "expected/new-stata/migration-checklist.csv", tolerance_id = "EXACT", key_columns = c("surface"))
  ),
  approved_divergence = NULL,
  scope_note = "F046 verifies stable soft-deprecation warning text for retained legacy aliases method(dripw), method(stdipw), asinr, accepted rademacher multiplier spelling, and unsupported non-rademacher multiplier diagnostics. It also binds the migration guide checklist to long/long2 universal-base event-study compatibility, F045 legacy-default evidence, F016/F017 unbalanced and soft-deprecated balance-alias evidence, F035 bootstrap option evidence, and F040-F044/JEL release blockers."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
