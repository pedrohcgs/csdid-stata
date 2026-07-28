version 15
clear all
set more off

local root "`c(pwd)'"
do "`root'/src/build.do"

local plus "`c(tmpdir)'/csdid-plus"
local personal "`c(tmpdir)'/csdid-personal"
capture mkdir "`plus'"
capture mkdir "`personal'"
sysdir set PLUS "`plus'"
sysdir set PERSONAL "`personal'"

net install csdid, from("`root'") replace
which csdid
which csdid_estat
which csdid_stats
which csdid_plot
which csdid.mata
foreach f in csdid.sthlp csdid_postestimation.sthlp csdid_estat.sthlp csdid_stats.sthlp csdid_plot.sthlp {
    quietly findfile `f'
}

clear
input id time g y
1 1 2 0
1 2 2 2
2 1 2 0
2 2 2 2
3 1 2 0
3 2 2 2
4 1 2 0
4 2 2 2
5 1 2 0
5 2 2 2
6 1 0 1
6 2 0 1
7 1 0 1
7 2 0 1
8 1 0 1
8 2 0 1
9 1 0 1
9 2 0 1
10 1 0 1
10 2 0 1
end

csdid y, time(time) gvar(g) analytical
matrix A = e(attgt)
assert rowsof(A) == 1
assert abs(A[1,4] - 2) < 1e-12
