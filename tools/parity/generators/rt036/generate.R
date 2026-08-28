#!/usr/bin/env Rscript

# RT036 -- a calendar period whose covariate is missing on EVERY row ceases to
# exist before the period list is built (R did 2.5.1 pre_process_did.R: the
# complete-cases row drop at :162 precedes the tlist read at :215). The
# fixtures pin the surviving grids and every ATT/SE across the edge shapes --
# dead middle/first/last period, a dead varying base, a cohort's own
# treatment period dead, two dead periods, universal base, anticipation, and
# the early-period kill that trims a whole cohort -- plus the all-dead
# refusal. Shape 9 is the boundary the family surfaced: a covariate missing
# for SOME rows of a period such that balancing removes exactly the
# never-treated units. R's never-treated availability check has already run
# on the pre-balancing cohort list, so R returns an all-NA grid in silence;
# shape 9b feeds R the balanced sample itself, where its own fallback fires,
# and pins the grid csdid reports on the raw data (owner decision
# 2026-08-28: csdid keeps the loud fallback -- R's own rule, applied to the
# settled sample). Inputs are quantized to exact multiples of 2^-13 so
# 17-digit CSVs replay bit-identically through R and Stata parsers alike.

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt036/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)
OUT <- file.path(root, "tests/fixtures/parity/rt036")
dir.create(file.path(OUT, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUT, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUT, "metadata"), recursive = TRUE, showWarnings = FALSE)
# ---------------------------------------------------------------- parameters --
N_PER_COHORT <- 30L
PERIODS      <- 1:5
COHORTS      <- c(0, 3, 4)
SEED         <- 20260828L

g17 <- function(x) {
  vapply(x, function(v) if (is.na(v)) "" else sprintf("%.17g", v), character(1))
}

# R's own reader (scan/read.csv/as.numeric) is NOT correctly rounded for 17-digit
# decimals: sprintf("%.17g") -> as.numeric() differs by 1 ULP for ~18% of random
# doubles on this platform. A witness CSV must replay bit-identically in R AND in
# Stata, so the generated data is quantized to exact multiples of 2^-13. Such a
# value has an exact decimal expansion of at most 15 significant digits (for
# |x| < 100), so "%.17g" prints it exactly and any strtod-like parser recovers the
# identical double. Estimation OUTPUT (att/se) is still reported at full 17g.
QUANT <- 2^13
qz <- function(x) round(x * QUANT) / QUANT

# ---------------------------------------------------------------------- data --
make_base <- function() {
  set.seed(SEED)
  nc <- length(COHORTS)
  ids <- seq_len(N_PER_COHORT * nc)
  gvec <- rep(COHORTS, each = N_PER_COHORT)
  ufe <- rnorm(length(ids))
  d <- data.frame(
    id   = rep(ids, each = length(PERIODS)),
    time = rep(PERIODS, times = length(ids)),
    g    = rep(gvec, each = length(PERIODS))
  )
  d$ufe <- rep(ufe, each = length(PERIODS))
  d$x1 <- qz(0.5 * d$ufe + 0.2 * d$time + rnorm(nrow(d), sd = 0.4))
  eff <- ifelse(d$g > 0 & d$time >= d$g, 1 + 0.5 * (d$time - d$g), 0)
  d$y <- qz(1 + 2 * d$x1 + d$ufe + 0.3 * d$time + eff + rnorm(nrow(d), sd = 0.5))
  d$ufe <- NULL
  d[, c("id", "time", "g", "x1", "y")]
}

BASE <- make_base()

# hard gate: the 17g text must round-trip through R's reader bit-identically
stopifnot(identical(as.numeric(sprintf("%.17g", BASE$x1)), BASE$x1),
          identical(as.numeric(sprintf("%.17g", BASE$y)), BASE$y))

kill_periods <- function(d, periods, only_g = NULL) {
  m <- d$time %in% periods
  if (!is.null(only_g)) m <- m & (d$g %in% only_g)
  d$x1[m] <- NA_real_
  d
}

# the sample R's balanced-panel coercion leaves behind: every unit with a
# missing covariate cell is gone whole (pre_process_did2.R, the
# "units are missing in some periods" step)
drop_incomplete_units <- function(d) {
  d[!(d$id %in% unique(d$id[is.na(d$x1)])), ]
}

