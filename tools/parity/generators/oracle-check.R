# Oracle content gate. source() this before library(did) work in a generator.
#
# A version string is not evidence: an installed build has been observed
# reporting 2.5.1 while running older code. This gate therefore checks the
# CONTENT of the loaded package -- the presence of the 2.5.1-era code paths
# this repo's fixtures depend on -- and stops the generator cold when the
# loaded did is not the oracle the parity contract names.
#
# Set CSDID_DID_UPSTREAM to a did source checkout to pin the oracle to that
# tree (loaded via pkgload/devtools if available); otherwise the installed
# library is used and content-verified.

local({
  upstream <- Sys.getenv("CSDID_DID_UPSTREAM", "")
  if (nzchar(upstream)) {
    if (!requireNamespace("pkgload", quietly = TRUE)) {
      stop("CSDID_DID_UPSTREAM is set but pkgload is not installed; ",
           "install pkgload or unset CSDID_DID_UPSTREAM")
    }
    pkgload::load_all(upstream, export_all = FALSE, quiet = TRUE)
  } else {
    suppressPackageStartupMessages(library(did))
  }

  ver <- as.character(utils::packageVersion("did"))
  if (ver != "2.5.1") {
    stop("oracle gate: loaded did reports version ", ver,
         " but the parity contract is frozen on 2.5.1")
  }
  body_src <- deparse(body(did::att_gt))
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
  message("oracle gate: did 2.5.1 content-verified at ", find.package("did"))
})
