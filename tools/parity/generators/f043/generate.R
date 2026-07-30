#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f043/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

jel_root <- Sys.getenv("JEL_DID_REFERENCE", "/tmp/jel-did-reference")
if (!dir.exists(jel_root)) {
  stop("JEL reference checkout not found. Set JEL_DID_REFERENCE or create /tmp/jel-did-reference.", call. = FALSE)
}

fixture <- file.path(root, "tests/fixtures/parity/f043")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

covs <- c(
  "perc_female",
  "perc_white",
  "perc_hispanic",
  "unemp_rate",
  "poverty_rate",
  "median_income"
)

raw <- read.csv(file.path(jel_root, "data", "county_mortality_data.csv"), stringsAsFactors = FALSE)
raw$state <- substr(raw$county, nchar(raw$county) - 1, nchar(raw$county))
raw <- raw[!(raw$state %in% c("DC", "DE", "MA", "NY", "VT")), ]
raw$perc_white <- raw$population_20_64_white / raw$population_20_64 * 100
raw$perc_hispanic <- raw$population_20_64_hispanic / raw$population_20_64 * 100
raw$perc_female <- raw$population_20_64_female / raw$population_20_64 * 100
raw$unemp_rate <- raw$unemp_rate * 100
raw$median_income <- raw$median_income / 1000

keep <- c(
  "state",
  "county",
  "county_code",
  "year",
  "population_20_64",
  "yaca",
  "perc_female",
  "perc_white",
  "perc_hispanic",
  "unemp_rate",
  "poverty_rate",
  "median_income",
  "crude_rate_20_64"
)
mydata <- raw[, keep]
mydata <- mydata[complete.cases(mydata[, setdiff(names(mydata), "yaca")]), ]

has_1314 <- ave(mydata$year %in% c(2013, 2014), mydata$county_code, FUN = sum)
mydata <- mydata[has_1314 == 2, ]
mydata <- mydata[!is.na(mydata$crude_rate_20_64), ]
full_mortality <- ave(mydata$crude_rate_20_64, mydata$county_code, FUN = length)
mydata <- mydata[full_mortality == 11, ]

mydata$treat_year <- ifelse(!is.na(mydata$yaca) & mydata$yaca <= 2019, mydata$yaca, 0)
base_pop <- mydata[mydata$year == 2013, c("county_code", "population_20_64")]
names(base_pop)[2] <- "set_wt"
mydata <- merge(mydata, base_pop, by = "county_code", all.x = TRUE, sort = FALSE)
mydata <- mydata[order(mydata$county_code, mydata$year), ]
mydata$county_code <- as.numeric(mydata$county_code)

input <- mydata[, c(
  "county_code",
  "year",
  "treat_year",
  "crude_rate_20_64",
  "set_wt",
  covs
)]
write.csv(input, file.path(fixture, "inputs/gxt-input.csv"), row.names = FALSE, na = "")

trend_input <- input
trend_input$treat_year_label <- ifelse(
  trend_input$treat_year == 0,
  "Non-Expansion Counties",
  as.character(trend_input$treat_year)
)
trend_rows <- do.call(rbind, lapply(split(trend_input, list(trend_input$treat_year_label, trend_input$year), drop = TRUE), function(d) {
  data.frame(
    treat_year = d$treat_year_label[1],
    year = d$year[1],
    mortality = weighted.mean(d$crude_rate_20_64, d$set_wt),
    stringsAsFactors = FALSE
  )
}))
trend_rows <- trend_rows[order(trend_rows$treat_year, trend_rows$year), ]
write.csv(trend_rows, file.path(fixture, "expected/r/trends.csv"), row.names = FALSE, na = "")

scenario_specs <- list(
  figure6_no_cov_dr = list(covariates = "none", formula = NULL),
  figure9_cov_dr = list(covariates = "numeric", formula = as.formula(paste("~", paste(covs, collapse = "+"))))
)

