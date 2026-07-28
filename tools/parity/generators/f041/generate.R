#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f041/generate.R"
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

fixture <- file.path(root, "tests/fixtures/parity/f041")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/jel"), recursive = TRUE, showWarnings = FALSE)
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

short_data <- mydata[mydata$year %in% c(2013, 2014), ]
short_data$Treat <- as.integer(short_data$yaca == 2014 & !is.na(short_data$yaca))
short_data$Post <- as.integer(short_data$year == 2014)
base_pop <- short_data[short_data$year == 2013, c("county_code", "population_20_64")]
names(base_pop)[2] <- "set_wt"
short_data <- merge(short_data, base_pop, by = "county_code", all.x = TRUE, sort = FALSE)
short_data <- short_data[order(short_data$county_code, short_data$year), ]
short_data$treat_year <- ifelse(short_data$Treat == 1, 2014, 0)
short_data$county_code <- as.numeric(short_data$county_code)

input <- short_data[, c(
  "county_code",
  "year",
  "treat_year",
  "crude_rate_20_64",
  "set_wt",
  covs
)]
write.csv(input, file.path(fixture, "inputs/table7-input.csv"), row.names = FALSE, na = "")

run_cs <- function(method, weighted) {
  call_args <- list(
    yname = "crude_rate_20_64",
    tname = "year",
    idname = "county_code",
    gname = "treat_year",
    xformla = as.formula(paste("~", paste(covs, collapse = "+"))),
    data = input,
    panel = TRUE,
    control_group = "nevertreated",
    bstrap = FALSE,
    cband = FALSE,
    est_method = method,
    base_period = "universal"
  )
  if (weighted) call_args$weightsname <- "set_wt"
  mp <- suppressWarnings(do.call(att_gt, call_args))
  agg <- suppressWarnings(aggte(mp, type = "simple", na.rm = TRUE, bstrap = FALSE, cband = FALSE))
  data.frame(
    panel = ifelse(weighted, "weighted", "unweighted"),
    method = method,
    group = 2014,
    estimate = agg$overall.att,
    se = agg$overall.se,
    n = nrow(input),
    n_units = length(unique(input$county_code)),
    stringsAsFactors = FALSE
  )
}

table7_rows <- do.call(rbind, lapply(c(FALSE, TRUE), function(weighted) {
  do.call(rbind, lapply(c("reg", "ipw", "dr"), run_cs, weighted = weighted))
}))
write.csv(table7_rows, file.path(fixture, "expected/r/table7-analytical.csv"), row.names = FALSE, na = "")

extract_table7 <- function(path, source) {
  lines <- readLines(path, warn = FALSE)
  est_line <- grep("Medicaid Expansion", lines, value = TRUE)[1]
  se_line <- lines[grep("Medicaid Expansion", lines)[1] + 1]
  nums <- regmatches(est_line, gregexpr("-?[0-9]+\\.[0-9]+", est_line))[[1]]
  ses <- regmatches(se_line, gregexpr("-?[0-9]+\\.[0-9]+", se_line))[[1]]
  data.frame(
    source = source,
    panel = rep(c("unweighted", "weighted"), each = 3),
    method = rep(c("reg", "ipw", "dr"), times = 2),
    estimate_displayed = as.numeric(nums),
    se_displayed = as.numeric(ses),
    stringsAsFactors = FALSE
  )
}
committed <- rbind(
  extract_table7(file.path(jel_root, "tables", "table7_R.tex"), "R_committed"),
  extract_table7(file.path(jel_root, "tables", "table7_stata.tex"), "Stata_committed")
)
write.csv(committed, file.path(fixture, "expected/jel/table7-committed.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F041",
  fixture_family = "jel-table7-smoke",
  normative_source = "JEL-DiD Table 7 empirical design plus R did 2.5.1 analytical oracle",
  source_commit = "50f4f183783d2344f85bc4f39bcbcc1b7eba6466",
  decision_refs = c("D001", "D006", "D013"),
  tolerance_ids = c("TOL001", "TOL004"),
  inputs = list(list(path = "inputs/table7-input.csv", rows = nrow(input), columns = ncol(input))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f041/generate.R", path = "tools/parity/generators/f041/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did")), jsonlite = as.character(packageVersion("jsonlite"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/table7-analytical.csv", schema = "jel-table7-analytical"),
    list(path = "expected/jel/table7-committed.csv", schema = "jel-table7-committed-artifacts")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/table7-analytical.csv", expected = "expected/r/table7-analytical.csv", tolerance_id = "TOL001", key_columns = c("panel", "method")),
    list(actual = "committed JEL table context", expected = "expected/jel/table7-committed.csv", tolerance_id = "TOL004", key_columns = c("source", "panel", "method"))
  ),
  approved_divergence = NULL,
  scope_note = "Partial F041 JEL Table 7 smoke gate. It reconstructs the JEL Table 7 two-period covariate-adjusted analysis sample from the committed JEL data and verifies Stata csdid analytical simple aggregation against R did 2.5.1 for reg/ipw/dr, weighted and unweighted. The committed R/Stata Table 7 display values are recorded as empirical artifact context. Full JEL replication still requires the 25,000-rep bootstrap/table-rendering wrapper and comparison against committed/generated JEL artifacts."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