# ------------------------------------------------------------------ runner ----
run_shape <- function(name, d, faster_mode, ...) {
  warns <- character(0)
  msgs  <- character(0)
  err   <- NA_character_
  fit   <- NULL
  withCallingHandlers(
    tryCatch({
      fit <- did::att_gt(
        yname = "y", tname = "time", idname = "id", gname = "g",
        xformla = ~x1, data = d, panel = TRUE,
        allow_unbalanced_panel = FALSE,
        control_group = "nevertreated",
        est_method = "dr", bstrap = FALSE, cband = FALSE,
        faster_mode = faster_mode, print_details = FALSE, ...
      )
    }, error = function(e) {
      err <<- conditionMessage(e)
    }),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning")
    },
    message = function(m) {
      msgs <<- c(msgs, sub("\n$", "", conditionMessage(m))); invokeRestart("muffleMessage")
    }
  )

  tag <- name
  con <- file(file.path(OUT, "expected/r", paste0("result_", tag, ".txt")), open = "wt")
  on.exit(close(con))
  wl <- function(...) cat(..., "\n", sep = "", file = con)

  wl("SHAPE: ", name)
  wl("faster_mode: ", faster_mode)
  wl("ERROR: ", if (is.na(err)) "<none>" else err)
  wl("N_WARNINGS: ", length(warns))
  for (i in seq_along(warns)) wl("WARNING[", i, "]: ", warns[i])
  wl("N_MESSAGES: ", length(msgs))
  for (i in seq_along(msgs)) wl("MESSAGE[", i, "]: ", msgs[i])

  if (!is.null(fit)) {
    dp <- fit$DIDparams
    tl <- if (faster_mode) dp$time_periods else dp$tlist
    gl <- if (faster_mode) dp$treated_groups else dp$glist
    wl("tlist: ", paste(g17(tl), collapse = " "))
    wl("glist: ", paste(g17(gl), collapse = " "))
    wl("fit_t_unique: ", paste(g17(sort(unique(fit$t))), collapse = " "))
    wl("fit_group_unique: ", paste(g17(sort(unique(fit$group))), collapse = " "))
    wl("fit_n: ", g17(fit$n))
    wl("DIDparams_panel: ", dp$panel)
    wl("DIDparams_allow_unbalanced_panel: ",
       if (is.null(dp$allow_unbalanced_panel)) "<NULL>" else dp$allow_unbalanced_panel)
    wl("DIDparams_true_repeated_cross_sections: ",
       if (is.null(dp$true_repeated_cross_sections)) "<NULL>" else dp$true_repeated_cross_sections)
    wl("inffunc_nrow: ", if (is.null(fit$inffunc)) "<NULL>" else nrow(fit$inffunc))
    wl("inffunc_ncol: ", if (is.null(fit$inffunc)) "<NULL>" else ncol(fit$inffunc))
    wl("n_cells: ", length(fit$att))
    wl("--- (g,t) table ---")
    wl("group\ttime\tatt\tse")
    for (i in seq_along(fit$att)) {
      wl(g17(fit$group[i]), "\t", g17(fit$t[i]), "\t",
         if (is.na(fit$att[i])) "NA" else g17(fit$att[i]), "\t",
         if (is.na(fit$se[i])) "NA" else g17(fit$se[i]))
    }
    tab <- data.frame(
      group = g17(fit$group), time = g17(fit$t),
      att = ifelse(is.na(fit$att), "NA", g17(fit$att)),
      se  = ifelse(is.na(fit$se), "NA", g17(fit$se))
    )
    write.csv(tab, file.path(OUT, "expected/r", paste0("attgt_", tag, ".csv")),
              row.names = FALSE, quote = FALSE)
  }
  invisible(NULL)
}

write_input <- function(name, d) {
  o <- data.frame(
    id = g17(d$id), time = g17(d$time), g = g17(d$g),
    x1 = ifelse(is.na(d$x1), "", g17(d$x1)),
    y  = g17(d$y)
  )
  write.csv(o, file.path(OUT, "inputs", paste0("input_", name, ".csv")),
            row.names = FALSE, quote = FALSE, na = "")
}

