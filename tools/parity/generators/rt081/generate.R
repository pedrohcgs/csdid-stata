#!/usr/bin/env Rscript

# Contract-only inheritance refresh. Numerical expectations belong to the
# estimators' fixture generators, not to this source-test inventory.
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1L]]) else
  "tools/parity/generators/rt081/generate.R"
source(file.path(dirname(script_path), "../oracle-check.R"))
upstream <- Sys.getenv("CSDID_DID_UPSTREAM", "")
if (!nzchar(upstream)) stop("RT081 needs CSDID_DID_UPSTREAM to authenticate source tests")
status <- system2("python3", c(shQuote(file.path(dirname(script_path), "refresh.py")),
                               shQuote(upstream)))
if (status != 0L) stop("RT081 inheritance refresh failed: ", status)
