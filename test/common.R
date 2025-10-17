.savemat <- function(outf, mat) {
    con <- file(outf, 'wb')
    on.exit(close(con))
    writeBin(dim(mat), con)
    writeBin(c(mat), con)
    flush(con)
}