# ------------------------------------------------------------------- shapes ---
shapes <- list(
  list(name = "s00_clean",          d = BASE,                          args = list()),
  list(name = "s01_dead_middle",    d = kill_periods(BASE, 2),         args = list()),
  list(name = "s02_dead_first",     d = kill_periods(BASE, 1),         args = list()),
  list(name = "s03_dead_base",      d = kill_periods(BASE, 2),         args = list()),
  list(name = "s04_dead_g",         d = kill_periods(BASE, 3),         args = list()),
  list(name = "s05_dead_two",       d = kill_periods(BASE, c(2, 4)),   args = list()),
  list(name = "s06_dead_last",      d = kill_periods(BASE, 5),         args = list()),
  list(name = "s07_dead_universal", d = kill_periods(BASE, 2),         args = list(base_period = "universal")),
  list(name = "s08_dead_anticip",   d = kill_periods(BASE, 2),         args = list(anticipation = 1)),
  list(name = "s09_partial_control", d = kill_periods(BASE, 2, only_g = 0), args = list()),
  list(name = "s09b_partial_control_balanced",
       d = drop_incomplete_units(kill_periods(BASE, 2, only_g = 0)), args = list()),
  list(name = "s10_all_dead",       d = kill_periods(BASE, PERIODS),   args = list()),
  # extra boundary: the dead periods push the first SURVIVING period up onto a
  # cohort's own treatment date, so that cohort is dropped as "already treated in
  # the first period" -- the generalization of dead-first that shape 2 misses.
  list(name = "s11_dead_1and2",     d = kill_periods(BASE, c(1, 2)),   args = list())
)

for (s in shapes) {
  write_input(s$name, s$d)
  for (fm in c(TRUE)) {
    do.call(run_shape, c(list(name = s$name, d = s$d, faster_mode = fm), s$args))
  }
}

# ------------------------------------------- shape 1 unit-retention detail ----
{
  d1 <- kill_periods(BASE, 2)
  con <- file(file.path(OUT, "expected/r", "units_s01.txt"), open = "wt")
  wl <- function(...) cat(..., "\n", sep = "", file = con)
  wl("units_in_raw_data: ", length(unique(BASE$id)))
  wl("rows_raw: ", nrow(BASE))
  wl("rows_after_row_level_NA_drop: ", sum(!is.na(d1$x1)))
  wl("periods_surviving: ", paste(sort(unique(d1$time[!is.na(d1$x1)])), collapse = " "))
  wl("units_surviving_all_surviving_periods: ",
     length(unique(d1$id[!is.na(d1$x1)])))
  fitw <- suppressWarnings(suppressMessages(did::att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", xformla = ~x1,
    data = d1, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "nevertreated", est_method = "dr",
    bstrap = FALSE, cband = FALSE, faster_mode = TRUE)))
  wl("fit_n_fmTRUE: ", fitw$n)
  wl("inffunc_rownames_count_fmTRUE: ",
     if (is.null(rownames(fitw$inffunc))) "<none>" else length(rownames(fitw$inffunc)))
  fits <- suppressWarnings(suppressMessages(did::att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", xformla = ~x1,
    data = d1, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "nevertreated", est_method = "dr",
    bstrap = FALSE, cband = FALSE, faster_mode = FALSE)))
  wl("fit_n_fmFALSE: ", fits$n)
  wl("rows_in_dp_data_fmFALSE: ", nrow(fits$DIDparams$data))
  wl("units_in_dp_data_fmFALSE: ", length(unique(fits$DIDparams$data$id)))
  wl("periods_in_dp_data_fmFALSE: ",
     paste(sort(unique(fits$DIDparams$data$time)), collapse = " "))
  close(con)
}

cat("DONE\n")


suppressPackageStartupMessages(library(jsonlite))
manifest <- list(
  matrix_id = "RT036",
  fixture_family = "dead-period-covariate-rule",
  normative_source = "R did 2.5.1 pre_process_did.R: a period whose covariates are missing on every row is deleted before the period list exists; the reduced calendar governs the grid, base re-anchoring, the first-period cohort trim, balancing, and n",
  generators = list(list(
    runtime = "R",
    command = "Rscript tools/parity/generators/rt036/generate.R",
    path = "tools/parity/generators/rt036/generate.R"
  )),
  runtimes = list(list(name = "R", version = paste(R.version, R.version, sep = "."))),
  consumers = list("tests/stata/r/test-dead-period-covariate.do")
)
write_json(manifest, file.path(OUT, "metadata/manifest.json"), auto_unbox = TRUE, pretty = TRUE)
cat("rt036 fixtures written
")
