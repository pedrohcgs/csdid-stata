* test-rc-bucket-order.do
* ---------------------------------------------------------------------------
* The (cohort, period) row buckets keep their rows in ascending row order
* inside every bucket, and that order is load-bearing.
*
* Every repeated-cross-section and unbalanced-panel cell assembles its rows by
* reading slices out of csdid__rc_buckets' table. The order the rows come out
* in is the order every subsequent sum accumulates them in, so reversing a
* bucket changes the floating-point accumulation order of the fits and of the
* influence functions -- a divergence from R that no amount of algebra makes
* up for.
*
* NOTHING ELSE CATCHES IT. The bitwise differential grid is blind to it: a
* seeded reversal of the within-bucket order leaves all 260 of its channels
* identical, because the designs it runs are small enough that the two
* accumulation orders agree to the last bit. So the property is checked here
* directly, against an independent build.
*
* HOW. The bucket table is built twice on the same rows and compared element
* for element: once by csdid__rc_buckets, and once by rcbo_sorted() below,
* which is the sort-and-permute construction the engine used before the
* nested scan replaced it -- one order() on (bucket id, row number), then a
* permutation and a panelsetup to find where each bucket starts. The two
* builds share no code. Six shapes are checked: a dense grid, a grid with an
* empty bucket, a scattered estimation sample (unbalanced), cohort values
* that are neither contiguous nor sorted, periods that are neither 1-spaced
* nor sorted in the data, and a single bucket.
*
* SEEDING THE RED. This test was qualified against a worktree carrying one
* edit in csdid__rc_buckets (src/mata/csdid.mata), which reverses each
* bucket's rows while leaving the lookup table, the bucket sizes and the row
* multiset untouched:
*
*     rc_sorted_rows[|rc_pos \ rc_pos + rc_n - 1|] = rc_grows[rc_cpos]
*   becomes
*     rc_sorted_rows[|rc_pos \ rc_pos + rc_n - 1|] = ///
*         rc_grows[rc_cpos[rows(rc_cpos)::1]]
*
* Against that tree every one of the six shapes reports DIFFERENT and the
* do-file exits 459; against the engine as it stands all six report identical.
* ---------------------------------------------------------------------------
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

quietly do "`root'/src/mata/csdid.mata"

mata:

// The build the nested scan replaced, written out here so the two
// constructions share nothing: bucket ids from a pair of index loops, one
// full sort on (bucket id, row number), then a permutation and a panelsetup
// to recover each bucket's start and length.
void rcbo_sorted(real colvector tt, real colvector geff, real colvector use,
    real rowvector tlevels, real colvector gcats, real colvector srows,
    real matrix lut, real scalar nbg, real scalar nbt)
{
    real colvector rowsel, gidx, tidxv, bid, ord
    real matrix binfo
    real scalar b

    rowsel = selectindex(use :!= 0)
    gcats  = uniqrows(geff[rowsel])
    nbg    = rows(gcats)
    nbt    = cols(tlevels)
    gidx   = J(rows(rowsel), 1, .)
    for (b = 1; b <= nbg; b++) {
        ord = selectindex(geff[rowsel] :== gcats[b])
        if (length(ord) > 0) gidx[ord] = J(length(ord), 1, b)
    }
    tidxv = J(rows(rowsel), 1, .)
    for (b = 1; b <= nbt; b++) {
        ord = selectindex(tt[rowsel] :== tlevels[b])
        if (length(ord) > 0) tidxv[ord] = J(length(ord), 1, b)
    }
    bid   = (gidx :- 1) :* nbt :+ tidxv
    ord   = order((bid, rowsel), (1, 2))
    srows = rowsel[ord]
    bid   = bid[ord]
    binfo = panelsetup(bid, 1)
    lut   = J(nbg * nbt, 2, 0)
    for (b = 1; b <= rows(binfo); b++) {
        lut[bid[binfo[b, 1]], 1] = binfo[b, 1]
        lut[bid[binfo[b, 1]], 2] = binfo[b, 2] - binfo[b, 1] + 1
    }
}

