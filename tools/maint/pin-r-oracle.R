#!/usr/bin/env Rscript
# Pin the exact reference source and the loaded estimator bodies together.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || args != "--write")
  stop("usage: CSDID_DID_UPSTREAM=<checkout> Rscript tools/maint/pin-r-oracle.R --write")
upstream <- Sys.getenv("CSDID_DID_UPSTREAM")
if (!nzchar(upstream)) stop("CSDID_DID_UPSTREAM must name the reviewed checkout")
pkgload::load_all(upstream, export_all = FALSE, quiet = TRUE)
commit <- system2("git", c("-C", shQuote(upstream), "rev-parse", "HEAD"), stdout = TRUE)
dirty <- system2("git", c("-C", shQuote(upstream), "status", "--porcelain"), stdout = TRUE)
if (length(dirty)) stop("reference checkout must be clean")
fns <- list(did::att_gt, did::aggte, did:::compute.att_gt,
            did:::compute.aggte, did:::mboot, did:::pre_process_did,
            DRDID::drdid, DRDID::drdid_panel, DRDID::drdid_rc,
            DRDID::reg_did_panel, DRDID::reg_did_rc,
            DRDID::std_ipw_did_panel, DRDID::std_ipw_did_rc)
text <- paste(unlist(lapply(fns, deparse)), collapse = "\n")
short <- substr(digest::digest(text, algo = "sha256"), 1L, 16L)
records <- lapply(c("did", "DRDID"), function(package) {
  ns <- asNamespace(package)
  code <- lapply(sort(ls(ns, all.names = TRUE), method = "radix"), function(name) {
    fn <- get(name, envir = ns, inherits = FALSE)
    if (!is.function(fn)) return(NULL)
    paste(package, name,
          paste(deparse(formals(fn), width.cutoff = 500L), collapse = "\n"),
          paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n"), sep = "\n")
  })
  unlist(code, use.names = FALSE)
})
full <- digest::digest(paste(unlist(records, use.names = FALSE), collapse = "\n"),
                       algo = "sha256", serialize = FALSE)
writeLines(short, "inst/spec/r-oracle-code-digest.txt")
writeLines(full, "inst/spec/r-oracle-full-code-digest.txt")
jsonlite::write_json(list(did_version = as.character(packageVersion("did")),
  did_commit = commit, DRDID_version = as.character(packageVersion("DRDID"))),
  "inst/spec/r-oracle-reference.json", pretty = TRUE, auto_unbox = TRUE)
cat("Pinned", commit, "with", length(unlist(records, use.names = FALSE)), "functions:", full, "\n")
