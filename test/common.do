cap mata mata drop _loadmat()
mata:
real matrix function _loadmat(string scalar fname) {
    real vector mat
    real scalar fh, nr, nc
    colvector C
    fh  = fopen(fname, "r")
    C   = bufio()
    nr  = fbufget(C, fh, "%4bu", 1)
    nc  = fbufget(C, fh, "%4bu", 1)
    mat = fbufget(C, fh, "%8z", nr * nc)
    fclose(fh)
    return(rowshape(mat, nc)')
}
end
