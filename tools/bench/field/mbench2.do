* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do mbench2.do
foreach n in 12500 25000 50000 {
    mata: st_matrix("X", J(`n', 4, 1))
    timer clear 1
    timer on 1
    mata: __r = st_matrix("X")
    timer off 1
    mata: mata drop __r
    quietly timer list
    di "MB2 n=`n'  read_into_mata=" %8.2f r(t1)
    matrix drop X
}
