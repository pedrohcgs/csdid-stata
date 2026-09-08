# Runtime authentication checks; run by the R oracle environment gate.
gate <- normalizePath("tools/parity/generators/oracle-check.R")
generators <- sort(list.files("tools/parity/generators", "^generate\\.R$",
                              recursive = TRUE, full.names = TRUE))
stopifnot(length(generators) >= 100L)
for (generator in generators) {
  env <- new.env(parent = globalenv())
  env$commandArgs <- function(...) paste0("--file=", generator)
  env$source <- function(file, ...) {
    if (!identical(normalizePath(file), gate)) stop("unexpected source before authentication")
    stop(structure(list(message = "authenticated entry", call = NULL),
                   class = c("authenticated_entry", "error", "condition")))
  }
  env$library <- function(package, ...) {
    if (as.character(substitute(package)) %in% c("did", "DRDID"))
      stop("oracle loaded before authentication")
    invisible(NULL)
  }
  for (name in c("read.csv", "write.csv", "readRDS", "saveRDS", "system2",
                 "dir.create", "write_json")) {
    env[[name]] <- function(...) stop("fixture work before authentication")
  }
  reached <- tryCatch({eval(parse(generator), env); FALSE},
                      authenticated_entry = function(e) TRUE,
                      error = function(e) stop(generator, ": ", conditionMessage(e)))
  if (!reached) stop(generator, " completed without authenticating its oracle")
}

source(gate)
traced <- list(did = c("att_gt", "run_DRDID", "run_att_gt_estimation", "get_agg_inf_func"),
               DRDID = "fastglm_fit")
for (package in names(traced)) for (name in traced[[package]]) {
  invisible(suppressMessages(trace(name, where = asNamespace(package),
                                  exit = quote(invisible(NULL)), print = FALSE)))
}
source(gate)
for (package in names(traced)) for (name in traced[[package]]) {
  invisible(suppressMessages(untrace(name, where = asNamespace(package))))
}

reject_mutation <- function(package, name, alter, traced = FALSE) {
  ns <- asNamespace(package)
  old <- get(name, ns)
  unlockBinding(name, ns)
  assign(name, alter(old), ns)
  lockBinding(name, ns)
  on.exit({unlockBinding(name, ns); assign(name, old, ns); lockBinding(name, ns)})
  if (traced) invisible(suppressMessages(trace(name, where = ns,
    exit = quote(invisible(NULL)), print = FALSE)))
  rejected <- tryCatch({source(gate); FALSE}, error = function(e) {
    grepl("oracle gate:", conditionMessage(e), fixed = TRUE)
  })
  if (!rejected) stop(package, "::", name, " mutation was not rejected")
}
body_mutation <- function(fn) {
  body(fn) <- quote(stop("seeded implementation mutation"))
  fn
}
mutations <- 0L
for (package in c("did", "DRDID")) {
  ns <- asNamespace(package)
  for (name in sort(ls(ns, all.names = TRUE), method = "radix")) {
    if (!is.function(get(name, ns, inherits = FALSE))) next
    reject_mutation(package, name, body_mutation)
    mutations <- mutations + 1L
  }
}
reject_mutation("did", "run_DRDID", function(fn) {
  formals(fn)$force_rc <- TRUE
  fn
})
reject_mutation("did", "get_agg_inf_func", function(fn) NULL)
reject_mutation("did", "run_att_gt_estimation", body_mutation, traced = TRUE)
source(gate)

scratch <- tempfile("csdid-oracle-gate-")
dir.create(file.path(scratch, "tools/parity/generators"), recursive = TRUE)
dir.create(file.path(scratch, "inst/spec"), recursive = TRUE)
copy <- file.path(scratch, "tools/parity/generators/oracle-check.R")
file.copy(gate, copy)
fingerprints <- c("r-oracle-code-digest.txt", "r-oracle-full-code-digest.txt")
for (fingerprint in fingerprints) {
  for (mode in c("missing", "empty", "wrong")) {
    for (other in fingerprints) {
      file.copy(file.path("inst/spec", other), file.path(scratch, "inst/spec", other),
                overwrite = TRUE)
    }
    path <- file.path(scratch, "inst/spec", fingerprint)
    if (mode == "missing") unlink(path)
    if (mode == "empty") writeLines(character(), path)
    if (mode == "wrong") writeLines(strrep("0", 64L), path)
    rejected <- suppressWarnings(tryCatch({source(copy); FALSE}, error = function(e) TRUE))
    if (!rejected) stop(mode, " ", fingerprint, " was accepted")
  }
}
unlink(scratch, recursive = TRUE)
source("tools/parity/test-generator-child-status.R")
cat("Oracle authentication:", length(generators), "entry points; five simultaneous traces;",
    mutations, "altered bodies; default, binding and traced-body mutations; six invalid fingerprints checked\n")
