#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt019/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

f011_generator <- file.path(root, "tools/parity/generators/f011/generate.R")
f011_output <- system2("Rscript", f011_generator, stdout = TRUE, stderr = TRUE)
invisible(f011_output)

fixture <- file.path(root, "tests/fixtures/parity/rt019")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/contract"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

f011_fixture <- file.path(root, "tests/fixtures/parity/f011")
invisible(file.copy(file.path(f011_fixture, "inputs/input.csv"),
                    file.path(fixture, "inputs/input.csv"), overwrite = TRUE))
invisible(file.copy(file.path(f011_fixture, "inputs/sparse-factor.csv"),
                    file.path(fixture, "inputs/sparse-factor.csv"), overwrite = TRUE))

input_main <- read.csv(file.path(fixture, "inputs/input.csv"))
input_sparse <- read.csv(file.path(fixture, "inputs/sparse-factor.csv"))

source_file <- "tests/testthat/test-modelmatrix-hoist.R"
source_sha <- "f412253e6523b15e8ab45a3daa521765cf9b1ee4e76860199318bbd4710c6a9a"
source_tests <- c(
  "global design slice is bit-identical to per-subset model.matrix for numeric formulae",
  "slow path matches faster_mode for numeric / transform formulae",
  "RC-path (positional global slice) matches faster_mode",
  "unbalanced panel (positional global slice) matches faster_mode for factor / transform formulae",
  "RC-path matches faster_mode for factor / data-dependent-basis formulae",
  "transform / factor formulae match faster_mode under universal base, notyettreated, anticipation",
  "global basis is reparameterization-invariant: ~poly(X, 2) equals ~X + I(X^2)",
  "a factor covariate equals manually-expanded dummies EXACTLY (dense levels)",
  "transform formulae that evaluate to NaN drop those rows instead of crashing",
  "matrix-valued transformed formula terms drop non-finite rows row-wise",
  "a globally-empty factor level is dropped instead of NA-failing every cell",
  "a sparse factor (level absent from some cells) matches manual dummies, incl. warnings",
  "RC sparse factor (level absent from some cells) matches manual dummies, incl. warnings"
)
mapped_scenario <- c(
  "r-model-matrix-internal-only",
  "numeric-interaction-square-covariate-grid",
  "repeated-cross-section-numeric-covariate-grid",
  "r-unbalanced-faster-mode-formula-internal-only",
  "r-poly-data-dependent-basis-internal-only",
  "r-faster-mode-cross-option-formula-internal-only",
  "r-poly-reparameterization-internal-only",
  "dense-factor-equals-manual-dummies",
  "r-log-nonfinite-formula-internal-only",
  "r-matrix-valued-formula-internal-only",
  "r-empty-factor-level-internal-only",
  "panel-sparse-factor-equals-manual-dummy",
  "rc-sparse-factor-equals-manual-dummy"
)
assertion_family <- c(
  "R model.matrix global/per-cell slice identity is an internal R helper invariant",
  "Stata public covariate grid matches R ATT(g,t) and SE values for numeric, interaction, and squared covariates across dr/reg/ipw panel paths",
  "Stata repeated-cross-section covariate grid matches R ATT(g,t) and SE values for numeric covariates across dr/reg/ipw paths",
  "R allow_unbalanced_panel plus faster_mode formula-slicing identity is an internal R path comparison",
  "R faster_mode comparison for poly/data-dependent basis has no public Stata formula-language analogue",
  "R faster_mode comparison under not-yet-treated, universal-base, and anticipation formula internals has no separate public Stata path analogue",
  "R poly() global-basis reparameterization is an R formula/model.matrix invariant; Stata verifies raw squared-covariate public results",
  "Stata factor variables and manually expanded dummy variables produce identical ATT(g,t) and SE values for dense levels across dr/reg/ipw panel and repeated-cross-section paths",
  "R formula-time log() non-finite row dropping has no direct Stata varlist-expression analogue; users precompute transformed covariates before csdid",
  "R matrix-valued cbind() formula terms have no Stata csdid varlist analogue",
  "R factor objects can retain globally empty levels; Stata factor-variable expansion is based on observed levels",
  "Stata rank-deficient panel sparse factor and manual-dummy specifications have matching missing ATT/SE patterns and singular-warning counts",
  "Stata rank-deficient repeated-cross-section sparse factor and manual-dummy specifications have matching missing ATT/SE patterns and singular-warning counts"
)
coverage_status <- c(
  "approved-divergence",
  "mapped",
  "mapped",
  "approved-divergence",
  "approved-divergence",
  "approved-divergence",
  "approved-divergence",
  "mapped",
  "approved-divergence",
  "approved-divergence",
  "approved-divergence",
  "mapped",
  "mapped"
)
divergence_id <- c(
  "RT019-DIV001", "", "",
  "RT019-DIV002", "RT019-DIV002", "RT019-DIV002", "RT019-DIV003",
  "", "RT019-DIV004", "RT019-DIV005", "RT019-DIV006", "", ""
)

