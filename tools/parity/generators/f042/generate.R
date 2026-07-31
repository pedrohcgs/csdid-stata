#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f042/generate.R"
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

fixture <- file.path(root, "tests/fixtures/parity/f042")
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
raw <- raw[raw$yaca == 2014 | is.na(raw$yaca) | raw$yaca > 2019, ]
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

mydata$Treat <- as.integer(mydata$yaca == 2014 & !is.na(mydata$yaca))
mydata$Post <- as.integer(mydata$year >= 2014)
base_pop <- mydata[mydata$year == 2013, c("county_code", "population_20_64")]
names(base_pop)[2] <- "set_wt"
mydata <- merge(mydata, base_pop, by = "county_code", all.x = TRUE, sort = FALSE)
mydata <- mydata[order(mydata$county_code, mydata$year), ]
mydata$treat_year <- ifelse(mydata$Treat == 1, 2014, 0)
mydata$county_code <- as.numeric(mydata$county_code)

input <- mydata[, c(
  "county_code",
  "year",
  "treat_year",
  "Treat",
  "crude_rate_20_64",
  "set_wt",
  covs
)]
write.csv(input, file.path(fixture, "inputs/event-study-input.csv"), row.names = FALSE, na = "")

trend_rows <- do.call(rbind, lapply(split(input, list(input$Treat, input$year), drop = TRUE), function(d) {
  data.frame(
    expand = ifelse(d$Treat[1] == 1, "Expansion Counties", "Non-Expansion Counties"),
    year = d$year[1],
    mortality = weighted.mean(d$crude_rate_20_64, d$set_wt),
    stringsAsFactors = FALSE
  )
}))
trend_rows <- trend_rows[order(trend_rows$expand, trend_rows$year), ]
write.csv(trend_rows, file.path(fixture, "expected/r/trends.csv"), row.names = FALSE, na = "")

scenario_specs <- list(
  figure3_no_cov_reg = list(method = "reg", covariates = "none", formula = NULL),
  figure4_cov_reg = list(method = "reg", covariates = "numeric", formula = as.formula(paste("~", paste(covs, collapse = "+")))),
  figure4_cov_ipw = list(method = "ipw", covariates = "numeric", formula = as.formula(paste("~", paste(covs, collapse = "+")))),
  figure4_cov_dr = list(method = "dr", covariates = "numeric", formula = as.formula(paste("~", paste(covs, collapse = "+"))))
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
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = spec$method,
    weightsname = "set_wt",
    base_period = "universal"
  )
  if (!is.null(spec$formula)) call_args$xformla <- spec$formula
  mp <- suppressWarnings(do.call(att_gt, call_args))
  attgt_rows[[scenario]] <- data.frame(
    scenario = scenario,
    method = spec$method,
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
    method = spec$method,
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
    method = spec$method,
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
  matrix_id = "F042",
  fixture_family = "jel-2xt-event-study-smoke",
  normative_source = "JEL-DiD 2xT empirical design plus R did 2.5.1 analytical oracle",
  source_commit = "50f4f183783d2344f85bc4f39bcbcc1b7eba6466",
  decision_refs = c("D001", "D006", "D013", "D014", "D015"),
  tolerance_ids = c("TOL002", "TOL005"),
  inputs = list(list(path = "inputs/event-study-input.csv", rows = nrow(input), columns = ncol(input))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f042/generate.R", path = "tools/parity/generators/f042/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/trends.csv", schema = "jel-2xt-trends"),
    list(path = "expected/r/attgt.csv", schema = "attgt"),
    list(path = "expected/r/dynamic.csv", schema = "jel-2xt-dynamic"),
    list(path = "expected/r/post-window.csv", schema = "jel-2xt-post-window")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/trends.csv", expected = "expected/r/trends.csv", tolerance_id = "TOL005", key_columns = c("expand", "year")),
    list(actual = "expected/new-stata/attgt.csv", expected = "expected/r/attgt.csv", tolerance_id = "TOL002", key_columns = c("scenario", "group", "time")),
    list(actual = "expected/new-stata/dynamic.csv", expected = "expected/r/dynamic.csv", tolerance_id = "TOL002", key_columns = c("scenario", "seq")),
    list(actual = "expected/new-stata/post-window.csv", expected = "expected/r/post-window.csv", tolerance_id = "TOL002", key_columns = c("scenario"))
  ),
  approved_divergence = NULL,
  scope_note = "Partial F042 JEL 2xT smoke gate. It reconstructs the JEL 2xT sample from committed JEL data, verifies weighted trend data for Figure 2, and compares Stata csdid analytical dynamic aggregation against R did 2.5.1 for the weighted no-covariate regression event study and weighted covariate-adjusted reg/ipw/dr event studies. Full JEL Figure 3/4 replication still requires the 25,000-rep bootstrap confidence intervals, plotting wrapper, and rendered artifact comparison."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
