#!/usr/bin/env Rscript

# Record provenance without the maintainer's home directory: these fixtures are
# published, and an absolute path both leaks the layout and means nothing on
# another machine.
abbrev_home <- function(p) sub(path.expand("~"), "~", p, fixed = TRUE)

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/py014/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because the generator had previously written a stray
# tools/tests/ tree there -- which is exactly where that duplicate came from.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)
source(file.path(root, "tools/parity/generators/f040/generate.R"))