upstream_map <- data.frame(
  source_file = source_file,
  source_sha256 = source_sha,
  source_test = source_tests,
  mapped_scenario = mapped_scenario,
  assertion_family = assertion_family,
  coverage_status = coverage_status,
  divergence_id = divergence_id,
  stringsAsFactors = FALSE
)
write.csv(upstream_map, file.path(fixture, "expected/contract/upstream-test-map.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(upstream_map, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/upstream-test-map.json"))

divergence <- data.frame(
  divergence_id = c(
    "RT019-DIV001",
    "RT019-DIV002",
    "RT019-DIV003",
    "RT019-DIV004",
    "RT019-DIV005",
    "RT019-DIV006"
  ),
  source_tests = c(
    source_tests[1],
    paste(source_tests[c(4, 5, 6)], collapse = "; "),
    source_tests[7],
    source_tests[9],
    source_tests[10],
    source_tests[11]
  ),
  reason = c(
    "The source test compares R model.matrix output constructed globally against per-subset model.matrix output. Stata csdid does not expose R model.matrix objects or per-cell design-matrix helper output.",
    "The source tests compare R faster_mode against R slow-path formula slicing for unbalanced, repeated-cross-section, data-dependent basis, universal-base, not-yet-treated, and anticipation combinations. Stata exposes a public csdid command and records fast/nofast optimized equivalence separately; it does not expose R faster_mode internals.",
    "R poly() is a data-dependent R formula basis. Stata users represent the same public covariate span through explicit variables or factor-variable operators such as c.x#c.x; raw squared-covariate public parity is verified.",
    "R can evaluate log() inside xformla and then drop non-finite formula rows. Stata csdid accepts varlists/factor-variable terms, so users precompute transformed covariates and Stata missingness rules apply before estimation.",
    "R matrix-valued formula terms such as I(cbind(...)) have no direct Stata csdid varlist analogue.",
    "R factors can retain declared-but-empty levels after subsetting. Stata factor-variable expansion is based on observed levels, so the exact empty-level object state is not a separate public command surface."
  ),
  accepted_behavior = c(
    "RT019 verifies public covariate ATT(g,t), SE, factor/dummy equivalence, and sparse-factor warning behavior through Stata command gates.",
    "Public covariate behavior is verified through panel and repeated-cross-section ATT(g,t)/SE gates; fast-path policy and nofast equivalence are covered by F032/RT025-style gates.",
    "RT019 verifies explicit squared-covariate public results against R; users needing higher-order bases must materialize those covariates before invoking Stata csdid.",
    "Missing and subset construction are covered by F019 and public covariate gates; Stata expression transforms are intentionally not a separate formula surface.",
    "The public Stata contract supports scalar covariate variables and factor-variable terms, not matrix-valued formula expansion.",
    "RT019 verifies dense observed factor levels and sparse absent-in-cell factor levels; globally empty retained R levels are treated as an R object-model divergence."
  ),
  stringsAsFactors = FALSE
)
write.csv(divergence, file.path(fixture, "expected/contract/approved-divergence.csv"), row.names = FALSE, na = "")
writeLines(jsonlite::toJSON(divergence, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE),
           file.path(fixture, "expected/contract/approved-divergence.json"))

