# Runtime qualification of the observed design/support collector. No Stata or
# benchmark process is launched, and estimator values are never changed.
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) normalizePath(args[[1L]]) else normalizePath(".")
source(file.path(root, "tools/parity/generators/oracle-check.R"))
source(file.path(root, "tools/parity/capture-differential-designs.R"))
out <- tempfile("csdid-design-capture-")
dir.create(out)

run_case <- function(mode, ncov, method, degenerate = FALSE, gaps = FALSE, balanced_data = FALSE) {
  d <- expand.grid(id = 1:48, time = 1:5)
  d$g <- c(0, 3, 4)[1 + (d$id %% 3)]
  d$x1 <- (d$id %% 11) / 8 + d$time / 16
  d$x2 <- d$x1 + (d$id %% 7) / 2^30  # never fitted on ncov=0/1
  d$y <- d$id / 8 + d$time / 4 + (d$g > 0 & d$time >= d$g) * 2
  if (!degenerate) d$y <- d$y + (d$id %% 5) * d$time / 32 + ((d$id * d$time) %% 7) / 64
  if (mode != "rcs" && !balanced_data) d <- d[!(d$id == 1 & d$time == 2), ]
  if (ncov && !balanced_data) d$x1[d$id == 2 & d$time == 3] <- NA_real_
  if (gaps) {
    d$time <- 1990 + 5 * d$time
    d$g[d$g > 0] <- 1990 + 5 * d$g[d$g > 0]
  }
  formula <- if (ncov) ~x1 else ~1
  tag <- paste(mode, ncov, method, degenerate, gaps, balanced_data, sep = "-")
  input <- file.path(out, paste0(tag, ".csv"))
  write.csv(d, input, row.names = FALSE)
  csdid_design_begin(tag, input, list())
  call <- list(yname = "y", tname = "time", gname = "g", data = d,
    xformla = formula, panel = mode != "rcs", allow_unbalanced_panel = mode == "unbalanced",
    est_method = method, control_group = "notyettreated", base_period = "universal",
    anticipation = if (gaps) 1 else 0, bstrap = FALSE, cband = FALSE)
  if (mode != "rcs") call$idname <- "id"
  fit <- suppressWarnings(do.call(did::att_gt, call))
  for (type in c("simple", "group", "calendar", "dynamic")) {
    csdid_design_agg_begin(type)
    result <- tryCatch(suppressWarnings(did::aggte(fit, type = type, na.rm = TRUE,
      bstrap = FALSE, cband = FALSE)), error = function(e) e)
    csdid_design_agg_end(result)
  }
  csdid_design_agg_begin("dynwin")
  result <- tryCatch(suppressWarnings(did::aggte(fit, type = "dynamic", balance_e = 0,
    min_e = -5, max_e = 5, na.rm = TRUE, bstrap = FALSE, cband = FALSE)), error = function(e) e)
  csdid_design_agg_end(result)
  stopifnot(length(.csdid_design_capture$errors) == 0L)
  cells <- .csdid_design_capture$cells
  stopifnot(setequal(names(cells), paste(fit$group, fit$t, sep = ":")))
  if (balanced_data) {
    stopifnot(mode == "unbalanced", !fit$DIDparams$allow_unbalanced_panel)
    observed <- Filter(function(cell) !is.null(cell$route), cells)
    stopifnot(length(observed) > 0L,
      all(vapply(observed, function(cell) cell$route == "panel", logical(1L))))
  }
  q <- as.data.frame(fit$DIDparams$data)
  idname <- fit$DIDparams$idname
  source_keys <- paste(q[[idname]], q$time, sep = ":")
  structural <- 0L
  fitted <- 0L
  for (cell in cells) {
    if (cell$status == "structural_zero") {
      structural <- structural + 1L
      stopifnot(is.null(cell$X_f64le))
    }
    if (cell$status != "fitted") next
    fitted <- fitted + 1L
    stopifnot(cell$columns == ncov + 1L)
    x <- matrix(readBin(jsonlite::base64_dec(cell$X_f64le), "double",
      n = cell$rows * cell$columns, size = 8L, endian = "little"), nrow = cell$rows)
    rows <- match(paste(cell$ids, cell$periods, sep = ":"), source_keys)
    stopifnot(!anyNA(rows))
    expected <- unname(model.matrix(formula, q[rows, , drop = FALSE]))
    stopifnot(identical(dim(x), dim(expected)), identical(as.vector(x), as.vector(expected)))
    if (!ncov) stopifnot(kappa(x, exact = TRUE) == 1)
  }
  stopifnot(fitted > 0L, structural > 0L)
  # Universal-base dynamic rows contain explicit normalization-only support.
  support <- .csdid_design_capture$aggregations$dynamic$supports
  stopifnot(any(vapply(support, function(keys) length(keys) > 0L &&
    all(vapply(cells[unlist(keys)], function(cell) cell$status == "structural_zero", logical(1L))), logical(1L))))
  if (degenerate) stopifnot(any(is.finite(fit$att) & is.na(fit$se) & fit$att != 0))
  cat("design capture:", tag, "passed", fitted, "fits and", structural, "normalizations\n")
}

for (method in c("dr", "reg", "ipw")) run_case("balanced", 0L, method)
for (mode in c("balanced", "unbalanced", "rcs")) run_case(mode, 1L, "reg", gaps = TRUE)
run_case("balanced", 0L, "reg", degenerate = TRUE)
for (method in c("dr", "reg", "ipw")) for (ncov in 0:1) {
  run_case("unbalanced", ncov, method, balanced_data = TRUE)
}
# No post-treatment cells survive the original comparison cutoff. The default
# reference returns normalized/placebo cells but its aggregations refuse.
d <- expand.grid(id = 1:30, time = 1:4)
d$g <- rep(c(0, 3, 4), each = 10L)[d$id]
d <- d[!(d$g == 0 & d$time == 1), ]
d$y <- d$id * d$time / 64 + ((d$id * d$time) %% 11) / 8
input <- file.path(out, "refused-aggregation.csv")
write.csv(d, input, row.names = FALSE)
csdid_design_begin("refused-aggregation", input, list())
fit <- suppressWarnings(did::att_gt(yname = "y", tname = "time", gname = "g",
  idname = "id", data = d, panel = TRUE, allow_unbalanced_panel = FALSE,
  control_group = "nevertreated", base_period = "universal", est_method = "reg",
  bstrap = FALSE, cband = FALSE))
csdid_design_agg_begin("dynamic")
a <- tryCatch(suppressWarnings(did::aggte(fit, type = "dynamic", na.rm = TRUE,
  bstrap = FALSE, cband = FALSE)), error = function(e) e)
csdid_design_agg_end(a)
stopifnot(inherits(a, "error"), length(.csdid_design_capture$errors) == 0L,
  .csdid_design_capture$aggregations$dynamic$status == "refused",
  length(.csdid_design_capture$aggregations$dynamic$errors) > 0L)
# Missing observations on a successful returned aggregation remain fatal.
csdid_design_agg_begin("seeded-returned-error")
.csdid_design_capture$current_errors <- "seeded missing support"
csdid_design_agg_end(list(egt = numeric()))
stopifnot("seeded missing support" %in% .csdid_design_capture$errors)
cat("design capture: refused aggregation diagnostics stay distinct from returned estimates\n")
unlink(out, recursive = TRUE)
cat("DIFFERENTIAL-DESIGN-CAPTURE-COMPLETE\n")
