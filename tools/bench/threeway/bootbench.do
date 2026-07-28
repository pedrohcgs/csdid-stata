* Is the large-n multiplier bootstrap leaving speed on the table?
*
* csdid__bmisc_bootstrap_auto() uses the dense BLAS path only when
* rows(x)*biters <= 2e6, otherwise a byte-table gather approach. Both of the
* benchmark fixtures exceed that (6e6 and 3.4e7), so neither uses BLAS.
*
* A BLOCKED dense call consumes csdid__bmisc_unif_ints() in exactly the same
* order as one big dense call (biters*nints ints, rowshape'd by row), so
* stacking dense(block) calls reproduces the identical draw matrix while
* keeping peak memory bounded. This times both and checks they agree.
version 14
clear all
set more off
local REPO "`c(pwd)'"
adopath ++ "`REPO'/src/ado"
adopath ++ "`REPO'/src/mata"

* trigger the engine loader so the Mata library is resolvable
quietly import delimited using "`REPO'/examples/data/mpdta.csv", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(reg) analytical

mata:
real matrix boot_blocked(real matrix x, real scalar biters, real rowvector state,
    real scalar block)
{
    real matrix out
    real scalar done, take
    out = J(0, cols(x), .)
    done = 0
    while (done < biters) {
        take = min((block, biters - done))
        out = out \ csdid__bmisc_bootstrap_dense(x, take, state)
        done = done + take
    }
    return(out)
}

real rowvector fresh_state()
{
    real rowvector s
    real scalar i
    s = J(1, 625, 0)
    s[1] = 624
    // deterministic fill; exact values irrelevant, both paths get the same state
    for (i = 2; i <= 625; i++) s[i] = mod(69069 * (i - 1) + 12345, 4294967296)
    return(s)
}

void run_bootbench()
{
    real scalar i, n, k, biters
    real matrix x, A, B
    real rowvector s1, s2

    biters = 1000
    k = 15
    printf("{txt}n\tpath\tseconds\tmaxreldif\n")
    for (i = 1; i <= 3; i++) {
        if (i == 1) n = 6000
        if (i == 2) n = 33740
        if (i == 3) n = 100000
        x = rnormal(n, k, 0, 1)

        s1 = fresh_state()
        timer_clear(1); timer_on(1)
        A = csdid__bmisc_bootstrap_matrix(x, biters, s1)
        timer_off(1)
        printf("%9.0f\ttable\t%8.3f\n", n, timer_value(1)[1])

        s2 = fresh_state()
        timer_clear(2); timer_on(2)
        B = boot_blocked(x, biters, s2, 250)
        timer_off(2)
        printf("%9.0f\tblocked\t%8.3f\tmreldif=%10.3e\n", n, timer_value(2)[1], mreldif(A, B))
    }

}

run_bootbench()
end
display "BOOTBENCH DONE"