attgt_rows <- list()
dynamic_rows <- list()
window_rows <- list()
for (scenario in names(scenario_specs)) {
  spec <- scenario_specs[[scenario]]
  call_args <- list(
    yname = "crude_rate_20_64",
    tname = "year",
    idname = "county_code",
    gname = "treat_year",
    data = input,
    panel = TRUE,
    control_group = "notyettreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = "dr",
    weightsname = "set_wt",
    base_period = "universal"
  )
  if (!is.null(spec$formula)) call_args$xformla <- spec$formula
  mp <- suppressWarnings(do.call(att_gt, call_args))

  attgt_rows[[scenario]] <- data.frame(
    scenario = scenario,
    method = "dr",
    covariates = spec$covariates,
    seq = seq_along(mp$att),
    group = mp$group,
    time = mp$t,
    event_time = mp$t - mp$group,
    att = mp$att,
    se = mp$se,
    stringsAsFactors = FALSE
  )

  dyn <- suppressWarnings(aggte(mp, type = "dynamic", na.rm = TRUE, bstrap = FALSE, cband = FALSE))
  dynamic_rows[[scenario]] <- data.frame(
    scenario = scenario,
    method = "dr",
    covariates = spec$covariates,
    seq = seq_along(dyn$egt),
    egt = dyn$egt,
    att = dyn$att.egt,
    se = dyn$se.egt,
    overall_att = dyn$overall.att,
    overall_se = dyn$overall.se,
    stringsAsFactors = FALSE
  )

  post <- suppressWarnings(aggte(mp, type = "dynamic", min_e = 0, max_e = 5, na.rm = TRUE, bstrap = FALSE, cband = FALSE))
  window_rows[[scenario]] <- data.frame(
    scenario = scenario,
    method = "dr",
    covariates = spec$covariates,
    min_e = 0,
    max_e = 5,
    n_effects = length(post$att.egt),
    overall_att = post$overall.att,
    overall_se = post$overall.se,
    stringsAsFactors = FALSE
  )
}

attgt <- do.call(rbind, attgt_rows)
dynamic <- do.call(rbind, dynamic_rows)
window <- do.call(rbind, window_rows)
write.csv(attgt, file.path(fixture, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(dynamic, file.path(fixture, "expected/r/dynamic.csv"), row.names = FALSE, na = "")
write.csv(window, file.path(fixture, "expected/r/post-window.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F043",
  fixture_family = "jel-gxt-smoke",
  normative_source = "JEL-DiD GxT empirical design plus R did 2.5.1 analytical oracle",
  source_commit = "50f4f183783d2344f85bc4f39bcbcc1b7eba6466",
  decision_refs = c("D001", "D006", "D013", "D014", "D015"),
  tolerance_ids = c("TOL004", "TOL005"),
  inputs = list(list(path = "inputs/gxt-input.csv", rows = nrow(input), columns = ncol(input))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f043/generate.R", path = "tools/parity/generators/f043/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/trends.csv", schema = "jel-gxt-trends"),
    list(path = "expected/r/attgt.csv", schema = "jel-gxt-attgt"),
    list(path = "expected/r/dynamic.csv", schema = "jel-gxt-dynamic"),
    list(path = "expected/r/post-window.csv", schema = "jel-gxt-post-window")
  ),
  comparison_plan = list(
    list(actual = "build/test-artefacts/f043/trends.csv", expected = "expected/r/trends.csv", tolerance_id = "TOL005", key_columns = c("treat_year", "year")),
    list(actual = "build/test-artefacts/f043/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL004", key_columns = c("scenario", "group", "time")),
    list(actual = "build/test-artefacts/f043/dynamic.csv", expected = "expected/r/dynamic.csv", tolerance_id = "TOL004", key_columns = c("scenario", "seq")),
    list(actual = "build/test-artefacts/f043/post-window.csv", expected = "expected/r/post-window.csv", tolerance_id = "TOL004", key_columns = c("scenario"))
  ),
  approved_divergence = list(
    type = "numerical-tolerance-exception",
    threshold = "absolute 1e-8 plus relative 2e-6 for F043 analytical ATT/SE vector comparisons",
    reason = "The actual JEL GxT covariate-adjusted DR design shows cross-runtime solver-level drift in raw ATT(g,t) cells, while point estimates, SEs, dynamic aggregates, and post-window summaries remain numerically aligned at published empirical precision.",
    evidence = c("tests/stata/test-f043.do", "test-f043.log")
  ),
  scope_note = "Partial F043 JEL GxT smoke gate. It reconstructs the JEL staggered-adoption sample from committed JEL data, verifies weighted timing-group trends for Figure 5, and compares Stata csdid analytical ATT(g,t) plus dynamic aggregation against R did 2.5.1 for weighted no-covariate and covariate-adjusted DR event-study designs with not-yet-treated controls and universal base periods. Raw ATT/SE vector comparisons use a recorded JEL-scale numerical tolerance exception for cross-runtime solver drift. Full JEL Figure 5-9 replication still requires 25,000-rep bootstrap confidence intervals, plotting wrappers, rendered artifact comparison, and runtime hardening."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
