#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f017/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f017")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:15
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 5, 3, ifelse(d$id <= 10, 4, 0))
d$y0 <- 1 + 0.40 * d$time + 0.08 * d$id + 0.03 * sin(d$id + d$time)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.55 + 0.08 * (d$time - d$g), 0)
d$y <- d$y0 + d$te
d$y0 <- NULL
d$te <- NULL
d <- d[!(d$id == 2 & d$time == 2), ]
d <- d[!(d$id == 7 & d$time == 3), ]
d <- d[!(d$id == 14 & d$time == 4), ]

write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

# The bal() vocabulary is full / pair / none, and those three spellings plus
# the unabbreviated balance() are the whole surface.
#
# The six spellings in the `removed` block below were development-era names
# that never appeared in any released csdid: they are absent from the pinned
# Version 1.82 source, and 2.0.0 is the first release of this rewrite. There is
# therefore nothing to deprecate. They are not options, and csdid must say so
# with the ordinary unknown-option refusal (rc 198) rather than accepting them
# quietly or pretending they once worked.
#
# unbalanced and allowunbalanced / allow_unbalanced are a different case and
# are NOT in that block. unbalanced is the documented spelling of the bal(none)
# synonym; allowunbalanced / allow_unbalanced are the longhand for the same
# thing, carrying the argument name the reference implementation uses --
# did::att_gt(allow_unbalanced_panel = TRUE) -- so code written with that
# vocabulary transliterates directly. All are first-class synonyms of
# bal(none): accepted, silent, and current. No warning is printed, because
# there is nothing to warn about. Combining one of them with a bal() that means
# something else is an error rather than a silent resolution.
#
# long / long2 / asinr ARE genuine Version 1.82 options, so they stay: accepted,
# working, and announcing their deprecation.
long_message <- "warning: long/long2 are legacy event-study aliases slated for removal; do not use them in new code. Specify baseperiod(universal) explicitly for legacy layouts."
asinr_message <- "csdid legacy compatibility: asinr is accepted and ignored; use notyet to select the not-yet-treated comparison group."

removed <- c(
  "balanceall",
  "balancepair",
  "bal(all)",
  "bal(unbal)",
  "bal(unbalanced)",
  "bal(allow_unbalanced)"
)
removed_keys <- c(
  "removed_balanceall",
  "removed_balancepair",
  "removed_bal_all",
  "removed_bal_unbal",
  "removed_bal_unbalanced",
  "removed_bal_allow_unbalanced"
)
# For an error row, the bal() setting the user should type instead; for an
# accepted row, the bal() setting the spelling resolves to. csdid never prints
# either -- an unknown option gets the ordinary Stata refusal and no message of
# its own, and an accepted synonym is silent -- so this column is documentation
# and the mode the test compares estimates against.
removed_bal_mode <- c(
  "bal(full)",
  "bal(pair)",
  "bal(full)",
  "bal(none)",
  "bal(none)",
  "bal(none)"
)

# Typed in full, with no abbreviations: prefixes such as unbal or allow are
# unknown options. `unbal` in particular would read as the refused bal(unbal)
# token, so accepting it would make that confusion silent. The prefix refusals
# are asserted in test-f051.do.
accepted <- c("unbalanced", "allowunbalanced", "allow_unbalanced")
accepted_keys <- c(
  "accepted_unbalanced",
  "accepted_allowunbalanced",
  "accepted_allow_unbalanced"
)

events <- data.frame(
  event_key = c(removed_keys, accepted_keys, "legacy_long", "legacy_long2", "legacy_asinr_noop"),
  return_code = c(rep(198, length(removed)), rep(0, length(accepted)), 0, 0, 0),
  event_type = c(rep("error", length(removed)), rep("accepted", length(accepted)), "warning", "warning", "warning"),
  offending_option = c(removed, accepted, "long", "long2", "asinr"),
  message_normalized = c(rep(NA, length(removed) + length(accepted)), long_message, long_message, asinr_message),
  bal_mode = c(removed_bal_mode, rep("bal(none)", length(accepted)), NA, NA, NA),
  stringsAsFactors = FALSE
)

write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(events, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "expected/r/events.json"))

manifest <- list(
  matrix_id = "F017",
  fixture_family = "balance-vocabulary-and-legacy-spellings",
  normative_source = "D003/D008 conformance contract; bal() vocabulary is full/pair/none, with unbalanced (longhand allowunbalanced) as the synonym spelling of bal(none)",
  source_commit = "fdbae25521a941314af8d84ec0c93fb0596daa8e",
  decision_refs = c("D003", "D008"),
  tolerance_ids = c("EXACT"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f017/generate.R", path = "tools/parity/generators/f017/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/events.json", schema = "error-warning-events"),
    list(path = "expected/r/events.csv", schema = "error-warning-events-csv")
  ),
  comparison_plan = list(
    list(actual = "Stata captured balance-vocabulary refusals and legacy-option warnings", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = list(
    status = "removed-development-era-spelling",
    reason = "The balance spellings in the error rows never appeared in a released csdid; they are absent from the pinned Version 1.82 source and 2.0.0 is the first release of this rewrite. There is nothing to deprecate, so they are refused as unknown options rather than accepted as aliases. unbalanced and allowunbalanced/allow_unbalanced are not among them: unbalanced is the documented spelling of the bal(none) synonym and allowunbalanced is the longhand carrying the argument name did::att_gt uses for this setting. All are supported as silent, non-deprecated synonyms of bal(none)."
  ),
  scope_note = "F017 pins the bal() vocabulary as full/pair/none: the three modes are three different estimands on this deliberately unbalanced fixture, unbalanced and its longhand allowunbalanced/allow_unbalanced are accepted silently as synonyms of bal(none), typed in full with no abbreviations, and must reproduce it exactly, the development-era spellings (balanceall, balancepair, bal(all), bal(unbal), bal(unbalanced), bal(allow_unbalanced)) are refused with rc 198, and the genuine Version 1.82 options long/long2 stay accepted with a deprecation warning and use baseperiod(universal) when baseperiod() is omitted, as does asinr as a no-op warning."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
