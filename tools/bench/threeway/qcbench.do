version 14
clear all
set more off
mata:
void qc()
{
    real matrix x, h1, h2
    real colvector w
    real scalar i, n, k, reps, t1, t2
    n = 5000; k = 3; reps = 2000
    x = rnormal(n, k, 0, 1); x[.,1] = J(n,1,1)
    w = runiform(n,1) :+ 0.5
    // warm
    h1 = quadcross(x, w, x); h2 = cross(x, w, x)
    timer_clear(1); timer_on(1)
    for (i = 1; i <= reps; i++) h1 = quadcross(x, w, x)
    timer_off(1)
    timer_clear(2); timer_on(2)
    for (i = 1; i <= reps; i++) h2 = cross(x, w, x)
    timer_off(2)
    printf("{txt}quadcross(x,w,x)  %8.4f s / %g reps  = %8.5f ms each\n",
        timer_value(1)[1], reps, 1000*timer_value(1)[1]/reps)
    printf("{txt}cross(x,w,x)      %8.4f s / %g reps  = %8.5f ms each\n",
        timer_value(2)[1], reps, 1000*timer_value(2)[1]/reps)
    printf("{txt}ratio quad/double = %6.2fx   mreldif(h)= %10.3e\n",
        timer_value(1)[1]/timer_value(2)[1], mreldif(h1,h2))

    // and the k x 1 form used for the RHS
    timer_clear(3); timer_on(3)
    for (i = 1; i <= reps; i++) h1 = quadcross(x, w :* x[.,2])
    timer_off(3)
    timer_clear(4); timer_on(4)
    for (i = 1; i <= reps; i++) h2 = cross(x, w :* x[.,2])
    timer_off(4)
    printf("{txt}quadcross(x, wz)  %8.4f s  vs  cross %8.4f s  ratio %5.2fx\n",
        timer_value(3)[1], timer_value(4)[1], timer_value(3)[1]/timer_value(4)[1])
}
end
mata: qc()
display "QCBENCH DONE"