scenarios <- data.frame(
  scenario = c(
    "numeric-interaction-square-covariate-grid",
    "repeated-cross-section-numeric-covariate-grid",
    "dense-factor-equals-manual-dummies",
    "panel-sparse-factor-equals-manual-dummy",
    "rc-sparse-factor-equals-manual-dummy"
  ),
  input = c("input.csv", "input.csv", "input.csv", "sparse-factor.csv", "sparse-factor.csv"),
  expected_behavior = c(
    "Panel numeric, interaction, and squared covariate ATT(g,t)/SE values match R for dr/reg/ipw",
    "Repeated-cross-section numeric covariate ATT(g,t)/SE values match R for dr/reg/ipw",
    "Dense Stata factor-variable and manual-dummy covariates give identical ATT(g,t)/SE values and match R",
    "Panel sparse factor and manual dummy specifications share missing ATT/SE patterns and singular-warning counts",
    "Repeated-cross-section sparse factor and manual dummy specifications share missing ATT/SE patterns and singular-warning counts"
  ),
  stringsAsFactors = FALSE
)
write.csv(scenarios, file.path(fixture, "expected/contract/scenarios.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "RT019",
  fixture_family = "r-modelmatrix-hoist",
  normative_source = "R did 2.5.1 tests/testthat/test-modelmatrix-hoist.R",
  source_commit = "622d7cec474790934cdaeb68c82c5c38c0711426",
  source_sha256 = source_sha,
  decision_refs = c("D001", "D003", "D004", "D014"),
  tolerance_ids = c("TOL002", "EXACT"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(input_main), columns = ncol(input_main)),
    list(path = "inputs/sparse-factor.csv", rows = nrow(input_sparse), columns = ncol(input_sparse))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt019/generate.R", path = "tools/parity/generators/rt019/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = list(inherited_f011_seed_sparse_factor = 11),
  expected_outputs = list(
    list(path = "expected/r/covariate-grid.csv", schema = "attgt-covariate-grid"),
    list(path = "expected/r/dense-factor-dummy-grid.csv", schema = "attgt-dense-factor-dummy-grid"),
    list(path = "expected/r/sparse-factor-grid.csv", schema = "attgt-sparse-factor-grid"),
    list(path = "expected/r/sparse-factor-events.csv", schema = "warning-event-counts"),
    list(path = "expected/contract/upstream-test-map.csv", schema = "source-test-map"),
    list(path = "expected/contract/upstream-test-map.json", schema = "source-test-map"),
    list(path = "expected/contract/approved-divergence.csv", schema = "approved-divergence"),
    list(path = "expected/contract/approved-divergence.json", schema = "approved-divergence"),
    list(path = "expected/contract/scenarios.csv", schema = "modelmatrix-hoist-public-scenarios")
  ),
  comparison_plan = list(
    list(actual = "Stata covariate formula-family ATT(g,t)/SE checks", expected = "expected/r/covariate-grid.csv", tolerance_id = "TOL002", key_columns = c("scenario", "est_method", "group", "time")),
    list(actual = "Stata dense factor/manual-dummy ATT(g,t)/SE checks", expected = "expected/r/dense-factor-dummy-grid.csv", tolerance_id = "TOL002", key_columns = c("panel_mode", "covariate_spec", "method", "group", "time")),
    list(actual = "Stata sparse factor/manual-dummy ATT(g,t)/SE and warning checks", expected = "expected/r/sparse-factor-grid.csv", tolerance_id = "TOL002", key_columns = c("panel_mode", "covariate_spec", "group", "time")),
    list(actual = "Mapped source tests", expected = "expected/contract/upstream-test-map.csv", tolerance_id = "EXACT", key_columns = c("source_test"))
  ),
  approved_divergence = list(status = "approved-divergence", path = "expected/contract/approved-divergence.csv"),
  scope_note = "RT019 maps public covariate behavior from R did's modelmatrix-hoist tests to Stata command gates for numeric, interaction, squared, dense-factor, and sparse-factor specifications. R-only model.matrix, faster_mode, poly(), formula-time non-finite transform, matrix-valued formula, and retained-empty-factor-level internals are recorded as approved divergences."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