// One shape: build it both ways, compare every element of the row list, the
// lookup table and the cohort list. The row list is what carries the order,
// so a reversed bucket shows up there and nowhere else.
real scalar rcbo_case(string scalar label, real colvector tt,
    real colvector geff, real colvector use, real rowvector tlevels)
{
    real colvector y, g1, s1, g2, s2, mask2
    real matrix l1, l2
    real scalar b1, t1, b2, t2, built2, ok

    g1 = s1 = J(0, 1, .)
    l1 = J(0, 0, .)
    b1 = t1 = .
    rcbo_sorted(tt, geff, use, tlevels, g1, s1, l1, b1, t1)

    y = J(rows(tt), 1, 0)
    g2 = s2 = mask2 = J(0, 1, .)
    l2 = J(0, 0, .)
    b2 = t2 = built2 = .
    csdid__rc_buckets(y, tt, geff, use, tlevels, g2, s2, l2, mask2, built2,
        b2, t2)

    ok = (built2 == 1) & (b1 == b2) & (t1 == t2) &
         (rows(g1) == rows(g2)) & (rows(s1) == rows(s2)) &
         (rows(l1) == rows(l2)) & (cols(l1) == cols(l2))
    if (ok) {
        ok = (sum(g1 :!= g2) == 0) & (sum(s1 :!= s2) == 0) &
             (sum(l1 :!= l2) == 0)
    }
    printf("%-36s buckets=%4.0f rows=%6.0f  %s\n", label, b1 * t1, rows(s1),
        ok ? "identical" : "DIFFERENT")
    return(ok)
}

void rcbo_run()
{
    real colvector tt, geff, use
    real rowvector tlevels
    real scalar n, i, allok

    allok = 1
    n     = 4000

    // 1. dense: every cohort observed in every period
    tt   = J(n, 1, .)
    geff = J(n, 1, .)
    for (i = 1; i <= n; i++) {
        tt[i]   = mod(i, 10) + 1
        geff[i] = 3 * mod(floor((i - 1) / 10), 4)
    }
    tlevels = (1..10)
    use     = J(n, 1, 1)
    allok   = allok & rcbo_case("dense", tt, geff, use, tlevels)

    // 2. a period absent from one cohort, i.e. an empty bucket
    use = J(n, 1, 1)
    for (i = 1; i <= n; i++) {
        if (geff[i] == 6 & tt[i] == 4) use[i] = 0
    }
    allok = allok & rcbo_case("one empty bucket", tt, geff, use, tlevels)

    // 3. a scattered `use', so the estimation sample is not contiguous --
    //    the unbalanced case, where row numbers skip
    use = J(n, 1, 0)
    for (i = 1; i <= n; i++) {
        if (mod(i, 3) != 0) use[i] = 1
    }
    allok = allok & rcbo_case("scattered estimation sample", tt, geff, use,
        tlevels)

    // 4. cohort values neither contiguous nor sorted in the data
    for (i = 1; i <= n; i++) {
        geff[i] = (0, 17, 4, 900)[mod(floor((i - 1) / 10), 4) + 1]
    }
    use   = J(n, 1, 1)
    allok = allok & rcbo_case("cohort values 0/17/4/900", tt, geff, use,
        tlevels)

    // 5. periods neither 1-spaced nor sorted in the data: the repeated
    //    cross section as it arrives, one row per observation
    for (i = 1; i <= n; i++) {
        tt[i] = (1990, 2005, 1997, 2001, 1993)[mod(i, 5) + 1]
    }
    tlevels = (1990, 1993, 1997, 2001, 2005)
    allok   = allok & rcbo_case("biennial, unsorted periods", tt, geff, use,
        tlevels)

    // 6. one cohort, one period
    tt      = J(n, 1, 1990)
    geff    = J(n, 1, 0)
    tlevels = (1990)
    allok   = allok & rcbo_case("one cohort, one period", tt, geff, use,
        tlevels)

    if (allok == 0) {
        errprintf("the bucket table's within-bucket row order is not the sorted order\n")
        _error(459)
    }
}

end

mata: rcbo_run()

display as text "test-rc-bucket-order: all assertions passed"
