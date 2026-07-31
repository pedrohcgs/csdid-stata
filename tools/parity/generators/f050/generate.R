#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f050/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f050")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/new-stata"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

d <- data.frame(
  id = rep(1:10, each = 2),
  time = rep(1:2, times = 10),
  g = rep(c(rep(2, 5), rep(0, 5)), each = 2),
  y = c(rep(c(0, 2), 5), rep(c(1, 1), 5))
)
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

install_schema <- list(
  matrix_id = "F050",
  fixture_family = "clean-install-portability",
  checks = list(
    build_script_runs = TRUE,
    net_install_source = "local checkout",
    sysdir_plus_is_temporary = TRUE,
    sysdir_personal_is_temporary = TRUE,
    installed_files = c(
      "csdid.ado",
      "csdid_estat.ado",
      "csdid_stats.ado",
      "csdid_plot.ado",
      "csdid.mata",
      "csdid.sthlp",
      "csdid_postestimation.sthlp",
      "csdid_estat.sthlp",
      "csdid_stats.sthlp",
      "csdid_plot.sthlp"
    ),
    smoke_commands = c("csdid", "csdid_stats simple", "csdid saverif")
  )
)
writeLines(
  jsonlite::toJSON(install_schema, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "expected/new-stata/install-schema.json")
)

manifest <- list(
  matrix_id = "F050",
  fixture_family = "clean-install-portability",
  normative_source = "Stata release engineering contract for local clean install",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D001", "D016"),
  tolerance_ids = c("EXACT"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f050/generate.R", path = "tools/parity/generators/f050/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/new-stata/install-schema.json", schema = "install-portability")),
  comparison_plan = list(list(actual = "installed Stata package state", expected = "expected/new-stata/install-schema.json", tolerance_id = "EXACT", key_columns = c("check"))),
  approved_divergence = NULL,
  scope_note = "Clean local build and net install into isolated temporary PLUS/PERSONAL directories, with installed command resolution, direct help files for all public commands, and smoke commands. Full release hardening still depends on the broader implementation, JEL, documentation, and engineering gates."
)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
  file.path(fixture, "metadata/manifest.json")
)
