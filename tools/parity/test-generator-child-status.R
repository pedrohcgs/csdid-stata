# Base-R transport qualification; no numerical generator or oracle is run.
# The authentication mock permits entry into the child-call boundary only;
# test-oracle-authentication.R independently verifies the real oracle gate.
local({
  root <- normalizePath(getwd())
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  scratch <- tempfile("csdid-generator-child-")
  dir.create(scratch)
  failures <- character()
  checks <- 0L
  tryCatch({
    for (family in c("rt005", "rt019")) {
      child <- if (family == "rt005") "py003" else "f011"
      for (layout in c("plain", "with spaces")) for (status in c(0L, 7L, 23L, 42L)) {
        work <- file.path(scratch, family, layout, status)
        entry <- file.path(work, "tools/parity/generators", family, "generate.R")
        dir.create(dirname(entry), recursive = TRUE)
        file.copy(file.path(root, "tools/parity/generators", family, "generate.R"), entry)
        oracle <- file.path(work, "tools/parity/generators/oracle-check.R")
        writeLines("# test authentication boundary", oracle)
        inputs <- file.path(work, "tests/fixtures/parity", child, "inputs")
        dir.create(inputs, recursive = TRUE)
        for (name in c("input.csv", "sparse-factor.csv"))
          writeLines(c("sentinel", "1"), file.path(inputs, name))
        stub <- file.path(work, "child-stub.R")
        writeLines(c('if (length(commandArgs(TRUE)) != 1L) quit(status = 64L)',
                     if (status == 23L) "" else 'cat("controlled child result\\n")',
                     paste0("quit(status = ", status, "L)")), stub)
        authenticated <- FALSE
        child_status <- NA_integer_
        child_calls <- 0L
        env <- new.env(parent = globalenv())
        env$commandArgs <- function(...) paste0("--file=", entry)
        env$source <- function(file, ...) {
          stopifnot(identical(normalizePath(file), normalizePath(oracle)))
          authenticated <<- TRUE
          invisible(NULL)
        }
        env$library <- function(package, ...) {
          stopifnot(as.character(substitute(package)) == "jsonlite")
          invisible(NULL)
        }
        env$system2 <- function(command, args, ...) {
          stopifnot(authenticated, identical(command, if (family == "rt005") "python3" else "Rscript"))
          child_calls <<- child_calls + 1L
          result <- base::system2(rscript, c("--vanilla", shQuote(stub), args), ...)
          child_status <<- attr(result, "status")
          if (is.null(child_status)) child_status <<- 0L
          result
        }
        env$dir.create <- function(...) {
          stop(structure(list(message = "fixture boundary", call = NULL),
                         class = c("fixture_boundary", "error", "condition")))
        }
        verdict <- suppressWarnings(tryCatch({eval(parse(entry), env); "completed"},
          fixture_boundary = function(e) "fixture boundary",
          error = function(e) conditionMessage(e)))
        expected <- if (status == 0L) identical(verdict, "fixture boundary") else
          grepl(paste0(toupper(child), " generator failed with exit status ", status), verdict, fixed = TRUE)
        if (!expected || child_calls != 1L || !identical(child_status, status))
          failures <- c(failures, paste(family, layout, status, "observed child", child_status, ":", verdict))
        if (dir.exists(file.path(work, "tests/fixtures/parity", family)))
          failures <- c(failures, paste(family, "wrote fixtures during transport qualification"))
        checks <- checks + 1L
      }
    }
  }, finally = unlink(scratch, recursive = TRUE))
  if (length(failures)) stop(paste(failures, collapse = "\n"), call. = FALSE)
  cat("Generator child status:", checks,
      "real child-exit cases pass; no numerical generators or fixture writes\n")
})
