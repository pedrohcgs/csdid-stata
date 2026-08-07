* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do mbench.do
* Cost of an n-row matrix crossing the Mata <-> Stata matrix boundary,
* and of Stata-side copies of it. No csdid code involved.
foreach n in 25000 50000 100000 {
    timer clear 1
    timer on 1
    mata: st_matrix("X", J(`n', 10, 1))
    timer off 1
    timer clear 2
    timer on 2
    matrix Y = X
    timer off 2
    timer clear 3
    timer on 3
    matrix colnames X = a b c d e f g h i j
    timer off 3
    quietly timer list
    di "MB n=`n'  st_matrix_write=" %8.2f r(t1) "  stata_copy=" %8.2f r(t2) "  colnames=" %8.2f r(t3)
    matrix drop X Y
}
