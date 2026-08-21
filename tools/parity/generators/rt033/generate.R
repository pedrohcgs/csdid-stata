#!/usr/bin/env Rscript

# ---------------------------------------------------------------------------
# rt033 -- the three panel-shape refusals, judged on the sample BEFORE the
# missingness screen.
#
# R runs validate_args() on the data as it is handed over and removes rows with
# missing or non-finite values only afterwards, in did_standardization(). A
# duplicate (id, time), a cohort reversal or a time-varying cluster variable
# carried by a row that a complete-case screen would remove is therefore still
# a refusal for the oracle. csdid decides the same three on a sample that has
# already lost those rows, so the two can only agree if the checks are re-run
# on the wider sample under R's own per-check screens -- and those screens are
# not the same for the three checks, which is what the negative cells below
# pin down.
#
# The designs come in three kinds:
#   the nine-cell matrix   each check against a violation on a KEPT row, the
#                          same violation on a row the screen DROPS, and no
#                          violation at all
#   the screen negatives   violations that R does NOT refuse because its own
#                          screen removes them (a duplicate whose copy has no
#                          time or no id, a reversal on a row with no gvar or
#                          no id, a cluster missing in every period of a unit)
#   the order designs      panels that break two rules at once, which fix the
#                          sentence the user is asked to act on
#
# Expected verdicts are the oracle's, recorded as refuse/proceed plus which of
# the three refusals fired.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt033/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt033")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

# ---- the panel every design starts from ------------------------------------
n_units <- 12L
n_times <- 4L
base_panel <- function() {
  set.seed(20260816L)
  id <- rep(seq_len(n_units), each = n_times)
  t  <- rep(seq_len(n_times), times = n_units)
  g  <- rep(c(0, 0, 0, 0, 3, 3, 3, 3, 4, 4, 4, 4), each = n_times)
  x  <- rep(rnorm(n_units), each = n_times)
  w  <- rep(runif(n_units, 0.5, 1.5), each = n_times)
  cl <- rep(rep(1:2, length.out = n_units), each = n_times)
  y  <- 0.3 * x + 0.5 * t + (g > 0 & t >= g) * 1.0 +
        rnorm(n_units * n_times, 0, 0.2)
  data.frame(id = id, t = t, g = g, y = y, x = x, w = w, cl = cl)
}

designs <- list(
  # -- the nine-cell matrix -------------------------------------------------
  gvar_kept = function(d) { d$g[d$id == 5 & d$t == 3] <- 4; d },
  gvar_dropped = function(d) { i <- d$id == 5 & d$t == 3
                               d$g[i] <- 4; d$y[i] <- NA; d },
  gvar_none = function(d) d,
  dup_kept = function(d) rbind(d, d[d$id == 5 & d$t == 2, ]),
  dup_dropped = function(d) { r <- d[d$id == 5 & d$t == 2, ]; r$y <- NA
                              rbind(d, r) },
  dup_none = function(d) d,
  cluster_kept = function(d) { d$cl[d$id == 5 & d$t == 2] <- 2; d },
  # a cluster present in one period and missing in another is TWO values, and
  # the row that carries the missing one is exactly the row csdid's screen
  # removes -- the check and the screen collide on the same row
  cluster_missing_one_period = function(d) { d$cl[d$id == 5 & d$t == 2] <- NA
                                             d },
  cluster_dropped = function(d) { i <- d$id == 5 & d$t == 2
                                  d$cl[i] <- 2; d$x[i] <- NA; d },
  cluster_none = function(d) d,

  # -- the other screen channels -------------------------------------------
  dup_weight = function(d) { r <- d[d$id == 5 & d$t == 2, ]; r$w <- NA
                             rbind(d, r) },
  dup_covariate = function(d) { r <- d[d$id == 5 & d$t == 2, ]; r$x <- NA
                                rbind(d, r) },
  dup_gvar = function(d) { r <- d[d$id == 5 & d$t == 2, ]; r$g <- NA
                           rbind(d, r) },

  # -- the screen negatives: R's own screens excuse these -------------------
  dup_missing_time = function(d) { r <- d[d$id == 5 & d$t == 2, ]; r$t <- NA
                                   rbind(d, r) },
  dup_missing_id = function(d) { r <- d[d$id == 5 & d$t == 2, ]; r$id <- NA
                                 rbind(d, r) },
  gvar_missing_gvar = function(d) { d$g[d$id == 5 & d$t == 3] <- NA; d },
  gvar_missing_id = function(d) { i <- d$id == 5 & d$t == 3
                                  d$g[i] <- 4; d$id[i] <- NA; d },
  cluster_all_missing = function(d) { d$cl[d$id == 5] <- NA; d },
  cluster_missing_id_agree = function(d) { d$cl[d$id %in% c(5, 6)] <- 1
                                           d$id[d$id %in% c(5, 6) & d$t == 2] <- NA
                                           d },
  cluster_missing_id_differ = function(d) { d$id[d$id %in% c(5, 6) & d$t == 2] <- NA
                                            d },

  # -- two rules broken at once: which sentence the user gets ---------------
  order_dup_beats_cluster = function(d) { d$cl[d$id == 7 & d$t == 2] <- 2
                                          rbind(d, d[d$id == 5 & d$t == 2, ]) },
  order_gvar_beats_dup = function(d) { d$g[d$id == 9 & d$t == 3] <- 3
                                       rbind(d, d[d$id == 5 & d$t == 2, ]) },
  order_dup_beats_cluster_dropped = function(d) { i <- d$id == 7 & d$t == 2
                                                  d$cl[i] <- 2; d$y[i] <- NA
                                                  rbind(d, d[d$id == 5 & d$t == 2, ]) }
)

