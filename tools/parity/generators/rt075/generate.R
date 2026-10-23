#!/usr/bin/env Rscript
# RT075: the pre-period OR sign in DRDID 1.4.0, through every csdid RC route.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/rt075/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = TRUE)
fixture <- file.path(root, "tests/fixtures/parity/rt075")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(fixture, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(path) digest::digest(file = path, algo = "sha256")
inputs <- list(); outputs <- list()
write17 <- function(z, path, input = FALSE, schema = "matrix") {
  z <- as.data.frame(z)
  original_dim <- dim(z)
  numeric <- vapply(z, is.numeric, logical(1))
  z[numeric] <- lapply(z[numeric], function(v) ifelse(is.na(v), "", sprintf("%.17g", v)))
  write.csv(z, file.path(fixture, path), row.names = FALSE, quote = FALSE, na = "")
  entry <- list(path = path, sha256 = sha(file.path(fixture, path)), rows = original_dim[1], columns = original_dim[2])
  if (input) inputs[[length(inputs) + 1L]] <<- entry else {
    entry$schema <- schema
    outputs[[length(outputs) + 1L]] <<- entry
  }
}
write_matrix <- function(x, path, keys = NULL) {
  x <- as.matrix(x)
  colnames(x) <- paste0("v", seq_len(ncol(x)))
  if (!is.null(keys)) x <- cbind(unit = keys, x)
  write17(x, path)
}

# The propensity index is nonlinear in x. Outcomes contain nonlinear trends
# and particularly noisy pre-treatment comparison observations, making the
# two pre-period OR derivative moments differ rather than cancel by accident.
make_data <- function(route, seed) {
  set.seed(seed)
  n <- 112L
  if (route == "rc") {
    z <- data.frame(id = seq_len(4L * n), time = rep(1:4, each = n))
    z$x <- rnorm(nrow(z))
    treated <- runif(nrow(z)) < plogis(-0.7 + 1.1 * pmax(z$x, 0)^2)
    z$g <- ifelse(treated, sample(2:4, nrow(z), replace = TRUE), 0)
    z$x2 <- runif(nrow(z), -1, 1)
    u <- rnorm(nrow(z))
  } else {
    x <- rnorm(n)
    treated <- runif(n) < plogis(-0.7 + 1.1 * pmax(x, 0)^2)
    g <- ifelse(treated, sample(2:4, n, replace = TRUE), 0)
    z <- expand.grid(time = 1:4, id = seq_len(n))[, c("id", "time")]
    z$g <- g[z$id]
    z$x <- x[z$id] + 0.06 * z$time * (z$g > 0)
    z$x2 <- runif(n)[z$id] + 0.03 * z$time
    u <- rnorm(n)[z$id]
  }
  z$y <- 0.8 + 1.2 * z$x + 0.4 * z$x2 + 0.3 * z$x^2 +
    z$time * (0.3 + 0.35 * z$x + 0.2 * z$x^2) + 0.4 * u +
    ifelse(z$g > 0 & z$time >= z$g, 0.6 + 0.25 * (z$time - z$g) + 0.2 * z$x, 0) +
    rnorm(nrow(z), sd = ifelse(z$g == 0 & z$time <= 2, 2.5, 0.7))
  z$w <- exp(0.25 * z$x + 0.15 * z$x2 + 0.04 * z$time)
  z$wzero <- ifelse((z$id + z$time) %% 11 == 0, 0, z$w)
  # Cluster sizes cycle through 3, 5 and 7 units; cl is never idname.
  block <- (z$id - 1L) %/% 15L
  remainder <- (z$id - 1L) %% 15L
  z$cl <- 3L * block + 1L + (remainder >= 3L) + (remainder >= 8L)
  if (route == "unbal") z <- z[!(z$id %% 5 == 0 & z$time == 2) & !(z$id %% 7 == 0 & z$time == 4), ]
  z <- z[order(z$id, z$time), ]
  rownames(z) <- NULL
  z
}

specs <- list(); data_sets <- list()
for (route in c("rc", "unbal", "vary")) {
  for (weight in c("none", "w", "wzero")) {
    seed <- c(none = 20261021L, w = 20261022L, wzero = 20261023L)[[weight]]
    input <- paste0(route, "_", weight)
    data_sets[[input]] <- make_data(route, seed)
    write17(data_sets[[input]], paste0("inputs/", input, ".csv"), input = TRUE)
    grid <- if (weight == "wzero") data.frame(base = c("universal", "varying"), control = c("nevertreated", "notyettreated")) else
      expand.grid(base = c("universal", "varying"), control = c("nevertreated", "notyettreated"), stringsAsFactors = FALSE)
    for (j in seq_len(nrow(grid))) specs[[length(specs) + 1L]] <- data.frame(
      scenario = paste(route, weight, grid$base[j], grid$control[j], "dr", sep = "_"),
      route = route, input = input, weight = weight, base = grid$base[j], control = grid$control[j], method = "dr", seed = seed)
  }
  for (method in c("reg", "ipw")) specs[[length(specs) + 1L]] <- data.frame(
    scenario = paste(route, "w_universal_nevertreated", method, sep = "_"),
    route = route, input = paste0(route, "_w"), weight = "w", base = "universal", control = "nevertreated", method = method, seed = 20261022L)
}
specs <- do.call(rbind, specs)
specs$bootstrap <- as.integer(specs$weight == "w" & specs$base == "universal" & specs$control == "nevertreated" & specs$method == "dr")
specs$cluster <- 0L
clustered <- specs[specs$bootstrap == 1L, ]
clustered$scenario <- paste0(clustered$scenario, "_cluster")
clustered$cluster <- 1L
specs <- rbind(specs, clustered)
write17(specs, "inputs/scenarios.csv", input = TRUE)

fit_spec <- function(s, boot = FALSE) {
  a <- list(yname = "y", tname = "time", idname = "id", gname = "g", xformla = ~x + x2,
    data = data_sets[[s$input]], panel = s$route != "rc", allow_unbalanced_panel = s$route == "unbal",
    control_group = s$control, base_period = s$base, est_method = s$method,
    bstrap = boot, cband = boot, biters = 199L)
  if (s$weight != "none") a$weightsname <- s$weight
  if (s$route == "vary") a$fix_weights <- "varying"
  if (s$cluster) a$clustervars <- "cl"
  suppressWarnings(suppressMessages(do.call(did::att_gt, a)))
}
ordered_if <- function(fit, z) {
  inf <- as.matrix(fit$inffunc)
  keys <- sort(unique(z$id))
  ord <- match(as.character(keys), rownames(inf))
  stopifnot(!anyNA(ord))
  list(inf = inf[ord, , drop = FALSE], order = ord, keys = keys)
}
agg_parts <- function(ag) {
  if (ag$type == "simple") return(list(
    table = matrix(c(NA_real_, ag$overall.att, ag$overall.se, ag$overall.att, ag$overall.se), 1L),
    inf = cbind(ag$inf.function$simple.att, ag$inf.function$simple.att)))
  inf <- ag$inf.function
  list(table = cbind(ag$egt, ag$att.egt, ag$se.egt, ag$overall.att, ag$overall.se),
       inf = cbind(as.matrix(inf[[1]]), as.numeric(inf[[2]])))
}

diagnostics <- list()
export_fit <- function(s, fit, suffix = "") {
  stem <- paste0(s$scenario, suffix)
  z <- data_sets[[s$input]]
  oi <- ordered_if(fit, z)
  stopifnot(length(fit$att) > 0L, all(is.finite(fit$att)))
  write17(data.frame(group = fit$group, time = fit$t, att = fit$att, se = fit$se), paste0("expected/r/", stem, "-attgt.csv"), schema = "attgt")
  write_matrix(oi$inf, paste0("expected/r/", stem, "-if.csv"), oi$keys)
  # did's V_analytical is n times Var(ATT); Stata posts Var(ATT), and
  # omits the universal-base normalization cells from its coefficient vector.
  posted <- if (s$base == "universal") which(fit$t != fit$group - 1) else seq_along(fit$att)
  covariance_path <- paste0("expected/r/", stem, "-v.csv")
  if (!nzchar(suffix)) write_matrix(as.matrix(fit$V_analytical)[posted, posted, drop = FALSE] / fit$n,
    covariance_path) else unlink(file.path(fixture, covariance_path))
  # The registered cluster+bootstrap divergence reports the available
  # analytical clustered Wald test rather than leaving it unset.
  wald_fit <- if (s$cluster && nzchar(suffix)) fit_spec(s) else fit
  diagnostics[[length(diagnostics) + 1L]] <<- data.frame(scenario = stem,
    wald = if (is.null(wald_fit$W)) NA_real_ else as.numeric(wald_fit$W),
    pvalue = if (is.null(wald_fit$Wpval)) NA_real_ else wald_fit$Wpval, crit = fit$c)
  for (type in c("dynamic", "group", "calendar", "simple")) {
    ag <- suppressWarnings(did::aggte(fit, type = type, bstrap = nzchar(suffix), cband = nzchar(suffix)))
    p <- agg_parts(ag)
    write_matrix(p$table, paste0("expected/r/", stem, "-", type, ".csv"))
    write_matrix(p$inf[oi$order, , drop = FALSE], paste0("expected/r/", stem, "-", type, "-if.csv"), oi$keys)
    if (nzchar(suffix)) write17(data.frame(crit = if (is.null(ag$crit.val.egt)) qnorm(0.975) else ag$crit.val.egt),
      paste0("expected/r/", stem, "-", type, "-crit.csv"), schema = "bootstrap-critical-value")
  }
}
for (i in seq_len(nrow(specs))) {
  s <- specs[i, ]
  export_fit(s, fit_spec(s))
  if (s$bootstrap) {
    set.seed(20261025L)
    export_fit(s, fit_spec(s, boot = TRUE), "_boot")
  }
}
write17(do.call(rbind, diagnostics), "expected/r/diagnostics.csv", schema = "wald-and-critical-values")

# This independent derivative check does not use att.inf.func to construct its
# target. Richardson extrapolation removes the O(h^2) finite-difference error.
set.seed(20261024L)
n <- 320L
x <- rnorm(n); x2 <- runif(n, -1, 1)
d <- as.numeric(runif(n) < plogis(-0.5 + 1.5 * pmax(x, 0)^2))
post <- as.numeric(runif(n) < 0.5)
y <- 1 + 2 * x + 0.5 * d + post * (0.5 + x + d) + rnorm(n) * ifelse(d == 0 & post == 0, 3, 1)
fddata <- data.frame(y = y, post = post, d = d, x = x, x2 = x2, w = exp(0.25 * x))
write17(fddata, "inputs/finite-difference.csv", input = TRUE)
X <- cbind(1, x, x2)
old <- DRDID::drdid_rc
old_body <- paste(deparse(body(old), width.cutoff = 500L), collapse = "\n")
old_body <- gsub("inf.treat.or.post - inf.treat.or.pre", "inf.treat.or.post + inf.treat.or.pre", old_body, fixed = TRUE)
old_body <- gsub("inf.cont.or.post - inf.cont.or.pre", "inf.cont.or.post + inf.cont.or.pre", old_body, fixed = TRUE)
body(old) <- parse(text = old_body)[[1L]]
checks <- list(); sensitivity <- list()
for (weight in c("none", "w", "wzero")) {
  w <- if (weight == "none") rep(1, n) else fddata$w
  if (weight == "wzero") w[seq(11, n, 11)] <- 0
  args <- list(y = y, post = post, D = d, covariates = X, i.weights = w, inffunc = TRUE, trim.level = 1)
  ref <- do.call(DRDID::drdid_rc, args)
  prior <- do.call(old, args)
  idx <- unlist(lapply(split(seq_len(n), interaction(d, post)), head, 2L), use.names = FALSE)
  fd <- function(i, h) {
    eval <- function(delta) {
      a <- args; a$i.weights[i] <- w[i] * (1 + delta)
      do.call(DRDID::drdid_rc, a)$ATT
    }
    n * (eval(h) - eval(-h)) / (2 * h)
  }
  derivative <- vapply(idx, function(i) (4 * fd(i, 0.005) - fd(i, 0.01)) / 3, numeric(1))
  stopifnot(all(abs(ref$att.inf.func[idx] - derivative) <= 1e-8 + 1e-8 * abs(derivative)))
  stopifnot(max(abs(prior$att.inf.func[idx] - derivative)) > 0.01)
  checks[[length(checks) + 1L]] <- data.frame(weight = weight, row = idx, if_value = ref$att.inf.func[idx], derivative = derivative)
  sensitivity[[length(sensitivity) + 1L]] <- data.frame(weight = weight, att_change = ref$ATT - prior$ATT,
    se_old = prior$se, se_new = ref$se, max_if_change = max(abs(ref$att.inf.func - prior$att.inf.func)),
    max_fd_error = max(abs(ref$att.inf.func[idx] - derivative)))
}
write17(do.call(rbind, checks), "expected/r/finite-difference.csv", schema = "independent-weight-derivative")
write17(do.call(rbind, sensitivity), "expected/r/sign-sensitivity.csv", schema = "old-versus-corrected-sign")

manifest <- list(matrix_id = "RT075", fixture_family = "r-drdid-140-rc-pre-or-sign",
  normative_source = "DRDID 1.4.0 drdid_rc.R:337-339; did 2.5.1 att_gt and aggte",
  source_commit = "eaac3b49cd225d0d7706c633858555a5f204e21e", decision_refs = list(), tolerance_ids = c("EXACT", "TOL001", "TOL002", "TOL003"),
  inputs = inputs, expected_outputs = outputs,
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/rt075/generate.R", path = "tools/parity/generators/rt075/generate.R", sha256 = sha(script_path))),
  runtimes = list(list(name = "R", version = as.character(getRversion()), package_versions = list(did = as.character(packageVersion("did")), DRDID = as.character(packageVersion("DRDID"))))),
  rng = list(data_seeds = 20261021:20261024, bootstrap_seed = 20261025L, biters = 199L,
    distribution = "rademacher", exact_draw_parity = TRUE,
    boundary = "Raw draws are not exported; all seeded cell/aggregation standard errors and critical values are checked at matched stream positions. Aggregation order: dynamic, group, calendar, simple."),
  comparison_plan = list(
    list(actual = "Every cell/SE, Wald statistic and rounded p-value; every aggregate effect/overall/SE", expected = "expected/r/*-attgt.csv, diagnostics.csv, *-{dynamic,group,calendar,simple}.csv", tolerance_id = "TOL001"),
    list(actual = "Every ATT and aggregation influence entry; ATT covariance", expected = "expected/r/*-if.csv, *-v.csv", tolerance_id = "TOL002"),
    list(actual = "Independent Richardson observation-weight derivatives", expected = "expected/r/finite-difference.csv", tolerance_id = "TOL002"),
    list(actual = "Seeded multiplier inference through all four aggregations", expected = "expected/r/*_boot-*", tolerance_id = "TOL003")),
  approved_divergence = NULL,
  scope_note = "39 scenarios on repeated cross sections, unbalanced bal(none) panels and balanced fix_weights(varying) panels; both bases and control groups, unweighted/weighted/zero-weight samples, three seeds, reg/ipw negative controls. Three additional clustered scenarios use cl distinct from id, with unbalanced cluster sizes 3/5/7, under analytical and bootstrap inference. The registered cluster+bootstrap Wald divergence compares against the analytical clustered R fit. All four aggregations and saved-RIF analytical roundtrips are exercised. Nonlinear propensity and outcome trends, covariate composition changes, heteroskedastic pre-control errors. Independent 2x2 weight derivatives and an old-sign mutant demonstrate sensitivity.")
jsonlite::write_json(manifest, file.path(fixture, "metadata/manifest.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("RT075:", nrow(specs), "scenarios,", sum(specs$bootstrap), "seeded chains,", length(outputs), "outputs\n")
print(do.call(rbind, sensitivity))
