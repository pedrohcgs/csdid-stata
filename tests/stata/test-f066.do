* F066 -- the same command on the same data returns the same numbers,
* whatever ran before it in the session.
*
* Mata's order() is NOT stable across ties: measured, `order(cl, 1)' on an
* unchanged vector returns a DIFFERENT permutation depending on what Mata did
* earlier in the same process. Cluster identifiers are nothing but ties, so
* csdid__cluster_sums was accumulating each cluster's influence-function
* contributions in an order that varied with session history -- and the
* clustered standard errors moved by an ulp between two runs of the identical
* command on the identical data.
*
* Point estimates were never affected; this was always a last-bit effect. It
* is pinned anyway, because a result that depends on session history is not
* reproducible in the sense the package promises, and because the same
* unstable sort decides the bootstrap draw order on the fallback paths, where
* it would not have stayed a last-bit effect.
*
* The fix is to order on (key, original row number) everywhere a tie is
* possible, which makes the permutation unique. R's order() is a stable radix
* sort, so this also matches the oracle's accumulation order.
*
* Qualified: against the pre-fix build both halves of this test fail, with
* maxabs 2.78e-17 on the clustered standard errors and 1.24e-14 on the direct
* Mata check.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f066_data
    version 15
    clear
    quietly set obs 400
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, 4)
    quietly generate double g = cond(arm == 0, 0, 1 + arm * floor(5 / 4) + 1)
    quietly replace g = 0 if g > 6
    quietly generate double cl = mod(id, 17) + 1
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 6
    quietly bysort id: generate double time = _n
    quietly generate double x1 = mod(id * 13 + time * 5, 29) / 29
    quietly generate double x2 = mod(id * 3 + time * 17, 19) / 19
    quietly generate double y = ui + 0.2 * time + 0.7 * x1 - 0.4 * x2 ///
        + mod(id * 5 + time * 3, 31) / 31 ///
        + cond(g > 0 & time >= g, 1.1 + 0.3 * (time - g), 0)
end

* -----------------------------------------------------------------------
* 1. A clustered estimation is bit-identical whether or not other csdid
*    runs preceded it in the process.
* -----------------------------------------------------------------------
f066_data
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    cluster(cl)
matrix F066_ALONE = e(attgt)

f066_data
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated analytical
f066_data
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) notyet analytical
quietly csdid_stats, type(dynamic) dropmissing
f066_data
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    cluster(cl)
matrix F066_AFTER = e(attgt)

mata:
    a = st_matrix("F066_ALONE")
    b = st_matrix("F066_AFTER")
    st_numscalar("f066_rows", rows(a) == rows(b) & cols(a) == cols(b))
    st_numscalar("f066_exact", all(editmissing(a, -99) :== editmissing(b, -99)))
end
assert scalar(f066_rows) == 1
assert scalar(f066_exact) == 1

* And the clustered aggregations too, which is where the per-cell sums live.
f066_data
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    cluster(cl)
quietly csdid_stats, type(dynamic) dropmissing
matrix F066_AGG_ALONE = e(aggte)

f066_data
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated analytical
foreach a in simple group calendar dynamic {
    capture quietly csdid_stats, type(`a') dropmissing
}
f066_data
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    cluster(cl)
quietly csdid_stats, type(dynamic) dropmissing
matrix F066_AGG_AFTER = e(aggte)

mata:
    a = st_matrix("F066_AGG_ALONE")
    b = st_matrix("F066_AGG_AFTER")
    st_numscalar("f066_agg_exact", rows(a) == rows(b) & cols(a) == cols(b) ///
        ? all(editmissing(a, -99) :== editmissing(b, -99)) : 0)
end
assert scalar(f066_agg_exact) == 1

* -----------------------------------------------------------------------
* 2. The mechanism itself: the cluster layout is a pure function of the
*    cluster vector, so it must not move when unrelated Mata work happens
*    in between.
* -----------------------------------------------------------------------
mata:
    n = 2400
    cl_v = J(n, 1, 0)
    xv = J(n, 1, 0)
    for (i = 1; i <= n; i++) {
        cl_v[i] = mod(i, 17) + 1
        xv[i] = (mod(i * 7919, 104729) / 104729 - 0.5) * 3
    }
    csdid__cluster_layout(cl_v, ord1 = J(0, 1, .), info1 = J(0, 0, .))
    s1 = csdid__cluster_sums_pre(ord1, info1, xv)

    // unrelated Mata work of the kind an aggregation does in between
    junk = 0
    for (r = 1; r <= 25; r++) {
        A = J(400, 10, 0)
        for (i = 1; i <= 400; i++) {
            for (j = 1; j <= 10; j++) A[i, j] = mod(i * j * r, 97) / 97
        }
        junk = junk + sum(diagonal(quadcross(A, A)))
        B = order(A[., 1], 1)
        junk = junk + sum(panelsum(A[B, .], panelsetup(round(A[B, 1] :* 10), 1)))
    }

    csdid__cluster_layout(cl_v, ord2 = J(0, 1, .), info2 = J(0, 0, .))
    s2 = csdid__cluster_sums_pre(ord2, info2, xv)

    st_numscalar("f066_ord", all(ord1 :== ord2))
    st_numscalar("f066_sums", all(s1 :== s2))
end
assert scalar(f066_ord) == 1
assert scalar(f066_sums) == 1

display as text "test-f066: results do not depend on session history OK"
