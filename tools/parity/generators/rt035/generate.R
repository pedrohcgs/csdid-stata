#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt035/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/rt035")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

# Element-wise influence-function pin for the covariate-adjusted DR kernels
# on the three routes that share csdid__dr_rc_fit: a genuine repeated cross
# section, and an unbalanced panel on the allow-unbalanced route. Cell-level
# ATT/SE parity cannot see a defect that leaves the point estimate unchanged
# while corrupting the influence function (a sign flip inside one correction
# term, for example): only the element-wise matrix pins the inference chain
# -- analytic SEs, clustering, the multiplier bootstrap, aggregations --
# at its source. NOTE (alignment): att_gt returns repeated-cross-section
# influence-function rows keyed by ORIGINAL row index in its rownames, not
# in data order; the matrix is re-sorted into data order here so the
# committed oracle compares row-by-row against e(inffunc).
set.seed(20260828)
n <- 400; TT <- 4
gen_rcs <- function() {
  t <- sample(1:TT, n * TT, replace = TRUE)
  g <- sample(c(0, 3, 4), n * TT, replace = TRUE, prob = c(.4, .3, .3))
  id <- seq_len(n * TT)
  x1 <- rnorm(n * TT); x2 <- runif(n * TT)
  y <- 1 + 0.4 * x1 + 0.6 * x2 + 0.2 * t + 0.5 * (g > 0 & t >= g) + rnorm(n * TT, sd = 0.8)
  data.frame(id = id, t = t, g = g, x1 = x1, x2 = x2, y = y)
}
d_rcs <- gen_rcs()
write_17 <- function(d, path) {
  num <- vapply(d, is.numeric, logical(1))
  d[num] <- lapply(d[num], function(v) sprintf("%.17g", v))
  write.csv(d, path, row.names = FALSE, quote = FALSE)
}
write_17(d_rcs, file.path(fixture, "inputs/dr-rcs.csv"))

fit_rcs <- att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
                  xformla = ~ x1 + x2, data = d_rcs, panel = FALSE,
                  control_group = "nevertreated", base_period = "varying",
                  est_method = "dr", bstrap = FALSE, cband = FALSE)

export_fit <- function(fit, tag, ids_in_data_order) {
  att <- data.frame(group = fit$group, time = fit$t,
                    att = sprintf("%.17g", fit$att), se = sprintf("%.17g", fit$se))
  write.csv(att, file.path(fixture, sprintf("expected/r/%s-attgt.csv", tag)),
            row.names = FALSE, quote = FALSE)
  IF <- as.matrix(fit$inffunc)
  ord <- match(as.character(ids_in_data_order), rownames(IF))
  stopifnot(!anyNA(ord))
  IF <- IF[ord, , drop = FALSE]
  out <- as.data.frame(IF)
  names(out) <- sprintf("if%d", seq_len(ncol(IF)))
  out[] <- lapply(out, function(v) sprintf("%.17g", v))
  write.csv(out, file.path(fixture, sprintf("expected/r/%s-inffunc.csv", tag)),
            row.names = FALSE, quote = FALSE)
}
export_fit(fit_rcs, "rcs", d_rcs$id)

# unbalanced panel: units missing random periods, allow_unbalanced_panel route
gen_unbal <- function() {
  nu <- 300
  gu <- sample(c(0, 3, 4), nu, replace = TRUE, prob = c(.4, .3, .3))
  x1u <- rnorm(nu)
  rows <- do.call(rbind, lapply(seq_len(nu), function(i) {
    keep <- sort(sample(1:TT, sample(2:TT, 1)))
    data.frame(id = i, t = keep, g = gu[i], x1 = x1u[i])
  }))
  rows$x2 <- runif(nrow(rows))
  rows$y <- 1 + 0.4 * rows$x1 + 0.6 * rows$x2 + 0.2 * rows$t +
    0.5 * (rows$g > 0 & rows$t >= rows$g) + rnorm(nrow(rows), sd = 0.8)
  rows
}
d_un <- gen_unbal()
write_17(d_un, file.path(fixture, "inputs/dr-unbalanced.csv"))
fit_un <- suppressMessages(att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
                 xformla = ~ x1 + x2, data = d_un, panel = TRUE,
                 allow_unbalanced_panel = TRUE,
                 control_group = "nevertreated", base_period = "varying",
                 est_method = "dr", bstrap = FALSE, cband = FALSE))
IFu <- as.matrix(fit_un$inffunc)
# unbalanced-route IF rows are per UNIT; key by sorted unique id
export_fit_unit <- function(fit, tag, unit_ids) {
  att <- data.frame(group = fit$group, time = fit$t,
                    att = sprintf("%.17g", fit$att), se = sprintf("%.17g", fit$se))
  write.csv(att, file.path(fixture, sprintf("expected/r/%s-attgt.csv", tag)),
            row.names = FALSE, quote = FALSE)
  IF <- as.matrix(fit$inffunc)
  # the allow-unbalanced route's IF rows arrive in the reference's own unit
  # order (cohort-grouped), keyed by unit id in the rownames; re-sort into
  # ascending unit order, which is the order e(inffunc) reports
  ord <- match(as.character(unit_ids), rownames(IF))
  stopifnot(!anyNA(ord))
  IF <- IF[ord, , drop = FALSE]
  out <- as.data.frame(IF)
  names(out) <- sprintf("if%d", seq_len(ncol(IF)))
  out[] <- lapply(out, function(v) sprintf("%.17g", v))
  out <- cbind(data.frame(unit = unit_ids), out)
  write.csv(out, file.path(fixture, sprintf("expected/r/%s-inffunc.csv", tag)),
            row.names = FALSE, quote = FALSE)
}
export_fit_unit(fit_un, "unbalanced", sort(unique(d_un$id)))

manifest <- list(
  matrix_id = "RT035",
  fixture_family = "dr-covariate-inference-element-wise",
  normative_source = "R did 2.5.1 att_gt influence functions (DRDID drdid_rc kernel) on the covariate-adjusted DR repeated-cross-section and allow-unbalanced routes, element by element",
  generators = list(list(
    runtime = "R",
    command = "Rscript tools/parity/generators/rt035/generate.R",
    path = "tools/parity/generators/rt035/generate.R"
  )),
  inputs = list(
    list(path = "inputs/dr-rcs.csv", rows = nrow(d_rcs), columns = ncol(d_rcs)),
    list(path = "inputs/dr-unbalanced.csv", rows = nrow(d_un), columns = ncol(d_un))
  ),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."))),
  consumers = list("tests/stata/r/test-dr-inffunc-elementwise.do")
)
write_json(manifest, file.path(fixture, "metadata/manifest.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("rt035 fixtures written:", fixture, "\n")
cat("rcs cells:", length(fit_rcs$att), " IF dim:", paste(dim(as.matrix(fit_rcs$inffunc)), collapse = "x"), "\n")
cat("unbal cells:", length(fit_un$att), " IF dim:", paste(dim(IFu), collapse = "x"), "\n")
