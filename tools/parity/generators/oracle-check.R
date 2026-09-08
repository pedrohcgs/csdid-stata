# Oracle content gate. source() this before library(did) work in a generator.
#
# A version string is not evidence: an installed build has been observed
# reporting 2.5.1 while running older code. This gate therefore checks the
# CONTENT of the loaded did/DRDID functions against the frozen fingerprint,
# before a generator can write its expectations.
#
# Set CSDID_DID_UPSTREAM to a did source checkout to pin the oracle to that
# tree (loaded via pkgload/devtools if available); otherwise the installed
# library is used and content-verified.

local({
  source_paths <- vapply(sys.frames(), function(frame) {
    path <- frame$ofile
    if (is.null(path)) "" else as.character(path)[1L]
  }, character(1))
  source_paths <- source_paths[nzchar(source_paths)]
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  gate_path <- if (length(source_paths)) tail(source_paths, 1L) else
    if (length(file_arg)) sub("^--file=", "", file_arg[1L]) else
      "tools/parity/generators/oracle-check.R"
  digest_file <- file.path(dirname(normalizePath(gate_path, mustWork = TRUE)),
                           "../../../inst/spec/r-oracle-code-digest.txt")

  upstream <- Sys.getenv("CSDID_DID_UPSTREAM", "")
  if (nzchar(upstream)) {
    if (!requireNamespace("pkgload", quietly = TRUE)) {
      stop("CSDID_DID_UPSTREAM is set but pkgload is not installed; ",
           "install pkgload or unset CSDID_DID_UPSTREAM")
    }
    loaded_path <- if ("did" %in% loadedNamespaces()) find.package("did") else ""
    if (!identical(loaded_path, normalizePath(upstream, mustWork = TRUE))) {
      pkgload::load_all(upstream, export_all = FALSE, quiet = TRUE)
    }
  } else {
    suppressPackageStartupMessages(library(did))
  }

  ver <- as.character(utils::packageVersion("did"))
  if (ver != "2.5.1") {
    stop("oracle gate: loaded did reports version ", ver,
         " but the parity contract is frozen on 2.5.1")
  }
  drdid_ver <- as.character(utils::packageVersion("DRDID"))
  if (drdid_ver != "1.3.0") {
    stop("oracle gate: loaded DRDID reports version ", drdid_ver,
         " but the parity contract is frozen on 1.3.0")
  }
  # Regeneration traces calls to attest their execution. Inspect each traced
  # function's original body, so instrumentation cannot change the fingerprint.
  original <- function(fn) {
    while (methods::is(fn, "traceable")) fn <- fn@original
    fn
  }
  body_src <- deparse(body(original(did::att_gt)))
  probes <- c(
    "extra_clustervars",   # 2.5.1 cluster handling (analytic cluster-robust V)
    "cluster_analytic"
  )
  missing_probes <- probes[!vapply(probes, function(p) any(grepl(p, body_src, fixed = TRUE)), logical(1))]
  if (length(missing_probes)) {
    stop("oracle gate: loaded did (", find.package("did"), ") reports 2.5.1 ",
         "but its att_gt body lacks: ", paste(missing_probes, collapse = ", "),
         " -- the installed build is stale; reinstall from the pinned source")
  }
  fns <- list(did::att_gt, did::aggte, did:::compute.att_gt,
              did:::compute.aggte, did:::mboot, did:::pre_process_did,
              DRDID::drdid, DRDID::drdid_panel, DRDID::drdid_rc,
              DRDID::reg_did_panel, DRDID::reg_did_rc,
              DRDID::std_ipw_did_panel, DRDID::std_ipw_did_rc)
  text <- paste(unlist(lapply(fns, function(fn) deparse(original(fn)))),
                collapse = "\n")
  actual <- substr(digest::digest(text, algo = "sha256"), 1L, 16L)
  expected <- trimws(paste(readLines(digest_file, warn = FALSE), collapse = ""))
  if (!nzchar(expected) || !identical(actual, expected)) {
    stop("oracle gate: loaded did/DRDID code digest ", actual,
         " differs from the frozen fingerprint in ", digest_file)
  }
  # The original fingerprint predates the fast route. Authenticate every
  # function bound in each package namespace, including internal helpers.
  # Canonical text excludes environments, bytecode and source references.
  records <- lapply(c("did", "DRDID"), function(package) {
    ns <- asNamespace(package)
    names <- sort(ls(ns, all.names = TRUE), method = "radix")
    code <- lapply(names, function(name) {
      fn <- get(name, envir = ns, inherits = FALSE)
      if (!is.function(fn)) return(NULL)
      fn <- original(fn)
      paste(package, name,
            paste(deparse(formals(fn), width.cutoff = 500L), collapse = "\n"),
            paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n"),
            sep = "\n")
    })
    unlist(code, use.names = FALSE)
  })
  full_text <- paste(unlist(records, use.names = FALSE), collapse = "\n")
  full_actual <- digest::digest(full_text, algo = "sha256", serialize = FALSE)
  full_digest_file <- file.path(dirname(digest_file), "r-oracle-full-code-digest.txt")
  full_expected <- trimws(paste(readLines(full_digest_file, warn = FALSE), collapse = ""))
  if (!nzchar(full_expected) || !identical(full_actual, full_expected)) {
    stop("oracle gate: loaded did/DRDID full code digest ", full_actual,
         " differs from the frozen fingerprint in ", full_digest_file)
  }
  message("oracle gate: did 2.5.1 / DRDID 1.3.0 content-verified (", actual,
          "; all ", length(unlist(records, use.names = FALSE)), " R functions ",
          full_actual, ") at ", find.package("did"))
})
