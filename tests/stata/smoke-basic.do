* ---------------------------------------------------------------------------
* The cheapest proof that the tree is runnable at all: a ten-unit 2x2 panel
* with a known ATT of exactly 1, estimated from src/ through adopath, then
* read back through csdid_estat. It pins that csdid loads, estimates, posts a
* one-row e(attgt) with the right number in column 4, and that postestimation
* can consume what estimation left behind. It is the gate that separates a
* broken build from a wrong answer, so every other test's failure means what
* it says.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

adopath ++ "`c(pwd)'/src/ado"
adopath ++ "`c(pwd)'/src/mata"

clear
input id time g y
1 1 2 0
1 2 2 1
2 1 2 0
2 2 2 1
3 1 2 0
3 2 2 1
4 1 2 0
4 2 2 1
5 1 2 0
5 2 2 1
6 1 0 0
6 2 0 0
7 1 0 0
7 2 0 0
8 1 0 0
8 2 0 0
9 1 0 0
9 2 0 0
10 1 0 0
10 2 0 0
end

csdid y, time(time) gvar(g) analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)
assert rowsof(A) == 1
assert abs(A[1,4] - 1) < 1e-12
csdid_estat attgt