# ---- workhorse: write the design, record the oracle's verdict ---------------
# The refusal is classified by its message so the Stata side can assert WHICH
# check fired, not merely that something did.
classify <- function(msg) {
  if (grepl("must be the same across all periods", msg, fixed = TRUE)) return("gvar")
  if (grepl("must be unique (by tname)", msg, fixed = TRUE)) return("dup")
  if (grepl("Time-varying cluster variables", msg, fixed = TRUE)) return("cluster")
  paste0("other: ", msg)
}

probe <- function(tag, mutate) {
  d <- mutate(base_panel())
  write.csv(d, file.path(fixture, "inputs", paste0(tag, ".csv")),
            row.names = FALSE, na = ".")
  v <- tryCatch({
    att_gt(yname = "y", tname = "t", idname = "id", gname = "g", xformla = ~x,
           weightsname = "w", clustervars = "cl", data = d,
           control_group = "notyettreated", base_period = "universal",
           bstrap = FALSE, cband = FALSE)
    list(refuses = 0L, refusal = "none")
  }, error = function(e) list(refuses = 1L,
                              refusal = classify(conditionMessage(e))))
  data.frame(tag = tag, rows = nrow(d), refuses = v$refuses,
             refusal = v$refusal, stringsAsFactors = FALSE)
}

verdicts <- do.call(rbind, lapply(names(designs),
                                  function(k) suppressWarnings(probe(k, designs[[k]]))))
write.csv(verdicts, file.path(fixture, "expected/r/verdicts.csv"),
          row.names = FALSE)

stray <- verdicts$refusal[grepl("^other: ", verdicts$refusal)]
if (length(stray)) {
  stop("rt033: a design refused for a reason outside the three shape checks, ",
       "so it does not measure what it claims: ", paste(stray, collapse = " | "))
}

manifest <- list(
  matrix_id = "RT033",
  fixture_family = "shape-checks-before-missingness",
  normative_source = paste(
    "R did 2.5.1: validate_args() decides gname irreversibility, duplicate",
    "(id, time) and time-varying clustervars on the data as supplied, before",
    "did_standardization() removes rows with missing or non-finite values;",
    "each check screens its own columns only"),
  generators = list(list(
    runtime = "R",
    command = "Rscript tools/parity/generators/rt033/generate.R",
    path = "tools/parity/generators/rt033/generate.R"
  )),
  inputs = lapply(seq_len(nrow(verdicts)), function(i) list(
    path = paste0("inputs/", verdicts$tag[i], ".csv"),
    rows = verdicts$rows[i], columns = 7L)),
  runtimes = list(list(name = "R",
                       version = paste(R.version$major, R.version$minor, sep = "."))),
  consumers = list("tests/stata/r/test-shape-checks-pre-screen.do")
)
write_json(manifest, file.path(fixture, "metadata/manifest.json"),
           auto_unbox = TRUE, pretty = TRUE)

cat("rt033 fixtures written:", fixture, "\n")
print(verdicts)
