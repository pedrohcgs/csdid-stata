*! csdid 2.0.0 28aug2026
version 14
mata:
// matastrict is deliberately NOT set here. This file is do-ed at runtime on
// the source-fallback path, and setting it left matastrict ON in the user's
// session after csdid returned -- breaking any non-strict Mata they or
// another package later compiled, csdid_rif included. src/build.do sets it
// before compiling, which is where strictness belongs; the source below
// satisfies it either way.


// ===========================================================================
// THE csdid ENGINE
//
// One file, read top to bottom in the order the work happens: primitives,
// then the 2x2 estimators, then the ATT(g,t) engine, then the bootstrap,
// then aggregation, then everything that crosses back into Stata.
//
//    1  Primitives and grid lookups
//    2  Profiling counters
//    3  The engine object
//    4  Numeric primitives for the 2x2 fits
//    5  The propensity-score fit
//    6  Cell diagnostics and their warnings
//    7  The 2x2 estimators
//    8  The pre-estimation scan
//    9  ATT(g,t) cell helpers
//   10  The ATT(g,t) engine
//   11  Cluster and influence-function helpers
//   12  Bootstrap statistics
//   13  The bootstrap object
//   14  Bootstrap entry points
//   15  32-bit arithmetic and MT19937 tables
//   16  The MT19937 generator and its draws
//   17  R's bootstrap draw order
//   18  Draw matrices and the RNG-advance shims
//   19  Aggregation
//   20  Posting results back to Stata
//
// NAMING. `csdid_' (one underscore) means the function is reached from
// outside this file. There are 30 of them; 26 are called from the ado layer,
// and that set, with the CSDID_* globals the ado reads, is the engine's
// public surface. `csdid__' (two underscores) means internal, and free to
// restructure. Six of the 26 are the csdid_cache_* readers in section 3, and
// a seventh, csdid_cache_validate, is what gates them: the ado asks the
// engine object its questions through them rather than reading its state, so
// the object itself stays internal and can be rearranged freely.
//
// Five grandfathered exceptions carry two underscores and are called from the
// ado anyway: csdid__mean, csdid__globals_init and csdid__prescan from the
// loader and the pre-estimation scan, csdid__cluster_sums from the Wald
// pre-test, and csdid__bmisc_rng_init from the seeding path. Four more carry
// one underscore but are reached only from tests and tools:
// csdid_bmisc_aggskip, csdid_bmisc_attgtskip, csdid_bmisc_labelse and
// csdid_bmisc_skipdraws. Do not add new exceptions, and do not rename the old
// ones -- tests and tools pin them by name. Several other `csdid__' helpers
// are pinned the same way, so grep tests/ and tools/ before renaming anything
// in this file.
//
// PRECISION POLICY (declared 2026-08-23). Accumulations that feed variances
// and influence functions use the quad-precision family (quadcross,
// quadsum, quadcolsum) throughout; R's did accumulates in double. That is a
// deliberate, standing excess-accuracy stance, not 52 separate choices: the
// differences it can produce sit below every parity tolerance the fixture
// suite enforces, and the fixtures are the gate that would catch a case
// where they did not. The ONE deliberate double-precision site is the rcond
// crossprod (`crossprod in double precision ... to match R', section 4),
// which feeds a threshold comparison R makes on the double-precision
// object itself. Do not "optimize" quad to plain on a hot path without
// taking the change through the perf-differential harness AND the parity
// suite; do not upgrade the rcond site without owner sign-off.
//
// EVOLVING THE PUBLIC SURFACE. The 26 ado-called entry points (and the
// test-pinned names above) are frozen at 2.0.0. A future release that must
// change one of their signatures does it the sanctioned way -- a
// callersversion() split with the old body kept in its own version block
// ([M-3] lmbuild, "Version control") -- never a hard edit; see
// docs/stored-results-api.md for the policy.
//
// HOW MANY NAMES, and why the count is worth keeping. 132 free functions and
// three classes: `mata mlib add csdid*()' writes one library member per free
// function and ONE per class, so the compiled library holds 135 top-level
// names and the 28 class methods travel inside the three classdef entries
// rather than beside them (165 members in all: 21 methods on csdid__Agg,
// 3 on csdid__Boot, 4 on csdid__Engine). Mata answers a global name it
// is not already holding by walking c(matalibs), so each free name is a
// first-call lookup a session pays once and a method is not.
//
// WHAT THAT IS WORTH HERE, measured rather than assumed, because the obvious
// figure is the wrong one. 1.17ms per name is what a library answered LAST
// costs, and _csdid_engine_load.ado moves the accepted library to the FRONT
// of the search order on the call that accepts it; from first position the
// same probe measured 0.06ms per name. So the eleven free names this file
// lost at the signature sweep are worth about 0.7ms once per session, not
// about 13ms, and the two the duplication hunt then spent are worth about
// 0.12ms; tools/bench/run-session-warmup.py cannot see either the saving or
// the spend: six alternated readings against the parent put the first run of
// a session within +/-1ms on all three phases, which is the resolution of the
// clock it uses. The name count is worth keeping for the
// arrangement it describes, and the 1.17ms figure is worth quoting only for a
// library that is not first.
// ===========================================================================

// ===========================================================================
// SECTION 1 -- PRIMITIVES AND GRID LOOKUPS
//
// Small helpers used everywhere below: an empty-safe selectindex, a mean
// that survives an empty column, and the binary searches over the period
// grid and the sorted unit list. They run inside the per-cell and
// per-observation loops, so they allocate nothing and branch little.
// ===========================================================================

// ---------------------------------------------------------------------------
// csdid__selidx() with a usable empty result.
//
// Mata's selectindex returns 1 x 0 when nothing matches AND the input is
// either a row vector or a 1 x 1 column; it returns 0 x 1 for a longer
// column. So `rows(idx) > 0` -- the natural guard, used at a dozen sites here
// -- is TRUE for an empty result whenever the input had a single element.
//
// That is not hypothetical: a seeded multiplier bootstrap on a design with
// exactly one ATT(g,t) cell whose sigma is missing (an outcome with no
// within-group variation) passed the guard in csdid__boot_table and then
// multiplied a biters x 1 matrix by a 0 x 1 one, aborting with r(3200)
// instead of returning missing standard errors.
//
// Normalising the empty case to 0 x 1 makes rows(), cols() and length() all
// agree with each other and with every existing guard. Non-empty results are
// returned untouched, so no live path changes shape.
// ---------------------------------------------------------------------------
real vector csdid__selidx(real vector v)
{
    real vector idx
    idx = selectindex(v)
    if (length(idx) == 0) return(J(0, 1, .))
    return(idx)
}


real scalar csdid__mean(real colvector x)
{
    if (rows(x) == 0) return(.)
    return(mean(x))
}


// ---------------------------------------------------------------------------
// What the compiled library says it is.
//
// The loader every command goes through (_csdid_engine_load.ado) asks the
// library two questions. The first is whether a name it needs is there at
// all, which csdid__mean above answers. That is not
// enough: a library left behind by a different csdid, or compiled by a NEWER
// Stata than the one now running, has every name the loader probes and answers
// them with the wrong code -- the failure is a wrong number, or an
// unaccountable r(3499) deep inside an estimation, rather than a load error.
// So the library also carries a stamp, and the loader compares it.
//
// The stamp is the package version and the Stata that COMPILED the library,
// which is the fact that cannot be recovered at runtime any other way.
// src/build.do rewrites the second half of the string below, in a copy, just
// before it compiles the library; the source this file ships as the fallback
// keeps the word `source', which is exactly what it is -- a session that
// compiles this file compiles it under its own Stata, so there is nothing to
// mismatch.
// ---------------------------------------------------------------------------
string scalar csdid_mlib_version()
{
    return("2.0.0|source")
}


// tlist is ALWAYS the period grid, which is built by uniqrows() and is
// therefore strictly ascending with no duplicates (src/mata/csdid.mata,
// csdid_basic_attgt and the aggregation setup are the only producers, and
// every one of the 17 call sites passes `tlevels'). Both lookups below use
// that, because between them they run up to five times per (g,t) cell AND
// once per observation in the panel-layout scan -- a linear scan there is
// O(N x T) for an answer that is O(log T).
//
// Semantics are unchanged and must stay so: previous_time returns the
// LARGEST period strictly below t (missing when there is none), and
// sorted_index returns the position of an EXACT match (missing when there is
// none). csdid__sorted_index, immediately below, is that exact search,
// and it is one routine because the two lists it is asked about differ only in
// their orientation: the ascending period list is a ROW and the ascending
// unit-id list is a COLUMN. `real vector' takes both, subscripting a vector by
// one index reads either, and length() is the upper bound for either -- priced
// at 400,000 calls x 3 rounds against cols() and rows() separately
// (tools/bench/probe-bsearch-bound.do): 952.5 to 955ns per call across all
// four forms, a spread of 2.5ns which is exactly the clock's resolution over
// that many calls. Both are called per ROW of the sample, so it was measured
// rather than assumed.
real scalar csdid__previous_time(real rowvector tlist, real scalar t)
{
    real scalar lo, hi, mid, prev

    lo = 1
    hi = cols(tlist)
    prev = .
    while (lo <= hi) {
        mid = floor((lo + hi) / 2)
        if (tlist[mid] < t) {
            prev = tlist[mid]
            lo = mid + 1
        }
        else {
            hi = mid - 1
        }
    }
    return(prev)
}

real scalar csdid__sorted_index(real vector values, real scalar target)
{
    real scalar lo, hi, mid

    lo = 1
    hi = length(values)
    while (lo <= hi) {
        mid = floor((lo + hi) / 2)
        if (values[mid] == target) return(mid)
        if (values[mid] < target) {
            lo = mid + 1
        }
        else {
            hi = mid - 1
        }
    }
    return(.)
}

// ===========================================================================
// SECTION 2 -- PROFILING COUNTERS
//
// Four independent (elapsed, calls, work) matrices -- estimation,
// bootstrap, bootstrap kernel, aggregate bootstrap -- that the ado reads
// back into its profile matrices. Reset once, add once per phase; nothing
// here is on a numeric path.
// ===========================================================================


void csdid__profile_reset()
{
    external real matrix CSDID_PROFILE

    CSDID_PROFILE = J(8, 3, 0)
}

real scalar csdid__profile_start()
{
    return(now())
}

void csdid__profile_add(real scalar phase, real scalar started, real scalar work)
{
    external real matrix CSDID_PROFILE

    if (rows(CSDID_PROFILE) < 8 | cols(CSDID_PROFILE) < 3) {
        CSDID_PROFILE = J(8, 3, 0)
    }
    if (phase < 1 | phase > rows(CSDID_PROFILE)) return
    CSDID_PROFILE[phase, 1] = CSDID_PROFILE[phase, 1] + (now() - started) / 1000
    CSDID_PROFILE[phase, 2] = CSDID_PROFILE[phase, 2] + 1
    CSDID_PROFILE[phase, 3] = CSDID_PROFILE[phase, 3] + work
}

void csdid__boot_profile_reset()
{
    external real matrix CSDID_BOOT_PROFILE

    CSDID_BOOT_PROFILE = J(6, 3, 0)
}

void csdid__boot_profile_add(real scalar phase, real scalar started, real scalar work)
{
    external real matrix CSDID_BOOT_PROFILE

    if (rows(CSDID_BOOT_PROFILE) < 6 | cols(CSDID_BOOT_PROFILE) < 3) {
        CSDID_BOOT_PROFILE = J(6, 3, 0)
    }
    if (phase < 1 | phase > rows(CSDID_BOOT_PROFILE)) return
    CSDID_BOOT_PROFILE[phase, 1] = CSDID_BOOT_PROFILE[phase, 1] + (now() - started) / 1000
    CSDID_BOOT_PROFILE[phase, 2] = CSDID_BOOT_PROFILE[phase, 2] + 1
    CSDID_BOOT_PROFILE[phase, 3] = CSDID_BOOT_PROFILE[phase, 3] + work
}

void csdid__boot_kernel_profile_reset()
{
    external real matrix CSDID_BOOT_KERNEL_PROFILE

    CSDID_BOOT_KERNEL_PROFILE = J(5, 3, 0)
}

void csdid__boot_kernel_profile_add(real scalar phase, real scalar started, real scalar work)
{
    external real matrix CSDID_BOOT_KERNEL_PROFILE

    if (rows(CSDID_BOOT_KERNEL_PROFILE) < 5 | cols(CSDID_BOOT_KERNEL_PROFILE) < 3) {
        CSDID_BOOT_KERNEL_PROFILE = J(5, 3, 0)
    }
    if (phase < 1 | phase > rows(CSDID_BOOT_KERNEL_PROFILE)) return
    CSDID_BOOT_KERNEL_PROFILE[phase, 1] = CSDID_BOOT_KERNEL_PROFILE[phase, 1] + (now() - started) / 1000
    CSDID_BOOT_KERNEL_PROFILE[phase, 2] = CSDID_BOOT_KERNEL_PROFILE[phase, 2] + 1
    CSDID_BOOT_KERNEL_PROFILE[phase, 3] = CSDID_BOOT_KERNEL_PROFILE[phase, 3] + work
}

void csdid__agg_boot_profile_reset()
{
    external real matrix CSDID_AGG_BOOT_PROFILE

    CSDID_AGG_BOOT_PROFILE = J(3, 3, 0)
}

void csdid__agg_boot_profile_add(real scalar phase, real scalar started, real scalar work)
{
    external real matrix CSDID_AGG_BOOT_PROFILE

    if (rows(CSDID_AGG_BOOT_PROFILE) < 3 | cols(CSDID_AGG_BOOT_PROFILE) < 3) {
        CSDID_AGG_BOOT_PROFILE = J(3, 3, 0)
    }
    if (phase < 1 | phase > rows(CSDID_AGG_BOOT_PROFILE)) return
    CSDID_AGG_BOOT_PROFILE[phase, 1] = CSDID_AGG_BOOT_PROFILE[phase, 1] + (now() - started) / 1000
    CSDID_AGG_BOOT_PROFILE[phase, 2] = CSDID_AGG_BOOT_PROFILE[phase, 2] + 1
    CSDID_AGG_BOOT_PROFILE[phase, 3] = CSDID_AGG_BOOT_PROFILE[phase, 3] + work
}

// ===========================================================================
// SECTION 3 -- THE ENGINE OBJECT
//
// csdid__Engine is the state one estimation carries and the postestimation
// commands read back: the results cache, the options the run settled on, the
// pre-estimation scan's measurements, and the doubly-robust per-cell cache.
// A single instance, CSDID_ENGINE, is created once per session by
// csdid__globals_init and lives as long as the session does -- csdid and
// csdid_stats are separate commands, so what the first computes has to
// survive until the second asks for it.
//
// The class is INTERNAL. No ado file names it and no help file documents it:
// the ado layer reaches the cache through the csdid_cache_* readers at the
// end of this section, which answer exactly the questions it needs
// answered. The csdid prefix on the class name is
// not decoration -- class names collide silently across mlibs, and a
// collision is a wrong-answer bug, not a load error.
//
// Members are grouped by how long they live. The cache outlives the run that
// filled it, by design. The options and the scan outputs describe one run.
// The dr-cache describes one (g,t) cell and is refilled whenever the cell's
// key changes. new() zero-initialises and settles the token base (the one
// value that cannot be recomputed later, because it is what makes THIS
// engine's tokens distinguishable from another session's); every other field
// is set by the routine that owns it, before anything reads it.
// ===========================================================================

class csdid__Engine {
    // ---- results cache: what the postestimation layer reads back ----
    // Filled by csdid_basic_attgt under lean storage, where an n_units-row
    // matrix must not cross into Stata's classic-matrix layer (quadratic in
    // n_units; see csdid_aggte).
    //
    // Two members say which estimation the cache belongs to, and they answer
    // different questions. `token' is the handle e(mata_cache_token) carries:
    // it identifies the RUN, so that a cache left behind by a LATER csdid is
    // never merged into an earlier estimation's e(V). `attgt' is the ATT(g,t)
    // table that was computed alongside these influence functions: it
    // identifies the RESULTS, so that a token which matches for any reason
    // other than being the same estimation is caught before a number is
    // computed from the pairing. csdid_cache_validate requires both.
    real matrix    inffunc
    real matrix    unit_group
    real matrix    unit_row
    real matrix    row_unit
    real matrix    cluster_vec
    real matrix    agg_inffunc
    real matrix    attgt
    real scalar    token
    real scalar    token_base
    real scalar    token_counter
    real scalar    agg_token

    // ---- the options this run settled on ----
    string scalar  base_period
    string scalar  notyet
    string scalar  balance_mode
    string scalar  fix_weights
    real scalar    anticipation
    real scalar    trim_level

    // ---- csdid__prescan's measurements ----
    // The scan publishes these to the ado through named Stata scalars and
    // locals, which is the ado's contract and does not change; the copies
    // here are the engine's own, for a routine inside this file that wants
    // what the scan found without going back out through Stata. They are the
    // LAST scan's answers. The three shape violations are deliberately not
    // among them -- see the note at the writes in csdid__prescan.
    real scalar    ps_tmin
    real scalar    ps_tmax
    real scalar    ps_gmin
    real scalar    ps_gmax
    real scalar    ps_never
    real scalar    ps_firstunits
    real scalar    ps_baltime
    real scalar    ps_nunits
    real scalar    ps_incunits
    real scalar    ps_incobs
    real scalar    ps_balunits
    real scalar    ps_balobs
    real scalar    ps_shape_nunit
    string scalar  ps_tlevels
    string scalar  ps_glevels
    real matrix    ps_gcounts

    // ---- the doubly-robust per-cell cache ----
    // Consecutive (g,t) cells that share a cohort, a covariate period, a
    // weight period, a comparison group and the same unit set share one
    // propensity-score fit and everything derived from it. dr_valid plus the
    // five keys below decide that; dr_status carries the fit verdict so a
    // refused cell is refused identically on every cell that reuses the fit.
    real scalar    dr_valid
    real scalar    dr_g
    real scalar    dr_tidx_x
    real scalar    dr_tidx_w
    real scalar    dr_control_key
    real scalar    dr_status
    real scalar    dr_n
    real scalar    dr_mw_treat
    real scalar    dr_mw_cont
    real colvector dr_uids
    real colvector dr_w
    real colvector dr_ps
    real colvector dr_trim
    real colvector dr_w_treat
    real colvector dr_w_cont
    real colvector dr_weights_ols
    real colvector dr_score_ps
    real colvector dr_xgamma_treat
    real colvector dr_xgamma_cont
    real matrix    dr_xtwx_inv
    real matrix    dr_xpx_inv
    real matrix    dr_h

    void           new()
    real matrix    cell_grid()
    void           dr_cache_reset()
    real scalar    token_seed()
}

void csdid__Engine::new()
{
    inffunc         = J(0, 0, .)
    unit_group      = J(0, 0, .)
    unit_row        = J(0, 0, .)
    row_unit        = J(0, 0, .)
    cluster_vec     = J(0, 0, .)
    agg_inffunc     = J(0, 0, .)
    attgt           = J(0, 0, .)
    token           = 0
    token_base      = token_seed()
    token_counter   = 0
    agg_token       = 0

    base_period     = ""
    notyet          = ""
    balance_mode    = ""
    fix_weights     = ""
    anticipation    = .
    trim_level      = .

    ps_tmin         = .
    ps_tmax         = .
    ps_gmin         = .
    ps_gmax         = .
    ps_never        = .
    ps_firstunits   = .
    ps_baltime      = .
    ps_nunits       = .
    ps_incunits     = .
    ps_incobs       = .
    ps_balunits     = .
    ps_balobs       = .
    ps_shape_nunit  = .
    ps_tlevels      = ""
    ps_glevels      = ""
    ps_gcounts      = J(0, 0, .)

    // The doubly-robust cache's twenty-two fields are zeroed by the routine
    // that has to zero them between runs anyway (dr_cache_reset, section 9).
    // Birth and reset want the same twenty-two values, so a second copy of the
    // list here could only ever drift out of step with it.
    dr_cache_reset()
}

// ---------------------------------------------------------------------------
// The half of the cache token that this engine cannot count its way to.
//
// The token used to BE the counter: first lean estimation of a session, token
// 1. Every session starts a fresh engine at 0, so every session's first lean
// estimation had the same token as every other session's, and the guard that
// exists to stop one run's influence functions being read against another
// run's results compared 1 against 1 and let it through. The witness is an
// ordinary documented workflow: estimate, `estimates save', start Stata again,
// estimate something else, `estimates use' the saved run, aggregate -- and the
// aggregation reported the SECOND estimation's standard errors under the
// FIRST estimation's point estimates, with return code 0 and no message.
// A counter is a name for a run within a session; it was never a name for a
// run. This makes the token's high half a name for the SESSION, so that the
// low half can go on being the counter it always was.
//
// What it is built from, and why each part is there:
//
//   st_tempfilename() is Stata's own per-session unique name generator. On
//   this platform it answers /var/.../T//St<pid>.<nnnnnn> -- the operating
//   system's process id, which is what separates two Stata sessions running at
//   the same moment, and a counter that advances on every temporary name the
//   session has taken, which is what separates two engines constructed in one
//   session (`mata clear' then csdid again). It creates no file: it reserves a
//   name.
//
//   c(current_date) and c(current_time) separate two sessions that a recycled
//   process id would not. Second resolution is enough for that and for nothing
//   else, which is why it is the second component and not the only one.
//
// What it is deliberately NOT built from: any random number. Mata's generator
// is the bootstrap's generator, and csdid's seeded bootstrap is reproducible
// because nothing else in the engine draws from the stream a user seeded. A
// token derived from runiform() would advance that stream once per session and
// silently change every unseeded bootstrap -- buying a property this gets from
// the process id for free. Neither call below touches the generator state, and
// that is measured rather than asserted: the last arm of
// tests/stata/test-cache-token-session.do builds an engine with nothing else
// running and requires c(rngstate) to be unchanged character for character,
// then runs the same UNSEEDED bootstrap from the same seed on either side of
// an engine construction and requires the draws to be identical to the bit.
//
// The value is used as the high half of token = base * 2^20 + counter, so it
// must be an integer and the product must stay exactly representable: hash1()
// returns at most 2^32-1, and (2^32)*(2^20) + (2^20-1) is 4.5e15, comfortably
// inside a double's 2^53 exact-integer range and inside what a Stata macro
// round-trips digit for digit (measured: both, on the maximum value).
// ---------------------------------------------------------------------------
real scalar csdid__Engine::token_seed()
{
    // hash1() with one argument can answer 0; the token base is required to be
    // positive, because a zero token is what the ado layer reads as "no cache".
    return(hash1(st_tempfilename() + "|" + st_global("c(current_date)") +
        " " + st_global("c(current_time)")) + 1)
}

// The construction guarantee. Every routine below that names CSDID_ENGINE
// calls this first, because the object is NOT born on every load path: this
// file constructs it in its own trailing csdid__globals_init() call, and a
// session that takes the compiled-library route never runs a line of this
// file. csdid_stats after a `using' RIF file is exactly that session -- no
// csdid ran in it, so nothing else would have constructed the engine, and
// a class-typed external is not forgiving about absence the way the matrix
// globals it replaced were.
//
// Three measured facts fix the shape of this function (Stata 17 MP):
//   1. `external class C scalar X' where X does not exist does NOT raise at
//      the declaration -- it MATERIALISES X as a non-class scalar, and the
//      raise (3261) comes later, at the first member reference.
//   2. Because of (1), findexternal("CSDID_ENGINE") is never NULL inside a
//      function that declares the external: the declaration has already
//      created the name by the time any statement of that function runs.
//      Testing for the object itself would therefore never fire. The test is
//      on CSDID_GLOBALS_READY, the flag csdid__globals_init sets last.
//   3. The declaration binds LAZILY, at the member reference and not at
//      function entry, so constructing the object here -- after the caller's
//      declaration, before the caller's first member reference -- is in time.
// csdid__globals_init returns immediately when the flag is already set, so on
// every session where csdid has run this costs one external read and changes
// nothing: the cache the postestimation commands are about to read survives.
void csdid__engine_ensure()
{
    external real scalar CSDID_GLOBALS_READY

    if (CSDID_GLOBALS_READY != 1) csdid__globals_init()
}

// ---------------------------------------------------------------------------
// The cache readers the ado layer uses.
//
// Four questions, and nothing else, are asked of the cache from outside this
// file: does the estimation influence-function matrix still fit the results
// being posted, what is a column slice of it (the Wald pre-test), what are
// the cluster identifiers, and how wide is the aggregate influence-function
// cache and which run does it belong to. Each reader answers exactly one of
// them.
//
// None of them returns the influence-function matrix whole. Mata returns by
// value, so handing back an n_units x n_cells object would copy it on every
// call -- the copy the lean-storage path exists to avoid. The readers return
// a dimension, a slice, or a scalar.
//
// The engine is not absence-tolerant the way the matrix globals it replaces
// were. An absent matrix global materialised as a 0x0 and every reader that
// touched it silently answered an empty object; an absent class-typed
// external materialises as a non-class scalar and raises r(3261) at the first
// member reference. So absence is not a state a reader may be left in:
// csdid__engine_ensure, called first in every routine here, constructs the
// object on the load paths that would not otherwise have it -- the compiled
// library, and any session reached without running csdid.
//
// What a reader meets instead is the EMPTY engine: constructed, never filled,
// which is the session where no csdid has run yet. Each reader answers that
// state rather than raising -- no rows, no columns, an empty cluster matrix,
// a zero token -- which is what the ado layer is written against. The one
// exception is the column slice: a slice of an empty matrix has no answer, so
// it raises, and its call site tests the dimensions through the two readers
// above it before asking for one.
//
// The ado's three uses in csdid.ado are bare `mata:' calls, and stay correct
// because they run inside the estimation that has just filled the cache. The
// uses in csdid_stats.ado and _csdid_post.ado run in sessions that may have
// no estimation behind them: each is wrapped in capture, and each turns an
// empty answer into a named refusal or a documented fallback.
// ---------------------------------------------------------------------------
real scalar csdid_cache_if_rows()
{
    external class csdid__Engine scalar CSDID_ENGINE

    csdid__engine_ensure()

    return(rows(CSDID_ENGINE.inffunc))
}

real scalar csdid_cache_if_cols()
{
    external class csdid__Engine scalar CSDID_ENGINE

    csdid__engine_ensure()

    return(cols(CSDID_ENGINE.inffunc))
}

real matrix csdid_cache_if_select(real vector keep)
{
    external class csdid__Engine scalar CSDID_ENGINE

    csdid__engine_ensure()

    return(CSDID_ENGINE.inffunc[., keep])
}

real matrix csdid_cache_cluster_vec()
{
    external class csdid__Engine scalar CSDID_ENGINE

    csdid__engine_ensure()

    return(CSDID_ENGINE.cluster_vec)
}

real scalar csdid_cache_agg_token()
{
    external class csdid__Engine scalar CSDID_ENGINE

    csdid__engine_ensure()

    return(CSDID_ENGINE.agg_token)
}

real scalar csdid_cache_agg_cols()
{
    external class csdid__Engine scalar CSDID_ENGINE

    csdid__engine_ensure()

    return(cols(CSDID_ENGINE.agg_inffunc))
}

// ===========================================================================
// SECTION 4 -- NUMERIC PRIMITIVES FOR THE 2x2 FITS
//
// Vector and matrix primitives shared by every estimator below: the logit
// link with its overflow clamps, weight normalisation, the two R-parity
// inverses, and the propensity-score cap and trim rules. Each mirrors a
// specific R or DRDID expression, named in the comment at its own site.
// ===========================================================================


real colvector csdid__invlogit(real colvector eta)
{
    real colvector p
    real colvector e2, t

    // F-023 fix: replicate R stats::binomial()$linkinv exactly
    // (src/library/stats/src/family.c, logit_linkinv), which is what
    // DRDID's fastglm_fit(..., stats::binomial(), ...) calls. R thresholds
    // on ETA at +/-30 and uses DBL_EPSILON / 1-DBL_EPSILON, not a direct
    // clamp on p at [1e-8, 1-1e-8]. The post-fit cap at 1-1e-6 (l212)
    // already matches DRDID's pmin and is left alone.
    // PERF: the branchless clamping below is ~19 passes over eta, and it is a
    // no-op on essentially every real fit -- |eta| reaches 30 only under
    // near-perfect separation. When no element is missing and eta is inside
    // the band, every clamping term is identically zero, `e2' is `eta' and the
    // two `t' corrections add nothing, so exp(eta) :/ (1 :+ exp(eta)) is the
    // SAME arithmetic, not an approximation of it. Verified bit-identical over
    // eta inside the band, straddling it, entirely below -30, entirely above
    // 30, exactly on both boundaries, and containing missing.
    //
    // Missing must go the long way round: Mata orders missing above every
    // number, so the general path sends it through the eta > 30 correction and
    // returns a probability, where exp(.) would return missing. hasmissing()
    // is checked separately because min()/max() ignore missing and so cannot
    // detect it.
    if (!hasmissing(eta)) {
        if (min(eta) >= -30 & max(eta) <= 30) {
            t = exp(eta)
            return(t :/ (1 :+ t))
        }
    }

    e2 = eta
    e2 = e2 :+ (e2 :< -30) :* (-30 :- e2)
    e2 = e2 :- (e2 :>  30) :* (e2 :- 30)
    t  = exp(e2)
    t  = t :+ (eta :< -30) :* (epsilon(1) :- t)
    t  = t :+ (eta :>  30) :* (1 / epsilon(1) :- t)
    p  = t :/ (1 :+ t)
    return(p)
}

real colvector csdid__normalize_weights(real colvector w)
{
    real scalar mw

    mw = mean(w)
    if (mw <= 0 | mw >= .) return(J(rows(w), 1, .))
    return(w / mw)
}

real scalar csdid__nonconstant_weights(real colvector w)
{
    return(max(abs(w :- 1)) > 1e-10)
}

real scalar csdid__valid_inverse(real matrix a)
{
    if (sum(a :>= .) > 0) return(0)
    if (rows(a) == cols(a) & diag0cnt(a) > 0) return(0)
    return(1)
}

real matrix csdid__inv_r_parity(real matrix a)
{
    // R parity (F-005): invsym() drops near-collinear columns at its own
    // sweep tolerance, refusing cells R computes. Once the R-side rcond
    // guard has passed, fall back to LU inversion so Stata computes exactly
    // where R computes; a truly singular matrix still yields missings and
    // the caller's csdid__valid_inverse check refuses as before.
    real matrix ai

    ai = invsym(a)
    if (csdid__valid_inverse(ai)) return(ai)
    ai = luinv(a)
    if (hasmissing(ai)) return(J(rows(a), cols(a), .))
    return(ai)
}

real matrix csdid__hessinv_r_parity(real matrix a, real scalar n)
{
    // R parity (F-005): DRDID inverts the pscore hessian XtWX.ps via
    // chol2inv(chol(.)) after guarding rcond(XtWX.ps) < eps (stop()).
    // invsym's sweep instead ZEROES the near-null direction, which rewrites
    // the IF estimation-correction term by O(1) on ill-conditioned designs
    // while atts/SEs barely move. Mirror R: refuse where R stops, otherwise
    // Cholesky-based inverse. Missing return -> caller's existing refusal.
    if (csdid__rcond1(a) < epsilon(1)) return(J(rows(a), cols(a), .))
    return(cholinv(a) * n)
}

real colvector csdid__cap_ps_rc(real colvector ps)
{
    real scalar ps_cap

    // DRDID's own ceiling, pmin(ps.fit, 1 - 1e-06), applied before a control
    // weight ps/(1 - ps) can be formed.
    ps_cap = 1 - 1e-6
    ps = ps :- (ps :> ps_cap) :* (ps :- ps_cap)
    return(ps)
}

// DRDID keeps a control iff `ps.fit < trim.level'. Which side of that test an
// exact tie falls on is decided by the FIT, not by the rule: R's ps comes from
// fastglm's IRLS, whose terminal iterate lands below the exact share at some
// shares (3.9e-15 under at 0.995, 1.5e-9 under at 0.90) and at or above it at
// others (exact at 0.50 for every n measured, up to 4.2e-15 over at 0.85), so
// what R does at an exact tie is floating-point residue that varies with the
// share and the sample size. No deterministic rule can match it everywhere.
// csdid's closed form is exact, and the convention is STRICT everywhere: a
// score exactly at the level trims, the cell refuses loudly with the trimming
// warning. Where that departs from R-as-executed (a keep-side tie such as
// 995/1000 at the default level), the departure is a visible missing with a
// named cause, never a number the reference declines to report. Documented as
// a knife-edge divergence in AGENTS.md; the convention is this one comparison.
real colvector csdid__trim_keep(real colvector ps, real scalar trim_level)
{
    return(ps :< trim_level)
}
// ===========================================================================
// SECTION 5 -- THE PROPENSITY-SCORE FIT
//
// csdid__logit_fit reproduces fastglmPure(family = binomial, method = 3):
// its IRLS iterate, its convergence rule and its clamps. Every ipw and dr
// estimate below inherits the last bits of that iterate, so the arithmetic
// here is transcription, not implementation.
// ===========================================================================


real colvector csdid__logit_fit(real colvector d, real matrix x, real colvector w)
{
    // F-002: bit-faithful replica of R DRDID's propensity-score fitter,
    // fastglmPure(family = binomial, method = 3, tol = 1e-8, maxit = 100):
    // GLM-style IRLS with mustart = (w*d + 0.5)/(w + 1), working-response
    // WLS steps, and the glm deviance stopping rule
    // |dev - dev_old| / (|dev| + 0.1) < 1e-8. Parity requires replicating
    // the trajectory AND the stopping point, so there is no warm start to
    // take: every fit begins at mustart (validated bit-exact vs fastglmPure
    // at 1e-16 with identical iteration counts).
    real scalar iter, pbar, dev, dev_old, unit_w, fastglm_tol, mu_floor
    real colvector b, mu, eta, z, ww, omu, mumu, omd
    real matrix h, h_inv

    // fastglmPure's own two constants: the deviance tolerance it stops on, and
    // the floor it clamps the fitted mean to. Both are R's, not ours.
    fastglm_tol = 1e-8
    mu_floor    = 1e-8

    if (cols(x) == 1) {
        pbar = mean(w :* d) / mean(w)
        if (pbar < mu_floor) pbar = mu_floor
        if (pbar > 1 - mu_floor) pbar = 1 - mu_floor
        return(log(pbar / (1 - pbar)))
    }

    // PERF: (1 :- mu) was recomputed three times per iteration and
    // mu :* (1 :- mu) twice, and (1 :- d) -- loop-invariant -- once per
    // iteration. Hoisting them changes no grouping: `w :* mu :* omu' is still
    // (w :* mu) :* (1 :- mu), and `mumu' is the same product the divisor used.
    // Bit-identical, and together with the invlogit guard the fit measured
    // 0.512s -> 0.328s over 60 refits of a 9,716-row cell.
    // The overlap guard fits this model with unit weights (R runs its own
    // guard unweighted, so csdid does too), which is every dr and ipw cell of
    // a weighted run -- half of all fits. Multiplying by 1.0 is exact, so
    // dropping those multiplies changes nothing: `w :* mu :* omu' is
    // (1 :* mu) :* omu, which is the mu :* omu already in hand, and
    // quadsum(1 :* v) is quadsum(v) term for term. One pass to detect, three
    // saved per iteration.
    unit_w = all(w :== 1)
    if (unit_w) mu = (d :+ 0.5) :/ 2
    else        mu = (w :* d :+ 0.5) :/ (w :+ 1)
    omu = 1 :- mu
    eta = log(mu :/ omu)
    omd = 1 :- d
    dev_old = 1e308
    b = J(cols(x), 1, .)
    for (iter = 1; iter <= 100; iter++) {
        mumu = mu :* omu
        if (unit_w) ww = mumu
        else        ww = w :* mu :* omu
        z = eta :+ (d :- mu) :/ mumu
        h = quadcross(x, ww, x)
        h_inv = invsym(h)
        if (csdid__valid_inverse(h_inv)) {
            b = h_inv * quadcross(x, ww :* z)
        }
        else {
            b = qrsolve(h, quadcross(x, ww :* z))
        }
        if (sum(b :>= .) > 0) return(J(cols(x), 1, .))
        eta = x * b
        mu = csdid__invlogit(eta)
        omu = 1 :- mu
        if (unit_w) dev = -2 * quadsum(d :* log(mu) :+ omd :* log(omu))
        else        dev = -2 * quadsum(w :* (d :* log(mu) :+ omd :* log(omu)))
        if (abs(dev - dev_old) / (abs(dev) + 0.1) < fastglm_tol) break
        dev_old = dev
    }
    return(b)
}
// ===========================================================================
// SECTION 6 -- CELL DIAGNOSTICS AND THEIR WARNINGS
//
// Everything that decides a (g,t) cell cannot be estimated, and everything
// that says so: the overlap check, the two conditioning tests, and the two
// warning printers. Where R warns about the same case the text mirrors R's
// wording -- check the upstream string before rewording one.
// ===========================================================================


real scalar csdid__overlap_status(real matrix x, real colvector d)
{
    // F-040: one classifier for the two distinct reasons R refuses a
    // propensity-score cell before estimating it, so that the warning the user
    // reads names the cause R names. Return codes are the fit_status codes
    // csdid__fit_status_warning() maps to text:
    //
    //   1 = did::overlap_check_fail() -- the fitted propensity reaches 0.999,
    //       i.e. the overlap condition is violated. R runs this guard on an
    //       UNWEIGHTED logit of D on the cohort design, so it fires identically
    //       with and without iweights;
    //   2 = the propensity fit cannot be computed at all, which is DRDID's
    //       separate "coefficients have NA components / multicollinearity"
    //       refusal (the F-013 singular-design branch);
    //   0 = design usable.
    //
    // This extends the F-013 singular-vs-overlap split to the weighted
    // branches. Those previously collapsed both reasons onto 2, so a user who
    // supplied iweights was told that a pure overlap violation -- the same
    // design R warns about with "overlap condition violated" -- was a singular
    // covariate matrix.
    external real matrix CSDID_OVL_X
    external real colvector CSDID_OVL_D
    external real scalar CSDID_OVL_STATUS
    real colvector beta, ps
    real scalar pbar, status, decided, overlap_cut, knife_edge_band

    // did::overlap_check_fail()'s cut, and the width of the band around it
    // inside which R defers to a real fit instead of answering outright.
    overlap_cut     = 0.999
    knife_edge_band = 1e-6

    if (rows(d) == 0) return(2)

    // PERF: this is a PURE function of (x, d) -- an unweighted logit and a
    // threshold on its fitted values -- and it is called once per 2x2 cell from
    // every estimator path, so it was running one full IRLS per cell on top of
    // the estimation fit (measured: 15 of the 30 logit fits on a 15-cell run).
    // On a balanced panel the overlap design is invariant in t for a fixed
    // cohort and control set, so consecutive cells present identical (x, d).
    //
    // The memo key is EXACT ELEMENTWISE EQUALITY of the inputs, not a hash and
    // not a derived key: if (x, d) are identical then the returned status is by
    // construction the one this function would have recomputed, so the result
    // is bit-identical and no staleness across runs is possible. The comparison
    // is O(n*k) against an IRLS costing several passes of transcendentals over
    // the same data, so a miss is cheap and a hit removes the whole fit.
    if (rows(CSDID_OVL_D) == rows(d) & rows(CSDID_OVL_X) == rows(x) &
        cols(CSDID_OVL_X) == cols(x)) {
        if (CSDID_OVL_D == d & CSDID_OVL_X == x) return(CSDID_OVL_STATUS)
    }

    // With an intercept-only design the unweighted logit MLE fits EVERY unit at
    // mean(d), so max(fitted) is mean(d) and the guard's answer is known in
    // both directions with no fit at all. That mirrors R's structure --
    // overlap_check_fail() returns `pbar >= 0.999' outright outside the
    // knife-edge band and defers to a fit inside it. INSIDE the band on an
    // intercept-only design, the fit below is the closed form (the exact
    // MLE), which reproduces pbar and refuses at the exact tie -- the
    // registered trim-tie rule: R's outcome there is the sign of fastglm's
    // terminal float residue, which no deterministic rule can match, so
    // csdid refuses loudly rather than chase it (AGENTS.md register). With
    // covariates the IRLS below runs and its iterate decides, as R's does.
    //
    // csdid used the closed form only to REFUSE. When the cell was fine -- the
    // common case -- it fell through and ran the fit anyway: a logit, an
    // n-length invlogit and a max, to re-derive a number already in hand. It
    // also meant the accept decision came from a value round-tripped through
    // log() and invlogit() rather than from mean(d) itself, which is not how R
    // decides it.
    //
    // The singular-design status 2 is unreachable here: the intercept-only
    // branch of csdid__logit_fit returns log(pbar / (1 - pbar)) with pbar
    // clamped away from both ends, so it never produces a missing coefficient.
    // A cell with no controls has mean(d) == 1 and is refused above, which is
    // where R's separate rcond_check_fail(!any(y == 0)) sends it too.
    status = 0
    decided = 0
    if (cols(x) == 1) {
        pbar = mean(d)
        if (abs(pbar - overlap_cut) > knife_edge_band) {
            status = (pbar >= overlap_cut)
            decided = 1
        }
    }
    if (!decided) {
        beta = csdid__logit_fit(d, x, J(rows(d), 1, 1))
        if (sum(beta :>= .) > 0) {
            status = 2
        }
        else {
            ps = csdid__invlogit(x * beta)
            if (max(ps) >= overlap_cut) status = 1
        }
    }

    CSDID_OVL_X = x
    CSDID_OVL_D = d
    CSDID_OVL_STATUS = status
    return(status)
}

real scalar csdid__rcond1(real matrix a)
{
    // F-005: exact 1-norm reciprocal condition number 1/(||A||_1 ||A^-1||_1),
    // matching R's rcond() (LAPACK dgecon 1-norm estimate; the estimator
    // attains the exact norm for these small blocks except on knife-edge
    // inputs — divergence registry). Returns 0 for singular/invalid input.
    real matrix ai
    real scalar n1a, n1ai

    n1a = max(colsum(abs(a)))
    if (n1a >= . | n1a == 0) return(0)
    ai = luinv(a)
    if (hasmissing(ai)) return(0)
    n1ai = max(colsum(abs(ai)))
    if (n1ai >= . | n1ai == 0) return(0)
    return(1 / (n1a * n1ai))
}

real scalar csdid__rcond_fail(real matrix x, real colvector d)
{
    real matrix xc

    if (cols(x) == 1) return(sum(d :== 0) == 0)
    xc = select(x, d :== 0)
    if (rows(xc) == 0) return(1)
    // F-005 R parity: did 2.5.1 rcond_check_fail tests
    //   rcond(crossprod(control_covs)) < .Machine$double.eps
    // (a rank() test disagrees with it in both directions: misses extreme
    // column-scale disparity; fires on benign near-collinearity R accepts).
    // crossprod in double precision (cross, not quadcross) to match R.
    return(csdid__rcond1(cross(xc, xc)) < epsilon(1))
}

// R's compute.att_gt raises four DISTINCT warnings when a 2x2 cell has no
// observations in one of its four corners, and names the BASE period -- not
// the cell's own period -- for the two pre-period corners. csdid carried five
// byte-similar copies of a guard that produced output for one corner only, so
// a cell blanked because its pre period was empty, or because there were no
// comparison units in either period, was dropped from the table with no
// explanation. Wordings are R's verbatim.
//
// Two of the five call sites alias nt0 to nt1 and nc0 to nc1, so only the
// treated-empty and comparison-empty states exist there; the helper is still
// correct in that case because equal counts cannot produce a pre-only
// message.
//
// CHANNEL. Every per-cell warning in this file is written with errprintf, not
// printf, and that is the whole difference between a warning and a warning the
// user sees. These announce a cell that is NOT in the table -- the same class
// of event as the sample-changing warnings the ado layer prints "as error" for
// exactly this reason -- and printf is silenced by a caller's `quietly',
// while errprintf is not (measured: under `quietly' the printf line is gone
// and the errprintf line survives). A scripted run that loses cells would
// otherwise leave no trace of why. The wordings are unchanged, including R's
// verbatim ones; only the channel is.
void csdid__empty_cell_warning(
    real scalar nt1,
    real scalar nt0,
    real scalar nc1,
    real scalar nc0,
    real scalar g,
    real scalar t,
    real scalar pret)
{
    if (nt1 <= 0) errprintf("warning: No units in group %g in time period %g\n", g, t)
    if (nt0 <= 0) errprintf("warning: No units in group %g in time period %g\n", g, pret)
    if (nc1 <= 0) errprintf("warning: No available control units for group %g in time period %g\n", g, t)
    if (nc0 <= 0) errprintf("warning: No available control units for group %g in time period %g\n", g, pret)
}

void csdid__fit_status_warning(
    real scalar fit_status,
    string scalar method,
    real scalar has_x,
    real scalar g,
    real scalar t)
{
    // Single source of truth for the per-cell refusal warnings; the three
    // 2x2 routes in csdid_basic_attgt used to carry byte-identical copies.
    if (fit_status == 1) {
        errprintf("warning: overlap condition violated for group %g in time period %g\n", g, t)
        return
    }
    if (fit_status == 3) {
        // Status 3 is "the weights are unusable": csdid__normalize_weights
        // produced missing values, or trimming left no effective comparison
        // mass. Ten call sites return it and none of them said anything, so
        // the cell arrived as a blank row with no explanation at all -- in a
        // package whose rule is loud refusal over silent fallback.
        errprintf("warning: no usable weights for group %g in time period %g; the supplied weights are missing or non-positive on this cell, or the propensity-score trim left no effective comparison mass. ATT(g,t) is not estimable\n", g, t)
        return
    }
    if (fit_status != 2) return
    // DS-04b: the covariate wordings below name a covariate matrix the user
    // never supplied when the model has no covariates. Only R's covariate
    // texts are reproduced when covariates exist; otherwise the message names
    // the actual cause, a degenerate comparison group.
    if (!has_x) {
        errprintf("warning: no usable comparison units for group %g in time period %g; ATT(g,t) is not estimable\n", g, t)
        return
    }
    if (method == "ipw") {
        // F-013 R parity: ipw singular-design refusals were misrouted through
        // the overlap warning; R's run_DRDID ipw rcond stop uses the ps-design
        // wording.
        errprintf("warning: The propensity score design matrix is singular for group %g in time period %g. Consider removing some covariates.\n", g, t)
        return
    }
    if (method == "dr" | method == "reg") {
        errprintf("warning: Covariate matrix for control units is singular or numerically ill-conditioned for group %g in time period %g; consider centering/rescaling covariates or removing collinear terms\n", g, t)
    }
}

// ===========================================================================
// SECTION 7 -- THE 2x2 ESTIMATORS
//
// The six kernels that produce one ATT(g,t) and its influence function:
// reg, ipw and dr, for a panel and for repeated cross sections. Each
// transcribes the corresponding DRDID routine, including the order of the
// arithmetic, and returns (att \ influence function \ status) so a caller
// can tell a refusal from a number.
// ===========================================================================


real colvector csdid__reg_panel_fit(
    real colvector y1,
    real colvector y0,
    real colvector d,
    real matrix x,
    real colvector wraw)
{
    real scalar n, mw_treat, mw_cont, eta_treat, eta_cont, att
    real matrix xtwx, xtwx_inv, xpx_inv
    real colvector dy, w, beta, out_delta, w_treat, w_cont
    real colvector reg_att_treat, reg_att_cont, weights_ols
    real colvector inf_treat, inf_cont_1, inf_cont_2, inf_control, inf
    real colvector m1, gamma_ols, ols_resid

    n = rows(d)
    dy = y1 :- y0
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    // DS-04: no `n_control <= cols(x)' pre-test here. R did 2.5.1 gates this
    // cell on rcond_check_fail() ALONE, so a comparison group with exactly one
    // unit (or with as many units as regressors) is estimated by R and must be
    // estimated here too. csdid__rcond_fail() already refuses every design R
    // refuses -- including the zero-control case (cols(x)==1 branch) and the
    // rank-deficient control design -- so the extra count test only produced
    // missing ATT/SE where R returns finite values.
    if (csdid__rcond_fail(x, d)) return(. \ J(n, 1, .) \ 2)  // F-005: R rcond_check_fail on the control design

    weights_ols = w :* (1 :- d)
    xtwx = quadcross(x, weights_ols, x)
    xtwx_inv = csdid__inv_r_parity(xtwx)  // F-005: R-parity inverse
    if (!csdid__valid_inverse(xtwx_inv)) return(. \ J(n, 1, .) \ 2)
    beta = xtwx_inv * quadcross(x, weights_ols :* dy)
    out_delta = x * beta

    w_treat = w :* d
    w_cont = w :* d
    mw_treat = mean(w_treat)
    mw_cont = mean(w_cont)
    // The eighth fit site gains the guard the other seven carry (the
    // register's rule; cold-audit round 8, F2): a treated or control arm
    // with no effective mass -- a zero-weight cohort, say -- is an
    // ANNOUNCED blank (fit_status 3), never a silent division by zero.
    // min() ignores missing, so each mean is also tested against missing.
    if (min((mw_treat, mw_cont)) <= 0 |
        mw_treat >= . | mw_cont >= .) return(. \ J(n, 1, .) \ 3)
    reg_att_treat = w_treat :* dy
    reg_att_cont = w_cont :* out_delta
    eta_treat = mean(reg_att_treat) / mw_treat
    eta_cont = mean(reg_att_cont) / mw_cont
    att = eta_treat - eta_cont

    xpx_inv = n * xtwx_inv
    ols_resid = weights_ols :* (dy :- out_delta)

    inf_treat = (reg_att_treat :- w_treat * eta_treat) / mw_treat
    inf_cont_1 = reg_att_cont :- w_cont * eta_cont
    m1 = quadcross(x, w_cont) / n
    gamma_ols = xpx_inv * m1
    inf_cont_2 = ols_resid :* (x * gamma_ols)
    inf_control = (inf_cont_1 + inf_cont_2) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__ipw_panel_fit(
    real colvector y1,
    real colvector y0,
    real colvector d,
    real matrix x,
    real colvector wraw,
    real scalar trim_level)
{
    real scalar n, mw_treat, mw_cont, eta_treat, eta_cont, att, nonconstant_w, pbar, hscalar, keep_control
    real scalar mean_w, mean_wd, mean_w0, treat_moment, cont_moment, cont_factor, m2_scalar
    real scalar overlap_status, overlap_cut, mu_floor, ps_cap
    real matrix h
    real colvector dy, beta, ps, trim, w, w_treat, w_cont, att_treat, att_cont
    real colvector inf_treat, inf_cont_1, inf_cont_2, inf_control, inf
    real colvector m2, gamma_ps

    overlap_cut = 0.999          // did::overlap_check_fail()
    mu_floor    = 1e-8           // fastglmPure's clamp on the fitted mean
    ps_cap      = 1 - 1e-6       // DRDID's pmin(ps.fit, 1 - 1e-06)

    n = rows(d)
    dy = y1 :- y0
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    nonconstant_w = csdid__nonconstant_weights(w)
    if (cols(x) == 1) {
        // The overlap refusal is did::overlap_check_fail(), which fits an
        // UNWEIGHTED logit (utility_functions.R:86-93) and so must be decided on
        // mean(d), knife edge included; only the pbar below -- the weighted
        // intercept-only MLE DRDID estimates with -- carries the weights. The
        // two coincide without iweights, so this is the same set of refused
        // cells there, and the classifier is the one every other pscore path
        // already uses.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
        pbar = mean(w :* d) / mean(w)
        if (pbar < mu_floor) pbar = mu_floor
        // DRDID's own ceiling, before the control weight ps/(1-ps) is formed.
        // The shortcut bypasses csdid__cap_ps_rc(), so it caps here, at DRDID's
        // level -- clamping at 1 - mu_floor instead let a control weight reach
        // ~1e8 where DRDID's stops at ~1e6.
        if (pbar > ps_cap) pbar = ps_cap
        keep_control = (pbar < trim_level)  // see csdid__trim_keep: ties trim
        mean_w = mean(w)
        mean_wd = quadcross(w, d) / n
        mean_w0 = mean_w - mean_wd
        cont_factor = keep_control * pbar / (1 - pbar)
        mw_treat = mean_wd
        mw_cont = cont_factor * mean_w0
        // Both tests, in that order, at every site in this family. Mata's
        // min() IGNORES missing -- min((., 5)) is 5 -- so a missing mean walks
        // straight through the <= 0 half and the cell is then reported as a
        // SUCCESSFUL fit carrying a missing ATT. The live doubly-robust panel
        // route already tests both; see the note at the general branch below.
        if (min((mw_treat, mw_cont)) <= 0 |
            mw_treat >= . | mw_cont >= .) return(. \ J(n, 1, .) \ 3)
        treat_moment = quadcross(w, d :* dy) / n
        cont_moment = cont_factor * quadcross(w, (1 :- d) :* dy) / n
        eta_treat = treat_moment / mw_treat
        eta_cont = cont_moment / mw_cont
        att = eta_treat - eta_cont
        m2_scalar = cont_moment - mw_cont * eta_cont
        hscalar = 1 / (pbar * (1 - pbar))
        inf = (w :* d :* (dy :- eta_treat)) / mw_treat :-
            ((cont_factor * w :* (1 :- d) :* (dy :- eta_cont)) :+
            (w :* (d :- pbar)) * (hscalar * m2_scalar)) / mw_cont
        return(att \ inf \ 0)
    }
    if (nonconstant_w) {
        // F-040: classify the pre-estimation refusal the way R does. The guard
        // itself is unchanged (same unweighted fit, same overlap cut-off, same
        // set of refused cells); only the reported cause changes, so an
        // overlap violation under iweights no longer reaches the user as a
        // singular-covariate-matrix message.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
    }
    beta = csdid__logit_fit(d, x, w)
    if (sum(beta :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap
    // DRDID::ipw_did_panel / drdid_panel apply pmin(ps.fit, 1 - 1e-06) before
    // forming the control weight ps/(1-ps) and the Hessian weight ps*(1-ps).
    // Without the cap an uncapped ps could reach 1-2.2e-16 and blow the control
    // weight up to ~4.5e15 where R caps it at ~1e6. Unreachable at the 0.995
    // default (such controls are trimmed), but reachable once pscoretrim() >= 1
    // (no trimming) is accepted, so cap here exactly as DRDID does.
    ps = csdid__cap_ps_rc(csdid__invlogit(x * beta))
    if (!nonconstant_w & max(ps) >= overlap_cut) return(. \ J(n, 1, .) \ 1)
    trim = J(n, 1, 1)
    trim = trim :* ((d :== 1) :| csdid__trim_keep(ps, trim_level))

    w_treat = trim :* w :* d
    w_cont = trim :* w :* ps :* (1 :- d) :/ (1 :- ps)
    mw_treat = mean(w_treat)
    mw_cont = mean(w_cont)
    // Both branches of this routine DIVIDE by these means, and only the
    // intercept-only branch above said so. A trim that leaves no effective
    // comparison mass therefore arrived as a blank ATT with fit_status 0 --
    // a refusal the user was never told about. No number moves: the divisions
    // already produced missing. The cell now announces its cause, exactly as
    // the intercept-only branch, both RC twins and the live doubly-robust
    // panel route do.
    // APPROVED DIVERGENCE from R: DRDID::std_ipw_did_panel divides by the same
    // zero and returns NaN in silence. The doubly-robust panel route already
    // diverges here in the same direction and for the same reason; csdid is
    // loud where R is quiet, and the two agree on every number.
    // The second test is not redundant with the first. min() ignores missing,
    // so without it a missing mean is classified fit_status 0 -- a successful
    // fit with a missing ATT -- which is the one verdict this cell must never
    // report. It moves no number either: the divisions below already produce
    // missing wherever it fires.
    if (min((mw_treat, mw_cont)) <= 0 |
        mw_treat >= . | mw_cont >= .) return(. \ J(n, 1, .) \ 3)
    att_treat = w_treat :* dy
    att_cont = w_cont :* dy
    eta_treat = mean(att_treat) / mw_treat
    eta_cont = mean(att_cont) / mw_cont
    att = eta_treat - eta_cont

    h = quadcross(x, ps :* (1 :- ps) :* w, x)
    h = csdid__hessinv_r_parity(h, n)  // F-005: R chol2inv(chol()) after the rcond guard
    if (sum(h :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap

    inf_treat = (att_treat :- w_treat * eta_treat) / mw_treat
    inf_cont_1 = att_cont :- w_cont * eta_cont
    m2 = quadcross(x, w_cont :* (dy :- eta_cont)) / n
    gamma_ps = h * m2
    inf_cont_2 = (w :* (d :- ps)) :* (x * gamma_ps)
    inf_control = (inf_cont_1 + inf_cont_2) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__dr_panel_fit_precomputed(
    real colvector y1,
    real colvector y0,
    real colvector d,
    real matrix x,
    real colvector w_treat,
    real colvector w_cont,
    real colvector score_ps,
    real colvector xgamma_treat_ols,
    real colvector xgamma_cont_ols,
    real scalar mw_treat,
    real scalar mw_cont,
    real matrix xtwx_inv,
    real matrix h,
    real colvector weights_ols)
{
    real scalar n, eta_treat, eta_cont, att
    real colvector dy, beta_or, out_delta, dr_treat, dr_cont, ols_resid
    real colvector inf_treat_1, inf_treat_2, inf_treat
    real colvector inf_cont_1, inf_cont_2, inf_cont_3, inf_control, inf
    real colvector m2, gamma_ps

    n = rows(d)
    dy = y1 :- y0
    beta_or = xtwx_inv * quadcross(x, weights_ols :* dy)
    out_delta = x * beta_or

    dr_treat = w_treat :* (dy :- out_delta)
    dr_cont = w_cont :* (dy :- out_delta)
    eta_treat = mean(dr_treat) / mw_treat
    eta_cont = mean(dr_cont) / mw_cont
    att = eta_treat - eta_cont

    ols_resid = weights_ols :* (dy :- out_delta)

    inf_treat_1 = dr_treat :- w_treat * eta_treat
    inf_treat_2 = ols_resid :* xgamma_treat_ols
    inf_treat = (inf_treat_1 - inf_treat_2) / mw_treat

    inf_cont_1 = dr_cont :- w_cont * eta_cont
    m2 = quadcross(x, w_cont :* (dy :- out_delta :- eta_cont)) / n
    gamma_ps = h * m2
    inf_cont_2 = score_ps :* (x * gamma_ps)
    inf_cont_3 = ols_resid :* xgamma_cont_ols
    inf_control = (inf_cont_1 + inf_cont_2 - inf_cont_3) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__reg_rc_fit(
    real colvector y,
    real colvector post,
    real colvector d,
    real matrix x,
    real colvector wraw)
{
    real scalar n, eta_treat_pre, eta_treat_post, eta_cont, att
    real scalar mw_treat_pre, mw_treat_post, mw_cont
    real matrix xpre, xpost, xtwx_pre, xtwx_post, xtwx_inv_pre, xtwx_inv_post, xpx_inv_pre, xpx_inv_post
    real colvector w, beta_pre, beta_post, out_pre, out_post
    real colvector w_treat_pre, w_treat_post, w_cont, reg_treat_pre, reg_treat_post, reg_cont
    real colvector weights_ols_pre, weights_ols_post
    real colvector inf_treat_pre, inf_treat_post, inf_treat
    real colvector inf_cont_1, inf_cont_2_pre, inf_cont_2_post, inf_control, inf
    real colvector m1, gamma_ols, ols_resid_pre, ols_resid_post
    real colvector m_cont_pre, m_cont_post

    n = rows(d)
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)

    // The two control-block masks were rebuilt from scratch three times each
    // -- once for the design, once for the weights, once for the weighted
    // outcome -- which is six full n-length elementwise passes for two
    // vectors. Compute them once. Same masks, same select(), same order.
    m_cont_pre = (d :== 0) :& (post :== 0)
    m_cont_post = (d :== 0) :& (post :== 1)
    xpre = select(x, m_cont_pre)
    xpost = select(x, m_cont_post)
    // DS-04, extended to the repeated-cross-section fits. This carried the
    // `rows <= cols(x)' pre-test that DS-04 removed from the panel fits for
    // R parity, and it is wrong here for the same reason: DRDID's reg_did_rc
    // has no count test at all, gating on anyNA(coefficients) plus rcond on
    // the per-block cross-products. Because the test used `<=', it bit at
    // EXACT identification -- a block with as many observations as
    // regressors, which is estimable and which the inverse guards below
    // accept -- so csdid returned a missing ATT and SE where R returns finite
    // values. csdid__rcond_fail plus csdid__inv_r_parity/csdid__valid_inverse
    // on each block already refuse every genuinely rank-deficient design.
    if (csdid__rcond_fail(x, d)) return(. \ J(n, 1, .) \ 2)  // F-005: R rcond_check_fail on the control design
    xtwx_pre = quadcross(xpre, select(w, m_cont_pre), xpre)
    xtwx_post = quadcross(xpost, select(w, m_cont_post), xpost)
    xtwx_inv_pre = csdid__inv_r_parity(xtwx_pre)  // F-005: R-parity inverse
    xtwx_inv_post = csdid__inv_r_parity(xtwx_post)  // F-005: R-parity inverse
    if (!csdid__valid_inverse(xtwx_inv_pre) | !csdid__valid_inverse(xtwx_inv_post)) return(. \ J(n, 1, .) \ 2)
    beta_pre = xtwx_inv_pre * quadcross(xpre, select(w :* y, m_cont_pre))
    beta_post = xtwx_inv_post * quadcross(xpost, select(w :* y, m_cont_post))
    out_pre = x * beta_pre
    out_post = x * beta_post

    w_treat_pre = w :* d :* (1 :- post)
    w_treat_post = w :* d :* post
    w_cont = w :* d
    mw_treat_pre = mean(w_treat_pre)
    mw_treat_post = mean(w_treat_post)
    mw_cont = mean(w_cont)
    // min() ignores missing; see csdid__ipw_panel_fit. Same family, same pair
    // of tests, so a missing mean is fit_status 3 here too.
    if (min((mw_treat_pre, mw_treat_post, mw_cont)) <= 0 |
        mw_treat_pre >= . | mw_treat_post >= . |
        mw_cont >= .) return(. \ J(n, 1, .) \ 3)

    reg_treat_pre = w_treat_pre :* y
    reg_treat_post = w_treat_post :* y
    reg_cont = w_cont :* (out_post :- out_pre)
    eta_treat_pre = mean(reg_treat_pre) / mw_treat_pre
    eta_treat_post = mean(reg_treat_post) / mw_treat_post
    eta_cont = mean(reg_cont) / mw_cont
    att = (eta_treat_post - eta_treat_pre) - eta_cont

    weights_ols_pre = w :* (1 :- d) :* (1 :- post)
    xpx_inv_pre = n * xtwx_inv_pre
    ols_resid_pre = weights_ols_pre :* (y :- out_pre)
    weights_ols_post = w :* (1 :- d) :* post
    xpx_inv_post = n * xtwx_inv_post
    ols_resid_post = weights_ols_post :* (y :- out_post)

    inf_treat_pre = (reg_treat_pre :- w_treat_pre * eta_treat_pre) / mw_treat_pre
    inf_treat_post = (reg_treat_post :- w_treat_post * eta_treat_post) / mw_treat_post
    inf_treat = inf_treat_post - inf_treat_pre
    inf_cont_1 = reg_cont :- w_cont * eta_cont
    m1 = quadcross(x, w_cont) / n
    gamma_ols = xpx_inv_post * m1
    inf_cont_2_post = ols_resid_post :* (x * gamma_ols)
    gamma_ols = xpx_inv_pre * m1
    inf_cont_2_pre = ols_resid_pre :* (x * gamma_ols)
    inf_control = (inf_cont_1 + inf_cont_2_post - inf_cont_2_pre) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__ipw_rc_fit(
    real colvector y,
    real colvector post,
    real colvector d,
    real matrix x,
    real colvector wraw,
    real scalar trim_level)
{
    real scalar n, att, att_treat_pre, att_treat_post, att_cont_pre, att_cont_post, nonconstant_w, pbar, hscalar, keep_control
    real scalar mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post, overlap_status
    real scalar overlap_cut, mu_floor, ps_cap
    real matrix h
    real colvector w, beta, ps, trim, W
    real colvector w_treat_pre, w_treat_post, w_cont_pre, w_cont_post
    real colvector eta_treat_pre, eta_treat_post, eta_cont_pre, eta_cont_post
    real colvector inf_treat_pre, inf_treat_post, inf_treat
    real colvector inf_cont_pre, inf_cont_post, inf_cont, inf_cont_ps, inf
    real colvector m2_pre, m2_post, gamma_ps

    overlap_cut = 0.999          // did::overlap_check_fail()
    mu_floor    = 1e-8           // fastglmPure's clamp on the fitted mean
    ps_cap      = 1 - 1e-6       // DRDID's pmin(ps.fit, 1 - 1e-06)

    n = rows(d)
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    nonconstant_w = csdid__nonconstant_weights(w)
    if (cols(x) == 1) {
        // See csdid__ipw_panel_fit: the overlap refusal is R's unweighted
        // overlap_check_fail(); only the estimator's pbar is weighted.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
        pbar = mean(w :* d) / mean(w)
        if (pbar < mu_floor) pbar = mu_floor
        if (pbar > ps_cap) pbar = ps_cap
        keep_control = (pbar < trim_level)  // see csdid__trim_keep: ties trim
        w_treat_pre = w :* d :* (1 :- post)
        w_treat_post = w :* d :* post
        w_cont_pre = keep_control * w :* pbar :* (1 :- d) :* (1 :- post) :/ (1 - pbar)
        w_cont_post = keep_control * w :* pbar :* (1 :- d) :* post :/ (1 - pbar)
        mw_treat_pre = mean(w_treat_pre)
        mw_treat_post = mean(w_treat_post)
        mw_cont_pre = mean(w_cont_pre)
        mw_cont_post = mean(w_cont_post)
        // min() ignores missing; see csdid__ipw_panel_fit.
        if (min((mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post)) <= 0 |
            mw_treat_pre >= . | mw_treat_post >= . |
            mw_cont_pre >= . | mw_cont_post >= .) return(. \ J(n, 1, .) \ 3)
        att_treat_pre = mean(w_treat_pre :* y) / mw_treat_pre
        att_treat_post = mean(w_treat_post :* y) / mw_treat_post
        att_cont_pre = mean(w_cont_pre :* y) / mw_cont_pre
        att_cont_post = mean(w_cont_post :* y) / mw_cont_post
        att = (att_treat_post - att_treat_pre) - (att_cont_post - att_cont_pre)
        inf_treat_pre = (w_treat_pre :* y :- w_treat_pre * att_treat_pre) / mw_treat_pre
        inf_treat_post = (w_treat_post :* y :- w_treat_post * att_treat_post) / mw_treat_post
        inf_treat = inf_treat_post - inf_treat_pre
        inf_cont_pre = (w_cont_pre :* y :- w_cont_pre * att_cont_pre) / mw_cont_pre
        inf_cont_post = (w_cont_post :* y :- w_cont_post * att_cont_post) / mw_cont_post
        inf_cont = inf_cont_post - inf_cont_pre
        m2_pre = mean(w_cont_pre :* (y :- att_cont_pre)) / mw_cont_pre
        m2_post = mean(w_cont_post :* (y :- att_cont_post)) / mw_cont_post
        hscalar = 1 / (pbar * (1 - pbar))
        inf_cont_ps = (w :* (d :- pbar)) :* (hscalar * (m2_post - m2_pre))
        inf_cont = inf_cont + inf_cont_ps
        inf = inf_treat - inf_cont
        return(att \ inf \ 0)
    }
    if (nonconstant_w) {
        // F-040: see csdid__ipw_panel_fit -- same guard, R's classification.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
    }
    beta = csdid__logit_fit(d, x, w)
    if (sum(beta :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap
    ps = csdid__cap_ps_rc(csdid__invlogit(x * beta))
    if (!nonconstant_w & max(ps) >= overlap_cut) return(. \ J(n, 1, .) \ 1)
    W = ps :* (1 :- ps) :* w
    trim = J(n, 1, 1)
    trim = trim :* ((d :== 1) :| csdid__trim_keep(ps, trim_level))

    w_treat_pre = trim :* w :* d :* (1 :- post)
    w_treat_post = trim :* w :* d :* post
    w_cont_pre = trim :* w :* ps :* (1 :- d) :* (1 :- post) :/ (1 :- ps)
    w_cont_post = trim :* w :* ps :* (1 :- d) :* post :/ (1 :- ps)
    mw_treat_pre = mean(w_treat_pre)
    mw_treat_post = mean(w_treat_post)
    mw_cont_pre = mean(w_cont_pre)
    mw_cont_post = mean(w_cont_post)
    // min() ignores missing; see csdid__ipw_panel_fit.
    if (min((mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post)) <= 0 |
        mw_treat_pre >= . | mw_treat_post >= . |
        mw_cont_pre >= . | mw_cont_post >= .) return(. \ J(n, 1, .) \ 3)

    eta_treat_pre = w_treat_pre :* y / mw_treat_pre
    eta_treat_post = w_treat_post :* y / mw_treat_post
    eta_cont_pre = w_cont_pre :* y / mw_cont_pre
    eta_cont_post = w_cont_post :* y / mw_cont_post
    att_treat_pre = mean(eta_treat_pre)
    att_treat_post = mean(eta_treat_post)
    att_cont_pre = mean(eta_cont_pre)
    att_cont_post = mean(eta_cont_post)
    att = (att_treat_post - att_treat_pre) - (att_cont_post - att_cont_pre)

    h = quadcross(x, W, x)
    h = csdid__hessinv_r_parity(h, n)  // F-005: R chol2inv(chol()) after the rcond guard
    if (sum(h :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap

    inf_treat_pre = eta_treat_pre :- w_treat_pre * att_treat_pre / mw_treat_pre
    inf_treat_post = eta_treat_post :- w_treat_post * att_treat_post / mw_treat_post
    inf_treat = inf_treat_post - inf_treat_pre
    inf_cont_pre = eta_cont_pre :- w_cont_pre * att_cont_pre / mw_cont_pre
    inf_cont_post = eta_cont_post :- w_cont_post * att_cont_post / mw_cont_post
    inf_cont = inf_cont_post - inf_cont_pre
    m2_pre = quadcross(x, w_cont_pre :* (y :- att_cont_pre)) / n / mw_cont_pre
    m2_post = quadcross(x, w_cont_post :* (y :- att_cont_post)) / n / mw_cont_post
    gamma_ps = h * (m2_post - m2_pre)
    inf_cont_ps = (w :* (d :- ps)) :* (x * gamma_ps)
    inf_cont = inf_cont + inf_cont_ps
    inf = inf_treat - inf_cont

    return(att \ inf \ 0)
}

real colvector csdid__dr_rc_fit(
    real colvector y,
    real colvector post,
    real colvector d,
    real matrix x,
    real colvector wraw,
    real scalar trim_level)
{
    real scalar n, att, mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post, nonconstant_w
    real scalar mw_d, mw_dt1, mw_dt0, overlap_status, overlap_cut
    real scalar att_treat_pre, att_treat_post, att_cont_pre, att_cont_post
    real scalar att_d_post, att_dt1_post, att_d_pre, att_dt0_pre
    real matrix xcp, xct, xtp, xtt, h
    real matrix xtwx_c_pre, xtwx_c_post, xtwx_t_pre, xtwx_t_post
    real matrix xtwx_inv_c_pre, xtwx_inv_c_post, xtwx_inv_t_pre, xtwx_inv_t_post
    real matrix xpx_inv_pre, xpx_inv_post, xpx_inv_pre_treat, xpx_inv_post_treat
    real colvector w, beta_ps, ps, W, trim, post0, d0, wd, wc, wy, psratio
    real colvector m_c_pre, m_c_post, m_t_pre, m_t_post
    real colvector beta_c_pre, beta_c_post, beta_t_pre, beta_t_post
    real colvector out_c_pre, out_c_post, out_c, out_t_pre, out_t_post
    real colvector w_treat_pre, w_treat_post, w_cont_pre, w_cont_post, w_d, w_dt1, w_dt0
    real colvector eta_treat_pre, eta_treat_post, eta_cont_pre, eta_cont_post
    real colvector eta_d_post, eta_dt1_post, eta_d_pre, eta_dt0_pre
    real colvector weights_ols_pre, weights_ols_post, weights_ols_pre_treat, weights_ols_post_treat
    real colvector inf_treat_pre, inf_treat_post, inf_treat, inf_cont_pre, inf_cont_post, inf_cont
    real colvector inf_treat_or_post, inf_treat_or_pre, inf_cont_or_post, inf_cont_or_pre
    real colvector inf_treat_or, inf_cont_or, inf_cont_ps, inf_eff, inf_or, inf
    real colvector inf_eff1, inf_eff2, inf_eff3, inf_eff4, inf_or_post, inf_or_pre
    real colvector m1_post, m1_pre, m2_post, m2_pre, m3_post, m3_pre, mom_post, mom_pre
    real colvector ols_res_pre, ols_res_post, ols_res_pre_treat, ols_res_post_treat
    real colvector gamma_ps
    real colvector twd, twcps, resid_c, dout_post, dout_pre
    real matrix gmat, xgam

    overlap_cut = 0.999          // did::overlap_check_fail()

    n = rows(d)
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    nonconstant_w = csdid__nonconstant_weights(w)
    if (nonconstant_w) {
        // F-040: see csdid__ipw_panel_fit -- same guard, R's classification.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
    }
    beta_ps = csdid__logit_fit(d, x, w)
    if (sum(beta_ps :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap
    ps = csdid__cap_ps_rc(csdid__invlogit(x * beta_ps))
    if (!nonconstant_w & max(ps) >= overlap_cut) return(. \ J(n, 1, .) \ 1)
    trim = J(n, 1, 1)
    trim = trim :* ((d :== 1) :| csdid__trim_keep(ps, trim_level))
    post0 = 1 :- post
    d0 = 1 :- d
    wd = w :* d
    wc = w :* d0
    psratio = ps :/ (1 :- ps)

    m_c_pre = d0 :& post0
    m_c_post = d0 :& post
    m_t_pre = d :& post0
    m_t_post = d :& post
    xcp = select(x, m_c_pre)
    xct = select(x, m_c_post)
    xtp = select(x, m_t_pre)
    xtt = select(x, m_t_post)
    // DS-04, extended: no `rows <= cols(x)' pre-test. DRDID's drdid_rc gates
    // on anyNA plus rcond on the four weighted cross-products, with no count
    // test, and the four per-block inverse guards below reproduce that. See
    // the note in csdid__reg_rc_fit.
    if (csdid__rcond_fail(x, d)) return(. \ J(n, 1, .) \ 2)  // F-005: R rcond_check_fail on the control design
    xtwx_c_pre = quadcross(xcp, select(w, m_c_pre), xcp)
    xtwx_c_post = quadcross(xct, select(w, m_c_post), xct)
    xtwx_t_pre = quadcross(xtp, select(w, m_t_pre), xtp)
    xtwx_t_post = quadcross(xtt, select(w, m_t_post), xtt)
    xtwx_inv_c_pre = csdid__inv_r_parity(xtwx_c_pre)  // F-005: R-parity inverse
    xtwx_inv_c_post = csdid__inv_r_parity(xtwx_c_post)  // F-005: R-parity inverse
    xtwx_inv_t_pre = csdid__inv_r_parity(xtwx_t_pre)  // F-005: R-parity inverse
    xtwx_inv_t_post = csdid__inv_r_parity(xtwx_t_post)  // F-005: R-parity inverse
    if (!csdid__valid_inverse(xtwx_inv_c_pre) | !csdid__valid_inverse(xtwx_inv_c_post) | !csdid__valid_inverse(xtwx_inv_t_pre) | !csdid__valid_inverse(xtwx_inv_t_post)) return(. \ J(n, 1, .) \ 2)

    // PERF: pure common-subexpression elimination, no regrouping. `trim :* wd'
    // was built five times and `trim :* wc :* psratio' twice; w_dt1 and w_dt0
    // are character-for-character the same expressions as w_treat_post and
    // w_treat_pre, so they are the same vector and their means are the same
    // scalar. Association is unchanged -- `trim :* wd :* post0' is
    // ((trim :* wd) :* post0), which is exactly `twd :* post0'.
    twd = trim :* wd
    twcps = trim :* wc :* psratio
    w_treat_pre = twd :* post0
    w_treat_post = twd :* post
    w_cont_pre = twcps :* post0
    w_cont_post = twcps :* post
    w_d = twd
    w_dt1 = w_treat_post
    w_dt0 = w_treat_pre
    mw_treat_pre = mean(w_treat_pre)
    mw_treat_post = mean(w_treat_post)
    mw_cont_pre = mean(w_cont_pre)
    mw_cont_post = mean(w_cont_post)
    mw_d = mean(w_d)
    mw_dt1 = mw_treat_post
    mw_dt0 = mw_treat_pre
    // min() ignores missing; see csdid__ipw_panel_fit. mw_dt1 and mw_dt0 are
    // copies of mw_treat_post and mw_treat_pre and need no test of their own.
    if (min((mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post, mw_d, mw_dt1, mw_dt0)) <= 0 |
        mw_treat_pre >= . | mw_treat_post >= . |
        mw_cont_pre >= . | mw_cont_post >= . | mw_d >= .) return(. \ J(n, 1, .) \ 3)

    // With an intercept-only design the doubly robust estimator IS the
    // regression estimator. The propensity score is the constant weighted
    // treated share, so the inverse-probability factor is common to every
    // control and cancels between each numerator and its own normalising
    // mean; the control-side moments become deviations of y from their own
    // weighted mean and vanish; the two outcome-contrast terms are constants
    // that cancel in pairs; and m2_post - m2_pre is zero, so the
    // propensity-score correction to the influence function drops out. What
    // remains is the plain difference in differences with the regression
    // influence function.
    //
    // Measured over three repeated-cross-section designs crossed with five
    // option sets: identical to the last bit unweighted, and 8.9e-16 to
    // 1.3e-15 on the ATT with 1.4e-17 on the standard error when weighted --
    // three orders inside the tolerance, and with identical missing patterns
    // throughout.
    //
    // The delegation sits HERE, below every guard, and that placement is the
    // whole point. dr refuses cells reg does not, and not only through the
    // 0.999 overlap check: it also trims controls at ps >= trim_level, which
    // defaults to 0.995, so a cell at a 0.9968 treated share loses every
    // control and is refused as status 3 while reg estimates it happily
    // (measured: 3 cells refused against 0). Replicating that set in the
    // caller would have been a silent way to start estimating cells csdid
    // currently declines. Reaching this line means every one of those guards
    // has already run and passed, so only the arithmetic is swapped.
    if (cols(x) == 1) return(csdid__reg_rc_fit(y, post, d, x, wraw))

    // The four block regressions and their projections moved below the
    // delegation: none of the guards above reads them, and the intercept-only
    // case never uses them. The guard ORDER is untouched -- the four inverse
    // guards still fire before the mean-weight guard, exactly as before.
    // `wy' and `W' come with them: the weighted outcome feeds only these four
    // regressions, and the score weight feeds only the hessian further down.
    wy = w :* y
    W = ps :* (1 :- ps) :* w
    beta_c_pre = xtwx_inv_c_pre * quadcross(xcp, select(wy, m_c_pre))
    beta_c_post = xtwx_inv_c_post * quadcross(xct, select(wy, m_c_post))
    beta_t_pre = xtwx_inv_t_pre * quadcross(xtp, select(wy, m_t_pre))
    beta_t_post = xtwx_inv_t_post * quadcross(xtt, select(wy, m_t_post))

    out_c_pre = x * beta_c_pre
    out_c_post = x * beta_c_post
    out_c = post :* out_c_post + post0 :* out_c_pre
    out_t_pre = x * beta_t_pre
    out_t_post = x * beta_t_post

    // (y :- out_c) was formed four times and each outcome contrast twice.
    resid_c = y :- out_c
    dout_post = out_t_post :- out_c_post
    dout_pre = out_t_pre :- out_c_pre
    eta_treat_pre = w_treat_pre :* resid_c / mw_treat_pre
    eta_treat_post = w_treat_post :* resid_c / mw_treat_post
    eta_cont_pre = w_cont_pre :* resid_c / mw_cont_pre
    eta_cont_post = w_cont_post :* resid_c / mw_cont_post
    eta_d_post = w_d :* dout_post / mw_d
    eta_dt1_post = w_dt1 :* dout_post / mw_dt1
    eta_d_pre = w_d :* dout_pre / mw_d
    eta_dt0_pre = w_dt0 :* dout_pre / mw_dt0
    att_treat_pre = mean(eta_treat_pre)
    att_treat_post = mean(eta_treat_post)
    att_cont_pre = mean(eta_cont_pre)
    att_cont_post = mean(eta_cont_post)
    att_d_post = mean(eta_d_post)
    att_dt1_post = mean(eta_dt1_post)
    att_d_pre = mean(eta_d_pre)
    att_dt0_pre = mean(eta_dt0_pre)
    att = (att_treat_post - att_treat_pre) - (att_cont_post - att_cont_pre) + (att_d_post - att_dt1_post) - (att_d_pre - att_dt0_pre)

    weights_ols_pre = wc :* post0
    xpx_inv_pre = n * xtwx_inv_c_pre
    ols_res_pre = weights_ols_pre :* (y :- out_c_pre)
    weights_ols_post = wc :* post
    xpx_inv_post = n * xtwx_inv_c_post
    ols_res_post = weights_ols_post :* (y :- out_c_post)
    weights_ols_pre_treat = wd :* post0
    xpx_inv_pre_treat = n * xtwx_inv_t_pre
    ols_res_pre_treat = weights_ols_pre_treat :* (y :- out_t_pre)
    weights_ols_post_treat = wd :* post
    xpx_inv_post_treat = n * xtwx_inv_t_post
    ols_res_post_treat = weights_ols_post_treat :* (y :- out_t_post)

    h = quadcross(x, W, x)
    h = csdid__hessinv_r_parity(h, n)  // F-005: R chol2inv(chol()) after the rcond guard
    if (sum(h :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap

    // PERF: the correction terms below needed nine separate x * gamma products,
    // each O(n*k) with its own n-length allocation. Every gamma is a k-vector
    // built from quantities that are all available here, so they are stacked
    // once and multiplied once. Column j of x * gmat is elementwise equal to
    // x * gmat[., j] -- verified over varied n and k -- and the batched form
    // measured 0.260s -> 0.047s over 400 rounds of nine products on a
    // 9,716-row cell. Each gamma is computed by the same expression as before.
    m1_post = -quadcross(x, w_treat_post) / n / mw_treat_post
    m1_pre = -quadcross(x, w_treat_pre) / n / mw_treat_pre
    m2_pre = quadcross(x, w_cont_pre :* (resid_c :- att_cont_pre)) / n / mw_cont_pre
    m2_post = quadcross(x, w_cont_post :* (resid_c :- att_cont_post)) / n / mw_cont_post
    m3_post = -quadcross(x, w_cont_post) / n / mw_cont_post
    m3_pre = -quadcross(x, w_cont_pre) / n / mw_cont_pre
    mom_post = quadcross(x, (w_d / mw_d - w_dt1 / mw_dt1)) / n
    mom_pre = quadcross(x, (w_d / mw_d - w_dt0 / mw_dt0)) / n
    gamma_ps = h * (m2_post - m2_pre)

    gmat = xpx_inv_post * m1_post,
           xpx_inv_pre * m1_pre,
           gamma_ps,
           xpx_inv_post * m3_post,
           xpx_inv_pre * m3_pre,
           xpx_inv_post_treat * mom_post,
           xpx_inv_post * mom_post,
           xpx_inv_pre_treat * mom_pre,
           xpx_inv_pre * mom_pre
    xgam = x * gmat

    inf_treat_pre = eta_treat_pre :- w_treat_pre * att_treat_pre / mw_treat_pre
    inf_treat_post = eta_treat_post :- w_treat_post * att_treat_post / mw_treat_post
    inf_treat_or_post = ols_res_post :* xgam[., 1]
    inf_treat_or_pre = ols_res_pre :* xgam[., 2]
    inf_cont_pre = eta_cont_pre :- w_cont_pre * att_cont_pre / mw_cont_pre
    inf_cont_post = eta_cont_post :- w_cont_post * att_cont_post / mw_cont_post
    inf_cont_ps = (w :* (d :- ps)) :* xgam[., 3]
    inf_cont_or_post = ols_res_post :* xgam[., 4]
    inf_cont_or_pre = ols_res_pre :* xgam[., 5]
    inf_eff1 = eta_d_post :- w_d * att_d_post / mw_d
    inf_eff2 = eta_dt1_post :- w_dt1 * att_dt1_post / mw_dt1
    inf_eff3 = eta_d_pre :- w_d * att_d_pre / mw_d
    inf_eff4 = eta_dt0_pre :- w_dt0 * att_dt0_pre / mw_dt0
    inf_eff = (inf_eff1 - inf_eff2) - (inf_eff3 - inf_eff4)
    inf_or_post = ols_res_post_treat :* xgam[., 6] :- ols_res_post :* xgam[., 7]
    inf_or_pre = ols_res_pre_treat :* xgam[., 8] :- ols_res_pre :* xgam[., 9]
    inf_treat_or = inf_treat_or_post + inf_treat_or_pre
    inf_cont_or = inf_cont_or_post + inf_cont_or_pre
    inf_or = inf_or_post - inf_or_pre
    inf_treat = inf_treat_post - inf_treat_pre + inf_treat_or
    inf_cont = inf_cont_post - inf_cont_pre + inf_cont_ps + inf_cont_or
    inf = (inf_treat - inf_cont) + inf_eff + inf_or

    return(att \ inf \ 0)
}


// ===========================================================================
// SECTION 8 -- THE PRE-ESTIMATION SCAN
//
// One read of the data producing everything the driver needs before the
// first estimator runs -- sizes, level lists, sample counts, the bal(full)
// verdict and the panel-shape flags. The routine's own header lists them.
// ===========================================================================

// ---------------------------------------------------------------------------
// One-pass pre-estimation scan. Reads time, gvar and (when panel) id and the
// cluster variable once, and returns everything the driver needs to size the
// problem, announce the sample and settle bal(full). Pure bookkeeping: every
// output feeds a guard, a message or a local; nothing here touches estimate
// arithmetic.
//
// Everything is a sort plus a run-boundary scan. A level list is `sort(v, 1)'
// followed by one vectorized comparison of each element with its predecessor:
// the positions where they differ are the run starts, the values there are the
// ascending distinct levels, and the gaps between consecutive run starts are
// the per-level row counts. No hashing, no histogram, no per-level pass, and
// the memory is bounded by the data rather than by the value range, so a
// pathological axis costs a sort and nothing else.
//
// What it returns:
//   - time/gvar min-max, ascending level lists, and per-level "gsmall" counts
//     (gsmall = gvar with cohorts beyond max_time + anticipation folded to 0,
//     the never-treated fold the kernel also applies);
//   - the never-treated and already-treated-in-the-first-period counts, the
//     latter in UNITS, on the same reduced grid R counts it on;
//   - the bal(full) balance verdict: units observed in fewer than n_time
//     periods, from a run scan over id in data order (grouped data needs no
//     sort; interleaved data falls back to one order() by id), writing a 0/1
//     drop marker only when incomplete units exist;
//   - the four panel-shape flags (unit count, gvar varying within unit,
//     cluster varying within unit, duplicate (id, time) rows).
// ---------------------------------------------------------------------------
void csdid__prescan(
    string scalar idname,
    string scalar timename,
    string scalar gname,
    string scalar clname,
    string scalar tousename,
    real scalar anticipation,
    real scalar want_balance,
    string scalar dropmarkname,
    string scalar gcountname)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real colvector tv, gv, idv, clv, rowsel, runlen, runstart, runheads, gsmall
    real colvector tlev, glev, gcnt, ord, badunit, okrow, csum
    real colvector sid, stime, sg, scl, same, ordf, d_id, within, fpsel
    real scalar n, i, r0, nrun, tmin, tmax, gmin, gmax, nt, cutoff
    real scalar nt_bal, unit_bal, bal_units, bal_obs
    real scalar never_ct, firstper_ct, firstper_units, n_units, inc_units, inc_obs, grouped
    real scalar hascl, sorted_it, sh_nunit, sh_gvary, sh_cvary, sh_dup
    string scalar tlist, glist

    csdid__engine_ensure()

    rowsel = csdid__selidx(st_data(., tousename) :!= 0)
    n = rows(rowsel)
    tv = st_data(., timename)[rowsel]
    gv = st_data(., gname)[rowsel]
    hascl = (clname != "")
    idv = J(0, 1, .)
    clv = J(0, 1, .)
    if (idname != "") {
        idv = st_data(., idname)[rowsel]
        if (hascl) clv = st_data(., clname)[rowsel]
    }

    tmin = min(tv); tmax = max(tv)
    gmin = min(gv); gmax = max(gv)

    // ---- time levels (ascending) via one sort + vectorized run bounds ----
    ord = sort(tv, 1)
    if (n > 1) runstart = csdid__selidx((1 :: n) :== 1 :| (ord :!= (ord[1] \ ord[|1 \ n - 1|])))
    else runstart = J(1, 1, 1)
    tlev = ord[runstart]
    nt = rows(tlev)
    tlist = ""
    for (i = 1; i <= nt; i++) tlist = tlist + (i > 1 ? " " : "") + strofreal(tlev[i], "%21.0g")

    // ---- gsmall levels and per-level row counts ----
    cutoff = tmax + anticipation
    gsmall = gv :* (gv :<= cutoff)          // cohorts beyond the horizon fold to 0
    ord = sort(gsmall, 1)
    if (n > 1) runstart = csdid__selidx((1 :: n) :== 1 :| (ord :!= (ord[1] \ ord[|1 \ n - 1|])))
    else runstart = J(1, 1, 1)
    glev = ord[runstart]
    if (rows(runstart) > 1) gcnt = (runstart[|2 \ rows(runstart)|] \ (n + 1)) :- runstart
    else gcnt = J(1, 1, n)
    // keep the treated levels only; the zero bucket becomes never_ct
    // selectindex on a 1x1 input returns a 1x0 ROWVECTOR, so an emptiness
    // guard on rows() passes and the subscript aborts with 3301 - length()
    // is orientation-proof (caught by the single-period refusal fixture)
    ord = csdid__selidx(glev :> 0)
    if (length(ord) > 0) {
        glev = glev[ord]
        gcnt = gcnt[ord]
    }
    else {
        glev = J(0, 1, .)
        gcnt = J(0, 1, .)
    }
    never_ct = n - sum(gcnt)
    firstper_ct = 0
    for (i = 1; i <= rows(glev); i++) {
        if (glev[i] <= tmin + anticipation) firstper_ct = firstper_ct + gcnt[i]
    }
    // The announced count is UNITS, not rows: R reports
    // length(unique(data[treated_first_period, idname])) on a panel and the
    // row count on repeated cross sections (pre_process_did.R:297), and the
    // row count is n_periods times too large to put in front of the word
    // "unit". It is also taken on the data R's period filter has already
    // reduced (:263/:270 run before :297), so a unit whose every row lies at
    // or beyond the no-never-treated cutoff is not in R's count; the same
    // cutoff the balance verdict below applies is applied here. Computed only
    // when such a cohort exists, so an ordinary run pays nothing for it.
    firstper_units = 0
    if (firstper_ct > 0) {
        fpsel = (gsmall :<= tmin + anticipation) :& (gsmall :> 0)
        if (never_ct == 0 & rows(glev) > 0) fpsel = fpsel :& (tv :< (max(glev) - anticipation))
        ord = csdid__selidx(fpsel)
        if (length(ord) > 0) {
            if (idname != "") firstper_units = rows(uniqrows(idv[ord]))
            else firstper_units = length(ord)
        }
    }
    // the counts matrix is (value, rows) per distinct group value in
    // ascending order, with never-treated (0) first when present
    if (never_ct > 0) st_matrix(gcountname, (0, never_ct \ (glev, gcnt)))
    else st_matrix(gcountname, (glev, gcnt))

    st_numscalar("__csdid_ps_tmin", tmin)
    st_numscalar("__csdid_ps_tmax", tmax)
    st_numscalar("__csdid_ps_gmin", gmin)
    st_numscalar("__csdid_ps_gmax", gmax)
    st_numscalar("__csdid_ps_never", never_ct)
    st_numscalar("__csdid_ps_firstunits", firstper_units)
    st_local("__csdid_ps_tlevels", tlist)
    glist = ""
    for (i = 1; i <= rows(glev); i++) glist = glist + (i > 1 ? " " : "") + strofreal(glev[i], "%21.0g")
    st_local("__csdid_ps_glevels", glist)

    // ---- balance verdict ----
    // R coerces the balanced panel AFTER the no-never-treated period filter,
    // not before: pre_process_did.R drops the periods at or beyond
    // latest_g - anticipation (:263/:270) and recomputes tlist before
    // the keep_bal count-and-filter at :437-446, whose denominator is that REDUCED
    // grid. Completeness is therefore judged on the periods the estimator will
    // actually use; a unit missing only a period the kernel is about to delete
    // stays in the sample. The fold to never-treated and the cutoff below are
    // the same ones csdid_basic_attgt applies to `use'.
    nt_bal = nt
    okrow = J(0, 1, .)
    if (want_balance & never_ct == 0 & rows(glev) > 0) {
        okrow = (tv :< (max(glev) - anticipation))
        nt_bal = sum(tlev :< (max(glev) - anticipation))
    }
    // the grid the balance test used, which is what the drop message must name
    st_numscalar("__csdid_ps_baltime", nt_bal)
    n_units = .
    inc_units = 0
    inc_obs = 0
    // R counts the balance drop over the SETTLED grid: uid/n.old are taken
    // from the data the period filter has already reduced
    // (pre_process_did.R:437-446 runs after the :263/:270 filter), so a unit
    // whose every row lies at or beyond the cutoff is not a balance drop for
    // R -- it is not in uid at all, and R issues no warning for it. csdid
    // still marks it, because dropping it from `touse' cannot change an
    // estimate the kernel's own cutoff already excludes it from; only the
    // announced count is R's.
    bal_units = 0
    bal_obs = 0
    if (want_balance & idname != "" & n > 0) {
        // runs in data order (n == 1 and single-run panels need their own
        // ranges: a [|2 \ 1|] subscript is an error, not an empty vector)
        if (n == 1) runstart = 1
        else runstart = csdid__selidx((1 :: n) :== 1 :| (idv :!= (idv[1] \ idv[|1 \ n - 1|])))
        nrun = rows(runstart)
        if (nrun > 1) runlen = (runstart[|2 \ nrun|] \ (n + 1)) :- runstart
        else runlen = J(1, 1, n)
        runheads = idv[runstart]
        grouped = 1
        if (nrun > 1) {
            ord = sort(runheads, 1)
            for (i = 2; i <= nrun; i++) {
                if (ord[i] == ord[i - 1]) {
                    grouped = 0
                    break
                }
            }
        }
        if (grouped) {
            n_units = nrun
            // Whole units are dropped, as in R: the drop mark covers every row
            // of the unit, including the periods the cutoff already excluded
            // from the completeness count.
            if (nt_bal == nt) badunit = csdid__selidx(runlen :< nt)
            else {
                csum = runningsum(okrow)
                badunit = csdid__selidx((csum[runstart :+ runlen :- 1] :- csum[runstart] :+ okrow[runstart]) :< nt_bal)
            }
            inc_units = rows(badunit)
            if (inc_units > 0) {
                for (i = 1; i <= inc_units; i++) {
                    r0 = badunit[i]
                    inc_obs = inc_obs + runlen[r0]
                    if (nt_bal == nt) unit_bal = runlen[r0]
                    else unit_bal = csum[runstart[r0] + runlen[r0] - 1] - csum[runstart[r0]] + okrow[runstart[r0]]
                    if (unit_bal > 0) {
                        bal_units = bal_units + 1
                        bal_obs = bal_obs + runlen[r0]
                    }
                    st_store(rowsel[|runstart[r0] \ runstart[r0] + runlen[r0] - 1|], dropmarkname, J(runlen[r0], 1, 1))
                }
            }
        }
        else {
            // interleaved panel: fall back to one sort by id. The row number
            // is the second key for the same reason as in
            // csdid__cluster_layout -- Mata's order() is not stable across
            // ties, and ids repeat once per period.
            ord = order((idv, (1::n)), (1, 2))
            // One prefix sum for the whole panel, as the grouped branch above
            // already does. The per-unit `sum(okrow[ord[|r0 \ i|]])' this
            // replaces allocated a range subscript for every unit; okrow is
            // 0/1, so the difference of two partial sums is the same integer
            // count, exactly.
            if (nt_bal != nt) csum = runningsum(okrow[ord])
            i = 1
            n_units = 0
            while (i <= n) {
                r0 = i
                while (i < n) {
                    if (idv[ord[i + 1]] != idv[ord[r0]]) break
                    i = i + 1
                }
                n_units = n_units + 1
                if (nt_bal == nt) unit_bal = i - r0 + 1
                else unit_bal = csum[i] - csum[r0] + okrow[ord[r0]]
                if (unit_bal < nt_bal) {
                    inc_units = inc_units + 1
                    inc_obs = inc_obs + (i - r0 + 1)
                    if (unit_bal > 0) {
                        bal_units = bal_units + 1
                        bal_obs = bal_obs + (i - r0 + 1)
                    }
                    st_store(rowsel[ord[|r0 \ i|]], dropmarkname, J(i - r0 + 1, 1, 1))
                }
                i = i + 1
            }
        }
    }
    st_numscalar("__csdid_ps_nunits", n_units)
    st_numscalar("__csdid_ps_incunits", inc_units)
    st_numscalar("__csdid_ps_incobs", inc_obs)
    st_numscalar("__csdid_ps_balunits", bal_units)
    st_numscalar("__csdid_ps_balobs", bal_obs)

    // ---- panel shape flags -------------------------------------------
    // The four shape refusals the ado raises before the kernel runs: unit
    // count, gvar varying within a unit, cluster varying within a unit, and
    // duplicate (id, time) rows. They are computed HERE, from the id, time and
    // gvar this routine already holds, rather than in a pass of their own -- a
    // separate pass re-reading the same three variables measured 0.19s of a
    // 0.79s panel run at 600,000 rows.
    //
    // What sample they describe: touse, as it stands on the call that computes
    // them. The driver calls this routine again on the reduced sample whenever
    // bal(full) dropped a unit, and keeps the three VIOLATION flags from the
    // FIRST call -- the pre-balance sample, which is the one R checks them on
    // -- while the unit count comes from the last call, which describes the
    // sample that will be estimated. The three flags are then widened once
    // more, by csdid_shapescan below, onto the sample as it stood before the
    // missingness screen; what the driver finally refuses on is the OR of the
    // two, and that routine's header is where the per-check screens live.
    // They do NOT describe the sample the
    // kernel finally estimates on, which is smaller again:
    // csdid__settle_sample() drops the periods from
    // the last cohort's onward, less anticipation, when no never-treated
    // group exists, and the units treated at or before the first period plus
    // anticipation, and neither reduction is modelled here. A duplicate
    // (id, time) row, or a cluster that varies only inside rows one of those
    // reductions would have removed, therefore refuses a design the kernel
    // could have estimated.
    //
    // That is R's placement and not a divergence from it. did 2.5.1 runs the
    // same three checks -- gname irreversibility, duplicate (id, time), and
    // time-varying clustervars -- in validate_args() on the RAW data
    // (pre_process_did2.R:72-86 and 96-109), and validate_args() is called
    // at pre_process_did2.R:736, before did_standardization() at 763, which
    // is where the no-comparison-group period filter happens (247-264). So
    // for the two reductions this placement is about -- the period filter and
    // the first-period-treated drop -- csdid refuses where R refuses.
    //
    // bal(full) is the third reduction, and it happens between the two calls
    // rather than after both, which is why the driver keeps the first call's
    // violation flags: a duplicate (id, time), a time-varying clustervar or a
    // gname reversal confined to a unit that bal(full) drops is refused, as R
    // refuses it. Verified against did 2.5.1 on 12 units x 3 periods with
    // unit 1 present only at t=1 -- duplicated there, its cohort reversed, or
    // its cluster changed -- all three stop in R and all three now stop here.
    sh_nunit = .
    sh_gvary = 0
    sh_cvary = 0
    sh_dup = 0
    if (idname != "" & n > 0) {
        if (n == 1) {
            sh_nunit = 1
        }
        else {
            // Real panels arrive in (id, time) order, and checking that is one
            // pass with no allocation; only an out-of-order dataset pays for a
            // sort. The row number is the final key so the permutation is
            // unique -- Mata's order() is not stable across ties.
            // Vectorized: an interpreted scan of 600,000 rows costs more
            // than the pass it is trying to avoid.
            d_id = idv[2::n] :- idv[1::(n - 1)]
            if (min(d_id) < 0) {
                sorted_it = 0
            }
            else {
                within = csdid__selidx(d_id :== 0)
                if (rows(within) == 0) {
                    sorted_it = 1
                }
                else {
                    sorted_it = (min(tv[within :+ 1] :- tv[within]) >= 0)
                }
            }
            if (sorted_it) {
                sid = idv
                stime = tv
                sg = gv
                if (hascl) scl = clv
            }
            else {
                ordf = order((idv, tv, (1::n)), (1, 2, 3))
                sid = idv[ordf]
                stime = tv[ordf]
                sg = gv[ordf]
                if (hascl) scl = clv[ordf]
            }
            same = (sid[2::n] :== sid[1::(n - 1)])
            sh_nunit = 1 + sum(!same)
            sh_gvary = any(same :& (sg[2::n] :!= sg[1::(n - 1)]))
            if (hascl) sh_cvary = any(same :& (scl[2::n] :!= scl[1::(n - 1)]))
            sh_dup = any(same :& (stime[2::n] :== stime[1::(n - 1)]))
        }
    }
    st_numscalar("__csdid_ps_shape_nunit", sh_nunit)
    st_numscalar("__csdid_ps_shape_gvary", sh_gvary)
    st_numscalar("__csdid_ps_shape_cvary", sh_cvary)
    st_numscalar("__csdid_ps_shape_dup", sh_dup)

    // The same measurements, on the object. The named Stata scalars above are
    // the ado's contract and stay exactly as they are -- csdid.ado reads and
    // then drops them, and test-mutation-safety asserts that it leaves none
    // behind. These are the engine's own copy, so a routine inside this file
    // does not have to go back out through Stata to ask what the scan found.
    // The driver calls the scan twice when bal(full) dropped a unit, so what
    // stands here is the SECOND call's answer: the sample that is estimated.
    // That is why the three shape VIOLATIONS have no copy on the object. The
    // ado decides those on the FIRST call, through the Stata scalars above,
    // because the sample before balancing is the one they are judged on -- so
    // a member holding the other answer would be a trap and not a shortcut.
    CSDID_ENGINE.ps_tmin        = tmin
    CSDID_ENGINE.ps_tmax        = tmax
    CSDID_ENGINE.ps_gmin        = gmin
    CSDID_ENGINE.ps_gmax        = gmax
    CSDID_ENGINE.ps_never       = never_ct
    CSDID_ENGINE.ps_firstunits  = firstper_units
    CSDID_ENGINE.ps_baltime     = nt_bal
    CSDID_ENGINE.ps_nunits      = n_units
    CSDID_ENGINE.ps_incunits    = inc_units
    CSDID_ENGINE.ps_incobs      = inc_obs
    CSDID_ENGINE.ps_balunits    = bal_units
    CSDID_ENGINE.ps_balobs      = bal_obs
    CSDID_ENGINE.ps_shape_nunit = sh_nunit
    CSDID_ENGINE.ps_tlevels     = tlist
    CSDID_ENGINE.ps_glevels     = glist
    CSDID_ENGINE.ps_gcounts     = st_matrix(gcountname)
}

// ---------------------------------------------------------------------------
// csdid_shapescan: the same three panel-shape violations csdid__prescan
// measures, judged on the sample BEFORE the missingness screen.
//
// The scan above reads `touse', which has already lost the rows with a
// missing outcome, covariate or weight. R runs validate_args() on the data as
// the user handed it over (pre_process_did2.R:72-109, called at :736) and
// removes incomplete rows only afterwards, in did_standardization() at :763.
// A violation carried by a row that only csdid has dropped is therefore
// refused by R and used to be estimated here -- measured on twelve designs
// against did 2.5.1, among them a duplicated (id, time) whose second copy has
// a missing outcome, a missing weight, a missing covariate or a missing gvar,
// and a cohort reversal carried by the row with the missing covariate.
//
// The three screens are R's own and they are NOT the same screen, which is
// the whole reason this cannot be one flag over one sample:
//
//   gvar reversal        rows whose id AND gvar are both present
//                        (pre_process_did2.R:74-76). A reversal carried by a
//                        row missing either one is not a reversal for R.
//   duplicate (id, time) rows whose id AND time are both present (:81-83).
//                        A missing gvar, outcome, covariate or weight on the
//                        duplicate does not excuse it; a missing id or time
//                        does.
//   time-varying cluster every row, with no screen at all (:104-106). R asks
//                        length(unique(col)) == 1 by id, so a cluster present
//                        in one period and missing in another is two distinct
//                        values and refuses, while a cluster missing in EVERY
//                        period of a unit is one value and does not. Rows
//                        with a missing id form a single group, the way
//                        data.table groups NA -- verified, it refuses when
//                        their clusters disagree.
//
// Every branch above is a measured witness, not a reading of the R source.
//
// Only the three VIOLATION flags are written. Everything else the prescan
// reports describes the estimation sample and must keep coming from there.
// ---------------------------------------------------------------------------
void csdid_shapescan(
    string scalar idname,
    string scalar timename,
    string scalar gname,
    string scalar clname,
    string scalar tousename)
{
    real colvector rowsel, idv, tv, gv, clv, sel, ord, sid, sval, same
    real scalar n, m, sh_gvary, sh_cvary, sh_dup

    sh_gvary = 0
    sh_cvary = 0
    sh_dup = 0
    rowsel = csdid__selidx(st_data(., tousename) :!= 0)
    n = rows(rowsel)
    if (idname != "" & n > 1) {
        idv = st_data(., idname)[rowsel]

        // -- gvar reversal, over the rows carrying both an id and a gvar
        gv = st_data(., gname)[rowsel]
        sel = csdid__selidx((idv :< .) :& (gv :< .))
        m = length(sel)
        if (m > 1) {
            // the row number is the final sort key for the same reason as in
            // csdid__cluster_layout: Mata's order() is not stable across ties,
            // and an id repeats once per period
            ord = sel[order((idv[sel], (1 :: m)), (1, 2))]
            sid = idv[ord]
            sval = gv[ord]
            same = (sid[2 :: m] :== sid[1 :: (m - 1)])
            sh_gvary = any(same :& (sval[2 :: m] :!= sval[1 :: (m - 1)]))
        }

        // -- duplicate (id, time), over the rows carrying both an id and a time
        tv = st_data(., timename)[rowsel]
        sel = csdid__selidx((idv :< .) :& (tv :< .))
        m = length(sel)
        if (m > 1) {
            ord = sel[order((idv[sel], tv[sel], (1 :: m)), (1, 2, 3))]
            sid = idv[ord]
            sval = tv[ord]
            same = (sid[2 :: m] :== sid[1 :: (m - 1)])
            sh_dup = any(same :& (sval[2 :: m] :== sval[1 :: (m - 1)]))
        }

        // -- time-varying cluster, over every row. A missing id groups with
        // the other missing ids because Mata's `.' compares equal to `.', and
        // a missing cluster differs from a present one for the same reason.
        if (clname != "") {
            clv = st_data(., clname)[rowsel]
            ord = order((idv, (1 :: n)), (1, 2))
            sid = idv[ord]
            sval = clv[ord]
            same = (sid[2 :: n] :== sid[1 :: (n - 1)])
            sh_cvary = any(same :& (sval[2 :: n] :!= sval[1 :: (n - 1)]))
        }
    }
    st_numscalar("__csdid_sh_gvary", sh_gvary)
    st_numscalar("__csdid_sh_cvary", sh_cvary)
    st_numscalar("__csdid_sh_dup", sh_dup)
}
// ===========================================================================
// SECTION 9 -- ATT(g,t) CELL HELPERS
//
// The five routines the engine calls inside its (g,t) loop: a bucket slice,
// the emitter for cells that never reach an estimator, the
// repeated-cross-section influence-function accumulator, the choice between
// the repeated-cross-section estimators, and the writer that puts a finished
// cell into the table. They are separate functions so that the engine's four
// cell routes cannot come to disagree about what a refused cell looks like,
// which estimator a method() name means, or how a cell is written.
//
// None of the five is called per ROW. That is the line that matters, because
// Mata passes matrices by address (measured ~0.13us per call regardless of
// size), so cell-granularity helpers are free and row-granularity ones are
// not. Two of them are entered more than once for a cell, and both times are
// meant. csdid__rc_slice runs 2 + 2 x (qualifying control cohorts) times per
// cell on the general route. csdid__emit_degenerate_cell runs TWICE for every
// cell that reaches the general route's assembled-rows branch -- once on the
// counts the four row selections give, and again on the counts left after the
// rows are assembled and any unit missing its weight period has been dropped
// -- so a run of C cells on that branch, F of which the first call finishes,
// enters it 2C - F times (counted: 32 cells, 4 finished, 60 entries). The
// other three run at most once per cell.
// ===========================================================================


real colvector csdid__rc_slice(
    real colvector srows,
    real matrix lut,
    real scalar nbt,
    real scalar bg,
    real scalar tid)
{
    real scalar key, st, ct

    if (bg >= . | tid >= .) return(J(0, 1, .))
    key = (bg - 1) * nbt + tid
    st = lut[key, 1]
    ct = lut[key, 2]
    if (ct <= 0) return(J(0, 1, .))
    return(srows[|st \ st + ct - 1|])
}

// ---------------------------------------------------------------------------
// The two ways a (g,t) cell is finished before any estimator touches it, in
// the order R runs them, shared by every route csdid_basic_attgt takes to a
// cell (panel, fast panel, unbalanced panel, repeated cross-section).
//
// The normalisation row comes FIRST: under a universal base period
// ATT(g, g-1) is zero by construction, before any data is read, so it stays
// zero with a structurally zero influence-function column even when the base
// period has no observations for this cohort. Judging emptiness first would
// turn that structural zero into a missing.
//
// A pair-empty cell is still a cell. R appends the NA row and an all-NA
// influence column for every cell it declines (compute.att_gt.R:679-687,
// :840-849) and never drops one, so an emitted cell advances `cell_ix' exactly
// as an estimated one does; skipping the iteration instead would silently
// apply dropmissing to that cell.
//
// Returns 1 when a row has been written and the caller must move on to the
// next cell, 0 when the cell is fit to estimate.
real scalar csdid__emit_degenerate_cell(
    real scalar universal_base,
    real scalar g,
    real scalar t,
    real scalar pret,
    real scalar nt1,
    real scalar nt0,
    real scalar nc1,
    real scalar nc0,
    real scalar n_units,
    real matrix out,
    real matrix ifmat_t,
    real scalar cell_ix)
{
    if (universal_base) {
        cell_ix = cell_ix + 1
        out[cell_ix, .] = (g, t, t - g, 0, ., nt1, nt0, nc1, nc0, pret)
        ifmat_t[cell_ix, .] = J(1, n_units, 0)
        return(1)
    }
    if (min((nt1, nt0, nc1, nc0)) <= 0) {
        csdid__empty_cell_warning(nt1, nt0, nc1, nc0, g, t, pret)
        cell_ix = cell_ix + 1
        out[cell_ix, .] = (g, t, t - g, ., ., nt1, nt0, nc1, nc0, pret)
        ifmat_t[cell_ix, .] = J(1, n_units, .)
        return(1)
    }
    return(0)
}

// ---------------------------------------------------------------------------
// The per-unit influence function of a repeated-cross-section cell, from the
// per-ROW influence function the 2x2 estimator returns. Both repeated
// cross-section routes -- the bucket-sliced one and the general one -- reach
// this with the same objects and the same contract, and the two routes are
// required to produce bit-identical columns, so they read the same code.
//
// A refused cell (att missing) gets an all-missing column, which is what
// carries the refusal into every downstream aggregation.
void csdid__rc_accumulate_unit_if(
    real scalar att,
    real colvector fit,
    real scalar n1,
    real scalar n_units,
    real colvector valid_rows,
    real colvector row_unit_index,
    real colvector idlevels,
    real colvector id,
    real scalar sorted_unit_scan,
    real colvector unit_if)
{
    real colvector fit_if, uid_vec, uid_sums
    real matrix uid_fit, uid_info
    real scalar k, r, uid_index, k_uid, uid_unique

    unit_if = J(n_units, 1, 0)
    if (att < .) {
        fit_if = (n_units / n1) * fit[2..(n1 + 1)]
        uid_vec = row_unit_index[valid_rows]
        // `idname != ""' used to sit in front of this, which excluded
        // repeated cross sections -- and RCS is exactly where the vector
        // route is cheapest. The unit run-scan was already ungated from
        // idname for this reason (see the note where sorted_unit_scan is
        // set); its consumer was not, so every RCS cell fell into the scalar
        // loop below: n1 interpreted iterations, each with two subscripted
        // reads, a missing test, a binary-search fallback call and a
        // read-modify-write, for an accumulation that under RCS is a pure
        // permutation (each row is its own unit, so panelsum copies).
        //
        // What actually guarantees the mapping is valid is sorted_unit_scan
        // plus no missings in uid_vec: the first makes uid_vec ascending,
        // which panelsetup requires, and the second makes every row map to a
        // unit. Summation order is unchanged -- panelsum adds within a panel
        // in row order, which is the order the scalar loop used.
        if (sorted_unit_scan & sum(uid_vec :>= .) == 0) {
            // When the cell has AT MOST ONE ROW PER UNIT the whole grouped
            // reduction is a permutation: there is nothing to add up. That is
            // the normal case on a repeated cross section, where every row IS
            // a unit -- and it was paying for an n1 x 2 matrix build, a
            // panelsetup scan, a panelsum over singleton panels and a second
            // gather to recover the unit numbers. Measured at 600,000 RCS
            // units and 40 cells: 0.78s of a 0.87s assembly phase, itself
            // 0.87s of a 3.70s run.
            //
            // uid_vec is ascending here (that is what sorted_unit_scan buys),
            // so "one row per unit" is "strictly increasing", which is one
            // pass and no allocation. Bit-identical either way: panelsum over
            // singleton panels returns the element itself, and the scatter
            // targets the same units.
            k_uid = rows(uid_vec)
            if (k_uid <= 1) {
                uid_unique = 1
            }
            else {
                uid_unique = (min(uid_vec[2::k_uid] :- uid_vec[1::(k_uid - 1)]) > 0)
            }
            if (uid_unique) {
                unit_if[uid_vec] = fit_if
            }
            else {
                uid_fit = uid_vec, fit_if
                uid_info = panelsetup(uid_fit, 1)
                uid_sums = panelsum(uid_fit[., 2], uid_info)
                unit_if[uid_fit[uid_info[., 1], 1]] = uid_sums
            }
        }
        else {
            for (k = 1; k <= n1; k++) {
                r = valid_rows[k]
                uid_index = row_unit_index[r]
                if (uid_index >= .) uid_index = csdid__sorted_index(idlevels, id[r])
                if (uid_index < .) unit_if[uid_index] = unit_if[uid_index] + fit_if[k]
            }
        }
    }
    else {
        unit_if = J(n_units, 1, .)
    }
}
// ---------------------------------------------------------------------------
// The 2x2 repeated-cross-section estimator, chosen by method(). Three cell
// routes reach it with the same six objects and the same contract -- the panel
// route under fix_weights(varying), the unbalanced-panel route, and the
// repeated-cross-section route -- so the choice is written once and they
// cannot come to disagree about which estimator a method() name means.
//
// The fit is an output argument, not a return value: it is two rows per
// observation in the cell, and returning it would copy that once more per cell
// for nothing. Called once per cell, never per row.
void csdid__rc_fit_dispatch(
    string scalar method,
    real colvector y_rc,
    real colvector post_rc,
    real colvector d_rc,
    real matrix x_rc,
    real colvector w_rc,
    real scalar trim_level,
    real colvector fit)
{
    if (method == "ipw") {
        fit = csdid__ipw_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc, trim_level)
    }
    else if (method == "dr") {
        fit = csdid__dr_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc, trim_level)
    }
    else {
        fit = csdid__reg_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc)
    }
}

// ---------------------------------------------------------------------------
// One (g,t) cell, written. Every route that finishes a cell ends here -- the
// fast panel closed form and the refusal it raises before fitting anything,
// the panel fit, the unbalanced-panel fit, and the two repeated-cross-section
// routes -- so the row layout and the influence-function orientation are
// stated in one place. csdid__emit_degenerate_cell writes the two kinds of
// cell that never reach an estimator, and writes them the same way.
//
// A refused cell arrives with a missing att, a missing se and an all-missing
// influence column, which is what carries the refusal into every downstream
// aggregation.
void csdid__store_cell(
    real scalar g,
    real scalar t,
    real scalar att,
    real scalar se,
    real scalar nt1,
    real scalar nt0,
    real scalar nc1,
    real scalar nc0,
    real scalar pret,
    real colvector unit_if,
    real matrix out,
    real matrix ifmat_t,
    real scalar cell_ix)
{
    cell_ix = cell_ix + 1
    out[cell_ix, .] = (g, t, t - g, att, se, nt1, nt0, nc1, nc0, pret)
    ifmat_t[cell_ix, .] = unit_if'
}

// ===========================================================================
// SECTION 10 -- THE ATT(g,t) ENGINE
//
// csdid_basic_attgt settles the sample, walks the (g,t) grid, routes each
// cell to one of the kernels above, and returns the ATT table with its
// influence functions. csdid_cluster_attgt recomputes the standard errors
// at the cluster level from those influence functions, and
// csdid_cache_validate is how the ado checks that the Mata cache still
// belongs to the results currently posted.
//
// csdid_basic_attgt itself is an orchestrator over named phases, in the order
// it runs them: settle the sample, build the unit layout, weight the units
// and compute the cohort probabilities, build the repeated-cross-section row
// buckets where they pay, list the (g,t) cells and hand them to one of four
// routes, and store the results. Each phase is one routine below, and the
// phase routines take the engine by reference so the run's options do not
// travel as arguments.
//
// State that is the size of the data -- the outcome and time vectors, the
// unit layout, the cell table -- stays a local of csdid_basic_attgt and
// travels by argument. Mata passes matrices by address, so this costs
// nothing, and nothing about one run's data then outlives the run on the
// engine object.
// ===========================================================================


// ---------------------------------------------------------------------------
// SEAM 1 -- the estimation sample.
//
// Reads the variables the run was given, clears from `use' every row the
// command will not look at, and republishes the period and cohort lists that
// every later phase indexes by. Nothing below this routine clears another bit
// of `use', which is what lets the layout build treat it as settled.
//
// The six options live on the engine (csdid_basic_attgt records them the
// moment they arrive), so only the variable names travel as arguments.
// ---------------------------------------------------------------------------
void csdid__settle_sample(
    pointer(class csdid__Engine scalar) scalar eng,
    string scalar yname,
    string scalar tname,
    string scalar gname,
    string scalar idname,
    string scalar xnames,
    string scalar wname,
    string scalar method,
    string scalar tousename,
    string scalar clustername,
    string scalar usemarkname,
    real colvector y,
    real colvector tt,
    real colvector gg,
    real colvector geff,
    real colvector id,
    real colvector ww,
    real colvector cl,
    real colvector use,
    real matrix x,
    real rowvector tlevels,
    real rowvector glevels,
    real scalar has_x,
    real scalar has_w,
    real scalar has_cluster,
    real scalar first_t)
{
    real colvector touse, drop_ids
    real scalar max_t, has_never, latest_g, cutoff_t, exclude_latest_g
    real scalar anticipation
    string scalar notyet

    anticipation = eng->anticipation
    notyet       = eng->notyet

    y = st_data(., yname)
    tt = st_data(., tname)
    gg = st_data(., gname)
    if (idname == "") {
        id = (1::rows(y))
    }
    else {
        id = st_data(., idname)
    }
    has_w = (strlen(strtrim(wname)) > 0)
    if (has_w) {
        ww = st_data(., wname)
    }
    else {
        ww = J(rows(y), 1, 1)
    }
    has_x = (strlen(strtrim(xnames)) > 0)
    if (has_x) {
        x = J(rows(y), 1, 1), st_data(., tokens(xnames))
    }
    else if (method == "reg" & !has_w) {
        x = J(rows(y), 0, .)
    }
    else {
        x = J(rows(y), 1, 1)
    }
    touse = st_data(., tousename)
    has_cluster = (strlen(strtrim(clustername)) > 0)
    if (has_cluster) {
        cl = st_data(., clustername)
    }
    else {
        cl = J(0, 1, .)
    }

    use = touse
    tlevels = uniqrows(select(tt, use :!= 0))'
    max_t = max(tlevels)
    first_t = min(tlevels)
    geff = gg :- ((use :!= 0) :& (gg :> max_t + anticipation)) :* gg
    has_never = (sum((use :!= 0) :& (geff :== 0)) > 0)
    drop_ids = select(geff, (use :!= 0) :& (geff :> 0))
    latest_g = .
    if (rows(drop_ids) > 0) latest_g = max(drop_ids)
    exclude_latest_g = .
    if (!has_never & latest_g < .) {
        cutoff_t = latest_g - anticipation
        // Both sweeps below only ever CLEAR bits, so the `use[r] == 0'
        // guard was redundant and the whole thing is elementwise. These ran
        // as interpreted scalar loops over every row in the dataset, and they
        // fire on every run that has no never-treated group.
        use = use :* (tt :< cutoff_t)
        if (notyet == "") {
            geff = geff :- ((use :!= 0) :& (geff :== latest_g)) :* geff
        }
        else {
            exclude_latest_g = latest_g
        }
    }
    if (idname == "") {
        // Same shape as the two above: clears bits only, so it is elementwise.
        // This one fires on EVERY repeated-cross-section run.
        use = use :* !((geff :> 0) :& (geff :<= first_t + anticipation))
    }
    else {
        // #29(d). This drops units treated at or before the first period. It
        // used to run an interpreted scalar loop over EVERY row, each
        // iteration calling csdid__sorted_index() for a binary search of
        // the drop list -- measured at 1.602s of a 1.996s run on 600,000 rows.
        //
        // The loop's rule is unit-level: it builds the set of qualifying unit
        // ids and then clears every row whose id is in that set. The
        // elementwise clear below is the same rule ONLY because geff cannot
        // vary within a unit on this branch -- `idname != ""' -- and it cannot,
        // because csdid refuses a time-varying gvar() within ivar() outright
        // ("gvar() must be time-invariant within ivar(); treatment timing must
        // be irreversible", error 459). Given that, a unit either qualifies on
        // all of its rows or on none, and per-row and per-unit clearing
        // coincide.
        //
        // That is a real dependency on a guard several hundred lines away, so
        // it is pinned rather than assumed: test-f068 asserts the refusal
        // still fires, and asserts this branch's output against the unit-level
        // reduction computed independently. If the refusal is ever relaxed,
        // that test fails and this line has to become the grouped form again.
        use = use :* !((use :!= 0) :& (geff :> 0) :& (geff :<= first_t + anticipation))
    }

    // The estimation sample, settled. `use' started as touse and has since had
    // cleared from it every row this command will not look at: the periods the
    // no-never-treated fallback cuts away, and the units treated at or before
    // the first usable period. Nothing below clears another bit.
    //
    // The ado layer used to report e(N) and mark e(sample) from touse, i.e.
    // from BEFORE these two drops, while e(N_units) came from the kernel and
    // reflected them -- so a run that dropped first-period-treated units
    // reported 6,300 observations and 583 units of a 9-period panel, which
    // cannot both be true. Worse, csdid tells users in print that
    // `summarize ... if e(sample)' describes exactly the observations the
    // estimation used, and with those units present it did not.
    //
    // R settles the convention the same way: pre_process_did.R removes the
    // first-period-treated rows (l.309) BEFORE it computes its sample size
    // (l.423/442/454/499).
    if (usemarkname != "") st_store(., usemarkname, (use :!= 0))

    tlevels = uniqrows(select(tt, use :!= 0))'
    // first_t above defined the first-period-treated drop and so had to come
    // from the PRE-drop period list; every read below it -- the first_weight
    // scans and fixweights(first) -- means the first period of the ESTIMATION
    // sample, which is R's own convention: pre_process_did.R:309-317 re-derives
    // tlist and first.period after the identical drop, and compute.att_gt.R
    // reads the first-period weight by position in that new tlist. Unchanged
    // whenever the drop leaves the earliest period populated.
    first_t = min(tlevels)
    glevels = uniqrows(select(geff, (use :!= 0) :& (geff :> 0)))'
    if (exclude_latest_g < .) glevels = select(glevels, glevels :< exclude_latest_g)
}

// ---------------------------------------------------------------------------
// SEAM 2 -- the unit layout.
//
// Numbers the units, maps every used row to one of them, and (when ivar() was
// given) fills the wide unit x period map the panel cell routes read: row
// numbers, outcomes, weights and covariates. Three routes reach the same map
// -- a balanced sorted panel that rowshape() can lay out in one pass, a sorted
// but unbalanced one that panelsetup() can, and a scalar scan for everything
// else -- and each carries the same time-invariance refusals, which is why
// they are written next to each other rather than apart.
//
// The map is the phase's product; the driver keeps it as a local and passes it
// on, because it is the size of the data and has no business outliving the
// run.
// ---------------------------------------------------------------------------
void csdid__build_layout(
    string scalar idname,
    real colvector y,
    real colvector tt,
    real colvector gg,
    real colvector geff,
    real colvector id,
    real colvector ww,
    real colvector cl,
    real colvector use,
    real matrix x,
    real rowvector tlevels,
    real scalar first_t,
    real scalar has_x,
    real scalar has_w,
    real scalar has_cluster,
    real colvector idlevels,
    real scalar n_units,
    real scalar kx,
    real matrix row_index,
    real matrix y_panel,
    real matrix w_panel,
    real matrix x_panel,
    real colvector unit_group,
    real colvector unit_first_row,
    real colvector unit_cluster,
    real colvector wsum_vec,
    real colvector wcount_vec,
    real colvector first_weight,
    real colvector row_unit_index,
    real scalar sorted_unit_scan,
    real scalar balanced_panel)
{
    real colvector use_rows, id_use, tt_use, uid_vec, unit_weight_ref, unit_raw_group
    real colvector time_rows, time_uids
    real matrix id_panel, tt_panel, gg_panel, cl_panel, uid_info
    real scalar sorted_balanced_layout, nt, weight_varying, j, k, r, rowpos, xstart, xend

    sorted_unit_scan = 0
    sorted_balanced_layout = 0
    nt = cols(tlevels)
    idlevels = J(0, 1, .)
    n_units = 0
    if (idname != "" & nt > 0) {
        use_rows = select((1::rows(id)), use :!= 0)
        if (rows(use_rows) > 0 & mod(rows(use_rows), nt) == 0) {
            n_units = rows(use_rows) / nt
            id_use = id[use_rows]
            tt_use = tt[use_rows]
            id_panel = rowshape(id_use, n_units)
            tt_panel = rowshape(tt_use, n_units)
            idlevels = id_panel[., 1]
            sorted_balanced_layout = 1
            if (n_units > 1) {
                if (min(idlevels[2..n_units] :> idlevels[1..(n_units - 1)]) == 0) {
                    sorted_balanced_layout = 0
                }
            }
            // r-conformability broadcasts a column against a matrix and a
            // row against its rows, so the J() outer products here built a
            // full n_units x nt copy of the panel purely to line the operands
            // up. Same comparison, same result, without the N-sized temporary
            // -- and there were five of them in this block.
            if (sorted_balanced_layout &
                (sum(id_panel :!= idlevels) > 0 |
                 sum(tt_panel :!= tlevels) > 0)) {
                sorted_balanced_layout = 0
            }
            if (sorted_balanced_layout) sorted_unit_scan = 1
        }
    }
    if (!sorted_balanced_layout) {
        idlevels = uniqrows(select(id, use :!= 0))
        n_units = rows(idlevels)
    }
    // DS-01: a panel whose ivar() resolves to a single unit used to abort with
    // a raw r(3200) conformability error and a Mata traceback (the per-unit
    // vectors collapse to 1x1, and Mata orients a 1x1 as a ROW vector when it
    // is subscripted by a column index, so the time-invariance checks below
    // stopped conforming). No 2x2 comparison can be formed from one unit, so
    // refuse here with the same clean 459 class the other data-shape checks
    // use, before any of those checks can misfire.
    if (idname != "" & n_units == 1) {
        errprintf("ivar() identifies only one unit in the estimation sample; csdid needs at least two units (a treated unit and a comparison unit) to form a 2x2 comparison. Check that ivar() names the panel identifier and is not constant.\n")
        _error(459)
    }
    kx = (has_x ? cols(x) : 1)
    row_index = J(0, 0, .)
    y_panel = J(0, 0, .)
    w_panel = J(0, 0, .)
    x_panel = J(0, 0, .)
    balanced_panel = (idname != "")
    if (idname != "") {
        row_index = J(n_units, cols(tlevels), .)
        y_panel = J(n_units, cols(tlevels), .)
        if (has_w) w_panel = J(n_units, cols(tlevels), .)
        if (has_x) x_panel = J(n_units, kx * cols(tlevels), .)
    }
    unit_group = J(n_units, 1, .)
    wsum_vec = J(n_units, 1, 0)
    wcount_vec = J(n_units, 1, 0)
    first_weight = J(n_units, 1, .)
    unit_weight_ref = J(n_units, 1, .)
    unit_first_row = J(n_units, 1, .)
    unit_cluster = J(n_units, 1, .)
    unit_raw_group = J(n_units, 1, .)
    row_unit_index = J(rows(id), 1, .)

    weight_varying = 0
    k = 0
    // PERF: this run-length unit scan needs only a sorted id column, not an
    // ivar(). It used to be gated on idname != "", which excluded repeated
    // cross sections -- where id is the synthesized (1::rows(y)) and is
    // therefore strictly increasing, i.e. the single cheapest case there is.
    // RCS consequently fell through to the per-row scalar loop below and paid
    // a binary search per observation. Ungating it lets RCS reach the
    // vectorized panelsetup()/panelsum() branch. Downstream readers of
    // sorted_unit_scan all sit inside branches that already require
    // idname != "", so nothing else changes behaviour.
    if (!sorted_balanced_layout) {
        use_rows = select((1::rows(id)), use :!= 0)
        id_use = id[use_rows]
        sorted_unit_scan = (rows(id_use) > 0)
        if (rows(id_use) > 1 & min(id_use[2..rows(id_use)] :>= id_use[1..(rows(id_use) - 1)]) == 0) {
            sorted_unit_scan = 0
        }
        if (sorted_unit_scan) {
            uid_vec = J(rows(id_use), 1, 1)
            if (rows(id_use) > 1) {
                uid_vec[2..rows(id_use)] = (id_use[2..rows(id_use)] :!= id_use[1..(rows(id_use) - 1)])
            }
            uid_vec = runningsum(uid_vec)
            row_unit_index[use_rows] = uid_vec
            k = uid_vec[rows(uid_vec)]
        }
        if (k != n_units) sorted_unit_scan = 0
        if (!sorted_unit_scan) row_unit_index = J(rows(id), 1, .)
    }

    if (sorted_balanced_layout) {
        row_index = rowshape(use_rows, n_units)
        y_panel = rowshape(y[use_rows], n_units)
        if (has_w) w_panel = rowshape(ww[use_rows], n_units)
        if (has_x) x_panel = rowshape(x[use_rows, .], n_units)
        unit_first_row = row_index[., 1]
        unit_group = geff[unit_first_row]
        unit_raw_group = gg[unit_first_row]
        gg_panel = rowshape(gg[use_rows], n_units)
        if (sum(gg_panel :!= unit_raw_group) > 0) {
            errprintf("gvar() must be time-invariant within ivar(); treatment timing must be irreversible\n")
            _error(459)
        }
        if (has_w) {
            wsum_vec = w_panel * J(nt, 1, 1)
            wcount_vec = J(n_units, 1, nt)
            first_weight = w_panel[., 1]
            unit_weight_ref = first_weight
            if (max(abs(w_panel :- unit_weight_ref)) > 1e-12) {
                weight_varying = 1
            }
        }
        else {
            wsum_vec = J(n_units, 1, nt)
            wcount_vec = J(n_units, 1, nt)
            first_weight = J(n_units, 1, 1)
            unit_weight_ref = first_weight
        }
        row_unit_index[use_rows] = rowshape((1::n_units) * J(1, nt, 1), n_units * nt)
        if (has_cluster) {
            unit_cluster = cl[unit_first_row]
            cl_panel = rowshape(cl[use_rows], n_units)
            if (sum(cl_panel :!= unit_cluster) > 0) {
                errprintf("cluster() must be time-invariant within ivar()\n")
                _error(459)
            }
        }
    }
    else if (sorted_unit_scan) {
        id_use = id[use_rows]
        uid_info = panelsetup(id_use, 1)
        unit_first_row = use_rows[uid_info[., 1]]
        idlevels = id[unit_first_row]
        unit_group = geff[unit_first_row]
        unit_raw_group = gg[unit_first_row]
        uid_vec = row_unit_index[use_rows]
        if (sum(gg[use_rows] :!= unit_raw_group[uid_vec]) > 0) {
            errprintf("gvar() must be time-invariant within ivar(); treatment timing must be irreversible\n")
            _error(459)
        }

        wsum_vec = panelsum(ww[use_rows], uid_info)
        wcount_vec = uid_info[., 2] :- uid_info[., 1] :+ 1
        unit_weight_ref = ww[unit_first_row]
        if (has_w & max(abs(ww[use_rows] :- unit_weight_ref[uid_vec])) > 1e-12) {
            weight_varying = 1
        }
        if (has_cluster) {
            unit_cluster = cl[unit_first_row]
            if (sum(cl[use_rows] :!= unit_cluster[uid_vec]) > 0) {
                errprintf("cluster() must be time-invariant within ivar()\n")
                _error(459)
            }
        }

        // The wide panel layout (row_index/y_panel/w_panel/x_panel) exists only
        // when ivar() was supplied -- those matrices are left 0x0 otherwise --
        // and first_weight is likewise a panel-only concept. The scalar loop
        // this branch replaces guarded all of it behind idname != "", so the
        // repeated-cross-section path must skip it too.
        if (idname != "") {
            for (j = 1; j <= cols(tlevels); j++) {
                time_rows = select(use_rows, tt[use_rows] :== tlevels[j])
                if (rows(time_rows) == 0) continue
                time_uids = row_unit_index[time_rows]
                if (rows(uniqrows(time_uids)) != rows(time_uids)) {
                    errprintf("The value of ivar() must be unique within time(). Some units are observed more than once in a period.\n")
                    _error(459)
                }
                row_index[time_uids, j] = time_rows
                y_panel[time_uids, j] = y[time_rows]
                if (has_w) w_panel[time_uids, j] = ww[time_rows]
                if (has_x) {
                    xstart = (j - 1) * kx + 1
                    xend = j * kx
                    x_panel[time_uids, xstart..xend] = x[time_rows, .]
                }
                if (tlevels[j] == first_t) first_weight[time_uids] = ww[time_rows]
            }
        }
    }
    else {
        for (r = 1; r <= rows(id); r++) {
            if (use[r] == 0) continue
            if (row_unit_index[r] < .) {
                k = row_unit_index[r]
            }
            else {
                k = csdid__sorted_index(idlevels, id[r])
                if (k < .) row_unit_index[r] = k
            }
            if (k >= .) continue
            if (unit_group[k] >= .) {
                unit_group[k] = geff[r]
                unit_raw_group[k] = gg[r]
            }
            else if (gg[r] != unit_raw_group[k]) {
                errprintf("gvar() must be time-invariant within ivar(); treatment timing must be irreversible\n")
                _error(459)
            }
            if (unit_first_row[k] >= .) unit_first_row[k] = r
            if (has_cluster) {
                if (unit_cluster[k] >= .) {
                    unit_cluster[k] = cl[r]
                }
                else if (cl[r] != unit_cluster[k]) {
                    errprintf("cluster() must be time-invariant within ivar()\n")
                    _error(459)
                }
            }
            wsum_vec[k] = wsum_vec[k] + ww[r]
            wcount_vec[k] = wcount_vec[k] + 1
            if (has_w & idname != "") {
                if (unit_weight_ref[k] >= .) {
                    unit_weight_ref[k] = ww[r]
                }
                else if (abs(ww[r] - unit_weight_ref[k]) > 1e-12) {
                    weight_varying = 1
                }
            }
            if (idname != "") {
                rowpos = csdid__sorted_index(tlevels, tt[r])
                if (rowpos < .) {
                    if (row_index[k, rowpos] < .) {
                        errprintf("The value of ivar() must be unique within time(). Some units are observed more than once in a period.\n")
                        _error(459)
                    }
                    row_index[k, rowpos] = r
                    y_panel[k, rowpos] = y[r]
                    if (has_w) w_panel[k, rowpos] = ww[r]
                    if (has_x) {
                        xstart = (rowpos - 1) * kx + 1
                        xend = rowpos * kx
                        x_panel[k, xstart..xend] = x[r, .]
                    }
                }
                if (tt[r] == first_t) first_weight[k] = ww[r]
            }
        }
    }
    if (has_w & idname != "" & weight_varying) {
        // EUX-008: R's own text ends "Use the 'fix_weights' argument ... See
        // ?att_gt for details.", which points a Stata user at R help syntax and
        // at an R argument. The leading sentences (which tests and the frozen
        // f012 parity fixture key on) are unchanged; only the trailing pointer
        // is restated in the spellings src/help/csdid.sthlp documents.
        // errprintf, not printf: it announces which of two weights the
        // estimate used, so it has to survive `quietly' (channel note at
        // csdid__empty_cell_warning).
        errprintf("Time-varying weights detected. For balanced panel data, the default behavior uses the weight from the earlier of the two time periods in each 2x2 comparison (the base period for post-treatment cells). Use the fix_weights() option to control this behavior; see help csdid.\n")
    }

    // The layout is complete, so `balanced_panel' can stop being the
    // question ivar() asks and become the answer the map gives: a panel is
    // balanced exactly when every unit-period cell of row_index was filled.
    if (idname != "") {
        balanced_panel = (sum(row_index :>= .) == 0)
    }
}

// ---------------------------------------------------------------------------
// SEAM 3 -- unit weights and cohort probabilities.
//
// One weight per unit, the never-treated size guard, the p(g) column every
// aggregation divides by, and the unit_group table the bootstrap draws from.
// They are one phase because they read the same two vectors and because the
// guard has to run against the weights the probabilities will be built from.
// ---------------------------------------------------------------------------
void csdid__group_probs(
    pointer(class csdid__Engine scalar) scalar eng,
    string scalar idname,
    real scalar balanced_panel,
    real scalar n_units,
    real scalar reqsize,
    real rowvector tlevels,
    real rowvector glevels,
    real colvector idlevels,
    real colvector unit_group,
    real colvector wsum_vec,
    real colvector wcount_vec,
    real colvector first_weight,
    real matrix row_index,
    real colvector tt,
    real colvector unit_weight,
    real matrix group_prob_mat,
    real matrix unit_group_mat)
{
    real colvector wpos, unit_p1, p1_present  // F-001/F-022: first-appearance period sweep
    real scalar never_units, i, j, g
    string scalar notyet

    notyet = eng->notyet

    unit_weight = J(n_units, 1, .)
    // PERF: this was a scalar loop over n_units that re-tested two
    // loop-invariant conditions (including a string comparison) on every
    // iteration. The two are exact complements, so exactly one fired per unit
    // and the whole thing vectorizes with element-for-element identical
    // arithmetic -- no summation is reordered. Costly precisely where n_units
    // is largest, i.e. repeated cross sections (one unit per observation).
    if (idname != "" & balanced_panel) {
        unit_weight = first_weight
    }
    else {
        wpos = csdid__selidx(wcount_vec :> 0)
        if (rows(wpos) > 0) unit_weight[wpos] = wsum_vec[wpos] :/ wcount_vec[wpos]
    }
    unit_weight = editmissing(unit_weight, 1)
    // The same refusal the driver raises before it gets here, with the same
    // threshold and the same words, so a design cannot be refused by one of
    // them in one vocabulary and by the other in another.
    //
    // The threshold is R's, and it is now passed in rather than rebuilt here.
    // R uses reqsize <- length(rhs_vars(xformla)) + 5 (pre_process_did.R:540
    // at the 2.5.1 tag), which counts the COVARIATES THE USER NAMED. This
    // routine only ever sees the expanded design, so `kx + 4' -- one plus the
    // columns of x, plus four -- agreed with R on x1 x2 and disagreed with it
    // on any factor-variable term: i.state with fifty levels made the kernel
    // demand fifty-five never-treated units where R and the driver demand six,
    // and the kernel refused designs both of them accept. That is the whole
    // behavior change here.
    //
    // The COUNT stays a unit count while the driver's is R's rows/n_periods.
    // On a balanced panel the two are the same number; on an unbalanced one
    // rows/n_periods is strictly smaller, so the driver refuses everything
    // this guard would refuse and more, and it runs first. This guard is
    // therefore the backstop for a direct kernel call, and it cannot fire on
    // a design the driver let through.
    if (notyet == "") {
        never_units = sum(unit_group :== 0)
        if (never_units > 0 & never_units < reqsize) {
            errprintf("The never-treated group is too small to serve as a reliable comparison group. Try specifying notyet to include not-yet-treated units in the comparison group.\n")
            _error(459)
        }
    }
    group_prob_mat = J(cols(glevels), 3, .)
    for (i = 1; i <= cols(glevels); i++) {
        g = glevels[i]
        group_prob_mat[i, .] = (g, sum(unit_weight :* (unit_group :== g)) / n_units, n_units)
    }
    // Column 4 of the unit/group map is THE PERIOD KEY R DRAWS UNITS IN, and
    // it is cached here, at estimation time, because it is the one part of
    // the draw order that cannot be recovered from the map's own columns
    // later. Two of the three sample shapes need it, and they are the two
    // whose unit order is period-major:
    //
    //   allow_unbalanced (F-001/F-022): each unit's FIRST-APPEARANCE PERIOD,
    //     read off the already-built row_index map in a single descending
    //     column sweep — scanning periods last-to-first leaves the earliest
    //     present period in unit_p1 — so it is O(rows), not the donor's
    //     O(units x rows) per-unit scan. See csdid__boot_order_unbal.
    //
    //   repeated cross section: the observation's OWN period, which is also
    //     its first and only one. The aggregation bootstrap used to re-read
    //     these values from the LIVE dataset through the map's id column
    //     (st_data(unit_group[., 1], timename)) — estimation-time observation
    //     POSITIONS. Any sort, merge or collapse between csdid and
    //     csdid_stats then handed period values to the wrong cached rows, the
    //     multiplier draws landed on different units, and the reported
    //     bootstrap standard error moved. `tt[idlevels]' is bit-for-bit what
    //     that read returned when nothing had moved. See csdid__boot_order_rc.
    //
    // A balanced panel needs no key: its draw order is cohort-major, and a
    // three-column map is how a consumer knows so.
    //
    // The key reaches BOTH storage channels (st_matrix under full storage,
    // eng->unit_group under lean) with no separate augmentation call, and it
    // travels with `estimates store'/`restore' because it travels inside the
    // matrix. That is the whole reason it lives in the map rather than in a
    // member of its own: a key held beside the map can belong to a different
    // run than the map a consumer was handed.
    //
    // WHICH key it is, is decided by the same question the ado asks to set
    // e(panel_mode) and to pass or withhold the bootstrap's time variable --
    // whether ivar() was given -- so producer and consumers cannot disagree.
    if (idname != "" & !balanced_panel) {
        unit_p1 = J(n_units, 1, .)
        for (j = cols(tlevels); j >= 1; j--) {
            p1_present = csdid__selidx(row_index[., j] :< .)
            if (rows(p1_present) > 0) unit_p1[p1_present] = J(rows(p1_present), 1, tlevels[j])
        }
        unit_group_mat = idlevels, unit_group, unit_weight, unit_p1  // F-001/F-022
    }
    else if (idname == "") {
        unit_group_mat = idlevels, unit_group, unit_weight, tt[idlevels]
    }
    else {
        unit_group_mat = idlevels, unit_group, unit_weight
    }
}

// ---------------------------------------------------------------------------
// SEAM 4 -- the repeated-cross-section row buckets.
//
    // One-time (cohort-value, period) row buckets for the repeated-cross-
    // section / allow_unbalanced cell route. The per-cell boolean masks
    // this replaces cost some twenty O(N) vector passes per cell; the
    // buckets cost a handful of passes once, and every cell then assembles
    // exactly the same rows in exactly the same ascending order from a few
    // slice lookups. Same rows, same order, same arithmetic - the change
    // is where the rows come from, never what is computed on them.
    //
    // The layout is cohort-major, period-minor, each bucket's rows in
    // ascending row order. That is what a full sort on (bucket, row) gives,
    // and the nested scan below writes it directly: uniqrows() returns the
    // cohorts ascending, tlevels is already in period order, and
    // selectindex() hands back ascending positions. Sorting for it cost the
    // sort plus two permutations and a panelsetup, and none of the four is
    // needed to know where a bucket starts when the buckets are written in
    // order. Measured 2026-08-15 on a 400,000-row repeated cross section:
    // this phase was 0.212s of a 1.34s run -- 0.103s of it the sort and
    // 0.041s the permutation and panelsetup -- and is 0.060s, of which the
    // nested scan is 0.019s and uniqrows() on the cohort column 0.038s.
// ---------------------------------------------------------------------------
void csdid__rc_buckets(
    real colvector y,
    real colvector tt,
    real colvector geff,
    real colvector use,
    real rowvector tlevels,
    real colvector rc_gcats,
    real colvector rc_sorted_rows,
    real matrix rc_lut,
    real colvector rc_mask,
    real scalar rc_built,
    real scalar rc_nbg,
    real scalar rc_nbt)
{
    real colvector rc_rowsel, rc_geff, rc_tt, rc_gpos, rc_cpos, rc_grows, rc_gtt
    real scalar rc_b, rc_c, rc_n, rc_pos, prof_t0

    prof_t0 = csdid__profile_start()
    rc_rowsel = csdid__selidx(use :!= 0)
    if (rows(rc_rowsel) > 0) {
        // Gathered once, because the scans below read them repeatedly: the
        // cohort column is compared against once per cohort, and each
        // cohort's slice of the period column once per period. Both
        // comparisons used to re-gather from the full-length column on every
        // pass -- fifteen gathers of the whole estimation sample on the
        // 400,000-row design, where two now serve.
        rc_geff = geff[rc_rowsel]
        rc_tt = tt[rc_rowsel]
        rc_gcats = uniqrows(rc_geff)
        rc_nbg = rows(rc_gcats)
        rc_nbt = cols(tlevels)
        rc_sorted_rows = J(rows(rc_rowsel), 1, .)
        rc_lut = J(rc_nbg * rc_nbt, 2, 0)
        rc_pos = 1
        for (rc_b = 1; rc_b <= rc_nbg; rc_b++) {
            rc_gpos = csdid__selidx(rc_geff :== rc_gcats[rc_b])
            if (rows(rc_gpos) == 0) continue
            rc_grows = rc_rowsel[rc_gpos]
            rc_gtt = rc_tt[rc_gpos]
            for (rc_c = 1; rc_c <= rc_nbt; rc_c++) {
                rc_cpos = csdid__selidx(rc_gtt :== tlevels[rc_c])
                rc_n = rows(rc_cpos)
                if (rc_n == 0) continue
                rc_sorted_rows[|rc_pos \ rc_pos + rc_n - 1|] = rc_grows[rc_cpos]
                rc_lut[(rc_b - 1) * rc_nbt + rc_c, 1] = rc_pos
                rc_lut[(rc_b - 1) * rc_nbt + rc_c, 2] = rc_n
                rc_pos = rc_pos + rc_n
            }
        }
        // Every row of the estimation sample lands in exactly one bucket:
        // its cohort is one of the values uniqrows() just returned, and its
        // period is one of tlevels, which is built from these same rows. A
        // row that reached neither would vanish from every cell without a
        // word, so it is refused instead.
        if (rc_pos - 1 != rows(rc_rowsel)) {
            errprintf("csdid could not place %g estimation rows in the cohort-by-period grid; the data may be degenerate\n", rows(rc_rowsel) - rc_pos + 1)
            _error(498)
        }
        rc_built = 1
        rc_mask = J(rows(y), 1, 0)
    }
    csdid__profile_add(2, prof_t0, rows(rc_rowsel))
}

// ---------------------------------------------------------------------------
// SEAM 5 -- the (g,t) cells.
//
// The list of cells, the doubly-robust cache they share, and the four routes
// that estimate them. One route is chosen for the whole run and walks the
// list itself; the routes are ordered below by how much each may assume, the
// closed form first and the general route last.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// The cells this run will produce, in the order it produces them: one row per
// cell, (g, t, pret, control_time). Every route below walks this table, and
// the reference period is chosen here so that the four of them cannot come to
// disagree about which period a cell is differenced against.
//
// A cohort-period pair with no reference period at all is not a cell and is
// not listed: R has nothing to difference against there, and the engine's
// (g,t) table would carry a row for a comparison that was never made.
//
// previous_time() returns the largest observed period STRICTLY below its
// argument, so base_time < time on every cell except the universal-base
// normalisation row, where the reference period IS the cell's own period.
// ---------------------------------------------------------------------------
real matrix csdid__Engine::cell_grid(
    real rowvector glevels,
    real rowvector tlevels)
{
    real matrix cells
    real scalar i, j, n, g, t, pret

    cells = J(cols(glevels) * cols(tlevels), 4, .)
    n = 0
    for (i = 1; i <= cols(glevels); i++) {
        g = glevels[i]
        for (j = 1; j <= cols(tlevels); j++) {
            t = tlevels[j]
            if (t >= g) {
                pret = csdid__previous_time(tlevels, g - anticipation)
            }
            else if (base_period == "universal") {
                pret = csdid__previous_time(tlevels, g - anticipation)
            }
            else {
                pret = csdid__previous_time(tlevels, t)
            }
            if (pret >= .) continue
            n = n + 1
            cells[n, .] = (g, t, pret, max((t, pret)))
        }
    }
    if (n == 0) return(J(0, 4, .))
    return(cells[|1, 1 \ n, 4|])
}

// ---------------------------------------------------------------------------
// The doubly-robust cell cache, emptied. Every run starts with it invalid, so
// a cell can never reuse the propensity fit, trimming or refusal status of a
// cell in a PREVIOUS estimation -- the keys alone would not stop that, since a
// second run of the same design produces the same keys.
//
// It is one routine and not twenty-two lines in the driver because deleting a
// line of it is invisible to any gate that runs one estimation per process,
// and every gate in this repository does.
// ---------------------------------------------------------------------------
void csdid__Engine::dr_cache_reset()
{
    dr_valid = 0
    dr_g = .
    dr_tidx_x = .
    dr_tidx_w = .
    dr_uids = J(0, 1, .)
    dr_control_key = .
    dr_status = .
    dr_n = .
    dr_mw_treat = .
    dr_mw_cont = .
    dr_w = J(0, 1, .)
    dr_ps = J(0, 1, .)
    dr_trim = J(0, 1, .)
    dr_w_treat = J(0, 1, .)
    dr_w_cont = J(0, 1, .)
    dr_weights_ols = J(0, 1, .)
    dr_score_ps = J(0, 1, .)
    dr_xgamma_treat = J(0, 1, .)
    dr_xgamma_cont = J(0, 1, .)
    dr_xtwx_inv = J(0, 0, .)
    dr_xpx_inv = J(0, 0, .)
    dr_h = J(0, 0, .)
}

// ---------------------------------------------------------------------------
// Every (g,t) cell on the fast route: a balanced panel, no weights, no
// covariates, method(reg) or method(dr). The estimate is the plain difference
// in differences of the two period columns, and the influence function is the
// demeaned difference scaled by n_units over the group size -- no fit at all.
// The refusals R applies to dr are applied here in closed form, so the set of
// refused cells is the general route's and only the arithmetic differs.
// ---------------------------------------------------------------------------
void csdid__cells_fast(
    pointer(class csdid__Engine scalar) scalar eng,
    real matrix cells,
    real rowvector tlevels,
    real matrix y_fast,
    real colvector unit_group,
    real colvector uid_seq,
    real scalar n_units,
    string scalar method,
    real scalar has_x,
    real matrix out,
    real matrix ifmat_t,
    real scalar cell_ix)
{
    real scalar ic, g, t, pret, control_time
    real colvector dy_fast, treat_fast, control_fast, treat_uid, control_uid
    real colvector dy_treat, dy_control, fast_d, unit_if
    real scalar tidx_t, tidx_pre, nt1, nt0, nc1, nc0, mt1, mc1, att, se
    real scalar fast_pbar, fast_status, fast_ps, prof_if_t0
    real scalar overlap_cut, knife_edge_band, anticipation, trim_level
    string scalar notyet, base_period

    notyet       = eng->notyet
    base_period  = eng->base_period
    anticipation = eng->anticipation
    trim_level   = eng->trim_level

    // did::overlap_check_fail()'s cut: the treated share at or above
    // which R refuses the cell outright.
    overlap_cut = 0.999
    // ... and the width of the band around it inside which R defers to a
    // real fit instead of answering from the share.
    knife_edge_band = 1e-6

    for (ic = 1; ic <= rows(cells); ic++) {
        g            = cells[ic, 1]
        t            = cells[ic, 2]
        pret         = cells[ic, 3]
        control_time = cells[ic, 4]
        tidx_t = csdid__sorted_index(tlevels, t)
        tidx_pre = csdid__sorted_index(tlevels, pret)
        if (tidx_t >= . | tidx_pre >= .) continue
        dy_fast = y_fast[., tidx_t] :- y_fast[., tidx_pre]
        treat_fast = (unit_group :== g)
        if (notyet != "") {
            control_fast = (unit_group :!= g) :& ((unit_group :== 0) :| (unit_group :> control_time + anticipation))
        }
        else {
            control_fast = (unit_group :== 0)
        }
        treat_uid = select(uid_seq, treat_fast)
        control_uid = select(uid_seq, control_fast)
        nt1 = rows(treat_uid)
        nt0 = nt1
        nc1 = rows(control_uid)
        nc0 = nc1
        if (csdid__emit_degenerate_cell(base_period == "universal" & t == pret,
            g, t, pret, nt1, nt0, nc1, nc0, n_units, out, ifmat_t, cell_ix)) continue
        // The propensity-score guard R runs for dr and ipw but not
        // for reg. Same classifier the general path uses, so the same
        // cells are refused with the same fit_status and the same
        // warning text; with an intercept-only design it is the
        // closed form and costs no fit.
        if (method != "reg") {
            // mean(d) over nt1 ones and nc1 zeros is exactly
            // nt1 / (nt1 + nc1), so outside the knife-edge band this
            // guard needs no vectors at all -- the two J() allocations
            // and the classifier call only happen in the band, where R
            // defers to a real fit and so must csdid.
            fast_pbar = nt1 / (nt1 + nc1)
            if (abs(fast_pbar - overlap_cut) > knife_edge_band) {
                fast_status = (fast_pbar >= overlap_cut)
            }
            else {
                fast_d = J(nt1, 1, 1) \ J(nc1, 1, 0)
                fast_status = csdid__overlap_status(J(nt1 + nc1, 1, 1), fast_d)
            }
            // The second refusal the general path carries and this one
            // did not: DRDID trims controls at ps >= trim_level, so with
            // the constant intercept-only ps the trim is all-or-nothing
            // and pscoretrim() BELOW the treated share empties EVERY
            // control -- mw_cont is exactly 0 and drdid_panel returns
            // 0/0, which R reports as a missing ATT. fast_ps is the same
            // closed form csdid__logit_fit returns for an
            // intercept-only design, so the cell is refused on the same
            // side of the cutoff as the general path, with the same
            // fit_status 3 and the same warning, and still no fit. The
            // >= is csdid__trim_keep's strict tie convention, spelled
            // the other way round: a score exactly at the level refuses,
            // loudly (see the helper's comment for why no rule can match
            // R's float residue at every tie).
            if (fast_status == 0) {
                fast_ps = csdid__invlogit(log(fast_pbar / (1 - fast_pbar)))
                if (fast_ps >= trim_level) fast_status = 3
            }
            if (fast_status != 0) {
                csdid__fit_status_warning(fast_status, method, has_x, g, t)
                csdid__store_cell(g, t, ., ., nt1, nt0, nc1, nc0, pret,
                    J(n_units, 1, .), out, ifmat_t, cell_ix)
                continue
            }
        }
        dy_treat = dy_fast[treat_uid]
        dy_control = dy_fast[control_uid]
        mt1 = mean(dy_treat)
        mc1 = mean(dy_control)
        att = mt1 - mc1
        prof_if_t0 = csdid__profile_start()
        unit_if = J(n_units, 1, 0)
        unit_if[treat_uid] = (n_units / nt1) :* (dy_treat :- mt1)
        unit_if[control_uid] = -(n_units / nc1) :* (dy_control :- mc1)
        // R blanks the SE, not its sum of squares: att_gt l568-570
        // forms se = sqrt(diag(V)/n) and then applies
        // se[se <= sqrt(.Machine$double.eps)*10] <- NA. Testing the
        // sum of squares against the SQUARE of that tolerance makes
        // the threshold n_units times too tight. csdid__se_from_if
        // is that rule, and is what every clustered site already uses.
        se = csdid__se_from_if(unit_if)
        csdid__store_cell(g, t, att, se, nt1, nt0, nc1, nc0, pret,
            unit_if, out, ifmat_t, cell_ix)
        csdid__profile_add(4, prof_if_t0, n_units)
    }
}

// ---------------------------------------------------------------------------
// Every (g,t) cell on the panel route: a unit set, its two period columns, and
// one of the 2x2 panel estimators. This is also where bal(pair) lands.
//
// bal(pair) balances each 2x2 on its own, so it uses the panel
// branch: that branch already selects a per-cell unit set and
// scales the influence function by n_units / n1 with zeros
// elsewhere, so restricting the set further is the whole change.
// balanced_panel itself stays truthful -- weight handling, the
// unbalanced paths and the e(panel_mode) the ado reports all
// read it.
//
// The doubly-robust propensity fit and everything derived from it are cached
// on the engine across consecutive cells that share a cohort, a covariate
// period, a weight period, a comparison group and the same unit set.
// ---------------------------------------------------------------------------
void csdid__cells_panel(
    pointer(class csdid__Engine scalar) scalar eng,
    real matrix cells,
    real rowvector tlevels,
    real scalar first_t,
    real matrix y_panel,
    real matrix w_panel,
    real matrix x_panel,
    real matrix row_index,
    real colvector unit_group,
    real colvector uid_seq,
    real scalar n_units,
    real scalar kx,
    string scalar method,
    real scalar has_x,
    real scalar has_w,
    real scalar pair_mode,
    real matrix out,
    real matrix ifmat_t,
    real scalar cell_ix)
{
    real scalar ic, g, t, pret, control_time
    real colvector treat_fast, control_fast, eligible_vec, pair_obs_ok, valid_uid
    real colvector y1_cell, y0_cell, d_cell, w_cell, w1_cell, w0_cell
    real colvector y_rc, post_rc, d_rc, w_rc, beta_ps_cell, fit, unit_if
    real matrix x_cell, x_rc
    real scalar covt, tidx_t, tidx_pre, tidx_x, tidx_w, row_w_time, n1
    real scalar xstart, xend, nt1, nt0, nc1, nc0, att, se, fit_status
    real scalar dr_control_key, dr_nonconstant, dr_same_set
    real scalar prof_fit_t0, prof_if_t0, overlap_cut
    real scalar anticipation, trim_level
    string scalar notyet, base_period, fix_weights

    notyet       = eng->notyet
    base_period  = eng->base_period
    fix_weights  = eng->fix_weights
    anticipation = eng->anticipation
    trim_level   = eng->trim_level

    overlap_cut = 0.999          // did::overlap_check_fail()

    for (ic = 1; ic <= rows(cells); ic++) {
        g            = cells[ic, 1]
        t            = cells[ic, 2]
        pret         = cells[ic, 3]
        control_time = cells[ic, 4]
        covt = min((pret, t))
        tidx_t = csdid__sorted_index(tlevels, t)
        tidx_pre = csdid__sorted_index(tlevels, pret)
        tidx_x = csdid__sorted_index(tlevels, covt)
        if (fix_weights == "base_period") {
            row_w_time = csdid__previous_time(tlevels, g - anticipation)
        }
        else if (fix_weights == "first_period") {
            row_w_time = first_t
        }
        else {
            row_w_time = covt
        }
        tidx_w = csdid__sorted_index(tlevels, row_w_time)
        if (tidx_t >= . | tidx_pre >= . | tidx_x >= . | tidx_w >= .) continue
        treat_fast = (unit_group :== g)
        if (notyet != "") {
            control_fast = (unit_group :!= g) :& ((unit_group :== 0) :| (unit_group :> control_time + anticipation))
        }
        else {
            control_fast = (unit_group :== 0)
        }
        eligible_vec = treat_fast :| control_fast
        // bal(pair): keep only the units this comparison can actually
        // use -- observed in BOTH of its periods, and wherever the
        // covariates and weights are read from. row_index is missing
        // exactly where a unit-period has no row, which is what makes
        // this a lookup rather than a search.
        if (pair_mode) {
            pair_obs_ok = (row_index[., tidx_t] :< .) :& (row_index[., tidx_pre] :< .)
            if (has_x) pair_obs_ok = pair_obs_ok :& (row_index[., tidx_x] :< .)
            if (has_w) pair_obs_ok = pair_obs_ok :& (row_index[., tidx_w] :< .)
            eligible_vec = eligible_vec :& pair_obs_ok
        }
        n1 = sum(eligible_vec)
        // A pair-empty cell is still a cell. R appends the NA row and
        // an all-NA influence column for every cell it declines
        // (compute.att_gt.R:679-687, :840-849) and never drops one, so
        // n1 == 0 falls through to the shared blank-row emitters below
        // -- universal-base normalisation first, then the empty-cell
        // warning -- instead of skipping the (g,t) iteration, which
        // silently applied dropmissing to that cell.
        valid_uid = select(uid_seq, eligible_vec)
        y1_cell = y_panel[valid_uid, tidx_t]
        y0_cell = y_panel[valid_uid, tidx_pre]
        d_cell = treat_fast[valid_uid]
        if (!has_w) {
            w_cell = J(n1, 1, 1)
            w1_cell = w_cell
            w0_cell = w_cell
        }
        else if (fix_weights == "varying") {
            w_cell = w_panel[valid_uid, tidx_x]
            w1_cell = w_panel[valid_uid, tidx_t]
            w0_cell = w_panel[valid_uid, tidx_pre]
        }
        else {
            w_cell = w_panel[valid_uid, tidx_w]
            w1_cell = w_panel[valid_uid, tidx_t]
            w0_cell = w_panel[valid_uid, tidx_pre]
        }
        if (has_x) {
            xstart = (tidx_x - 1) * kx + 1
            xend = tidx_x * kx
            x_cell = x_panel[valid_uid, xstart..xend]
        }
        else if (method == "ipw") {
            x_cell = J(0, 1, .)
        }
        else {
            x_cell = J(n1, 1, 1)
        }
        nt1 = sum(d_cell :== 1)
        nt0 = nt1
        nc1 = sum(d_cell :== 0)
        nc0 = nc1
        if (csdid__emit_degenerate_cell(base_period == "universal" & t == pret,
            g, t, pret, nt1, nt0, nc1, nc0, n_units, out, ifmat_t, cell_ix)) continue

        prof_fit_t0 = csdid__profile_start()
        if (fix_weights == "varying" & has_w) {
            y_rc = y0_cell \ y1_cell
            post_rc = J(n1, 1, 0) \ J(n1, 1, 1)
            d_rc = d_cell \ d_cell
            w_rc = w0_cell \ w1_cell
            // method(ipw) with no covariates takes no design matrix
            // at all; every other combination takes the stacked one.
            if (method == "ipw" & !has_x) {
                x_rc = J(0, 1, .)
            }
            else {
                x_rc = x_cell \ x_cell
            }
            csdid__rc_fit_dispatch(method, y_rc, post_rc, d_rc, x_rc,
                w_rc, trim_level, fit = J(0, 1, .))
        }
        else {
            if (method == "ipw") {
                fit = csdid__ipw_panel_fit(y1_cell, y0_cell, d_cell, x_cell, w_cell, trim_level)
            }
            else if (method == "dr") {
                if (notyet != "") {
                    dr_control_key = control_time
                }
                else {
                    dr_control_key = 0
                }
                dr_same_set = 0
                if (eng->dr_valid & rows(eng->dr_uids) == n1) {
                    dr_same_set = !any(eng->dr_uids :!= valid_uid)
                }
                // Every cached object below is a function of the
                // cell's UNIT SET, not merely of its size: pair
                // balancing (and any future per-cell restriction) can
                // give two cells the same n1 with different members.
                // The key therefore carries the membership itself --
                // one O(n1) compare per cell, against silently
                // reusing another cell's propensity fit, trimming and
                // refusal status. Measurement never produced such a
                // collision (fast-vs-nofast agreed bitwise on every
                // geometry tried, and the hit branch never fired), so
                // this is a guard against a reachable state rather
                // than a repair of an observed one.
                if (!(eng->dr_valid &
                      eng->dr_g == g &
                      eng->dr_tidx_x == tidx_x &
                      eng->dr_tidx_w == tidx_w &
                      eng->dr_control_key == dr_control_key &
                      eng->dr_n == n1 &
                      dr_same_set)) {
                    eng->dr_valid = 1
                    eng->dr_g = g
                    eng->dr_tidx_x = tidx_x
                    eng->dr_tidx_w = tidx_w
                    eng->dr_control_key = dr_control_key
                    eng->dr_n = n1
                    eng->dr_uids = valid_uid
                    eng->dr_status = 0
                    eng->dr_w = csdid__normalize_weights(w_cell)
                    if (sum(eng->dr_w :>= .) > 0) {
                        eng->dr_status = 3
                    }
                    else {
                        dr_nonconstant = csdid__nonconstant_weights(eng->dr_w)
                        if (dr_nonconstant) {
                            // F-040: the refusal must name WHY the cell
                            // was refused, not only that it was. Every
                            // weighted-branch refusal used to be
                            // reported as an overlap violation, whatever
                            // its cause; csdid__overlap_status() is the
                            // one classifier, so the reported cause is
                            // the cause DRDID::drdid_panel refuses on.
                            eng->dr_status = csdid__overlap_status(x_cell, d_cell)
                        }
                        if (eng->dr_status == 0) {
                            beta_ps_cell = csdid__logit_fit(d_cell, x_cell, eng->dr_w)
                            if (sum(beta_ps_cell :>= .) > 0) {
                                // F-013/F-040: an uncomputable propensity
                                // fit is DRDID::drdid_panel's
                                // singular-design refusal (status 2),
                                // not an overlap violation.
                                eng->dr_status = 2
                            }
                            else {
                                // DRDID caps ps.fit at 1 - 1e-6 before the trim and
                                // every weight (drdid_panel), and this path was the
                                // one fitter without the cap. Defense in depth, not a
                                // reachable number: any cell with a score past the cap
                                // is refused by the 0.999 overlap guard first, in both
                                // engines (measured: a 1 - 3.9e-8 control refuses with
                                // "overlap condition violated" here and in did), so
                                // computed cells carry ps <= 0.999 and the cap is
                                // bit-inert. It exists so this fitter cannot diverge
                                // from DRDID if the guard chain ever changes.
                                eng->dr_ps = csdid__cap_ps_rc(csdid__invlogit(x_cell * beta_ps_cell))
                                if (!dr_nonconstant & max(eng->dr_ps) >= overlap_cut) {
                                    eng->dr_status = 1
                                }
                            }
                        }
                    }
                    if (eng->dr_status == 0) {
                        eng->dr_trim = J(n1, 1, 1)
                        eng->dr_trim = eng->dr_trim :* ((d_cell :== 1) :| csdid__trim_keep(eng->dr_ps, trim_level))
                        // DS-04: no `n_control <= cols(x)' pre-test
                        // here; R gates on rcond_check_fail() alone
                        // (see csdid__reg_panel_fit), so a
                        // one-control-unit comparison group is
                        // estimated, not blanked.
                    }
                    if (eng->dr_status == 0) {
                        // F-005: R-parity conditioning guard must also
                        // cover this precomputed fast path.
                        if (csdid__rcond_fail(x_cell, d_cell)) {
                            eng->dr_status = 2
                        }
                    }
                    if (eng->dr_status == 0) {
                        eng->dr_weights_ols = eng->dr_w :* (1 :- d_cell)
                        eng->dr_xtwx_inv = csdid__inv_r_parity(quadcross(x_cell, eng->dr_weights_ols, x_cell))  // F-005: R-parity inverse
                        if (!csdid__valid_inverse(eng->dr_xtwx_inv)) {
                            eng->dr_status = 2
                        }
                    }
                    if (eng->dr_status == 0) {
                        eng->dr_xpx_inv = n1 * eng->dr_xtwx_inv
                        eng->dr_h = csdid__hessinv_r_parity(quadcross(x_cell, eng->dr_ps :* (1 :- eng->dr_ps) :* eng->dr_w, x_cell), n1)  // F-005: R chol2inv(chol()) after the rcond guard
                        if (sum(eng->dr_h :>= .) > 0) {
                            // F-013/F-040: R's rcond stop on the
                            // propensity hessian is
                            // DRDID::drdid_panel's singular-design
                            // refusal (status 2); it is not an overlap
                            // violation.
                            eng->dr_status = 2
                        }
                    }
                    if (eng->dr_status == 0) {
                        eng->dr_w_treat = eng->dr_trim :* eng->dr_w :* d_cell
                        eng->dr_w_cont = eng->dr_trim :* eng->dr_w :* eng->dr_ps :* (1 :- d_cell) :/ (1 :- eng->dr_ps)
                        eng->dr_mw_treat = mean(eng->dr_w_treat)
                        eng->dr_mw_cont = mean(eng->dr_w_cont)
                        // The RC fits carry this guard and the live DR
                        // panel path did not. csdid__dr_panel_fit_precomputed
                        // DIVIDES by both means, so a cell whose trimming
                        // left no effective mass on one side produced an
                        // infinity or a missing with fit_status 0 -- i.e.
                        // it was reported as a successful fit. Status 3
                        // is the same classification the RC fits give it,
                        // and it now carries a warning too.
                        if (min((eng->dr_mw_treat, eng->dr_mw_cont)) <= 0 |
                            eng->dr_mw_treat >= . | eng->dr_mw_cont >= .) {
                            eng->dr_status = 3
                        }
                        eng->dr_score_ps = eng->dr_w :* (d_cell :- eng->dr_ps)
                        eng->dr_xgamma_treat = x_cell * (eng->dr_xpx_inv * (quadcross(x_cell, eng->dr_w_treat) / n1))
                        eng->dr_xgamma_cont = x_cell * (eng->dr_xpx_inv * (quadcross(x_cell, eng->dr_w_cont) / n1))
                    }
                }
                if (eng->dr_status != 0) {
                    fit = . \ J(n1, 1, .) \ eng->dr_status
                }
                else {
                    fit = csdid__dr_panel_fit_precomputed(
                        y1_cell, y0_cell, d_cell, x_cell,
                        eng->dr_w_treat, eng->dr_w_cont,
                        eng->dr_score_ps, eng->dr_xgamma_treat,
                        eng->dr_xgamma_cont,
                        eng->dr_mw_treat, eng->dr_mw_cont,
                        eng->dr_xtwx_inv,
                        eng->dr_h, eng->dr_weights_ols)
                }
            }
            else {
                fit = csdid__reg_panel_fit(y1_cell, y0_cell, d_cell, x_cell, w_cell)
            }
        }
        csdid__profile_add(3, prof_fit_t0, n1)
        att = fit[1]
        fit_status = fit[rows(fit)]
        if (att >= .) {
            csdid__fit_status_warning(fit_status, method, has_x, g, t)
        }
        prof_if_t0 = csdid__profile_start()
        unit_if = J(n_units, 1, 0)
        if (att < .) {
            if (fix_weights == "varying" & has_w) {
                unit_if[valid_uid] = (n_units / n1) * (fit[2..(n1 + 1)] + fit[(n1 + 2)..(2 * n1 + 1)]) / 2
            }
            else {
                unit_if[valid_uid] = (n_units / n1) * fit[2..(n1 + 1)]
            }
        }
        else {
            unit_if = J(n_units, 1, .)
        }
        se = csdid__se_from_if(unit_if)
        if (att >= .) se = .
        csdid__store_cell(g, t, att, se, nt1, nt0, nc1, nc0, pret,
            unit_if, out, ifmat_t, cell_ix)
        csdid__profile_add(4, prof_if_t0, n_units)
    }
}

// ---------------------------------------------------------------------------
// Every (g,t) cell on the unbalanced-panel route: ivar() was given but some
// unit-periods are missing, so the cell is assembled from ROWS rather than
// from panel columns and estimated with the repeated-cross-section 2x2. The
// influence function is then accumulated back to units, which is what keeps
// this route's standard errors comparable with the panel route's.
// ---------------------------------------------------------------------------
void csdid__cells_unbal_panel(
    pointer(class csdid__Engine scalar) scalar eng,
    real matrix cells,
    real rowvector tlevels,
    real colvector y,
    real colvector tt,
    real colvector geff,
    real colvector ww,
    real matrix x,
    real colvector id,
    real colvector idlevels,
    real matrix row_index,
    real colvector row_unit_index,
    real colvector unit_group,
    real colvector uid_seq,
    real scalar n_units,
    real scalar sorted_unit_scan,
    string scalar method,
    real scalar has_x,
    real matrix out,
    real matrix ifmat_t,
    real scalar cell_ix)
{
    real scalar ic, g, t, pret, control_time
    real colvector treat_fast, control_fast, treat_uid, control_uid
    real colvector row_treat_t, row_treat_pre, row_control_t, row_control_pre
    real colvector valid_rows, y_rc, post_rc, d_rc, w_rc, fit, unit_if
    real matrix x_rc
    real scalar tidx_t, tidx_pre, nt1, nt0, nc1, nc0, n1, att, se, fit_status
    real scalar prof_fit_t0, prof_if_t0, anticipation, trim_level
    string scalar notyet, base_period

    notyet       = eng->notyet
    base_period  = eng->base_period
    anticipation = eng->anticipation
    trim_level   = eng->trim_level

    for (ic = 1; ic <= rows(cells); ic++) {
        g            = cells[ic, 1]
        t            = cells[ic, 2]
        pret         = cells[ic, 3]
        control_time = cells[ic, 4]
        tidx_t = csdid__sorted_index(tlevels, t)
        tidx_pre = csdid__sorted_index(tlevels, pret)
        if (tidx_t >= . | tidx_pre >= .) continue
        treat_fast = (unit_group :== g)
        if (notyet != "") {
            control_fast = (unit_group :!= g) :& ((unit_group :== 0) :| (unit_group :> control_time + anticipation))
        }
        else {
            control_fast = (unit_group :== 0)
        }
        treat_uid = select(uid_seq, treat_fast)
        control_uid = select(uid_seq, control_fast)
        if (rows(treat_uid) > 0) {
            row_treat_t = row_index[treat_uid, tidx_t]
            row_treat_pre = row_index[treat_uid, tidx_pre]
            row_treat_t = select(row_treat_t, row_treat_t :< .)
            row_treat_pre = select(row_treat_pre, row_treat_pre :< .)
        }
        else {
            row_treat_t = J(0, 1, .)
            row_treat_pre = J(0, 1, .)
        }
        if (rows(control_uid) > 0) {
            row_control_t = row_index[control_uid, tidx_t]
            row_control_pre = row_index[control_uid, tidx_pre]
            row_control_t = select(row_control_t, row_control_t :< .)
            row_control_pre = select(row_control_pre, row_control_pre :< .)
        }
        else {
            row_control_t = J(0, 1, .)
            row_control_pre = J(0, 1, .)
        }

        nt1 = rows(row_treat_t)
        nt0 = rows(row_treat_pre)
        nc1 = rows(row_control_t)
        nc0 = rows(row_control_pre)
        if (csdid__emit_degenerate_cell(base_period == "universal" & t == pret,
            g, t, pret, nt1, nt0, nc1, nc0, n_units, out, ifmat_t, cell_ix)) continue

        if (sorted_unit_scan) {
            valid_rows = J(0, 1, .)
            if (rows(treat_uid) > 0) {
                valid_rows = valid_rows \ rowshape(row_index[treat_uid, (tidx_pre, tidx_t)], rows(treat_uid) * 2)
            }
            if (rows(control_uid) > 0) {
                valid_rows = valid_rows \ rowshape(row_index[control_uid, (tidx_pre, tidx_t)], rows(control_uid) * 2)
            }
            valid_rows = select(valid_rows, valid_rows :< .)
        }
        else {
            valid_rows = sort(row_treat_pre \ row_treat_t \ row_control_pre \ row_control_t, 1)
        }
        n1 = rows(valid_rows)
        y_rc = y[valid_rows]
        post_rc = (tt[valid_rows] :== t)
        d_rc = (geff[valid_rows] :== g)
        w_rc = ww[valid_rows]
        if (method == "reg" & !has_x) {
            x_rc = J(n1, 1, 1)
        }
        else {
            x_rc = x[valid_rows, .]
        }

        prof_fit_t0 = csdid__profile_start()
        csdid__rc_fit_dispatch(method, y_rc, post_rc, d_rc, x_rc, w_rc,
            trim_level, fit = J(0, 1, .))
        csdid__profile_add(3, prof_fit_t0, n1)
        att = fit[1]
        fit_status = fit[rows(fit)]
        if (att >= .) {
            csdid__fit_status_warning(fit_status, method, has_x, g, t)
        }
        prof_if_t0 = csdid__profile_start()
        csdid__rc_accumulate_unit_if(att, fit, n1, n_units, valid_rows,
            row_unit_index, idlevels, id, sorted_unit_scan,
            unit_if = J(0, 1, .))
        se = csdid__se_from_if(unit_if)
        if (att >= .) se = .
        csdid__store_cell(g, t, att, se, nt1, nt0, nc1, nc0, pret,
            unit_if, out, ifmat_t, cell_ix)
        csdid__profile_add(4, prof_if_t0, n_units)
    }
}

// ---------------------------------------------------------------------------
// Every (g,t) cell on the general route: no ivar(), or an unbalanced design
// that none of the routes above will take. The cell's rows come either from
// the one-time (cohort, period) buckets or, on panel-shaped data where the
// buckets do not pay, from four boolean masks over the whole sample; both
// yield the same rows in the same ascending order.
//
// Two estimators finish it. A design with weights, covariates or a
// not-yet-treated comparison group goes through the repeated-cross-section
// 2x2; the plain unweighted case is four group means, with the influence
// function accumulated row by row in the order the masks were swept.
// ---------------------------------------------------------------------------
void csdid__cells_rc(
    pointer(class csdid__Engine scalar) scalar eng,
    real matrix cells,
    real rowvector tlevels,
    real scalar first_t,
    real colvector y,
    real colvector tt,
    real colvector geff,
    real colvector ww,
    real matrix x,
    real colvector use,
    real colvector id,
    real colvector idlevels,
    real matrix row_index,
    real colvector row_unit_index,
    real scalar n_units,
    real scalar sorted_unit_scan,
    string scalar method,
    real scalar has_x,
    real scalar has_w,
    real scalar balanced_panel,
    real scalar rc_built,
    real colvector rc_gcats,
    real colvector rc_sorted_rows,
    real matrix rc_lut,
    real scalar rc_nbg,
    real scalar rc_nbt,
    real colvector rc_mask,
    real matrix out,
    real matrix ifmat_t,
    real scalar cell_ix)
{
    real scalar ic, g, t, pret, control_time
    real colvector rc_treat_t, rc_treat_pre, rc_ctrl_t, rc_ctrl_pre
    real colvector idx_t1, idx_t0, idx_c1, idx_c0, idx_rc, valid_rows, valid_rc
    real colvector y_rc, post_rc, d_rc, w_rc, fit, unit_if
    real matrix x_rc
    real scalar rc_bg, rc_b, rc_c, rc_tid_t, rc_tid_pre, rr, k, r
    real scalar nt1, nt0, nc1, nc0, n1, n_dropped_w, row_w, row_w_time, tidx_w
    real scalar uid_index, mt1, mt0, mc1, mc0, if_value, att, se, fit_status
    real scalar prof_fit_t0, prof_if_t0, anticipation, trim_level
    string scalar notyet, base_period, fix_weights

    notyet       = eng->notyet
    base_period  = eng->base_period
    fix_weights  = eng->fix_weights
    anticipation = eng->anticipation
    trim_level   = eng->trim_level

    for (ic = 1; ic <= rows(cells); ic++) {
        g            = cells[ic, 1]
        t            = cells[ic, 2]
        pret         = cells[ic, 3]
        control_time = cells[ic, 4]
        if (rc_built) {
            // bucket-slice assembly: the same rows, in the same ascending
            // order, that the boolean masks select - at O(rows in the
            // cell) instead of O(N) per mask.
            //
            // The not-yet-treated control condition carries R's
            // `g != current_g' exclusion (did compute.att_gt.R:362 and
            // :715), exactly as the panel routes in this file do with
            // their `unit_group :!= g' masks. Without it, any cell with
            // t + anticipation < g satisfies `geff > control_time +
            // anticipation' FOR COHORT g ITSELF -- control_time is
            // max(t, pret) -- so the cohort enters its own control group.
            rc_tid_t = csdid__sorted_index(tlevels, t)
            rc_tid_pre = csdid__sorted_index(tlevels, pret)
            rc_bg = .
            for (rc_b = 1; rc_b <= rc_nbg; rc_b++) {
                if (rc_gcats[rc_b] == g) rc_bg = rc_b
            }
            rc_treat_t = csdid__rc_slice(rc_sorted_rows, rc_lut, rc_nbt, rc_bg, rc_tid_t)
            rc_treat_pre = csdid__rc_slice(rc_sorted_rows, rc_lut, rc_nbt, rc_bg, rc_tid_pre)
            rc_ctrl_t = J(0, 1, .)
            rc_ctrl_pre = J(0, 1, .)
            for (rc_c = 1; rc_c <= rc_nbg; rc_c++) {
                if (notyet != "") {
                    if (rc_gcats[rc_c] == g) continue
                    if (!(rc_gcats[rc_c] == 0 | rc_gcats[rc_c] > control_time + anticipation)) continue
                }
                else {
                    if (rc_gcats[rc_c] != 0) continue
                }
                rc_ctrl_t = rc_ctrl_t \ csdid__rc_slice(rc_sorted_rows, rc_lut, rc_nbt, rc_c, rc_tid_t)
                rc_ctrl_pre = rc_ctrl_pre \ csdid__rc_slice(rc_sorted_rows, rc_lut, rc_nbt, rc_c, rc_tid_pre)
            }
            nt1 = rows(rc_treat_t); nt0 = rows(rc_treat_pre)
            nc1 = rows(rc_ctrl_t); nc0 = rows(rc_ctrl_pre)
        }
        else {
            // panel-shaped data: the original mask path, verbatim
            idx_t1 = (use :!= 0) :& (geff :== g) :& (tt :== t)
            idx_t0 = (use :!= 0) :& (geff :== g) :& (tt :== pret)
            if (notyet != "") {
                // (geff != g) is R's exclusion of the cohort from its own
                // control group; see the note on the bucket route above.
                idx_c1 = (use :!= 0) :& (geff :!= g) :& ((geff :== 0) :| (geff :> control_time + anticipation)) :& (tt :== t)
                idx_c0 = (use :!= 0) :& (geff :!= g) :& ((geff :== 0) :| (geff :> control_time + anticipation)) :& (tt :== pret)
            }
            else {
                idx_c1 = (use :!= 0) :& (geff :== 0) :& (tt :== t)
                idx_c0 = (use :!= 0) :& (geff :== 0) :& (tt :== pret)
            }
            nt1 = sum(idx_t1); nt0 = sum(idx_t0); nc1 = sum(idx_c1); nc0 = sum(idx_c0)
        }
        if (csdid__emit_degenerate_cell(base_period == "universal" & t == pret,
            g, t, pret, nt1, nt0, nc1, nc0, n_units, out, ifmat_t, cell_ix)) continue

        if (!balanced_panel & (has_w | has_x | notyet != "")) {
            if (rc_built) {
                // union of the four slices, deduplicated and ascending -
                // identical to select() over the OR of the masks; the
                // reusable 0/1 buffer needs no per-cell sort
                if (rows(rc_treat_t)) rc_mask[rc_treat_t] = J(rows(rc_treat_t), 1, 1)
                if (rows(rc_treat_pre)) rc_mask[rc_treat_pre] = J(rows(rc_treat_pre), 1, 1)
                if (rows(rc_ctrl_t)) rc_mask[rc_ctrl_t] = J(rows(rc_ctrl_t), 1, 1)
                if (rows(rc_ctrl_pre)) rc_mask[rc_ctrl_pre] = J(rows(rc_ctrl_pre), 1, 1)
                valid_rows = csdid__selidx(rc_mask)
                if (rows(valid_rows)) rc_mask[valid_rows] = J(rows(valid_rows), 1, 0)
            }
            else {
                idx_rc = idx_t0 :| idx_t1 :| idx_c0 :| idx_c1
                valid_rows = select((1::rows(y)), idx_rc)
            }
            n1 = rows(valid_rows)
            // Only rows(dropped_ids) is ever read, so accumulating the
            // ids themselves grew a vector by row-concatenation inside a
            // per-row loop -- a fresh allocation and a full copy on every
            // dropped row, for a number a counter gives in O(1).
            n_dropped_w = 0
            if (fix_weights == "base_period") {
                row_w_time = csdid__previous_time(tlevels, g - anticipation)
            }
            else if (fix_weights == "first_period") {
                row_w_time = first_t
            }
            else {
                row_w_time = .
            }
            if (row_w_time >= .) {
                y_rc = y[valid_rows]
                post_rc = (tt[valid_rows] :== t)
                d_rc = (geff[valid_rows] :== g)
                w_rc = ww[valid_rows]
                if (method == "reg" & !has_x) {
                    x_rc = J(n1, 1, 1)
                }
                else {
                    x_rc = x[valid_rows, .]
                }
            }
            else {
                y_rc = J(n1, 1, .)
                post_rc = J(n1, 1, .)
                d_rc = J(n1, 1, .)
                w_rc = J(n1, 1, .)
                if (method == "reg" & !has_x) {
                    x_rc = J(n1, 1, 1)
                }
                else {
                    x_rc = J(n1, cols(x), .)
                }
                tidx_w = csdid__sorted_index(tlevels, row_w_time)
                for (k = 1; k <= n1; k++) {
                    r = valid_rows[k]
                    uid_index = row_unit_index[r]
                    if (uid_index >= .) uid_index = csdid__sorted_index(idlevels, id[r])
                    if (uid_index < . & tidx_w < .) {
                        row_w = row_index[uid_index, tidx_w]
                    }
                    else {
                        row_w = .
                    }
                    if (row_w >= .) {
                        n_dropped_w = n_dropped_w + 1
                        continue
                    }
                    y_rc[k] = y[r]
                    post_rc[k] = (tt[r] == t)
                    d_rc[k] = (geff[r] == g)
                    w_rc[k] = ww[row_w]
                    if (!(method == "reg" & !has_x)) {
                        x_rc[k, .] = x[r, .]
                    }
                }
                if (n_dropped_w > 0) {
                    // errprintf: this one names units the cell EXCLUDED,
                    // so it is a sample announcement and follows the
                    // channel rule at csdid__empty_cell_warning.
                    errprintf("warning: Some units not observed in %s (period %g) for group %g in time period %g. These units are excluded.\n", fix_weights, row_w_time, g, t)
                }
                valid_rc = y_rc :< .
                valid_rows = select(valid_rows, valid_rc)
                y_rc = select(y_rc, valid_rc)
                post_rc = select(post_rc, valid_rc)
                d_rc = select(d_rc, valid_rc)
                w_rc = select(w_rc, valid_rc)
                x_rc = select(x_rc, valid_rc)
            }
            n1 = rows(y_rc)
            nt1 = sum((d_rc :== 1) :& (post_rc :== 1))
            nt0 = sum((d_rc :== 1) :& (post_rc :== 0))
            nc1 = sum((d_rc :== 0) :& (post_rc :== 1))
            nc0 = sum((d_rc :== 0) :& (post_rc :== 0))
            // Only the empty-cell half can fire here: this (g,t) already
            // passed the shared emitter above, before the repeated
            // cross-section rows were assembled, so a universal-base
            // normalisation row has moved on and the flag is 0 by
            // construction.
            if (csdid__emit_degenerate_cell(0,
                g, t, pret, nt1, nt0, nc1, nc0, n_units, out, ifmat_t, cell_ix)) continue
            prof_fit_t0 = csdid__profile_start()
            csdid__rc_fit_dispatch(method, y_rc, post_rc, d_rc, x_rc, w_rc,
                trim_level, fit = J(0, 1, .))
            csdid__profile_add(3, prof_fit_t0, n1)
            att = fit[1]
            fit_status = fit[rows(fit)]
            if (att >= .) {
                csdid__fit_status_warning(fit_status, method, has_x, g, t)
            }
            prof_if_t0 = csdid__profile_start()
            csdid__rc_accumulate_unit_if(att, fit, n1, n_units, valid_rows,
                row_unit_index, idlevels, id, sorted_unit_scan,
                unit_if = J(0, 1, .))
            se = csdid__se_from_if(unit_if)
            if (att >= .) se = .
            csdid__store_cell(g, t, att, se, nt1, nt0, nc1, nc0, pret,
                unit_if, out, ifmat_t, cell_ix)
            csdid__profile_add(4, prof_if_t0, n_units)
            continue
        }

        if (rc_built) {
            mt1 = csdid__mean(y[rc_treat_t])
            mt0 = csdid__mean(y[rc_treat_pre])
            mc1 = csdid__mean(y[rc_ctrl_t])
            mc0 = csdid__mean(y[rc_ctrl_pre])
        }
        else {
            mt1 = csdid__mean(select(y, idx_t1))
            mt0 = csdid__mean(select(y, idx_t0))
            mc1 = csdid__mean(select(y, idx_c1))
            mc0 = csdid__mean(select(y, idx_c0))
        }
        att = (mt1 - mt0) - (mc1 - mc0)
        prof_if_t0 = csdid__profile_start()
        unit_if = J(n_units, 1, 0)
        if (rc_built) {
            // the same if-value chain, evaluated only on the union rows
            // (ascending = original scan order); conditions and their
            // overwrite priority untouched
            if (rows(rc_treat_t)) rc_mask[rc_treat_t] = J(rows(rc_treat_t), 1, 1)
            if (rows(rc_treat_pre)) rc_mask[rc_treat_pre] = J(rows(rc_treat_pre), 1, 1)
            if (rows(rc_ctrl_t)) rc_mask[rc_ctrl_t] = J(rows(rc_ctrl_t), 1, 1)
            if (rows(rc_ctrl_pre)) rc_mask[rc_ctrl_pre] = J(rows(rc_ctrl_pre), 1, 1)
            valid_rows = csdid__selidx(rc_mask)
            if (rows(valid_rows)) rc_mask[valid_rows] = J(rows(valid_rows), 1, 0)
            for (rr = 1; rr <= rows(valid_rows); rr++) {
                r = valid_rows[rr]
                if_value = 0
                if (geff[r] == g & tt[r] == t) if_value = n_units / nt1 * (y[r] - mt1)
                if (geff[r] == g & tt[r] == pret) if_value = -n_units / nt0 * (y[r] - mt0)
                if (notyet != "") {
                    if ((geff[r] == 0 | geff[r] > control_time + anticipation) & tt[r] == t) if_value = -n_units / nc1 * (y[r] - mc1)
                    if ((geff[r] == 0 | geff[r] > control_time + anticipation) & tt[r] == pret) if_value = n_units / nc0 * (y[r] - mc0)
                }
                else {
                    if (geff[r] == 0 & tt[r] == t) if_value = -n_units / nc1 * (y[r] - mc1)
                    if (geff[r] == 0 & tt[r] == pret) if_value = n_units / nc0 * (y[r] - mc0)
                }
                if (if_value != 0) {
                    uid_index = row_unit_index[r]
                    if (uid_index >= .) uid_index = csdid__sorted_index(idlevels, id[r])
                    if (uid_index < .) unit_if[uid_index] = unit_if[uid_index] + if_value
                }
            }
        }
        else {
            // The loop bound used to be the WHOLE DATASET, not the cell:
            // a cell touching 5% of the rows still paid 100% of the
            // iterations, once per cell. Only rows in one of the four
            // masks can produce a nonzero contribution, so iterate over
            // exactly those. The masks are disjoint by construction
            // except where the original overwrite priority applied, and
            // that priority is preserved verbatim below, so the values
            // and the accumulation order are unchanged: selectindex
            // returns ascending row numbers, which is the order the full
            // sweep visited them in.
            valid_rows = csdid__selidx(idx_t1 :| idx_t0 :| idx_c1 :| idx_c0)
            for (rr = 1; rr <= rows(valid_rows); rr++) {
                r = valid_rows[rr]
                if_value = 0
                if (idx_t1[r]) if_value = n_units / nt1 * (y[r] - mt1)
                if (idx_t0[r]) if_value = -n_units / nt0 * (y[r] - mt0)
                if (idx_c1[r]) if_value = -n_units / nc1 * (y[r] - mc1)
                if (idx_c0[r]) if_value = n_units / nc0 * (y[r] - mc0)
                if (if_value != 0) {
                    uid_index = row_unit_index[r]
                    if (uid_index >= .) uid_index = csdid__sorted_index(idlevels, id[r])
                    if (uid_index < .) unit_if[uid_index] = unit_if[uid_index] + if_value
                }
            }
        }
        se = csdid__se_from_if(unit_if)
        csdid__store_cell(g, t, att, se, nt1, nt0, nc1, nc0, pret,
            unit_if, out, ifmat_t, cell_ix)
        csdid__profile_add(4, prof_if_t0, n_units)
    }
}

// ---------------------------------------------------------------------------
// SEAM 6 -- the results, stored.
//
// Trims the cell table to the cells that were actually written, restores the
// influence-function matrix to its documented n_units x n_cells orientation,
// and hands the run to its two consumers: the engine object, which the
// postestimation commands read back, and the Stata matrices and scalars the
// ado layer posts from.
//
// Which of the two carries the influence functions is the storage decision:
// under lean storage they stay in Mata, because an n_units-row matrix crossing
// into Stata's classic-matrix layer is quadratic in n_units (see csdid_aggte);
// under storeall they are posted and the cache is emptied so nothing stale can
// be read back.
// ---------------------------------------------------------------------------
void csdid__store_results(
    pointer(class csdid__Engine scalar) scalar eng,
    real scalar cell_ix,
    real scalar n_units,
    real scalar store_large,
    real scalar fast_used,
    real scalar balanced_panel,
    real scalar n_times,
    real matrix out,
    real matrix ifmat_t,
    real matrix group_prob_mat,
    real matrix unit_group_mat,
    real colvector unit_first_row,
    real colvector row_unit_index,
    real colvector unit_cluster,
    string scalar outname,
    string scalar ifname,
    string scalar gprobname,
    string scalar unitgroupname,
    string scalar cachetokenname,
    string scalar fastusedname,
    string scalar balancedname,
    string scalar ntimename)
{
    real matrix ifmat
    real scalar prof_t0

    if (cell_ix == 0) {
        out = J(0, 10, .)
        ifmat = J(n_units, 0, .)
    }
    else {
        out = out[1..cell_ix, .]
        ifmat = ifmat_t[1..cell_ix, .]'
    }
    prof_t0 = csdid__profile_start()
    if (store_large == 0) {
        // The token names this estimation: the session (token_base, settled
        // once at construction) in the high half, the estimation within the
        // session in the low half. A counter alone named only the second, so
        // the first lean run of every session shared a token with the first
        // lean run of every other session -- see csdid__Engine::token_seed.
        // The low half is 2^20 wide; a session that somehow exhausts it takes
        // a fresh base rather than wrapping onto its own earlier tokens.
        if (eng->token_counter >= 1048575) {
            eng->token_base = eng->token_seed()
            eng->token_counter = 0
        }
        eng->token_counter = eng->token_counter + 1
        eng->token = eng->token_base * 1048576 + eng->token_counter
        // The results this cache was computed alongside. csdid_cache_validate
        // reads it back against e(attgt) so that a token which matches for any
        // reason other than being this estimation is refused rather than
        // aggregated. Cell count, not unit count: this crossing is the small
        // one (see csdid_aggte for the one that is not).
        eng->attgt = out
        eng->inffunc = ifmat
        eng->unit_group = unit_group_mat
        eng->unit_row = unit_first_row
        eng->row_unit = row_unit_index
        eng->cluster_vec = unit_cluster
    }
    else {
        eng->token = 0
        eng->attgt = J(0, 0, .)
        eng->inffunc = J(0, 0, .)
        eng->unit_group = J(0, 0, .)
        eng->unit_row = unit_first_row
        eng->row_unit = row_unit_index
        eng->cluster_vec = unit_cluster
    }
    st_matrix(outname, out)
    if (store_large != 0) st_matrix(ifname, ifmat)
    st_matrix(gprobname, group_prob_mat)
    if (store_large != 0) st_matrix(unitgroupname, unit_group_mat)
    st_numscalar(cachetokenname, eng->token)
    st_numscalar(fastusedname, fast_used)
    st_numscalar(balancedname, balanced_panel)
    st_numscalar(ntimename, n_times)
    csdid__profile_add(5, prof_t0, rows(ifmat) * cols(ifmat))
}

void csdid_basic_attgt(
    string scalar yname,
    string scalar tname,
    string scalar gname,
    string scalar idname,
    string scalar xnames,
    string scalar wname,
    string scalar method,
    string scalar tousename,
    string scalar clustername,
    string scalar notyet,
    string scalar base_period,
    string scalar balance_mode,
    string scalar fix_weights,
    real scalar anticipation,
    real scalar trim_level,
    real scalar reqsize,
    real scalar fast_flag,
    string scalar fastusedname,
    string scalar balancedname,
    string scalar ntimename,
    real scalar store_large,
    string scalar outname,
    string scalar ifname,
    string scalar gprobname,
    string scalar unitgroupname,
    string scalar cachetokenname,
    string scalar usemarkname)
{
    external class csdid__Engine scalar CSDID_ENGINE
    pointer(class csdid__Engine scalar) scalar eng
    real colvector y, tt, gg, geff, id, ww, cl, use, glevels, tlevels, idlevels
    real colvector unit_group, unit_weight, wsum_vec, wcount_vec, first_weight
    real colvector row_unit_index, unit_first_row, unit_cluster, uid_seq
    real colvector rc_gcats, rc_sorted_rows, rc_mask
    real matrix out, ifmat_t, group_prob_mat, unit_group_mat, x, row_index
    real matrix y_fast, y_panel, w_panel, x_panel, rc_lut, cells
    real scalar first_t
    real scalar has_x, has_w, has_cluster, kx, n_units, max_cells, cell_ix
    real scalar balanced_panel, pair_mode, fast_eligible, fast_used
    real scalar sorted_unit_scan, rc_built, rc_nbg, rc_nbt
    real scalar prof_t0

    csdid__engine_ensure()

    // The engine is reached through a pointer: `eng' is what every phase and
    // cell routine below takes, and it is how this routine names members too.
    // The alias is not cosmetic. Naming CSDID_ENGINE directly inside one long
    // function costs Mata compile time that an alias does not -- measured
    // 2026-08-14 at 112 references in one routine, 0.083s of the 0.669s it
    // took to compile the 6,764-line source -- which every user of the
    // source-fallback path pays once per session. It is the rule the class
    // notes state: alias members before the code that reads them.
    eng = &CSDID_ENGINE

    // The six options that change what this run estimates rather than how it
    // is computed, recorded on the object the moment they arrive. They are
    // settled once, by the ado, and every phase and cell routine below reads
    // them from here instead of taking six more arguments.
    eng->base_period  = base_period
    eng->notyet       = notyet
    eng->balance_mode = balance_mode
    eng->fix_weights  = fix_weights
    eng->anticipation = anticipation
    eng->trim_level   = trim_level

    csdid__profile_reset()
    prof_t0 = csdid__profile_start()

    // The phase and cell routines below fill their output arguments; Mata's
    // strict compiler wants an argument set before it is passed, so each one
    // is opened empty here (the same reason csdid__cluster_layout's caller
    // opens `ord' and `info' in its call).
    y = tt = gg = geff = id = ww = cl = use = J(0, 1, .)
    idlevels = unit_group = unit_first_row = unit_cluster = J(0, 1, .)
    wsum_vec = wcount_vec = first_weight = row_unit_index = J(0, 1, .)
    x = row_index = y_panel = w_panel = x_panel = J(0, 0, .)
    tlevels = glevels = J(1, 0, .)
    has_x = has_w = has_cluster = first_t = .
    n_units = kx = sorted_unit_scan = balanced_panel = .
    unit_weight = J(0, 1, .)
    group_prob_mat = unit_group_mat = J(0, 0, .)
    rc_gcats = rc_sorted_rows = rc_mask = J(0, 1, .)
    rc_lut = J(0, 0, .)

    csdid__settle_sample(eng, yname, tname, gname, idname, xnames, wname,
        method, tousename, clustername, usemarkname,
        y, tt, gg, geff, id, ww, cl, use, x, tlevels, glevels,
        has_x, has_w, has_cluster, first_t)
    csdid__build_layout(idname, y, tt, gg, geff, id, ww, cl, use, x, tlevels,
        first_t, has_x, has_w, has_cluster,
        idlevels, n_units, kx, row_index, y_panel, w_panel, x_panel,
        unit_group, unit_first_row, unit_cluster, wsum_vec, wcount_vec,
        first_weight, row_unit_index, sorted_unit_scan, balanced_panel)

    pair_mode = (balance_mode == "pair" & idname != "")
    fast_used = (fast_flag != 0)
    // method(dr) with NO covariates is the same estimator as method(reg).
    // With an intercept-only design the propensity score is the constant
    // treated share, so the IPW and outcome-regression parts of the doubly
    // robust estimator both collapse to group means and the estimate is the
    // plain difference in differences. Measured on a 20,000-unit panel, the
    // two paths agree to 4.4e-16 on the ATT and 1.7e-18 on the standard error
    // (8.9e-16 / 1.3e-18 weighted and clustered), and the fast kernel is 6x
    // quicker: 1.37s against 0.22s.
    //
    // What is NOT shared are the REFUSALS: R runs the overlap guard for dr and
    // ipw and not for reg, so a cell whose treated share reaches 0.999 is
    // refused under dr and estimated under reg, and DRDID additionally trims
    // controls at ps >= pscoretrim(). Both are therefore applied inside the
    // fast branch below before anything is computed, in the intercept-only
    // closed form -- csdid__overlap_status already carries R's pbar = mean(d)
    // with its knife edge, and the trim reduces to a scalar comparison -- so
    // the set of refused cells is unchanged and only the arithmetic moves.
    //
    // ipw is deliberately not included: it reduces the same way, but its
    // guard set differs again and it deserves its own evidence.
    fast_eligible = (fast_flag != 0) & balanced_panel & !pair_mode & !has_w & !has_x & (method == "reg" | method == "dr") & (fix_weights == "")
    y_fast = J(0, 0, .)
    if (fast_eligible) {
        y_fast = y_panel
    }
    uid_seq = (1::n_units)
    csdid__group_probs(eng, idname, balanced_panel, n_units, reqsize, tlevels,
        glevels, idlevels, unit_group, wsum_vec, wcount_vec, first_weight,
        row_index, tt, unit_weight, group_prob_mat, unit_group_mat)
    max_cells = cols(glevels) * cols(tlevels)
    cell_ix = 0
    // Column 10 (base_time) carries the reference period pret this cell was
    // differenced against - previous_time(g - anticipation) under the
    // universal base, previous_time(t) for pre-treatment cells under the
    // varying base. It exists so that the posting layer can (a) identify the
    // universal-base NORMALISATION row exactly, as the row whose base_time
    // equals its own time (the kernel emits that row only under
    // `base_period == "universal" & t == pret'), and (b) name each posted
    // coefficient with the base period the cell actually used. Both were
    // previously inferred from event_time == -1, which is correct only when
    // the reference period happens to be exactly one time unit before g:
    // anticipation(), base_period(varying) and any non-unit-spaced time axis
    // (biennial, quinquennial) all break that inference. previous_time()
    // returns the largest observed period STRICTLY below its argument, so
    // base_time < time on every cell except the normalisation row, which
    // makes the equality test exact rather than heuristic.
    out = J(max_cells, 10, .)
    // ACCUMULATED TRANSPOSED, transposed once at the end.
    //
    // Mata stores matrices row-major, so `ifmat_t[cell_ix, .] = unit_if'' on an
    // n_units x max_cells matrix touches n_units addresses at a stride of
    // max_cells * 8 bytes. Once max_cells >= 8 every element write is its own
    // cache line and the working set is the entire array, re-swept once per
    // cell: at 600,000 repeated-cross-section units and 40 cells that is a
    // 192MB object traversed 40 times. Measured at that size, the assembly
    // phase was 0.93s of a 3.73s run.
    //
    // Writing a ROW per cell is contiguous, and one transpose at the end
    // restores the orientation. That orientation is not an internal detail --
    // e(inffunc) is posted under storeall, saverif() writes one variable per
    // (g,t) cell, csdid_cache_validate gates on rows == n_units, and
    // csdid.ado takes a column subscript of it for the Wald block -- so it is
    // deliberately unchanged. Only the fill order is.
    ifmat_t = J(max_cells, n_units, .)
    csdid__profile_add(1, prof_t0, rows(y))
    rc_built = 0
    rc_nbg = 0
    rc_nbt = 0
    // Shape gate, measured 2026-07-30: buckets win on repeated cross
    // sections (one row per unit; 6.41 -> 5.64s at 1M rows) and LOSE on
    // panel-shaped data (many rows per unit; 3.71 -> 4.23s at 850k rows,
    // slice concatenation outgrows the mask savings). Panels keep the
    // original mask path verbatim below.
    if (!balanced_panel & !pair_mode & idname == "") {
        csdid__rc_buckets(y, tt, geff, use, tlevels, rc_gcats,
            rc_sorted_rows, rc_lut, rc_mask, rc_built, rc_nbg, rc_nbt)
    }
    eng->dr_cache_reset()

    cells = eng->cell_grid(glevels, tlevels)

    // One run, one route. They are ordered by how much each may assume: the
    // closed form first, then the panel fit, then the unbalanced panel, and
    // last the general route, which assumes nothing about the shape of the
    // data. Which of them a run takes cannot change from cell to cell -- the
    // conditions below are all settled before the first cell is estimated --
    // so the route is chosen once and walks the whole grid itself.
    //
    // Choosing it once is also what makes the decomposition free. A route
    // entered per cell builds its frame per cell, and these frames are wide:
    // csdid__cells_rc as it stands takes 30 arguments and declares 56 locals,
    // and the per-cell csdid__cell_rc it replaced took 33 and declared 51.
    // Mata charges on every entry per argument and, about five times as much,
    // per DECLARED local, used or not; the coefficients are machine- and
    // probe-dependent (11-25ns and 57-92ns across three probes on 2026-08-15)
    // and are not worth predicting a route's frame from. The end-to-end number
    // is the one that decided this: measured 2026-08-15 on a 200-unit,
    // 12-period, 60-cell design (50 estimations per timing), entering the
    // routes once per cell rather than once per run cost 6.7us per cell on the
    // general route -- 1.6% of the run -- and 4.6us on the panel route.
    if (fast_eligible) {
        csdid__cells_fast(eng, cells, tlevels,
            y_fast, unit_group, uid_seq, n_units, method, has_x,
            out, ifmat_t, cell_ix)
    }
    else if (balanced_panel | pair_mode) {
        csdid__cells_panel(eng, cells, tlevels,
            first_t, y_panel, w_panel, x_panel, row_index, unit_group,
            uid_seq, n_units, kx, method, has_x, has_w, pair_mode,
            out, ifmat_t, cell_ix)
    }
    else if (!balanced_panel & idname != "" & (has_w | has_x | notyet != "") & fix_weights == "") {
        csdid__cells_unbal_panel(eng, cells, tlevels,
            y, tt, geff, ww, x, id, idlevels, row_index,
            row_unit_index, unit_group, uid_seq, n_units,
            sorted_unit_scan, method, has_x, out, ifmat_t, cell_ix)
    }
    else {
        csdid__cells_rc(eng, cells, tlevels, first_t,
            y, tt, geff, ww, x, use, id, idlevels, row_index,
            row_unit_index, n_units, sorted_unit_scan, method, has_x,
            has_w, balanced_panel, rc_built, rc_gcats, rc_sorted_rows,
            rc_lut, rc_nbg, rc_nbt, rc_mask, out, ifmat_t, cell_ix)
    }

    csdid__store_results(eng, cell_ix, n_units, store_large, fast_used,
        balanced_panel, cols(tlevels), out, ifmat_t, group_prob_mat,
        unit_group_mat, unit_first_row, row_unit_index, unit_cluster,
        outname, ifname, gprobname, unitgroupname, cachetokenname,
        fastusedname, balancedname, ntimename)
}

// ---------------------------------------------------------------------------
// Does the influence-function cache in this session belong to the results the
// postestimation command is about to summarize?
//
// Three of the four questions are about SHAPE -- a token, and two dimensions.
// Shape is not identity, and the fourth question is why. Two estimations on
// different data with the same number of units and the same (g,t) grid have
// the same shape, and until the token became session-unique they could have
// the same token as well: the first lean estimation of every session was
// token 1. That pairing computed, at return code 0, an aggregation whose point
// estimates came from one estimation and whose standard errors came from
// another (10x wrong on the witness in tests/stata/test-cache-token-session).
//
// So the last question is about CONTENT: the ATT(g,t) table the cache was
// filled beside, against the ATT(g,t) table the caller is holding. The table
// is the right thing to ask about rather than a hash of it -- it is one row
// per cell, so comparing it whole costs nothing at aggregation scale, and an
// exact comparison has no collision to reason about. It is also the object
// with the most estimation in it: the point estimates, the base period each
// cell was differenced against, and the four counts behind every cell.
//
// What it does NOT see, measured rather than assumed: a difference confined to
// the CLUSTERING. Two runs on identical data differing only in cluster() agree
// on every compared column -- the clustered standard error lands in column 5,
// which is excluded below -- so this comparison would accept one against the
// other's cache (witness: cl1 = mod(id,2)+1 vs cl2 = mod(id,12)+1, standard
// errors 30-50x apart, accepted once the token is forced to collide). That
// pairing is unreachable because the TOKEN is the first gate and now separates
// every estimation, within a session and across sessions. Which is the point:
// the token identifies the run, and this comparison is the second lock that
// catches a token that somehow matched the wrong estimation's cells.
//
// Column 5 is the exception, and it is excluded rather than forgiven. It is
// the standard-error column, and it is the ONE column written after this cache
// was filled: the cluster pass (csdid_cluster_attgt) and the bootstrap
// (csdid__boot_table) both replace it in place, so e(attgt) legitimately
// disagrees with the stored table there on every clustered or bootstrapped
// run. Every other column is written once, by the cell loop, and reaches e()
// and a .ster file unchanged.
// ---------------------------------------------------------------------------
void csdid_cache_validate(real scalar expected_token, real scalar n_units, real scalar n_attgt)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix live
    real rowvector settled

    csdid__engine_ensure()

    if (expected_token <= 0 | CSDID_ENGINE.token != expected_token) {
        errprintf("the stored influence functions do not match the active csdid results; re-run csdid with the storeall option, or re-run the estimation that produced these results\n")
        _error(498)
    }
    if (rows(CSDID_ENGINE.inffunc) != n_units | cols(CSDID_ENGINE.inffunc) != n_attgt) {
        errprintf("the stored influence functions have the wrong dimensions for the active csdid results; re-run csdid with the storeall option, or re-run the estimation that produced these results\n")
        _error(498)
    }
    if (rows(CSDID_ENGINE.unit_group) != n_units) {
        errprintf("the stored unit map does not match the active csdid results; re-run csdid with the storeall option, or re-run the estimation that produced these results\n")
        _error(498)
    }
    settled = (1, 2, 3, 4, 6, 7, 8, 9, 10)
    live = st_matrix("e(attgt)")
    if (rows(live) != rows(CSDID_ENGINE.attgt) | cols(live) != cols(CSDID_ENGINE.attgt) |
        cols(live) < max(settled)) {
        errprintf("the stored influence functions do not match the active csdid results; re-run csdid with the storeall option, or re-run the estimation that produced these results\n")
        _error(498)
    }
    // A missing cell compares equal to a missing cell (Mata's . == . is true),
    // so a grid with failed cells validates on its own missing pattern rather
    // than being refused for having one.
    if (sum(live[., settled] :!= CSDID_ENGINE.attgt[., settled]) > 0) {
        errprintf("the stored influence functions do not match the active csdid results; re-run csdid with the storeall option, or re-run the estimation that produced these results\n")
        _error(498)
    }
}

void csdid_cluster_attgt(
    string scalar clname,
    string scalar idname,
    string scalar tousename,
    string scalar attname,
    string scalar ifname,
    string scalar unitgroupname,
    string scalar nclustername,
    real scalar store_large,
    string scalar clustervecname)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real colvector cl, id, touse, cluster_vec, unit_id, se, unit_row, row_unit, sc_miss
    real scalar se_floor
    real matrix att, inf, unit_group, sc, idcl
    real scalar i, r, n, k, fast_cluster_map, prof_t0

    csdid__engine_ensure()

    prof_t0 = csdid__profile_start()
    att = st_matrix(attname)
    inf = st_matrix(ifname)
    unit_group = st_matrix(unitgroupname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_ENGINE.inffunc) > 0) {
        inf = CSDID_ENGINE.inffunc
    }
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_ENGINE.unit_group) > 0) {
        unit_group = CSDID_ENGINE.unit_group
    }
    n = rows(inf)
    if (n == 0 | cols(inf) == 0) {
        st_numscalar(nclustername, 0)
        return
    }

    cluster_vec = J(n, 1, .)
    if (rows(CSDID_ENGINE.cluster_vec) == n & sum(CSDID_ENGINE.cluster_vec :>= .) == 0) {
        cluster_vec = CSDID_ENGINE.cluster_vec
    }
    else if (idname == "") {
        cl = st_data(., clname)
        for (i = 1; i <= n; i++) {
            r = unit_group[i, 1]
            if (r >= . | r < 1 | r > rows(cl)) {
                errprintf("cluster() could not be aligned with repeated-cross-section influence functions\n")
                _error(498)
            }
            cluster_vec[i] = cl[r]
        }
    }
    else {
        cl = st_data(., clname)
        touse = st_data(., tousename)
        unit_row = CSDID_ENGINE.unit_row
        row_unit = CSDID_ENGINE.row_unit
        fast_cluster_map = (rows(unit_row) == n & rows(row_unit) == rows(cl))
        if (fast_cluster_map) {
            for (i = 1; i <= n; i++) {
                r = unit_row[i]
                if (r >= . | r < 1 | r > rows(cl)) {
                    errprintf("cluster() could not be aligned with panel influence functions\n")
                    _error(498)
                }
                cluster_vec[i] = cl[r]
            }
            for (r = 1; r <= rows(cl); r++) {
                if (touse[r] == 0) continue
                k = row_unit[r]
                if (k >= . | k < 1 | k > n) continue
                if (cl[r] != cluster_vec[k]) {
                    errprintf("cluster() must be time-invariant within ivar()\n")
                    _error(459)
                }
            }
        }
        else {
            id = st_data(., idname)
            unit_id = unit_group[., 1]
            idcl = select((id, cl), touse :!= 0)
            idcl = sort(idcl, 1)
            r = 1
            for (i = 1; i <= n; i++) {
                while (r <= rows(idcl)) {
                    if (idcl[r, 1] >= unit_id[i]) break
                    r = r + 1
                }
                if (r > rows(idcl)) {
                    errprintf("cluster() could not be aligned with panel influence functions\n")
                    _error(498)
                }
                if (idcl[r, 1] != unit_id[i]) {
                    errprintf("cluster() could not be aligned with panel influence functions\n")
                    _error(498)
                }
                cluster_vec[i] = idcl[r, 2]
                while (r <= rows(idcl)) {
                    if (idcl[r, 1] != unit_id[i]) break
                    if (idcl[r, 2] != cluster_vec[i]) {
                        errprintf("cluster() must be time-invariant within ivar()\n")
                        _error(459)
                    }
                    r = r + 1
                }
            }
        }
    }

    if (sum(cluster_vec :>= .) > 0) {
        errprintf("cluster() contains missing values in the estimation sample\n")
        _error(459)
    }

    sc = csdid__cluster_sums(cluster_vec, inf)
    // colsum() silently IGNORES missing, so a column of missing cluster sums
    // (a failed cell) would come back as se = 0 and read as "estimated with
    // zero variance". Blank those columns explicitly instead.
    sc_miss = colmissing(sc)'
    se = sqrt(colsum(sc:^2))' / n
    // R's degenerate-SE threshold; see csdid__se_from_if.
    se_floor = sqrt(epsilon(1)) * 10
    for (k = 1; k <= rows(se); k++) {
        if (sc_miss[k] > 0 | se[k] <= se_floor) se[k] = .
    }
    att[., 5] = se
    st_matrix(attname, att)
    st_numscalar(nclustername, rows(sc))
    if (store_large != 0) st_matrix(clustervecname, cluster_vec)
    csdid__profile_add(6, prof_t0, n)
}
// ===========================================================================
// SECTION 11 -- CLUSTER AND INFLUENCE-FUNCTION HELPERS
//
// Turning influence functions into standard errors: the one
// degenerate-variance rule, the panel-sum primitives, the cluster layout
// and its cached sums, and the permutation that puts influence-function
// rows back into the caller's data order.
// ===========================================================================


real scalar csdid__se_from_if(real colvector ifv)
{
    real scalar n, se, se_floor

    // R's degenerate-standard-error threshold (att_gt.R:570/593,
    // compute.aggte.R:312): at or below it the standard error is reported
    // missing rather than as a number. It is a threshold on an SE, never on a
    // variance, and it is the ONLY zero-variance floor in this file -- every
    // other site below sets the same value. The `epsilon(1)' tests in
    // csdid__rcond_fail and csdid__hessinv_r_parity are a different rule: they
    // are R's reciprocal-condition-number cut on a design matrix, not a floor
    // on a standard error, and the two must not be reconciled with each other.
    se_floor = sqrt(epsilon(1)) * 10

    n = rows(ifv)
    if (n == 0) return(.)
    se = sqrt(quadcross(ifv, ifv)) / n
    if (se <= se_floor) return(.)
    return(se)
}

// panelsum() deletes LISTWISE across columns: one missing anywhere in a row
// blanks that panel's sums in EVERY column. A blanked (g,t) cell makes its
// influence-function column all-missing by design, so under the listwise rule
// one failed cell destroys the cluster sums -- and with them every standard
// error -- of all the healthy cells too. R's rowsum() propagates NA per
// column, so summing column-by-column when the input carries missing is what
// keeps the two implementations aligned; the missing-free path keeps the
// single panelsum call bit-identically.
real matrix csdid__panelsum_bycol(real matrix xs, real matrix info)
{
    real matrix out
    real scalar j

    if (!hasmissing(xs)) return(panelsum(xs, info))
    out = J(rows(info), cols(xs), .)
    for (j = 1; j <= cols(xs); j++) out[., j] = panelsum(xs[., j], info)
    return(out)
}

real matrix csdid__cluster_sums(real colvector cluster_vec, real matrix x)
{
    real matrix info
    real colvector ord

    if (rows(cluster_vec) != rows(x) | rows(x) == 0) return(J(0, cols(x), .))
    csdid__cluster_layout(cluster_vec, ord = J(0, 1, .), info = J(0, 0, .))
    return(csdid__panelsum_bycol(x[ord, .], info))
}

// The cluster LAYOUT -- the sort permutation and the panel boundaries -- is a
// function of the cluster vector alone, and the cluster vector does not change
// across the cells of an aggregation. Computing it once and reusing it turns
// E+1 full O(n log n) sorts per aggregation into one.
//
// It is passed BY ARGUMENT rather than memoised in a global on purpose. A
// module-level cache keyed on the last cluster vector is exactly the kind of
// state that makes a result depend on what ran before it, and this package
// already has one such dependence on record: the unstable order() described
// below, which moved a clustered standard error between two runs of the same
// command in one session. The caller owns the lifetime.
void csdid__cluster_layout(real colvector cluster_vec, real colvector ord, real matrix info)
{
    real scalar n

    // The second key is the ORIGINAL ROW NUMBER, and it is not decoration.
    // Mata's order() is not stable across ties: measured, `order(cl, 1)' on
    // the same vector returns a DIFFERENT permutation depending on what Mata
    // did earlier in the process. Cluster ids are nothing but ties, so the
    // per-cluster sums were being accumulated in an order that varied with
    // session history, and the clustered standard errors moved by an ulp
    // between two runs of the identical command on the identical data. To see
    // it on a build without this second key: estimate a clustered
    // specification, run any unrelated Mata sort in the same session, estimate
    // the same specification again, and compare e(V) bit for bit.
    //
    // Ordering on (cluster, row) makes the permutation unique, so the sums
    // add in one fixed order forever. It also matches R, whose order() is a
    // stable radix sort.
    n = rows(cluster_vec)
    ord = order((cluster_vec, (1::n)), (1, 2))
    info = panelsetup(cluster_vec[ord], 1)
}

// Same sums, with the layout supplied. panelsum over the same permutation and
// the same boundaries adds the same numbers in the same order, so this is
// bit-identical to csdid__cluster_sums and not merely equivalent.
real matrix csdid__cluster_sums_pre(real colvector ord, real matrix info, real matrix x)
{
    if (rows(ord) != rows(x) | rows(x) == 0) return(J(0, cols(x), .))
    return(csdid__panelsum_bycol(x[ord, .], info))
}

void csdid__permute_if_to_data_order(
    string scalar ifname,
    string scalar idname,
    string scalar unitname,
    string scalar outname)
{
    real matrix inf, unit_group
    real colvector data_id, unit_id, order, taken
    real scalar r, idx, n_units_p, n_taken

    inf = st_matrix(ifname)
    unit_group = st_matrix(unitname)
    data_id = st_data(., idname)
    unit_id = unit_group[., 1]

    // First appearance of each unit in DATA order, mapped to its row in the
    // unit map. The previous form asked "have I seen this id?" by scanning a
    // vector that grew by one element per unit -- O(N x n_units) compares,
    // plus a reallocation and a full copy of that vector per unit, plus a
    // second growing vector for the answer.
    //
    // unit_id is ascending (it is idlevels), so membership is a binary
    // search, and "already taken" is a flag indexed by the unit's own row.
    // Same permutation, same order, no growing vectors.
    n_units_p = rows(unit_id)
    taken = J(n_units_p, 1, 0)
    order = J(n_units_p, 1, .)
    n_taken = 0
    for (r = 1; r <= rows(data_id); r++) {
        if (data_id[r] >= .) continue
        idx = csdid__sorted_index(unit_id, data_id[r])
        if (idx >= .) continue
        if (taken[idx]) continue
        taken[idx] = 1
        n_taken = n_taken + 1
        order[n_taken] = idx
    }
    if (n_taken < n_units_p) order = order[1..max((n_taken, 1))]
    if (n_taken == 0) order = J(0, 1, .)

    if (rows(order) != rows(inf)) {
        errprintf("could not align influence functions to data unit order\n")
        _error(498)
    }
    st_matrix(outname, inf[order, .])
}
// ===========================================================================
// SECTION 12 -- BOOTSTRAP STATISTICS
//
// The multiplier bootstrap's statistics in R's own definitions: the type-1
// quantile, the interquartile-range sigma, the simultaneous critical value,
// and the assembly of the ATT-level bootstrap table.
// ===========================================================================


real scalar csdid__type1_quantile(real colvector x, real scalar p)
{
    real colvector finite
    real scalar n, idx

    finite = select(x, x :< .)
    n = rows(finite)
    if (n == 0) return(.)
    finite = sort(finite, 1)
    idx = ceil(p * n)
    if (idx < 1) idx = 1
    if (idx > n) idx = n
    return(finite[idx])
}

real scalar csdid__bootstrap_sigma(real colvector bres, real scalar iqr_norm)
{
    real colvector finite
    real scalar n, idx25, idx75, if_ss, bsigma, se_floor

    // R's degenerate-SE threshold; see csdid__se_from_if.
    se_floor = sqrt(epsilon(1)) * 10

    if (sum(bres :>= .) == 0) {
        n = rows(bres)
        if_ss = quadcross(bres, bres)
        finite = sort(bres, 1)
    }
    else {
        finite = select(bres, bres :< .)
        n = rows(finite)
        if (n == 0) return(.)
        if_ss = quadcross(finite, finite)
        finite = sort(finite, 1)
    }
    if (if_ss <= se_floor) return(.)
    idx25 = max((1, min((n, ceil(.25 * n)))))
    idx75 = max((1, min((n, ceil(.75 * n)))))
    bsigma = (finite[idx75] - finite[idx25]) / iqr_norm
    if (bsigma <= se_floor) return(.)
    return(bsigma)
}

real scalar csdid__bootstrap_cband_crit(
    real matrix bres,
    real colvector bsigma,
    real scalar alp,
    real scalar pointcrit)
{
    real colvector bT, rowmax, scaled
    real scalar b, j, crit

    crit = pointcrit
    rowmax = J(rows(bres), 1, .)
    for (b = 1; b <= rows(bres); b++) {
        scaled = J(cols(bres), 1, .)
        for (j = 1; j <= cols(bres); j++) {
            if (bsigma[j] < .) scaled[j] = abs(bres[b, j] / bsigma[j])
        }
        scaled = select(scaled, scaled :< .)
        if (rows(scaled) > 0) rowmax[b] = max(scaled)
    }
    bT = select(rowmax, rowmax :< .)
    // R's aggregation-level fallbacks are LABELED, not silent: when the
    // band quantile cannot be computed, or comes back below the pointwise
    // quantile, compute.aggte warns, uses qnorm(1-alp/2) and sets
    // cband <- FALSE (so the reported band is pointwise by name). The
    // clamp below reproduces the VALUE; the scalar tells the ado which
    // fallback fired so it can reproduce the warning and the label too.
    // 1 = quantile below pointwise, 2 = no drawable max-|t| at all.
    if (rows(bT) > 0) {
        crit = csdid__type1_quantile(bT, 1 - alp)
        if (crit >= .) {
            st_numscalar("CSDID_AGG_CRIT_FALLBACK", 2)
            crit = pointcrit
        }
        else if (crit < pointcrit) {
            st_numscalar("CSDID_AGG_CRIT_FALLBACK", 1)
            crit = pointcrit
        }
    }
    else st_numscalar("CSDID_AGG_CRIT_FALLBACK", 2)
    // R warns without falling back when the band critical value is >= 7
    // (compute.aggte's very-large-crit warning); same channel, no clamp.
    if (crit < . & crit >= 7) st_numscalar("CSDID_AGG_CRIT_LARGE", 1)
    return(crit)
}

// csdid_bootstrap_attgt and csdid_bootstrap_attgt_cluster used to sit
// here: ~250 lines with no caller anywhere in the tree (csdid.ado calls
// csdid_bootstrap_attgt_fast, and there is no nofast route into them).
// They were worse than merely dead. Both ended their cband block with
//     if (crit < pointcrit) crit = pointcrit
// while the two LIVE att_gt paths carry an explicit comment saying the
// opposite -- the att_gt-level cband critical value is the raw type-1
// quantile of max-|t|, and clamping it up to the pointwise value is an
// R-parity violation. Reviving them, or copying from them, would have
// reintroduced exactly that. If a nofast fallback is ever wanted it must
// call the same summarize block the live paths use.


// ---------------------------------------------------------------------------
// #40. The step from a matrix of bootstrap draws to the reported table was
// written out twice, byte for byte: once in csdid_bootstrap_attgt_fast and
// once in csdid_boot_plugin_finish, which differ only in how they OBTAIN the
// draws. Two copies of the cluster-vs-unclustered scaling, two copies of the
// simultaneous-band quantile, two copies of the F-011 parity note, and two
// copies of the twelve-column assembly, all of which had to be kept in step by
// hand. One copy now, called from both.
//
// `att' is updated in place -- column 5 becomes the bootstrap standard error --
// which is what both callers relied on, and `crit' and `pointcrit' come back
// through their arguments because both callers post them afterwards.
// ---------------------------------------------------------------------------
real matrix csdid__boot_table(
    real matrix att,
    real matrix bres,
    real scalar n,
    real scalar nc,
    real scalar use_cluster,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    real scalar crit,
    real scalar pointcrit)
{
    real scalar j, k, iqr_norm, boot_t0, se_floor
    real colvector bsigma, seboot, seanalytic, rowmaxv, bT, active
    real matrix scaled, bootout

    // R's degenerate-SE threshold; see csdid__se_from_if.
    se_floor = sqrt(epsilon(1)) * 10

    k = rows(att)
    boot_t0 = csdid__profile_start()
    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    seanalytic = att[., 5]
    for (j = 1; j <= k; j++) {
        bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
        if (bsigma[j] < .) {
            seboot[j] = (use_cluster ? bsigma[j] * sqrt(nc) / n : bsigma[j] / sqrt(n))
        }
        // R's reported SE, exactly: att_gt l579-591 keeps the analytic NA
        // (zero_na_sd_entry) and otherwise ADOPTS the bootstrap SE -- which
        // is NA for a dimension mboot dropped, so a screened dimension must
        // not fall back on the analytic value it was computed alongside --
        // and l593 then blanks a zero SE. `seboot' stays the raw bootstrap
        // channel that e(boot_attgt) reports.
        att[j, 5] = (seanalytic[j] >= . ? . : seboot[j])
        if (att[j, 5] <= se_floor) att[j, 5] = .
    }

    pointcrit = invnormal(1 - alp / 2)  // transcribes R's qnorm(1 - alp/2); parity keeps the complement form
    crit = pointcrit
    if (cband) {
        active = csdid__selidx(bsigma :< .)
        if (rows(active) > 0) {
            scaled = J(biters, 1, 1) * bsigma[active]'
            scaled = abs(bres[., active] :/ scaled)
            rowmaxv = rowmax(scaled)
            bT = select(rowmaxv, rowmaxv :< .)
            if (rows(bT) > 0) crit = csdid__type1_quantile(bT, 1 - alp)
        }
        // F-011 R parity: att_gt-level cband crit is the raw type-1 quantile
        // of max-|t| (did::att_gt l240-266, no pointwise floor); only the
        // AGGREGATION level clamps to pointwise (compute.aggte l242-246),
        // which csdid__bootstrap_cband_crit — used only by agg kernels — keeps.
    }
    csdid__boot_profile_add(5, boot_t0, biters * k)

    boot_t0 = csdid__profile_start()
    bootout = J(k, 12, .)
    for (j = 1; j <= k; j++) {
        bootout[j, .] = (
            att[j, 1], att[j, 2], att[j, 3], att[j, 4],
            seboot[j], seanalytic[j],
            crit,
            att[j, 4] - crit * seboot[j],
            att[j, 4] + crit * seboot[j],
            pointcrit,
            att[j, 4] - pointcrit * seboot[j],
            att[j, 4] + pointcrit * seboot[j]
        )
    }
    return(bootout)
}

// ===========================================================================
// SECTION 13 -- THE BOOTSTRAP OBJECT
//
// csdid__Boot is the state one multiplier bootstrap carries: the table and
// the influence functions the draws are taken over, the policy they are taken
// under, the screen that says which columns can be drawn at all, and the
// table the draws are turned into. Its two methods are the parts both
// accelerators share -- everything before the draws, and everything after
// them -- so the all-Mata kernel and the C plugin differ in how the draws are
// OBTAINED and in nothing else.
//
// Also here: the aggregate-level assembly of a bootstrap table, which the
// three aggregation entry points share.
// ===========================================================================

// ---------------------------------------------------------------------------
// What csdid__boot_table does for ATT(g,t), at the AGGREGATION level. Three
// paths reach it -- the plugin finisher, the in-Mata kernel and its clustered
// twin -- and they differ only
// in how they build `seboot': the ten-column table, and the rule for what the
// aggregation itself reports, are the same from there on.
//
// `agg' is updated in place -- column 3 becomes the effect's bootstrap standard
// error and column 5 the overall one -- which is what all three callers rely
// on. `seboot' carries one entry per effect plus the overall column last, so
// its own length says which entry that is.
// ---------------------------------------------------------------------------
void csdid__agg_assemble_bootout(
    real matrix agg,
    real colvector seboot,
    real scalar crit,
    real scalar pointcrit,
    real matrix bootout)
{
    real scalar k_effects, k, j, se_floor

    // R's degenerate-SE threshold; see csdid__se_from_if.
    se_floor = sqrt(epsilon(1)) * 10

    k_effects = rows(agg)
    k = rows(seboot)
    // R's reported aggregate SE, exactly: under bstrap, getSE returns mboot's
    // se (compute.aggte.R l811-836), which is NA for a dimension mboot
    // dropped, so a dropped dimension must NOT fall back on the analytic
    // value it was computed alongside; each aggregation type then blanks a
    // zero SE (l312, l358/416, l505/548, l636/682). `seboot' stays the raw
    // bootstrap channel that e(boot_aggte) reports.
    for (j = 1; j <= k_effects; j++) {
        agg[j, 3] = seboot[j]
        agg[j, 5] = seboot[k]
        if (agg[j, 3] <= se_floor) agg[j, 3] = .
        if (agg[j, 5] <= se_floor) agg[j, 5] = .
    }

    bootout = J(k_effects, 10, .)
    for (j = 1; j <= k_effects; j++) {
        bootout[j, .] = (
            agg[j, 1], agg[j, 2], seboot[j],
            crit,
            agg[j, 2] - crit * seboot[j],
            agg[j, 2] + crit * seboot[j],
            pointcrit,
            agg[j, 2] - pointcrit * seboot[j],
            agg[j, 2] + pointcrit * seboot[j],
            seboot[k]
        )
    }
}

// Which columns can be DRAWN. R draws every column and judges degeneracy on
// the draws -- mboot l142, ndg.dim = !is.na(colSums(bres)) &
// colSums(bres^2) > sqrt(.Machine$double.eps)*10 -- which is exactly the test
// csdid__bootstrap_sigma applies to each drawn column. The only screen owed
// here is the one R never faces: a failed (g,t) cell is an all-missing column
// and has no draws at all. Judged per COLUMN, as ndg.dim is, so a failed cell
// drops out alone rather than taking the healthy columns' inference with it.
//
// Screening the CLUSTER SUMS against the same absolute tolerance -- as this
// did -- is a SECOND, tighter screen R does not have: the draws carry
// biters/nc times the column sum of squares, so on any run with more
// replications than clusters every column with a sum of squares in
// (tol*nc/biters, tol] lost its standard error here and kept it in R, and
// left the sup-t maximum with it, moving the band on every other cell too.
// The number of columns drawn does not move the random stream (multipliers
// are drawn per observation), so widening the keep-set is seed-neutral.
real colvector csdid__boot_drawable_cols(real matrix sc)
{
    return(csdid__selidx(colmissing(sc)' :== 0))
}

// ---------------------------------------------------------------------------
// The object itself.
//
// A bootstrap begins and ends inside one call from the ado, so this is a
// LOCAL of the entry point and never a session-lived external: nothing
// outside reads it and nothing has to survive to the next command. That is
// also why it carries no construction guard of the kind csdid__Engine needs.
// One instance per bootstrap, and the methods walk the whole draw matrix
// themselves -- a per-draw or per-column entry would pay this frame on every
// one of biters iterations.
//
// new() zero-initialises and does nothing else; each field is set by the
// method or the entry point that owns it, before anything reads it.
// ---------------------------------------------------------------------------
class csdid__Boot {
    // ---- what the draws are taken over ----
    // att is the ATT(g,t) table, updated in place: column 5 becomes the
    // bootstrap standard error. sc is what the multipliers multiply -- the
    // cluster sums under cluster(), the row-ordered influence functions
    // otherwise -- and nc is its row count, which the scaling of every
    // standard error downstream is written in terms of.
    real matrix    att
    real matrix    sc
    real scalar    n
    real scalar    nc
    real scalar    k
    real scalar    use_cluster

    // ---- the policy the draws are taken under ----
    // use_bmisc says the draws come from the seeded MT19937 stream carried in
    // rng_state rather than from Stata's own generator. The ado asks for it
    // by naming a state matrix, and the same name decides whether the
    // advanced state is handed back, so the flag and the name never disagree.
    real scalar    biters
    real scalar    alp
    real scalar    cband
    string scalar  dist
    real scalar    use_bmisc
    real rowvector rng_state

    // ---- the screen ----
    // Which columns can be drawn at all: a failed (g,t) cell is an
    // all-missing column with no draws in it. See csdid__boot_drawable_cols
    // for why that is the only screen owed here.
    real colvector active

    // ---- what the draws become ----
    real matrix    bres
    real matrix    bootout
    real scalar    crit
    real scalar    pointcrit

    void           new()
    void           preamble()
    void           finish()
}

void csdid__Boot::new()
{
    att         = J(0, 0, .)
    sc          = J(0, 0, .)
    n           = .
    nc          = .
    k           = .
    use_cluster = .

    biters      = .
    alp         = .
    cband       = .
    dist        = ""
    use_bmisc   = 0
    rng_state   = J(1, 0, .)

    active      = J(0, 1, .)

    bres        = J(0, 0, .)
    bootout     = J(0, 0, .)
    crit        = .
    pointcrit   = .
}

// ---------------------------------------------------------------------------
// Everything both att_gt bootstrap entries do before they diverge: read the
// ATT(g,t) table and the influence functions (falling back on the kernel's
// last run when the caller passes empty names), check them against each
// other and against the unit/group map, put the rows in the order R consumes
// its draws in, under cluster() align the cluster vector to that same order
// and collapse to cluster sums, and screen the columns that can be drawn.
//
// The order matters as much as the numbers: the multipliers are drawn per row,
// so a row order that differs from R's gives every draw to the wrong unit.
// Both entries have to make the same choice among the three orderings, and
// they make it here.
//
// The screen closes the preamble rather than sitting in each caller after its
// own validation, which is where the plugin path had it and the Mata path had
// it two statements later. Nothing in it can raise, so which of the callers'
// own refusals fires first is unchanged; only one of the two orderings
// survives.
// ---------------------------------------------------------------------------
void csdid__Boot::preamble(
    string scalar attname,
    string scalar ifname,
    string scalar unitname,
    string scalar timename,
    string scalar clustervecname)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix inf, unit_group
    real colvector cluster_vec, ord
    real scalar boot_t0

    csdid__boot_profile_reset()
    csdid__boot_kernel_profile_reset()
    csdid__engine_ensure()

    boot_t0 = csdid__profile_start()
    att = st_matrix(attname)
    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_ENGINE.inffunc) > 0) {
        inf = CSDID_ENGINE.inffunc
    }
    unit_group = st_matrix(unitname)
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_ENGINE.unit_group) > 0) {
        unit_group = CSDID_ENGINE.unit_group
    }
    n = rows(inf)
    k = cols(inf)
    if (n == 0 | k == 0 | k != rows(att)) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (rows(unit_group) != n | cols(unit_group) < 2) {
        errprintf("stored unit/group map does not match bootstrap influence functions\n")
        _error(498)
    }
    ord = csdid__boot_row_order(unit_group, timename, n)
    inf = inf[ord, .]
    csdid__boot_profile_add(1, boot_t0, n * k)

    boot_t0 = csdid__profile_start()
    use_cluster = (clustervecname != "")
    cluster_vec = J(0, 1, .)
    if (use_cluster) {
        cluster_vec = st_matrix(clustervecname)
        if ((rows(cluster_vec) == 0 | cols(cluster_vec) == 0) & rows(CSDID_ENGINE.cluster_vec) > 0) {
            cluster_vec = CSDID_ENGINE.cluster_vec
        }
        if (rows(cluster_vec) != n | sum(cluster_vec :>= .) > 0) {
            errprintf("cluster() could not be aligned with bootstrap influence functions\n")
            _error(498)
        }
        cluster_vec = cluster_vec[ord]
        sc = csdid__cluster_sums(cluster_vec, inf)
        nc = rows(sc)
        if (nc == 0) {
            errprintf("cluster() has no clusters in the estimation sample\n")
            _error(498)
        }
    }
    else {
        sc = inf
        nc = n
    }
    csdid__boot_profile_add(2, boot_t0, nc * k)

    boot_t0 = csdid__profile_start()
    active = csdid__boot_drawable_cols(sc)
    csdid__boot_profile_add(3, boot_t0, rows(active))
}

// ---------------------------------------------------------------------------
// Everything both att_gt bootstrap entries do after the draws exist: turn the
// draw matrix into the reported table and hand the results back to Stata.
// The two differ in one thing only, and it is the seeded stream: the Mata
// kernel advances rng_state and owes it back to the ado, the plugin path has
// no state to return. `statename' says which, exactly as it does on the way
// in -- an empty name is the caller with nothing to hand back.
// ---------------------------------------------------------------------------
void csdid__Boot::finish(
    string scalar attname,
    string scalar bootname,
    string scalar drawsname,
    string scalar statename,
    string scalar critname,
    string scalar pointcritname)
{
    real scalar boot_t0

    boot_t0 = csdid__profile_start()
    bootout = csdid__boot_table(att, bres, n, nc, use_cluster, biters, alp,
        cband, crit, pointcrit)

    st_matrix(attname, att)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    if (statename != "") st_matrix(statename, rng_state)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__boot_profile_add(6, boot_t0, biters * k)
}
// ===========================================================================
// SECTION 14 -- BOOTSTRAP ENTRY POINTS
//
// What the ado calls to run a bootstrap. csdid_bootstrap_attgt_fast is the
// all-Mata path; csdid_boot_plugin_prepare / _record / _finish and
// csdid_agg_boot_plugin_prep_vars / _finish are the halves of the C-plugin
// path at the ATT and aggregate levels. Both paths must produce the same
// draws from the same seed.
// ===========================================================================


void csdid_bootstrap_attgt_fast(
    string scalar attname,
    string scalar ifname,
    string scalar unitname,
    string scalar timename,
    string scalar clustervecname,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    class csdid__Boot scalar boot
    real matrix bres_active
    real scalar prof_t0, boot_t0

    prof_t0 = csdid__profile_start()
    boot.preamble(attname, ifname, unitname, timename, clustervecname)

    boot.biters    = biters
    boot.alp       = alp
    boot.cband     = cband
    boot.dist      = dist
    boot.rng_state = J(1, 625, .)
    boot.use_bmisc = (statename != "")
    if (boot.use_bmisc) {
        boot.rng_state = st_matrix(statename)
        // Mata's | does not short-circuit, so csdid__mt_state_absorbing is
        // called even on a mis-sized state; it returns 0 for anything
        // narrower than 625 rather than subscripting past the end.
        if (cols(boot.rng_state) != 625 | csdid__mt_state_absorbing(boot.rng_state)) {
            errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
            _error(498)
        }
    }
    if (biters < 1) {
        errprintf("wboot() reps() must be a positive integer\n")
        _error(198)
    }

    boot_t0 = csdid__profile_start()
    if (rows(boot.active) == boot.k) {
        boot.bres = csdid__bootstrap_auto(boot.sc, biters, dist, boot.rng_state, boot.use_bmisc, cband) / sqrt(boot.nc)
    }
    else {
        boot.bres = J(biters, boot.k, 0)
        if (rows(boot.active) > 0) {
            bres_active = csdid__bootstrap_auto(boot.sc[., boot.active], biters, dist, boot.rng_state, boot.use_bmisc, cband) / sqrt(boot.nc)
            boot.bres[., boot.active] = bres_active
        }
        else if (boot.use_bmisc) {
            csdid__bmisc_skipboot(boot.nc, biters, boot.rng_state)
        }
        else {
            boot.bres = csdid__bootstrap_auto(boot.sc, biters, dist, boot.rng_state, boot.use_bmisc, cband) / sqrt(boot.nc)
        }
    }
    csdid__boot_profile_add(4, boot_t0, boot.nc * biters)

    // Phase 6 measures the post step, and is timed inside finish(). Reusing
    // the draw phase's start made it re-report phase 4's elapsed time instead.
    boot.finish(attname, bootname, drawsname, statename, critname, pointcritname)
    csdid__profile_add(7, prof_t0, boot.nc * biters)
}

void csdid_boot_plugin_prepare(
    string scalar attname,
    string scalar ifname,
    string scalar unitname,
    string scalar timename,
    string scalar clustervecname,
    string scalar inputvars,
    string scalar nname,
    string scalar ncname,
    string scalar clustername,
    string scalar startedname)
{
    external real scalar CSDID_BOOT_PLUGIN_PROFILE_START
    class csdid__Boot scalar boot
    real colvector alive
    string rowvector scratchvars
    real scalar prof_t0, boot_t0, j

    prof_t0 = csdid__profile_start()
    CSDID_BOOT_PLUGIN_PROFILE_START = prof_t0
    boot.preamble(attname, ifname, unitname, timename, clustervecname)
    // The prepare step needs only att's row count, already delivered as k; the
    // finish step re-reads the table from Stata. The check keeps the
    // preamble's contract visible -- and if it ever fires, that is a csdid
    // bug, so the message says what to send rather than leaving a bare
    // conformability traceback naming an internal function.
    if (rows(boot.att) != boot.k) {
        errprintf("csdid internal error: the bootstrap preamble and the ATT(g,t) table disagree on the number of cells; please report this, with the output of csdid version, at the address in help csdid\n")
        _error(498)
    }

    // The C plugin reads the stored variables as plain doubles, so a dead
    // column (a failed cell: all-missing cluster sums) must be stored as
    // zeros, not as missings masquerading as 8.9e307. Zero columns produce
    // zero draws, and csdid__boot_table already maps a zero-variance draw
    // column to a missing standard error -- the same terminal state the
    // in-Mata partial-active path produces.
    if (rows(boot.active) < boot.k) {
        alive = J(boot.k, 1, 0)
        if (rows(boot.active) > 0) alive[boot.active] = J(rows(boot.active), 1, 1)
        for (j = 1; j <= boot.k; j++) {
            if (!alive[j]) boot.sc[., j] = J(rows(boot.sc), 1, 0)
        }
    }

    scratchvars = tokens(inputvars)
    if (cols(scratchvars) != boot.k | st_nobs() < boot.nc) {
        errprintf("the fast bootstrap could not be set up for these influence functions; re-run csdid with the nofast option\n")
        _error(498)
    }
    boot_t0 = csdid__profile_start()
    st_store((1::boot.nc), scratchvars, boot.sc)
    csdid__boot_profile_add(1, boot_t0, boot.nc * boot.k)
    st_numscalar(nname, boot.n)
    st_numscalar(ncname, boot.nc)
    st_numscalar(clustername, boot.use_cluster)
    st_numscalar(startedname, csdid__profile_start())
}

void csdid_boot_plugin_record(
    string scalar startedname,
    real scalar nc,
    real scalar biters)
{
    real scalar started

    started = st_numscalar(startedname)
    csdid__boot_profile_add(4, started, nc * biters)
}

void csdid_boot_plugin_finish(
    string scalar attname,
    string scalar bresname,
    real scalar n,
    real scalar nc,
    real scalar use_cluster,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    external real scalar CSDID_BOOT_PLUGIN_PROFILE_START
    class csdid__Boot scalar boot

    // The draws came back through Stata, so this half of the plugin path
    // rebuilds the object rather than inheriting it: prepare and finish are
    // two separate calls from the ado with a preserve/restore between them.
    boot.att         = st_matrix(attname)
    boot.bres        = st_matrix(bresname)
    boot.n           = n
    boot.nc          = nc
    boot.use_cluster = use_cluster
    boot.biters      = biters
    boot.alp         = alp
    boot.cband       = cband
    boot.k           = rows(boot.att)
    if (n < 1 | nc < 1 | rows(boot.bres) != biters | cols(boot.bres) != boot.k) {
        errprintf("the fast bootstrap returned results that do not match the ATT(g,t) estimates; re-run csdid with the nofast option\n")
        _error(498)
    }

    // Phase 6 measures the post step, and is timed inside finish(); unset,
    // its start made it report missing. There is no seeded state to hand
    // back on this path, which is what the empty state name says.
    boot.finish(attname, bootname, drawsname, "", critname, pointcritname)
    csdid__profile_add(7, CSDID_BOOT_PLUGIN_PROFILE_START, nc * biters)
}

void csdid_agg_boot_plugin_prep_vars(
    string scalar unitname,
    string scalar timename,
    real scalar use_cluster,
    string scalar inputvars,
    string scalar nname,
    string scalar ncname,
    string scalar clustername,
    string scalar startedname)
{
    // Variables-input feed for the aggregate-bootstrap plugin. The ordering
    // and cluster-collapse now live in csdid__agg_boot_assemble, shared with
    // the direct Mata driver, so the permutation R's draw order requires is
    // defined in exactly one place. The IF never leaves Mata as a Stata
    // matrix (matrix CREATION is quadratic in rows; measured 0.5s at 12,500
    // rows, 48s at 100,000): the plugin reads its input through temp
    // VARIABLES via st_store, which is linear -- exactly how the
    // estimation-stage plugin is fed.
    real matrix sc
    string rowvector scratchvars
    real scalar n, nc, k, phase_t0

    csdid__agg_boot_profile_reset()
    phase_t0 = csdid__profile_start()
    n = csdid__agg_boot_assemble(unitname, timename, use_cluster, sc = J(0, 0, .))
    nc = rows(sc)
    k = cols(sc)
    scratchvars = tokens(inputvars)
    if (cols(scratchvars) != k | st_nobs() < nc) {
        errprintf("the fast bootstrap could not be set up for this aggregation; re-run csdid with the nofast option\n")
        _error(498)
    }
    st_store((1::nc), scratchvars, sc)
    st_numscalar(nname, n)
    st_numscalar(ncname, nc)
    st_numscalar(clustername, use_cluster)
    csdid__agg_boot_profile_add(1, phase_t0, nc * k)
    st_numscalar(startedname, csdid__profile_start())
}

void csdid_agg_boot_plugin_finish(
    string scalar aggname,
    string scalar independentname,
    string scalar commonname,
    real scalar n,
    real scalar nc,
    real scalar use_cluster,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar startedname,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    external real matrix CSDID_AGG_BOOT_PROFILE
    real matrix agg, bres, common, bootout
    real colvector bsigma, bsigma_cband, seboot
    real scalar k, k_effects, j, iqr_norm, pointcrit, crit, phase_t0, scale

    CSDID_AGG_BOOT_PROFILE[2, 1] =
        (csdid__profile_start() - st_numscalar(startedname)) / 1000
    agg = st_matrix(aggname)
    bres = st_matrix(independentname)
    common = st_matrix(commonname)
    k_effects = rows(agg)
    k = cols(bres)
    if (n < 1 | nc < 1 | rows(bres) != biters | k != k_effects + 1) {
        errprintf("the fast bootstrap returned results that do not match the aggregation; re-run csdid with the nofast option\n")
        _error(498)
    }
    if (cband & (rows(common) != biters | cols(common) != k_effects)) {
        errprintf("the fast bootstrap returned simultaneous-band results that do not match the aggregation; re-run csdid with the nofast option\n")
        _error(498)
    }
    CSDID_AGG_BOOT_PROFILE[2, 2] = 1
    CSDID_AGG_BOOT_PROFILE[2, 3] = biters * nc * (k + cband * k_effects)

    phase_t0 = csdid__profile_start()
    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    scale = use_cluster ? sqrt(nc) / n : 1 / sqrt(n)
    for (j = 1; j <= k; j++) {
        bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
        if (bsigma[j] < .) seboot[j] = bsigma[j] * scale
    }

    pointcrit = invnormal(1 - alp / 2)  // transcribes R's qnorm(1 - alp/2); parity keeps the complement form
    crit = pointcrit
    if (cband) {
        bsigma_cband = J(k_effects, 1, .)
        for (j = 1; j <= k_effects; j++) {
            bsigma_cband[j] = csdid__bootstrap_sigma(common[., j], iqr_norm)
        }
        crit = csdid__bootstrap_cband_crit(common, bsigma_cband, alp, pointcrit)
    }
    csdid__agg_assemble_bootout(agg, seboot, crit, pointcrit, bootout = J(0, 0, .))

    st_matrix(aggname, agg)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__agg_boot_profile_add(3, phase_t0, biters * k)
}

// ===========================================================================
// SECTION 15 -- 32-BIT ARITHMETIC AND MT19937 TABLES
//
// Mata has no unsigned 32-bit integer type, so the generator below is built
// on doubles: modular reduction, shifts, and byte-table bitwise and/xor.
// The tables are built once into CSDID_* globals. All of it exists to
// reproduce R's Mersenne Twister bit for bit, so nothing here may be
// "simplified" into Mata's own arithmetic.
// ===========================================================================

// All zeros is the one ABSORBING state of MT19937: the twist maps it to
// itself, tempering leaves it zero, every draw comes back 0, and the
// integer conversion then returns 1 forever -- so every 31-observation
// block gets the identical sign pattern, every replication is identical,
// the interquartile range of the draws is 0 and the reported standard
// errors come back missing, with nothing raised anywhere. The state arrives
// from a Stata matrix (e(boot_rng_state) is restorable from a saved
// estimate and writable by the user), so it is reachable without a bug in
// this package. R guards the same case in FixupSeeds.
//
// The guard lives here, on the Mata loaders, and not only in the plugin:
// the plugin's refusal is swallowed by the `capture plugin call', after
// which the ado restores the state matrix and falls through to exactly this
// code.
real scalar csdid__mt_state_absorbing(real rowvector state)
{
    real scalar j

    if (cols(state) < 625) return(0)
    // element 1 is the index (csdid__bmisc_rng_init sets state[1] = 624);
    // the 624-word payload is elements 2..625.
    for (j = 2; j <= 625; j++) {
        if (state[j] != 0) return(0)
    }
    return(1)
}

// 32-bit integer arithmetic on doubles, for the MT19937 generator below.
//
// Mata passes arguments BY REFERENCE, so a helper that assigns to its own
// parameter overwrites the caller's variable. That is a live hazard for every
// routine in this group -- csdid__u32, csdid__u32_rshift, csdid__u32v,
// csdid__u32_lshiftv and the four bitwise helpers further down -- because call
// sites do pass live locals (the mask arguments in csdid__bmisc_rng_init among
// them) and those masks are read again on every subsequent pass. Each helper
// copies into a local before touching it; do not reintroduce assignment to a
// parameter anywhere in this group.
real scalar csdid__u32(real scalar x)
{
    real scalar m, v

    m = 4294967296
    v = x - floor(x / m) * m
    if (v < 0) v = v + m
    return(v)
}

real scalar csdid__u32_rshift(real scalar x, real scalar bits)
{
    return(floor(x / (2 ^ bits)))
}

real rowvector csdid__u32v(real rowvector x)
{
    real scalar m
    real rowvector v

    m = 4294967296
    v = x :- floor(x :/ m) :* m
    return(v :+ (v :< 0) :* m)
}

real rowvector csdid__u32_lshiftv(real rowvector x, real scalar bits)
{
    return(csdid__u32v(x :* (2 ^ bits)))
}

void csdid__rng_tables_init()
{
    external real matrix CSDID_AND8, CSDID_XOR8, CSDID_MT_XOR_MAG
    external real colvector CSDID_AND8F, CSDID_XOR8F, CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    external real matrix CSDID_RBITS8
    external real scalar CSDID_RNG_TABLES_READY
    real scalar bi, bj, bk, bp, ba, bb

    if (CSDID_RNG_TABLES_READY) return
    CSDID_AND8 = J(256, 256, 0)
    CSDID_XOR8 = J(256, 256, 0)
    CSDID_AND8F = J(65536, 1, 0)
    CSDID_XOR8F = J(65536, 1, 0)
    CSDID_RBITS8 = J(256, 8, -1)
    CSDID_MT_TEMPER_LO = J(65536, 1, 0)
    CSDID_MT_TEMPER_HI = J(65536, 1, 0)
    CSDID_MT_XOR_MAG = J(65536, 4, 0)
    for (bi = 0; bi < 256; bi++) {
        bp = 128
        for (bk = 1; bk <= 8; bk++) {
            if (mod(floor(bi / bp), 2) == 1) CSDID_RBITS8[bi + 1, bk] = 1
            bp = bp / 2
        }
        for (bj = 0; bj < 256; bj++) {
            bp = 1
            for (bk = 0; bk < 8; bk++) {
                ba = mod(floor(bi / bp), 2)
                bb = mod(floor(bj / bp), 2)
                if (ba == 1 & bb == 1) {
                    CSDID_AND8[bi + 1, bj + 1] = CSDID_AND8[bi + 1, bj + 1] + bp
                }
                if (ba != bb) {
                    CSDID_XOR8[bi + 1, bj + 1] = CSDID_XOR8[bi + 1, bj + 1] + bp
                }
                bp = bp * 2
            }
            CSDID_AND8F[bi * 256 + bj + 1] = CSDID_AND8[bi + 1, bj + 1]
            CSDID_XOR8F[bi * 256 + bj + 1] = CSDID_XOR8[bi + 1, bj + 1]
        }
    }
    CSDID_RNG_TABLES_READY = 1
    csdid__mt_twist_tables_init()
    csdid__mt_temper_tables_init()
}

// Reached only from csdid__bmisc_rng_twist, i.e. only from the differential
// reference tools/bench/validate-bootstrap-kernel.do exercises; the production
// twist splits the word arithmetically against the same two masks instead of
// going through the byte table.
real scalar csdid__u32_bitand(real scalar a, real scalar b)
{
    external real matrix CSDID_AND8
    real scalar out, shift, byte_a, byte_b, va, vb

    csdid__rng_tables_init()
    va = csdid__u32(a)
    vb = csdid__u32(b)
    out = 0
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(va / (2 ^ shift)), 256)
        byte_b = mod(floor(vb / (2 ^ shift)), 256)
        out = out + CSDID_AND8[byte_a + 1, byte_b + 1] * (2 ^ shift)
    }
    return(out)
}

real rowvector csdid__u32_andv(real rowvector a, real rowvector b)
{
    external real colvector CSDID_AND8F
    real rowvector out, byte_a, byte_b, idx
    real scalar shift

    csdid__rng_tables_init()
    out = J(1, cols(a), 0)
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(a :/ (2 ^ shift)), 256)
        byte_b = mod(floor(b :/ (2 ^ shift)), 256)
        idx = byte_a :* 256 :+ byte_b :+ 1
        out = out + CSDID_AND8F[idx]' :* (2 ^ shift)
    }
    return(out)
}

real scalar csdid__u32_bitxor(real scalar a, real scalar b)
{
    external real matrix CSDID_XOR8
    real scalar out, shift, byte_a, byte_b, va, vb

    csdid__rng_tables_init()
    va = csdid__u32(a)
    vb = csdid__u32(b)
    out = 0
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(va / (2 ^ shift)), 256)
        byte_b = mod(floor(vb / (2 ^ shift)), 256)
        out = out + CSDID_XOR8[byte_a + 1, byte_b + 1] * (2 ^ shift)
    }
    return(out)
}

real rowvector csdid__u32_xorv(real rowvector a, real rowvector b)
{
    external real colvector CSDID_XOR8F
    real rowvector out, byte_a, byte_b, idx
    real scalar shift

    csdid__rng_tables_init()
    out = J(1, cols(a), 0)
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(a :/ (2 ^ shift)), 256)
        byte_b = mod(floor(b :/ (2 ^ shift)), 256)
        idx = byte_a :* 256 :+ byte_b :+ 1
        out = out + CSDID_XOR8F[idx]' :* (2 ^ shift)
    }
    return(out)
}


real rowvector csdid__mt_twist_xorv(real rowvector source, real rowvector half, real rowvector odd)
{
    external real colvector CSDID_XOR8F
    external real matrix CSDID_MT_XOR_MAG
    real rowvector out, byte_source, byte_half, byte_base, byte_masked, idx
    real scalar byte_position, shift

    csdid__rng_tables_init()
    out = J(1, cols(source), 0)
    byte_position = 0
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_position = byte_position + 1
        byte_source = mod(floor(source :/ (2 ^ shift)), 256)
        byte_half = mod(floor(half :/ (2 ^ shift)), 256)
        idx = byte_source :* 256 :+ byte_half :+ 1
        byte_base = CSDID_XOR8F[idx]'
        byte_masked = CSDID_MT_XOR_MAG[idx', byte_position]'
        out = out + (byte_base :+ odd :* (byte_masked :- byte_base)) :* (2 ^ shift)
    }
    return(out)
}

void csdid__mt_twist_tables_init()
{
    external real colvector CSDID_XOR8F
    external real matrix CSDID_MT_XOR_MAG
    real colvector base
    real scalar byte_position, mask_byte, matrix_a, shift

    matrix_a = 2567483615
    base = CSDID_XOR8F
    byte_position = 0
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_position = byte_position + 1
        mask_byte = mod(floor(matrix_a / (2 ^ shift)), 256)
        CSDID_MT_XOR_MAG[., byte_position] = CSDID_XOR8F[base :* 256 :+ mask_byte :+ 1]
    }
}

real rowvector csdid__mt_temper_reference(real rowvector y)
{
    y = csdid__u32_xorv(y, floor(y :/ (2 ^ 11)))
    y = csdid__u32_xorv(y, csdid__u32_andv(csdid__u32_lshiftv(y, 7), J(1, cols(y), 2636928640)))
    y = csdid__u32_xorv(y, csdid__u32_andv(csdid__u32_lshiftv(y, 15), J(1, cols(y), 4022730752)))
    y = csdid__u32_xorv(y, floor(y :/ (2 ^ 18)))
    return(y)
}

real rowvector csdid__mt_temper_fast(real rowvector y)
{
    external real colvector CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    real rowvector lo, hi

    csdid__rng_tables_init()
    lo = mod(y, 65536) :+ 1
    hi = floor(y :/ 65536) :+ 1
    return(csdid__u32_xorv(CSDID_MT_TEMPER_LO[lo']', CSDID_MT_TEMPER_HI[hi']'))
}

real scalar csdid__mt_temper_scalar(real scalar y)
{
    external real colvector CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    real scalar lo, hi

    csdid__rng_tables_init()
    lo = mod(y, 65536) + 1
    hi = floor(y / 65536) + 1
    return(csdid__u32_bitxor(CSDID_MT_TEMPER_LO[lo], CSDID_MT_TEMPER_HI[hi]))
}

void csdid__mt_temper_tables_init()
{
    external real colvector CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    real rowvector values

    values = (0..65535)
    CSDID_MT_TEMPER_LO = csdid__mt_temper_reference(values)'
    values = (0..65535) :* 65536
    CSDID_MT_TEMPER_HI = csdid__mt_temper_reference(values)'
}
// ===========================================================================
// SECTION 16 -- THE MT19937 GENERATOR AND ITS DRAWS
//
// R's Mersenne Twister: seeding, the twist, tempering, uniforms, and the
// Rademacher draw the multiplier bootstrap consumes. csdid__bootstrap_auto
// chooses between this generator and Stata's own; the choice is free only
// when the run is unseeded, and it refuses rather than substitute a
// multiplier distribution it cannot reproduce.
// ===========================================================================


real rowvector csdid__bmisc_rng_init(real scalar seed)
{
    real rowvector state
    real scalar j

    state = J(1, 625, 0)
    seed = csdid__u32(seed)
    for (j = 1; j <= 50; j++) {
        seed = csdid__u32(69069 * seed + 1)
    }
    for (j = 1; j <= 625; j++) {
        seed = csdid__u32(69069 * seed + 1)
        state[j] = seed
    }
    state[1] = 624
    return(state)
}

// Reference implementation: no production caller. The scalar, bit-at-a-time
// twist is what tools/bench/validate-bootstrap-kernel.do checks
// csdid__bmisc_rng_twist_fast against, so a dead-code sweep must keep it.
void csdid__bmisc_rng_twist(real rowvector state)
{
    real scalar kk, y, mag
    real scalar upper_mask, lower_mask, matrix_a

    upper_mask = 2147483648
    lower_mask = 2147483647
    matrix_a = 2567483615

    for (kk = 0; kk < 227; kk++) {
        y = csdid__u32_bitand(state[kk + 2], upper_mask) + csdid__u32_bitand(state[kk + 3], lower_mask)
        mag = 0
        if (mod(y, 2) == 1) mag = matrix_a
        state[kk + 2] = csdid__u32_bitxor(csdid__u32_bitxor(state[kk + 399], csdid__u32_rshift(y, 1)), mag)
    }
    for (kk = 227; kk < 623; kk++) {
        y = csdid__u32_bitand(state[kk + 2], upper_mask) + csdid__u32_bitand(state[kk + 3], lower_mask)
        mag = 0
        if (mod(y, 2) == 1) mag = matrix_a
        state[kk + 2] = csdid__u32_bitxor(csdid__u32_bitxor(state[kk - 225], csdid__u32_rshift(y, 1)), mag)
    }
    y = csdid__u32_bitand(state[625], upper_mask) + csdid__u32_bitand(state[2], lower_mask)
    mag = 0
    if (mod(y, 2) == 1) mag = matrix_a
    state[625] = csdid__u32_bitxor(csdid__u32_bitxor(state[398], csdid__u32_rshift(y, 1)), mag)
    state[1] = 0
}

void csdid__bmisc_rng_twist_fast(real rowvector state)
{
    real rowvector s0, s1, y, half, mag, odd
    real scalar upper_mask, matrix_a

    // The scalar reference twist masks with a lower_mask constant; the
    // vectorised arithmetic below does that masking with the subtraction
    // itself, so no lower mask exists here.
    upper_mask = 2147483648
    matrix_a = 2567483615

    s0 = state[2..228]
    s1 = state[3..229]
    y = (s0 :>= upper_mask) :* upper_mask :+ s1 :- (s1 :>= upper_mask) :* upper_mask
    half = floor(y :/ 2)
    odd = (mod(y, 2) :== 1)
    state[2..228] = csdid__mt_twist_xorv(state[399..625], half, odd)

    s0 = state[229..455]
    s1 = state[230..456]
    y = (s0 :>= upper_mask) :* upper_mask :+ s1 :- (s1 :>= upper_mask) :* upper_mask
    half = floor(y :/ 2)
    odd = (mod(y, 2) :== 1)
    state[229..455] = csdid__mt_twist_xorv(state[2..228], half, odd)

    s0 = state[456..624]
    s1 = state[457..625]
    y = (s0 :>= upper_mask) :* upper_mask :+ s1 :- (s1 :>= upper_mask) :* upper_mask
    half = floor(y :/ 2)
    odd = (mod(y, 2) :== 1)
    state[456..624] = csdid__mt_twist_xorv(state[229..397], half, odd)

    y = (state[625] >= upper_mask) * upper_mask + state[2] - (state[2] >= upper_mask) * upper_mask
    half = floor(y / 2)
    mag = (mod(y, 2) == 1) * matrix_a
    state[625] = csdid__u32_bitxor(csdid__u32_bitxor(state[398], half), mag)
    state[1] = 0
}

real scalar csdid__bmisc_unif(real rowvector state)
{
    real scalar mti, y, x

    mti = state[1]
    if (mti >= 624) csdid__bmisc_rng_twist_fast(state)
    mti = state[1]
    y = state[mti + 2]
    state[1] = mti + 1

    y = csdid__mt_temper_scalar(y)

    x = y * 2.3283064365386963e-10
    if (x <= 0) return(0.5 * 2.328306437080797e-10)
    if ((1 - x) <= 0) return(1 - 0.5 * 2.328306437080797e-10)
    return(x)
}

real rowvector csdid__bmisc_unif_ints(real scalar n, real rowvector state)
{
    real rowvector out, y
    real scalar pos, mti, take, kernel_t0

    out = J(1, n, .)
    pos = 1
    while (pos <= n) {
        mti = state[1]
        if (mti >= 624) {
            kernel_t0 = csdid__profile_start()
            csdid__bmisc_rng_twist_fast(state)
            csdid__boot_kernel_profile_add(1, kernel_t0, 624)
            mti = state[1]
        }
        take = min((n - pos + 1, 624 - mti))
        y = state[(mti + 2)..(mti + take + 1)]
        state[1] = mti + take

        kernel_t0 = csdid__profile_start()
        y = csdid__mt_temper_fast(y)
        csdid__boot_kernel_profile_add(2, kernel_t0, take)

        out[pos..(pos + take - 1)] = floor((y :* 2.3283064365386963e-10) :* 2147483647) :+ 1
        pos = pos + take
    }
    return(out)
}

real colvector csdid__bmisc_bootstrap_draw(real scalar n, real rowvector state)
{
    external real matrix CSDID_RBITS8
    real colvector out
    real rowvector chunk
    real scalar k, i, nints, curr, remaining, take
    real scalar b3, b2, b1, b0

    out = J(n, 1, .)
    nints = ceil(n / 31)
    k = 1
    for (i = 1; i <= nints; i++) {
        curr = floor(csdid__bmisc_unif(state) * 2147483647) + 1
        b3 = floor(curr / (2 ^ 24))
        b2 = mod(floor(curr / (2 ^ 16)), 256)
        b1 = mod(floor(curr / (2 ^ 8)), 256)
        b0 = mod(curr, 256)
        chunk = CSDID_RBITS8[b3 + 1, 2..8], CSDID_RBITS8[b2 + 1, .], CSDID_RBITS8[b1 + 1, .], CSDID_RBITS8[b0 + 1, .]
        remaining = n - k + 1
        take = min((31, remaining))
        out[k..(k + take - 1)] = chunk[1..take]'
        k = k + take
    }
    return(out)
}

real colvector csdid__bootstrap_draw(
    real scalar n,
    string scalar dist,
    real rowvector rng_state,
    real scalar use_bmisc)
{
    real colvector u

    if (dist == "rademacher") {
        if (use_bmisc) return(csdid__bmisc_bootstrap_draw(n, rng_state))
        u = runiform(n, 1)
        return(2 :* (u :>= .5) :- 1)
    }
    if (dist == "normal" | dist == "gaussian") {
        return(rnormal(n, 1, 0, 1))
    }
    errprintf("unsupported bootstrap multiplier distribution: %s\n", dist)
    _error(498)
}


real matrix csdid__native_rboot(
    real matrix x,
    real scalar biters,
    real scalar seed)
{
    real matrix draws, out
    string scalar oldstate

    if (seed > 0) {
        oldstate = rngstate()
        uniformseed(seed)
    }
    draws = 2 :* (runiform(biters, rows(x)) :>= .5) :- 1
    out = draws * x
    if (seed > 0) rngstate(oldstate)
    return(out)
}

real matrix csdid__native_rboot_rows(
    real matrix x,
    real scalar biters)
{
    real matrix draws
    real scalar n

    n = rows(x)
    draws = runiform(n * biters, 1)
    draws = 2 :* (draws :>= .5) :- 1
    draws = rowshape(draws, biters)
    return(draws * x)
}

real matrix csdid__native_rboot_indep(
    real matrix x,
    real scalar biters)
{
    real matrix draws, out
    real scalar n, k, j

    n = rows(x)
    k = cols(x)
    out = J(biters, k, .)
    for (j = 1; j <= k; j++) {
        draws = runiform(biters, n)
        draws = 2 :* (draws :>= .5) :- 1
        out[., j] = draws * x[., j]
    }
    return(out)
}

real matrix csdid__bootstrap_auto(
    real matrix x,
    real scalar biters,
    string scalar dist,
    real rowvector rng_state,
    real scalar use_bmisc,
    real scalar cband)
{
    real matrix out
    real colvector draw
    real scalar b, n, seed

    n = rows(x)
    if (dist == "rademacher" & !use_bmisc & n * biters <= 20000000) {
        if (cband) return(csdid__native_rboot_rows(x, biters))
        seed = 0
        out = csdid__native_rboot(x, biters, seed)
        return(out)
    }
    if (use_bmisc) {
        // csdid__bmisc_bootstrap_auto only ever produces Rademacher +/-1
        // draws, and this branch used to be taken for ANY dist once a seed
        // was present -- so a seeded call asking for normal multipliers got
        // Rademacher ones, silently, behind an argument the surface accepts
        // and threads through eleven functions. Nothing diverges today only
        // because the ado refuses non-Rademacher up front; the kernel must
        // not depend on a caller it does not control. Loud refusal over
        // silent substitution.
        if (dist != "rademacher") {
            errprintf("seeded bootstrap draws are available only for rademacher multipliers; the requested %s multipliers cannot be reproduced from a stored state\n", dist)
            _error(498)
        }
        return(csdid__bmisc_bootstrap_auto(x, biters, rng_state))
    }

    out = J(biters, cols(x), .)
    for (b = 1; b <= biters; b++) {
        draw = csdid__bootstrap_draw(n, dist, rng_state, use_bmisc)
        out[b, .] = draw' * x
    }
    return(out)
}
// ===========================================================================
// SECTION 17 -- R'S BOOTSTRAP DRAW ORDER
//
// R draws over units in ITS unit order, not the caller's, so a seeded run
// reproduces R only if the rows are permuted first. These routines build
// that permutation for the balanced-panel, repeated-cross-section and
// unbalanced cases, and apply it to the influence functions and the cluster
// vector together.
// ===========================================================================


// ---------------------------------------------------------------------------
// Which of the three orders this run needs. Four callers ask the question --
// the estimation bootstrap's preamble, the aggregate bootstrap's, and the two
// reorder entries below -- and they must all answer it the same way, because
// a seeded run that permutes its rows differently from the run it is compared
// against consumes the multiplier draws in a different order and reproduces
// nothing.
//
// An empty `timename' means the caller has no time variable, i.e. this is not
// a repeated cross-section. `n' is the row count the order must cover.
//
// The two period-major orders read their key from COLUMN 4 of the unit/group
// map, where csdid__group_probs cached it at estimation time: each unit's
// first-appearance period on the allow_unbalanced path (F-001/F-022, see
// csdid__boot_order_unbal), the observation's own period in a repeated cross
// section (see csdid__boot_order_rc). The column count says only whether a
// key is there; WHICH key it is follows `timename', which every caller sets
// from the same question the producer branches on -- whether ivar() was
// given. A balanced panel carries no key and needs none.
//
// What that branch can and cannot get wrong, measured 2026-08-15 over 4,000
// random shapes: handed the SAME key and cohorts that are zero or positive,
// the two orders return the IDENTICAL permutation. So the branch decides
// which key is MEANT, never which permutation a key produces, and only the
// producer can pair a row with the wrong period. They stay two functions
// anyway -- the agreement is a property of the inputs this package builds,
// not of the routines: a negative cohort value is ordered by one and refused
// by the other.
//
// The st_data() fallback below is for a map that predates the cached key. It
// re-reads the period values from the LIVE dataset at the map's stored
// observation POSITIONS, which is correct only while the data sit where the
// estimation left them; a sort, merge or collapse in between silently pairs
// periods with the wrong cached rows and moves the reported standard error.
// Nothing this package writes reaches it any more.
// ---------------------------------------------------------------------------
real colvector csdid__boot_row_order(
    real matrix unit_group,
    string scalar timename,
    real scalar n)
{
    real colvector group, tt

    group = unit_group[., 2]
    if (timename != "") {
        if (cols(unit_group) >= 4) {
            return(csdid__boot_order_rc(unit_group[., 4], group))
        }
        tt = st_data(unit_group[., 1], timename)
        if (rows(tt) != n) {
            errprintf("could not align repeated-cross-section bootstrap rows to time()\n")
            _error(498)
        }
        return(csdid__boot_order_rc(tt, group))
    }
    if (cols(unit_group) >= 4) {
        return(csdid__boot_order_unbal(unit_group[., 4], group))
    }
    return(csdid__boot_order_panel(group))
}

// ---------------------------------------------------------------------------
// What both reorder entries do: read the influence functions and the unit map
// (either named, or from the cache when the run stored lean), put the rows in
// R's draw order, and write the influence functions and the cluster vector
// back under that one permutation. The entries differ in nothing but which
// order they ask for, which is `timename' -- so they are two names on this.
//
// CAUTION: the empty-read fallback below substitutes the ESTIMATION influence
// functions. That is the designed lean-storage path for the estimation-stage
// callers, but it must never see the AGGREGATE flow: both IF sets have
// n_units rows, so the shape guard cannot tell them apart. The aggregate flow
// therefore never reaches either entry with a lean-empty name -- fresh-fit
// estat goes through csdid_bootstrap_aggte_direct (no names at all), and the
// saved-RIF legacy path materializes the named matrix before calling here.
// ---------------------------------------------------------------------------
void csdid__boot_reorder(
    string scalar timename,
    string scalar unitname,
    string scalar ifname,
    string scalar clustername,
    string scalar outifname,
    string scalar outclustername)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix inf, unit_group
    real colvector cluster_vec, ord

    csdid__engine_ensure()

    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_ENGINE.inffunc) > 0) {
        inf = CSDID_ENGINE.inffunc
    }
    unit_group = st_matrix(unitname)
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_ENGINE.unit_group) > 0) {
        unit_group = CSDID_ENGINE.unit_group
    }
    if (rows(unit_group) != rows(inf) | cols(unit_group) < 2) {
        errprintf("stored unit/group map does not match bootstrap influence functions\n")
        _error(498)
    }

    ord = csdid__boot_row_order(unit_group, timename, rows(inf))
    st_matrix(outifname, inf[ord, .])

    if (clustername != "") {
        cluster_vec = st_matrix(clustername)
        if ((rows(cluster_vec) == 0 | cols(cluster_vec) == 0) & rows(CSDID_ENGINE.cluster_vec) > 0) {
            cluster_vec = CSDID_ENGINE.cluster_vec
        }
        if (rows(cluster_vec) != rows(inf)) {
            errprintf("cluster() could not be aligned with bootstrap influence functions\n")
            _error(498)
        }
        st_matrix(outclustername, cluster_vec[ord])
    }
}

void csdid_boot_reorder_r(
    string scalar unitname,
    string scalar ifname,
    string scalar clustername,
    string scalar outifname,
    string scalar outclustername)
{
    csdid__boot_reorder("", unitname, ifname, clustername, outifname,
        outclustername)
}

real colvector csdid__boot_order_panel(real colvector group)
{
    real scalar n

    // Treated cohorts ascending, never-treated last, original row order
    // within a cohort. That used to be a loop that ran csdid__selidx() -- a
    // full O(N) pass -- once per cohort, and concatenated the answer onto a
    // growing vector each time.
    //
    // One sort gives the identical permutation. The 1e100 offset moves the
    // never-treated bucket past every real cohort value; the row number is
    // the third key because Mata's order() is NOT stable across ties, and
    // this permutation decides which multiplier draw lands on which unit --
    // an unstable sort here would be a reproducibility defect in the
    // bootstrap, not a rounding one.
    n = rows(group)
    if (n == 0) return(J(0, 1, .))
    return(order((group :+ (group :== 0) :* 1e100, (1::n)), (1, 2)))
}

real colvector csdid__boot_order_rc(real colvector tt, real colvector group)
{
    real scalar n

    // Period ascending, then treated cohorts ascending with never-treated
    // last, then original row order. The loop this replaces ran two nested
    // full-length passes per (period x cohort) cell -- O(N x T x G) work, and
    // a growing concatenation per cell -- for a permutation one sort
    // produces. See csdid__boot_order_panel for the keys.
    n = rows(group)
    if (n == 0) return(J(0, 1, .))
    return(order((tt, group :+ (group :== 0) :* 1e100, (1::n)), (1, 2, 3)))
}

real colvector csdid__boot_order_unbal(real colvector p1, real colvector group)
{
    // F-001 / F-022: R did 2.5.1 unit order on the allow_unbalanced path.
    // pre_process_did's pseudo-RC conversion (.rowid = id) processes rows
    // period-major, so the effective unit order is FIRST-APPEARANCE PERIOD
    // ascending, then treated cohorts ascending with never-treated last, then
    // original (id) order within a cell.
    //
    // F-022: this used to key on a BINARY present-in-first-period flag, i.e.
    // one block for present units and one for absent ones. That collapses all
    // absent units into a single block regardless of when they actually enter,
    // and is only equivalent to R when sorting the absent block by (cohort, id)
    // happens to agree with sorting it by (entry period, cohort, id). It does
    // agree on F02 (one entry period) and F25u (no absent units) — and, by
    // coincidence, on F11 — which is why S032/S059/S060/S064/S066/S096/S097 all
    // passed. It does not agree on F27f, where absent units enter at two
    // periods and the permutations differ at 13 of 60 positions: witness S279,
    // att bit-identical but se off by 5.92e-02.
    //
    // p1 now carries the first-appearance PERIOD VALUE, not a flag. Units
    // present in the first period take the minimum value and so still sort
    // first, which makes the present/absent split a special case of the general
    // rule rather than a separate branch.
    real colvector plevels, glevels, ord, idx
    real scalar b, j

    plevels = uniqrows(p1)                   // ascending first-appearance periods
    glevels = uniqrows(select(group, group :> 0))
    ord = J(0, 1, .)
    for (b = 1; b <= rows(plevels); b++) {
        for (j = 1; j <= rows(glevels); j++) {
            idx = csdid__selidx((p1 :== plevels[b]) :& (group :== glevels[j]))
            if (rows(idx) > 0) ord = ord \ idx
        }
        idx = csdid__selidx((p1 :== plevels[b]) :& (group :== 0))
        if (rows(idx) > 0) ord = ord \ idx
    }
    if (rows(ord) != rows(group)) {
        errprintf("unbalanced bootstrap order could not be constructed\n")
        _error(498)
    }
    return(ord)
}

void csdid_boot_reorder_rc_r(
    string scalar timename,
    string scalar unitname,
    string scalar ifname,
    string scalar clustername,
    string scalar outifname,
    string scalar outclustername)
{
    // This entry is the repeated-cross-section one, and the shared chooser
    // reads an empty name as "no time variable, so not a repeated cross
    // section" and would hand back the PANEL order. Refuse here instead: the
    // caller that reaches this entry without time() has nothing to reorder by,
    // and a silently wrong draw order reproduces nothing and says nothing.
    if (timename == "") {
        errprintf("could not align repeated-cross-section bootstrap rows to time()\n")
        _error(498)
    }
    csdid__boot_reorder(timename, unitname, ifname, clustername, outifname,
        outclustername)
}
// ===========================================================================
// SECTION 18 -- DRAW MATRICES AND THE RNG-ADVANCE SHIMS
//
// The dense and blocked multiplier-draw matrices, and the shims that
// advance the generator by exactly the number of draws a path consumed, so
// a later path sees the state R would see.
// ===========================================================================


real matrix csdid__bmisc_boot_dense_indep(
    real matrix x,
    real scalar biters,
    real rowvector state)
{
    external real matrix CSDID_RBITS8
    real matrix chunks, draws, out
    real rowvector currs, cj, b3, b2, b1, b0
    real scalar n, k, nints, j, c1, c2

    csdid__rng_tables_init()
    n = rows(x)
    k = cols(x)
    nints = ceil(n / 31)

    // The draw stream is still taken in ONE call, so the random state
    // advances exactly as before and every column gets exactly the integers
    // it got before.
    currs = csdid__bmisc_unif_ints(biters * nints * k, state)

    // What changed is that the sign matrix is materialized one COLUMN of x at
    // a time rather than for all k at once.
    //
    // Before: `chunks' is (biters * nints * k) x 31 -- n * biters * k doubles,
    // 2GB at the threshold that routes work here -- built by a four-way
    // horizontal concatenation whose left-to-right intermediates (7, 15, 23,
    // 31 columns) are themselves live; then rowshape() makes a SECOND full
    // copy with `chunks' still in scope, and the trim to n columns makes a
    // THIRD. Peak was several times the 2GB, on a path with no other guard.
    //
    // Each column's integers occupy a CONTIGUOUS slice of `currs' -- row
    // (j-1)*biters + b of the reshaped matrix reads chunk rows
    // ((j-1)*biters + b - 1)*nints + 1 .. -- so slicing by column needs no
    // reordering and no extra draws. Peak becomes O(n * biters) instead of
    // O(n * biters * k), and the total work is unchanged: the same gathers,
    // the same reshape, the same multiply, in the same order.
    out = J(biters, k, .)
    for (j = 1; j <= k; j++) {
        c1 = (j - 1) * biters * nints + 1
        c2 = j * biters * nints
        cj = currs[c1..c2]
        b3 = floor(cj / (2 ^ 24))
        b2 = mod(floor(cj / (2 ^ 16)), 256)
        b1 = mod(floor(cj / (2 ^ 8)), 256)
        b0 = mod(cj, 256)
        chunks = CSDID_RBITS8[b3' :+ 1, 2..8], CSDID_RBITS8[b2' :+ 1, .], CSDID_RBITS8[b1' :+ 1, .], CSDID_RBITS8[b0' :+ 1, .]
        draws = rowshape(chunks, biters)
        chunks = J(0, 0, .)
        if (cols(draws) > n) draws = draws[., 1..n]
        out[., j] = draws * x[., j]
        draws = J(0, 0, .)
    }
    return(out)
}

real matrix csdid__bmisc_bootstrap_matrix(
    real matrix x,
    real scalar biters,
    real rowvector state)
{
    external real matrix CSDID_RBITS8
    real matrix out, outb, top, b2tab, b1tab, b0tab, currmat, xb
    real rowvector currs
    real colvector curr, b3, b2, b1, b0
    real scalar n, k, nints, p, start, pos, len, blocksize, jlo, jhi, kb

    csdid__rng_tables_init()
    n = rows(x)
    k = cols(x)
    nints = ceil(n / 31)
    out = J(biters, k, 0)

    // BLOCKED OVER COLUMNS.
    //
    // The four lookup tables are nints*896 rows deep and as WIDE AS x, i.e.
    // 28.9 * n * k doubles -- 28.9 times the input matrix. At n = 100,000 and
    // biters = 1000 that is 23.1MB per column: 231MB at k = 10, 1.16GB at
    // k = 50, 2.31GB at k = 100. The selector that routes work here looks at
    // rows(x) and biters and never at cols(x), so the widest jobs got the
    // widest tables.
    //
    // Building them a column block at a time caps table memory at
    // 23.1MB * blocksize regardless of k. Every output element is still the
    // same four table entries added in the same order, so the result is
    // bit-identical, not merely equivalent.
    //
    // The block is at least 8 columns wide because the per-chunk byte decode
    // below (b3/b2/b1/b0 from currmat) does not depend on k and is repeated
    // once per block: at blocksize 1 that redundant decode would roughly
    // double the accumulation work. At 8 it is under a tenth of it, and a job
    // narrower than 8 columns runs as a single block and is untouched.
    // Block ONLY when the unblocked tables would be large. Below the budget
    // the whole matrix is one block and this kernel behaves exactly as it did
    // -- same allocations, same timing -- so no ordinary job pays for the
    // guard. Above it, peak table memory is capped at the budget instead of
    // growing without limit in k.
    //
    // Blocking is not free: it rebuilds the per-chunk tables once per block,
    // and measured on a 100,000 x 40 job it costs about 2.6x the time to save
    // about 2.9x the memory. That is a good trade only where the alternative
    // is allocating hundreds of megabytes -- possibly more than the machine
    // has -- which is exactly what the budget selects for.
    //
    // Measured both ways on a 100,000 x 40 job: unblocked 3.66s / 1.01GB,
    // blocked into 4 pieces 7.23s / 0.47GB. Blocking is therefore close to a
    // 1:1 trade of time for memory, which makes it a SAFETY VALVE rather than
    // a default -- worth taking only when the alternative is an allocation
    // large enough to fail. The budget is set so that everything which works
    // today is untouched and the ceiling stops being unbounded in k:
    //
    //   128,000,000 doubles = 1GB of tables.
    //     k = 40,  n = 100,000  ->  115M doubles, single block, unchanged
    //     k = 100, n = 100,000  ->  289M doubles, 3 blocks, ~1GB not 2.3GB
    //     k = 200, n = 100,000  ->  578M doubles, 5 blocks, ~1GB not 4.6GB
    //
    // The floor of 8 columns keeps the repeated per-chunk table build from
    // dominating on very deep tables.
    blocksize = k
    if (nints * 896 > 0 & nints * 896 * k > 128000000) {
        blocksize = floor(128000000 / (nints * 896))
        if (blocksize < 8) blocksize = 8
        if (blocksize > k) blocksize = k
    }

    currs = csdid__bmisc_unif_ints(biters * nints, state)
    currmat = rowshape(currs, biters)

    for (jlo = 1; jlo <= k; jlo = jlo + blocksize) {
        jhi = min((jlo + blocksize - 1, k))
        kb = jhi - jlo + 1
        top = J(nints * 128, kb, 0)
        b2tab = J(nints * 256, kb, 0)
        b1tab = J(nints * 256, kb, 0)
        b0tab = J(nints * 256, kb, 0)
        // The block's columns are lifted out ONCE. Slicing x with a column
        // range inside the chunk loop makes every one of the nints * 4 row
        // slices a strided gather instead of a contiguous read, which
        // measured 2.3x SLOWER than the unblocked kernel even as it cut peak
        // memory. One n x kb copy (6.4MB at n = 100,000, kb = 8) buys the
        // contiguous slicing back.
        xb = x[., jlo..jhi]

        for (p = 1; p <= nints; p++) {
            start = (p - 1) * 31 + 1

            len = min((7, n - start + 1))
            if (len > 0) {
                top[((p - 1) * 128 + 1)..(p * 128), .] =
                    CSDID_RBITS8[1..128, 2..(len + 1)] * xb[start..(start + len - 1), .]
            }

            pos = start + 7
            len = min((8, n - pos + 1))
            if (len > 0) {
                b2tab[((p - 1) * 256 + 1)..(p * 256), .] =
                    CSDID_RBITS8[., 1..len] * xb[pos..(pos + len - 1), .]
            }

            pos = start + 15
            len = min((8, n - pos + 1))
            if (len > 0) {
                b1tab[((p - 1) * 256 + 1)..(p * 256), .] =
                    CSDID_RBITS8[., 1..len] * xb[pos..(pos + len - 1), .]
            }

            pos = start + 23
            len = min((8, n - pos + 1))
            if (len > 0) {
                b0tab[((p - 1) * 256 + 1)..(p * 256), .] =
                    CSDID_RBITS8[., 1..len] * xb[pos..(pos + len - 1), .]
            }
        }

        outb = J(biters, kb, 0)
        for (p = 1; p <= nints; p++) {
            curr = currmat[., p]
            b3 = floor(curr :/ (2 ^ 24))
            b2 = mod(floor(curr :/ (2 ^ 16)), 256)
            b1 = mod(floor(curr :/ (2 ^ 8)), 256)
            b0 = mod(curr, 256)
            // Four statements rather than one four-term sum. Addition is
            // left-associative either way, so every element is the same four
            // terms added in the same order -- but only one gathered block is
            // live at a time instead of four.
            outb = outb + top[(p - 1) * 128 :+ b3 :+ 1, .]
            outb = outb + b2tab[(p - 1) * 256 :+ b2 :+ 1, .]
            outb = outb + b1tab[(p - 1) * 256 :+ b1 :+ 1, .]
            outb = outb + b0tab[(p - 1) * 256 :+ b0 :+ 1, .]
        }
        out[., jlo..jhi] = outb
    }
    return(out)
}

real matrix csdid__bmisc_bootstrap_auto(
    real matrix x,
    real scalar biters,
    real rowvector state)
{
    // The `biters <= 64' branch used to send large-n, few-replication jobs to a
    // third kernel that accumulated one replication at a time. It was slower
    // AND less accurate than the table kernel at every size measured -- 12.0s
    // against 0.64s on 20,000 units by 499 replications, and 5.0e-15 against
    // 2.5e-15 relative error versus a quad-precision reference -- so there was
    // no configuration in which it was the right choice.
    //
    // It also produced a backwards performance cliff that a user could hit
    // without knowing the kernel existed: asking for FEWER replications made
    // the command slower. Measured on 60,000 units, reps(64) took 6.279s and
    // reps(65) took 2.451s, because 64 fell into that branch and 65 did not.
    // One kernel, no routing. The size threshold that used to send small
    // problems to the dense kernel is gone, and with it the last place where
    // csdid's own answer depended on something other than the data, the
    // options and the seed: the two kernels sum the same terms in different
    // orders, so a job that crossed the threshold moved in its last digits.
    // Nothing observable -- the selector was a pure function of the inputs, so
    // no user could see two answers for one command -- but it was a
    // reproducibility contract that had to be frozen, documented and never
    // touched, and it blocked routing the table kernel on cols(x).
    //
    // The table kernel is also the more accurate of the two: against a
    // quad-precision reference, 2.5e-15 relative against the dense kernel's
    // 2.2e-14.
    //
    // It costs something, and the cost is real rather than theoretical. On the
    // range the dense kernel used to serve, the whole bootstrap command
    // measured 1.36x slower at 1,250 units, 1.58x at 5,000 and 1.75x at 10,000
    // -- 0.171s to 0.299s at the top of that range. That lands on unseeded
    // bootstraps and on platforms where the C plugin cannot load, since every
    // seeded run with a working plugin goes through the plugin instead. An
    // unseeded bootstrap is not reproducible in the first place, which is the
    // case where a last-digit difference matters least.
    return(csdid__bmisc_bootstrap_matrix(x, biters, state))
}

void csdid__bmisc_skipboot(
    real scalar n,
    real scalar biters,
    real rowvector state)
{
    real scalar remaining, mti, take

    remaining = ceil(n / 31) * biters
    while (remaining > 0) {
        mti = state[1]
        if (mti >= 624) {
            csdid__bmisc_rng_twist_fast(state)
            mti = state[1]
        }
        take = min((remaining, 624 - mti))
        state[1] = mti + take
        remaining = remaining - take
    }
}

// Advance a stored multiplier state by exactly one bootstrap block of n
// units x biters replications, in place. The type(simple) plugin call
// consumes an overall-column block that R's single-mboot simple aggregation
// never draws (compute.aggte.R:310); the ado rewinds to the pre-call state
// and calls this once so the state it reports is the one R's stream holds.
void csdid_bmisc_skiponce(
    real scalar n,
    real scalar biters,
    string scalar statename)
{
    real rowvector rng_state

    rng_state = st_matrix(statename)
    if (cols(rng_state) != 625 | csdid__mt_state_absorbing(rng_state)) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    if (n < 1 | biters < 1) _error(498)
    csdid__bmisc_skipboot(n, biters, rng_state)
    st_matrix(statename, rng_state)
}

void csdid_bmisc_aggskip(
    string scalar ifname,
    real scalar biters,
    real scalar cband,
    string scalar statename)
{
    real matrix inf
    real rowvector rng_state
    real scalar n, k_effects, skip_calls, j

    inf = st_matrix(ifname)
    rng_state = st_matrix(statename)
    // Mata's | does not short-circuit, so csdid__mt_state_absorbing is
    // called even on a mis-sized state; it returns 0 for anything
    // narrower than 625 rather than subscripting past the end.
    if (cols(rng_state) != 625 | csdid__mt_state_absorbing(rng_state)) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    n = rows(inf)
    k_effects = cols(inf) - 1
    if (n == 0 | k_effects < 1 | biters < 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }

    skip_calls = k_effects + 1
    if (cband) skip_calls = skip_calls + 1
    for (j = 1; j <= skip_calls; j++) csdid__bmisc_skipboot(n, biters, rng_state)
    st_matrix(statename, rng_state)
}

void csdid_bmisc_attgtskip(
    string scalar ifname,
    real scalar biters,
    string scalar statename)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix inf
    real rowvector rng_state
    real scalar n

    csdid__engine_ensure()

    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_ENGINE.inffunc) > 0) {
        inf = CSDID_ENGINE.inffunc
    }
    rng_state = st_matrix(statename)
    // Mata's | does not short-circuit, so csdid__mt_state_absorbing is
    // called even on a mis-sized state; it returns 0 for anything
    // narrower than 625 rather than subscripting past the end.
    if (cols(rng_state) != 625 | csdid__mt_state_absorbing(rng_state)) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    n = rows(inf)
    if (n == 0 | biters < 1) {
        errprintf("stored influence functions do not match bootstrap results\n")
        _error(498)
    }

    csdid__bmisc_skipboot(n, biters, rng_state)
    st_matrix(statename, rng_state)
}

void csdid_bmisc_skipdraws(
    real scalar ndraws,
    string scalar statename)
{
    real rowvector rng_state
    real scalar remaining, mti, take

    rng_state = st_matrix(statename)
    // Mata's | does not short-circuit, so csdid__mt_state_absorbing is
    // called even on a mis-sized state; it returns 0 for anything
    // narrower than 625 rather than subscripting past the end.
    if (cols(rng_state) != 625 | csdid__mt_state_absorbing(rng_state)) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    remaining = ndraws
    while (remaining > 0) {
        mti = rng_state[1]
        if (mti >= 624) {
            csdid__bmisc_rng_twist_fast(rng_state)
            mti = rng_state[1]
        }
        take = min((remaining, 624 - mti))
        rng_state[1] = mti + take
        remaining = remaining - take
    }
    st_matrix(statename, rng_state)
}

void csdid_bmisc_labelse(
    string scalar ifname,
    real scalar biters,
    real scalar cband,
    string scalar statename,
    string scalar outname)
{
    real matrix inf, bres
    real rowvector rng_state
    real scalar n, k, k_effects, skip_calls, j, iqr_norm, bsigma, seboot

    inf = st_matrix(ifname)
    rng_state = st_matrix(statename)
    // Mata's | does not short-circuit, so csdid__mt_state_absorbing is
    // called even on a mis-sized state; it returns 0 for anything
    // narrower than 625 rather than subscripting past the end.
    if (cols(rng_state) != 625 | csdid__mt_state_absorbing(rng_state)) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    n = rows(inf)
    k = cols(inf)
    k_effects = k - 1
    if (n == 0 | k_effects < 1 | biters < 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }

    skip_calls = k_effects
    if (cband) skip_calls = skip_calls + 1
    for (j = 1; j <= skip_calls; j++) csdid__bmisc_skipboot(n, biters, rng_state)

    // One kernel here too. This site carried its own size threshold, a second
    // place where crossing a boundary moved the answer's last digits.
    bres = csdid__bmisc_bootstrap_auto(inf[., k], biters, rng_state) / sqrt(n)
    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = csdid__bootstrap_sigma(bres[., 1], iqr_norm)
    seboot = .
    if (bsigma < .) seboot = bsigma / sqrt(n)
    st_numscalar(outname, seboot)
    st_matrix(statename, rng_state)
}
// ===========================================================================
// SECTION 19 -- AGGREGATION
//
// The simple, group, calendar and dynamic aggregations, the weights and
// influence functions each implies, and their analytical and bootstrap
// standard errors. csdid__Agg -- the state one aggregation carries, the index
// and weight kernels it is built from, and the four types as four methods --
// comes first, then the entry points the ado calls.
// ===========================================================================


// ---------------------------------------------------------------------------
// The aggregation object.
//
// One aggregation, and separately one aggregation bootstrap, begins and ends
// inside a single call from the ado, so this is a LOCAL of the entry point and
// never a session-lived external. Nothing it holds has to survive to the next
// command: what does -- the aggregate influence functions and the token saying
// which estimation they belong to -- is written to csdid__Engine, which is
// where the postestimation layer reads it back from. So this object needs no
// construction guard of the kind csdid__Engine carries, for the same reason
// csdid__Boot needs none.
//
// Four groups of state on the aggregation side. What is being aggregated: the
// ATT(g,t) table, the influence functions, the unit map and the group
// probabilities. The window and balance rule the caller asked for, together
// with where the inputs come from and where the results go. The cluster vector
// and the sort layout every cell of the aggregation shares. And the effects
// the aggregation produces, with their influence maps. Three more on the
// bootstrap side: what the draws are taken over, the policy they are taken
// under with the seeded stream they come from, and the band and standard
// errors they become.
//
// THE TWO CORES STAY TWO. core() divides every standard error by sqrt(n) over
// the influence functions themselves; cluster_core() multiplies by sqrt(nc)/n
// over the cluster sums, and reaches the one-draw-block rule for type(simple)
// down a different branch. The eighteen lines they genuinely share are already
// one routine (csdid__agg_assemble_bootout). What is left differs in the
// arithmetic that produces every reported standard error, so unifying it would
// put a scaling branch inside the loop that produces them, on the hot path, to
// save eighteen lines that are already shared.
//
// Methods are entered once per aggregation or once per effect -- there are
// tens of effects on the widest event study -- and never per unit or per draw:
// the index and weight kernels walk the kept cells themselves, the draw
// kernels they call stay free functions on locals, and the two cores walk the
// whole draw matrix themselves, as csdid__Boot's methods do.
//
// new() zero-initialises and does nothing else; each field is set by the
// method or the entry point that owns it, before anything reads it.
// ---------------------------------------------------------------------------
class csdid__Agg {
    // ---- what is being aggregated ----
    // attgt keeps the posted columns; the four every branch reads are split
    // out beside it. inffunc is one row per UNIT and one column per (g,t)
    // cell, which is what the storage policy in store() exists for.
    real matrix    attgt
    real matrix    inffunc
    real matrix    group_prob
    real matrix    unit_map
    real colvector group
    real colvector tt
    real colvector event_time
    real colvector att
    real colvector pg
    real colvector unit_group
    real colvector unit_weight
    real colvector glist
    real colvector pgg

    // ---- the window, the balance rule, and where the inputs come from ----
    // use_cache says the influence functions live on the engine rather than in
    // e(): that is the lean-storage default, and its opposite is the full
    // storage and saved-RIF route where they genuinely are Stata matrices.
    // store_large is the same decision on the way out.
    string scalar  type
    real scalar    min_e
    real scalar    max_e
    real scalar    balance_e
    real scalar    na_rm
    real scalar    use_cache
    string scalar  outname
    string scalar  ifname
    real scalar    store_large

    // ---- the cluster vector, and the layout every cell shares ----
    real scalar    use_cluster
    real colvector cluster_vec
    real colvector cl_ord
    real matrix    cl_info

    // ---- what the aggregation produces ----
    real colvector egt
    real colvector tgrid_full
    real colvector effects
    real colvector ses
    real matrix    effect_if_mat
    real scalar    overall_att
    real scalar    overall_se
    real colvector overall_if
    real matrix    out

    // ---- the bootstrap: what the draws are taken over ----
    // agg is the table csdid_aggte wrote, updated in place: column 3 becomes
    // the effect's bootstrap standard error and column 5 the overall one. sc
    // is what the multipliers multiply -- the cluster sums under cluster(),
    // the row-ordered aggregate influence functions otherwise -- so n, the
    // UNIT count the clustered scaling is written in terms of, is NOT rows(sc)
    // on that branch and is carried separately.
    real matrix    agg
    real matrix    sc
    real scalar    n
    real scalar    nc
    real scalar    k
    real scalar    k_effects

    // ---- the policy the draws are taken under ----
    // use_bmisc says the draws come from the seeded MT19937 stream carried in
    // rng_state rather than from Stata's own generator. The ado asks for it by
    // naming a state matrix, and the same name decides whether the advanced
    // state is handed back, so the flag and the name never disagree.
    real scalar    biters
    real scalar    alp
    real scalar    cband
    string scalar  dist
    real scalar    is_simple
    real scalar    use_bmisc
    real rowvector rng_state

    // ---- the band, and what the draws become ----
    real matrix    bres
    real matrix    bootout
    real scalar    crit
    real scalar    pointcrit

    void           new()
    void           load()
    real rowvector which()
    real scalar    lookup_prob()
    void           cell_probs()
    real colvector take()
    real colvector cell_weights()
    real matrix    weight_if()
    real colvector combine_if()
    real scalar    cluster_se()
    void           cell_effect()
    void           overall()
    void           store()
    void           agg_simple()
    void           agg_group()
    void           agg_dynamic()
    void           agg_calendar()
    void           boot_setup()
    void           core()
    void           cluster_core()
    void           boot_finish()
}

void csdid__Agg::new()
{
    attgt         = J(0, 0, .)
    inffunc       = J(0, 0, .)
    group_prob    = J(0, 0, .)
    unit_map      = J(0, 0, .)
    group         = J(0, 1, .)
    tt            = J(0, 1, .)
    event_time    = J(0, 1, .)
    att           = J(0, 1, .)
    pg            = J(0, 1, .)
    unit_group    = J(0, 1, .)
    unit_weight   = J(0, 1, .)
    glist         = J(0, 1, .)
    pgg           = J(0, 1, .)

    type          = ""
    min_e         = .
    max_e         = .
    balance_e     = .
    na_rm         = 0
    use_cache     = 0
    outname       = ""
    ifname        = ""
    store_large   = 0

    use_cluster   = 0
    cluster_vec   = J(0, 1, .)
    cl_ord        = J(0, 1, .)
    cl_info       = J(0, 0, .)

    egt           = J(0, 1, .)
    effects       = J(0, 1, .)
    ses           = J(0, 1, .)
    effect_if_mat = J(0, 0, .)
    overall_att   = .
    overall_se    = .
    overall_if    = J(0, 1, .)
    out           = J(0, 5, .)

    agg           = J(0, 0, .)
    sc            = J(0, 0, .)
    n             = .
    nc            = .
    k             = .
    k_effects     = .

    biters        = .
    alp           = .
    cband         = .
    dist          = ""
    is_simple     = 0
    use_bmisc     = 0
    rng_state     = J(1, 0, .)

    bres          = J(0, 0, .)
    bootout       = J(0, 0, .)
    crit          = .
    pointcrit     = .
}

// ---------------------------------------------------------------------------
// Read what is being aggregated, check it against itself, and settle the two
// things every cell of the aggregation then shares: the cluster sort layout,
// and which cells have an estimate at all.
// ---------------------------------------------------------------------------
void csdid__Agg::load()
{
    external class csdid__Engine scalar CSDID_ENGINE
    real colvector notmiss
    real rowvector keep_notmiss

    csdid__engine_ensure()

    attgt = st_matrix("e(attgt)")
    // The original rank grid, taken BEFORE any missing-cell filtering:
    // R builds it as sort(unique(c(originaltlist, originalglist))) --
    // compute.aggte.R:239, "In case g's are not part of tlist" -- so the
    // union here is every cell's time, every cell's base period (the
    // periods that survive standardization are exactly those some cell
    // references), and every cohort date. Ranking on the SURVIVING cell
    // times alone was wrong twice over (cold-audit round 11): dropmissing
    // shifted the ranks, and an off-grid cohort has a rank of its own in
    // R's map rather than an exclusion.
    // the tlist half only: R's tlist stays the ORIGINAL periods under
    // na.rm (its recompute lines are commented out in compute.aggte.R:163,
    // :194), and every period survives preprocessing exactly when some cell
    // references it as its time or base. The glist half joins per route,
    // because R DOES refilter glist under na.rm (:164) and refilters it
    // again for type=group after a raw-scale max_e screen (:177-195).
    tgrid_full = uniqrows(attgt[., 2] \ attgt[., 10])
    group_prob = st_matrix("e(group_prob)")
    if (use_cache != 0) {
        inffunc = CSDID_ENGINE.inffunc
        unit_map = CSDID_ENGINE.unit_group
    }
    else {
        inffunc = st_matrix("e(inffunc)")
        unit_map = st_matrix("e(unit_group)")
    }
    cluster_vec = J(0, 1, .)
    if (use_cluster != 0 & st_global("e(clustervar)") != "") {
        if (use_cache != 0 & rows(CSDID_ENGINE.cluster_vec) == rows(inffunc)) {
            cluster_vec = CSDID_ENGINE.cluster_vec
        }
        else {
            cluster_vec = st_matrix("e(cluster_vec)")
        }
    }

    if (rows(attgt) == 0) {
        errprintf("no ATT(g,t) results available for aggregation\n")
        _error(498)
    }
    if (cols(inffunc) != rows(attgt)) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (use_cache != 0 & rows(unit_map) != st_numscalar("e(N_units)")) {
        errprintf("the stored influence functions do not match the active csdid results; re-run csdid before aggregating\n")
        _error(498)
    }

    // The cluster layout is a function of the cluster vector alone, and every
    // cell of this aggregation shares it. Computed once here, it replaces one
    // full O(n log n) sort per aggregation cell -- E+1 of them on an event
    // study -- with one.
    cl_ord = J(0, 1, .)
    cl_info = J(0, 0, .)
    if (rows(cluster_vec) > 0 & sum(cluster_vec :>= .) == 0) {
        csdid__cluster_layout(cluster_vec, cl_ord, cl_info)
    }

    att = attgt[., 4]
    if (sum(att :>= .) > 0) {
        if (!na_rm) {
            // Say how many cells are missing and out of how many, so the user
            // can judge whether dropping them is acceptable before asking for
            // it. R's aggte() defaults to na.rm = FALSE and stops here too.
            //
            // "the per-cell warnings above name it" is a promise about another
            // message, and it was only kept on a noisy run: the per-cell
            // warnings used printf, which a caller's `quietly' removes, while
            // this refusal is an errprintf, which it does not. A user who ran
            // the estimation quietly was sent to warnings that were not there.
            // Those warnings are errprintf now (see the channel note at
            // csdid__empty_cell_warning), so the sentence holds on every run
            // that reaches this line -- keep them on that channel.
            errprintf("%g of the %g ATT(g,t) cells have a missing estimate, so the aggregation is not defined over the full set of cells. Specify dropmissing to aggregate over the %g cells that were estimated, or address the cause of the failures (the per-cell warnings above name it) and re-run.\n",
                sum(att :>= .), rows(att), sum(att :< .))
            _error(498)
        }
        notmiss = (att :< .)
        if (sum(notmiss) == 0) {
            errprintf("all ATT(g,t) estimates are missing; cannot aggregate\n")
            _error(498)
        }
        keep_notmiss = which(notmiss)
        attgt = attgt[keep_notmiss, .]
        inffunc = inffunc[., keep_notmiss]
    }

    group = attgt[., 1]
    tt = attgt[., 2]
    event_time = attgt[., 3]
    att = attgt[., 4]
    unit_group = unit_map[., 2]
    if (cols(unit_map) >= 3) {
        unit_weight = unit_map[., 3]
    }
    else {
        unit_weight = J(rows(unit_map), 1, 1)
    }
    glist = group_prob[., 1]
    pgg = group_prob[., 2]
    cell_probs()
}

// ---------------------------------------------------------------------------
// The index and weight kernels every aggregation type is built from. They were
// eight free functions until the signature sweep, taking 23 arguments between
// them; 14 of those slots bound to a field of this object at every call site,
// and every call site was already a method on it. Ten of the fourteen are gone.
// The other four stayed arguments because two callers disagree about which
// field they carry -- weight_if runs over the cohort table (pgg, egt) for the
// group aggregation and the cell table (pg, group) for the other three, and
// combine_if combines cells for an effect row and effects for the overall row.
// As methods they are also free of a cost a free name carries -- Mata
// resolves each global function name it does not already hold by walking
// c(matalibs), and an installed package is indexed behind Stata's own
// libraries, which measured 1.17ms per name on the first call of a session
// (see the S3 record). A class travels as ONE library name and its methods
// ride inside it, so the aggregation path now goes and finds eight fewer.
//
// which() is the aggregation's cell selector: the columns of a windowed
// aggregation, as a ROW vector, because that is what every keep-index below
// subscripts with. It is not csdid__selidx (which normalises to a COLUMN and
// is what the estimation side's guards test with rows()).
// ---------------------------------------------------------------------------
real rowvector csdid__Agg::which(real colvector flag)
{
    real colvector idx

    idx = select((1::rows(flag)), flag)
    if (rows(idx) == 0) return(J(1, 0, .))
    return(idx')
}

real scalar csdid__Agg::lookup_prob(real scalar g)
{
    real scalar i

    for (i = 1; i <= rows(group_prob); i++) {
        if (group_prob[i, 1] == g) return(group_prob[i, 2])
    }
    return(.)
}

// p(g) for every ATT(g,t) cell, in cell order: the weight three of the four
// aggregation types are built on.
void csdid__Agg::cell_probs()
{
    real scalar i

    pg = J(rows(group), 1, .)
    for (i = 1; i <= rows(group); i++) {
        pg[i] = lookup_prob(group[i])
    }
}

real colvector csdid__Agg::take(real rowvector keep)
{
    real colvector out
    real scalar k

    out = J(cols(keep), 1, .)
    for (k = 1; k <= cols(keep); k++) out[k] = att[keep[k]]
    return(out)
}

// The kept cells' p(g) weights, normalised to sum to one.
real colvector csdid__Agg::cell_weights(real rowvector keep)
{
    real colvector weights
    real scalar kk, spg

    weights = J(cols(keep), 1, .)
    spg = 0
    for (kk = 1; kk <= cols(keep); kk++) {
        weights[kk] = pg[keep[kk]]
        spg = spg + weights[kk]
    }
    return(weights / spg)
}

// What treating the p(g) weights as ESTIMATED adds to the influence function.
// The probabilities and the cell grouping are arguments rather than fields
// because the group aggregation runs this over the cohort table (pgg, egt)
// and the other three over the cell table (pg, group).
//
// The second pass writes over the first. row_sum is taken before it, and each
// column's new value is a function of that column's old value and row_sum
// alone, so nothing the pass needs is destroyed by it -- and the n x k matrix
// the result used to be copied into is not allocated at all. The saving is the
// allocation and the missing-fill of an n x k matrix per effect; measured on
// the warmed aggregation instrument, 0 of 12 rounds slower on the simple
// aggregation and 2 of 12 on the total.
real matrix csdid__Agg::weight_if(
    real rowvector keep,
    real colvector pgv,
    real colvector cell_group)
{
    real matrix centered
    real colvector row_sum
    real scalar n, k, kk, spg

    n = rows(unit_group)
    k = cols(keep)
    if (k == 0) return(J(n, 0, .))
    spg = 0
    for (kk = 1; kk <= k; kk++) spg = spg + pgv[keep[kk]]

    centered = J(n, k, .)
    for (kk = 1; kk <= k; kk++) {
        centered[., kk] = unit_weight :* (unit_group :== cell_group[keep[kk]]) :- pgv[keep[kk]]
    }
    row_sum = rowsum(centered)
    for (kk = 1; kk <= k; kk++) {
        centered[., kk] = centered[., kk] / spg :- row_sum * (pgv[keep[kk]] / (spg ^ 2))
    }
    return(centered)
}

// One weighted combination of influence functions, plus the weight-estimation
// term. The estimates and their influence functions are arguments: the effect
// rows combine ATT(g,t) cells, and the overall row combines the effects.
real colvector csdid__Agg::combine_if(
    real colvector estv,
    real matrix ifmat,
    real rowvector keep,
    real colvector weights,
    real matrix wifm)
{
    real colvector out
    real scalar k, kk

    k = cols(keep)
    out = J(rows(ifmat), 1, 0)
    for (kk = 1; kk <= k; kk++) {
        out = out + weights[kk] * ifmat[., keep[kk]]
    }
    if (rows(wifm) > 0) {
        for (kk = 1; kk <= k; kk++) {
            out = out + estv[keep[kk]] * wifm[., kk]
        }
    }
    return(out)
}

// The standard error of one influence function under the cluster sort layout
// load() settled. Falls back to the unclustered form on the two conditions
// that make a cluster sum undefined, exactly as the free kernel it replaced
// did; the fallback is csdid__se_from_if, which the estimation side shares.
real scalar csdid__Agg::cluster_se(real colvector ifv)
{
    real matrix sc
    real scalar n, se, se_floor

    // R's degenerate-SE threshold; see csdid__se_from_if.
    se_floor = sqrt(epsilon(1)) * 10

    n = rows(ifv)
    if (n == 0) return(.)
    if (rows(cluster_vec) != n) return(csdid__se_from_if(ifv))
    if (sum(cluster_vec :>= .) > 0) return(csdid__se_from_if(ifv))

    sc = csdid__cluster_sums_pre(cl_ord, cl_info, ifv)
    se = sqrt(quadcross(sc[., 1], sc[., 1])) / n
    if (se <= se_floor) return(.)
    return(se)
}

// ---------------------------------------------------------------------------
// One aggregation cell, on R's weights: the kept ATT(g,t) cells enter in
// proportion to p(g), the weight influence map is what treating those weights
// as estimated adds to the influence function, and the standard error follows
// the cluster layout load() settled. Three of the four aggregation types build
// every one of their effects this way; the group aggregation, whose cells are
// equally weighted inside a cohort, does not.
//
// The results come back through the arguments so the caller can put them where
// its own table wants them -- a column of a preallocated matrix, or the end of
// one it is growing.
// ---------------------------------------------------------------------------
void csdid__Agg::cell_effect(
    real rowvector keep,
    real scalar effect,
    real colvector effect_if,
    real scalar se)
{
    real colvector weights
    real matrix wif

    weights = cell_weights(keep)
    wif = weight_if(keep, pg, group)
    effect = quadcross(weights, take(keep))
    effect_if = combine_if(att, inffunc, keep, weights, wif)
    se = cluster_se(effect_if)
}

// ---------------------------------------------------------------------------
// The overall row of a windowed aggregation: the influence function the
// weighting of the effects implies, and the standard error from it.
//
// The overall POINT ESTIMATE is not here, because it is not one expression.
// R takes a mean over the group aggregation's post-treatment effects and a
// p(g)-weighted sum over the cohorts, and a mean is not a quadcross against
// equal weights to the last bit. Each branch computes its own and leaves this
// with the part that is genuinely shared.
// ---------------------------------------------------------------------------
void csdid__Agg::overall(
    real rowvector keep,
    real colvector weights,
    real matrix wif)
{
    overall_if = combine_if(effects, effect_if_mat, keep, weights, wif)
    overall_se = cluster_se(overall_if)
}

// ---------------------------------------------------------------------------
// The five-column table, the influence-function cache, and the one crossing
// back into Stata. Every branch ends here.
//
// The aggregation influence functions are one row per UNIT. Stata's classic-
// matrix layer is quadratic in a matrix's longest dimension (measured on Stata
// MP: writing or copying an n x 1 matrix costs 4s at n=25,000, 27s at 50,000,
// 148s at 100,000 -- independent of orientation and of the number of cells),
// so an unconditional st_matrix() here made `estat event' after a
// 400,000-unit estimation hang for hours while csdid itself finished in
// seconds. The IF therefore always lands in the Mata cache, tagged with the
// token of the estimation it belongs to, and crosses into a Stata matrix only
// under full storage -- the same policy the estimator applies to e(inffunc).
// Consumers fall back to the cache through the same empty-name convention the
// bootstrap plumbing already uses.
// ---------------------------------------------------------------------------
void csdid__Agg::store()
{
    external class csdid__Engine scalar CSDID_ENGINE
    real scalar n_effects

    csdid__engine_ensure()

    // The five columns already exist as three vectors and two scalars, so the
    // table is one horizontal join rather than a row appended per effect.
    n_effects = rows(effects)
    out = (egt, effects, ses, J(n_effects, 1, overall_att), J(n_effects, 1, overall_se))
    CSDID_ENGINE.agg_inffunc = (effect_if_mat, overall_if)
    CSDID_ENGINE.agg_token = CSDID_ENGINE.token
    st_matrix(outname, out)
    if (store_large) st_matrix(ifname, CSDID_ENGINE.agg_inffunc)
}

// One weighted average over every post-treatment cell inside the window. Its
// single row IS the overall row -- the same estimate and the same standard
// error in both halves of the table -- and its influence function is the one
// the overall column carries, which is why the effect column of the cache is
// that same vector rather than a second one.
void csdid__Agg::agg_simple()
{
    real rowvector keep
    real colvector agg_tgrid, agg_tr, agg_gr
    real scalar agg_i

    // R rank-recodes periods and cohorts (orig2t) BEFORE applying max_e to
    // the simple and group keepers (compute.aggte.R:279, :335), so on a
    // gapped calendar max_e counts OBSERVED PERIODS, not calendar units --
    // measured: on periods {1,3,5} with g=3 and max_e=1, R keeps both post
    // cells and csdid's raw-calendar comparison kept one. The dynamic path
    // is different by R's own construction (eseq = originalt -
    // originalgroup, raw) and stays raw here too. The rank of a value is
    // its count of grid points at or below it, exact for every on-grid
    // value; missing max_e still means unbounded, since a comparison
    // against missing is true for the same reason it was on the raw scale.
    // grid = original tlist UNION the surviving cohort dates (R
    // compute.aggte.R:239 with glist as it stands after the na.rm filter)
    agg_tgrid = uniqrows(tgrid_full \ group)
    agg_tr = J(rows(tt), 1, 0)
    agg_gr = J(rows(group), 1, 0)
    for (agg_i = 1; agg_i <= rows(agg_tgrid); agg_i++) {
        agg_tr = agg_tr + (tt :>= agg_tgrid[agg_i])
        agg_gr = agg_gr + (group :>= agg_tgrid[agg_i])
    }
    keep = which((group :<= tt) :& (agg_tr :<= agg_gr :+ max_e))
    if (cols(keep) == 0) {
        errprintf("no valid ATT(g,t) estimates found for simple aggregation\n")
        _error(498)
    }
    cell_effect(keep, overall_att, overall_if, overall_se)
    egt = J(1, 1, .)
    effects = J(1, 1, overall_att)
    ses = J(1, 1, overall_se)
    effect_if_mat = overall_if
    store()
}

// One effect per treatment cohort, its cells equally weighted; the cohorts
// then enter the overall ATT in proportion to their own p(g), which is what
// the weight influence map below is taken over.
void csdid__Agg::agg_group()
{
    real rowvector keep
    real colvector weights, effect_if, overall_weights
    real colvector agg_tgrid, agg_tr, agg_gr, agg_gscreen
    real matrix wif
    real scalar i, g, n_effects, n_max, agg_i

    // One cohort at most per iteration, so the tables are opened at that size
    // and trimmed once if dropmissing left a cohort out. Appending a column to
    // effect_if_mat instead copies the whole n x j matrix on every iteration,
    // which is quadratic in the cohort count and linear in the UNIT count:
    // 5,000 units and five cohorts is 75,000 doubles moved to place five
    // columns. agg_dynamic already opened its table this way; measured on the
    // warmed aggregation instrument, this cell reads -3.26% with 0 of 12
    // rounds slower.
    n_max = rows(glist)
    effects = J(n_max, 1, .)
    ses = J(n_max, 1, .)
    egt = J(n_max, 1, .)
    pgg = J(n_max, 1, .)
    effect_if_mat = J(rows(inffunc), n_max, .)
    n_effects = 0
    // R's type=group na.rm screen runs BEFORE the rank recode, on RAW
    // calendar values (compute.aggte.R:177): a cohort with no surviving
    // cell inside (g <= t <= g + max_e) leaves glist entirely, and the
    // grid is then built from the SURVIVING cohorts (:195 feeding :239).
    // Without na.rm the screen never runs (it sits inside R's na.rm
    // block), and every cohort is present anyway.
    agg_gscreen = J(rows(glist), 1, 1)
    if (na_rm) {
        for (i = 1; i <= rows(glist); i++) {
            g = glist[i]
            if (cols(which((group :== g) :& (g :<= tt) :& (tt :<= g :+ max_e))) == 0) {
                agg_gscreen[i] = 0
            }
        }
    }
    agg_tgrid = uniqrows(tgrid_full \ select(glist, agg_gscreen))
    agg_tr = J(rows(tt), 1, 0)
    agg_gr = J(rows(group), 1, 0)
    for (agg_i = 1; agg_i <= rows(agg_tgrid); agg_i++) {
        agg_tr = agg_tr + (tt :>= agg_tgrid[agg_i])
        agg_gr = agg_gr + (group :>= agg_tgrid[agg_i])
    }
    for (i = 1; i <= n_max; i++) {
        g = glist[i]
        if (agg_gscreen[i] == 0) continue
        keep = which((group :== g) :& (group :<= tt) :& (agg_tr :<= agg_gr :+ max_e))
        if (cols(keep) == 0) {
            if (na_rm) continue
            errprintf("no valid ATT(g,t) estimates found for group aggregation\n")
            _error(498)
        }
        weights = J(cols(keep), 1, 1 / cols(keep))
        effect_if = combine_if(att, inffunc, keep, weights, J(0, 0, .))
        n_effects = n_effects + 1
        effects[n_effects] = quadcross(weights, take(keep))
        ses[n_effects] = cluster_se(effect_if)
        effect_if_mat[., n_effects] = effect_if
        egt[n_effects] = g
        pgg[n_effects] = lookup_prob(g)
    }
    if (n_effects == 0) {
        errprintf("no valid ATT(g,t) estimates found for group aggregation\n")
        _error(498)
    }
    if (n_effects < n_max) {
        effects = effects[1..n_effects]
        ses = ses[1..n_effects]
        egt = egt[1..n_effects]
        pgg = pgg[1..n_effects]
        effect_if_mat = effect_if_mat[., 1..n_effects]
    }
    overall_weights = pgg / sum(pgg)
    keep = (1::n_effects)'
    wif = weight_if(keep, pgg, egt)
    overall_att = quadcross(overall_weights, effects)
    overall(keep, overall_weights, wif)
    store()
}

// One effect per event time inside the window, and an overall ATT that is the
// unweighted mean of the post-treatment ones.
void csdid__Agg::agg_dynamic()
{
    real matrix t_first_mat  // F-009: defensive e(time_first) fetch
    real colvector include_balanced, pos, overall_weights, effect_if
    real rowvector keep, keep2
    real scalar i, e, n_effects, max_t, effect, se
    real scalar t_first  // F-009: balance_e truncation needs e(time_first)

    include_balanced = J(rows(group), 1, 1)
    if (balance_e >= 0) {
        max_t = max(tt)
        include_balanced = ((max_t :- group) :>= balance_e)
    }
    egt = uniqrows(select(event_time, include_balanced :!= 0))
    if (balance_e >= 0) {
        // R parity (did 2.5.1 compute.aggte): with balance_e set, event
        // times are restricted to [balance_e - (maxT - t_first), balance_e]
        // F-009: fetch defensively. st_numscalar() returns a 0x0 matrix
        // when the scalar is absent, and assigning that into a real scalar
        // aborts with a raw Mata conformability error (rc 3200) BEFORE the
        // refusal below can run. The saved-RIF path posts no e(time_first),
        // so `csdid_stats using <rif>, balance()' hit exactly that.
        t_first_mat = st_numscalar("e(time_first)")
        if (rows(t_first_mat) == 0 | cols(t_first_mat) == 0) {
            errprintf("e(time_first) not found; re-run csdid before using balance()\n")
            _error(498)
        }
        t_first = t_first_mat[1, 1]
        if (t_first >= .) {
            errprintf("e(time_first) not found; re-run csdid before using balance()\n")
            _error(498)
        }
        egt = select(egt, (egt :<= balance_e) :& (egt :>= balance_e - max_t + t_first))  // F-009
    }
    egt = select(egt, (egt :>= min_e) :& (egt :<= max_e))
    if (rows(egt) == 0) {
        errprintf("no event times fall within the requested aggregation window\n")
        _error(498)
    }
    n_effects = rows(egt)
    effects = J(n_effects, 1, .)
    ses = J(n_effects, 1, .)
    effect_if_mat = J(rows(inffunc), n_effects, .)
    // cell_effect() answers through these, so they are given a value before
    // the loop rather than inside it: an argument that is only ever written
    // still has to exist on the way in.
    effect = .
    se = .
    effect_if = J(0, 1, .)
    for (i = 1; i <= n_effects; i++) {
        e = egt[i]
        keep = which((event_time :== e) :& (include_balanced :!= 0))
        cell_effect(keep, effect, effect_if, se)
        effects[i] = effect
        ses[i] = se
        effect_if_mat[., i] = effect_if
    }
    pos = (egt :>= 0)
    if (sum(pos) == 0) {
        errprintf("no post-treatment event times fall within the requested aggregation window\n")
        _error(498)
    }
    overall_att = mean(select(effects, pos))
    keep2 = which(pos)
    overall_weights = J(cols(keep2), 1, 1 / cols(keep2))
    overall(keep2, overall_weights, J(0, 0, .))
    store()
}

// One effect per calendar period in which some cohort is already treated, and
// an overall ATT that is their unweighted mean.
void csdid__Agg::agg_calendar()
{
    real colvector tlist, overall_weights, effect_if
    real rowvector keep
    real scalar i, t, n_effects, n_max, effect, se

    tlist = uniqrows(tt)
    tlist = select(tlist, tlist :>= min(glist))
    // One period at most per iteration; see agg_group for why the table is
    // opened at that size rather than grown a column at a time. Measured on
    // the warmed aggregation instrument, this cell reads -3.41% with 0 of 12
    // rounds slower.
    n_max = rows(tlist)
    effects = J(n_max, 1, .)
    ses = J(n_max, 1, .)
    egt = J(n_max, 1, .)
    effect_if_mat = J(rows(inffunc), n_max, .)
    // see agg_dynamic: cell_effect() answers through these
    effect = .
    se = .
    effect_if = J(0, 1, .)
    n_effects = 0
    for (i = 1; i <= n_max; i++) {
        t = tlist[i]
        keep = which((tt :== t) :& (group :<= tt))
        if (cols(keep) == 0) continue
        cell_effect(keep, effect, effect_if, se)
        n_effects = n_effects + 1
        effects[n_effects] = effect
        ses[n_effects] = se
        effect_if_mat[., n_effects] = effect_if
        egt[n_effects] = t
    }
    if (n_effects == 0) {
        errprintf("no calendar periods have valid post-treatment ATT(g,t) estimates\n")
        _error(498)
    }
    if (n_effects < n_max) {
        effects = effects[1..n_effects]
        ses = ses[1..n_effects]
        egt = egt[1..n_effects]
        effect_if_mat = effect_if_mat[., 1..n_effects]
    }
    overall_att = mean(effects)
    keep = (1::n_effects)'
    overall_weights = J(n_effects, 1, 1 / n_effects)
    overall(keep, overall_weights, J(0, 0, .))
    store()
}

// The aggregation, as the ado asks for it. The four types are four methods on
// one object; a type this does not know writes nothing, which is the contract
// the ado's own validation is written against.
void csdid_aggte(
    string scalar type,
    real scalar min_e,
    real scalar max_e,
    real scalar balance_e,
    real scalar na_rm,
    real scalar use_cluster,
    real scalar use_cache,
    string scalar outname,
    string scalar ifname,
    real scalar store_large)
{
    class csdid__Agg scalar ag

    ag.type = type
    ag.min_e = min_e
    ag.max_e = max_e
    ag.balance_e = balance_e
    ag.na_rm = na_rm
    ag.use_cluster = use_cluster
    ag.use_cache = use_cache
    ag.outname = outname
    ag.ifname = ifname
    ag.store_large = store_large

    ag.load()
    if (type == "simple") ag.agg_simple()
    else if (type == "group") ag.agg_group()
    else if (type == "dynamic") ag.agg_dynamic()
    else if (type == "calendar") ag.agg_calendar()
}

// ---------------------------------------------------------------------------
// The policy one aggregation bootstrap is run under, and the seeded stream it
// is run from. All three entries read both off the ado's arguments and checked
// the stream the same way, so both are settled in one place now. An empty
// `statename' is the caller using Stata's own generator, with no state to hand
// back afterwards -- the same convention csdid__Boot uses, on the way in and
// on the way out.
// ---------------------------------------------------------------------------
void csdid__Agg::boot_setup(
    real scalar reps,
    real scalar alpha,
    real scalar band,
    string scalar draws_dist,
    real scalar simple_type,
    string scalar statename)
{
    biters = reps
    alp = alpha
    cband = band
    dist = draws_dist
    is_simple = simple_type

    rng_state = J(1, 625, .)
    use_bmisc = (statename != "")
    if (use_bmisc) {
        rng_state = st_matrix(statename)
        // Mata's | does not short-circuit, so csdid__mt_state_absorbing is
        // called even on a mis-sized state; it returns 0 for anything
        // narrower than 625 rather than subscripting past the end.
        if (cols(rng_state) != 625 | csdid__mt_state_absorbing(rng_state)) {
            errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
            _error(498)
        }
    }
}

// ---------------------------------------------------------------------------
// Everything the aggregate-bootstrap entries do once the draws exist: hand the
// updated table, the band and the draws back to Stata. The seeded stream is
// the one thing they do not share -- an entry that was given a state matrix
// owes the advanced state back, one that was not has nothing to return -- and
// `statename' says which, exactly as it does on the way in.
// ---------------------------------------------------------------------------
void csdid__Agg::boot_finish(
    string scalar aggname,
    string scalar bootname,
    string scalar drawsname,
    string scalar statename,
    string scalar critname,
    string scalar pointcritname)
{
    st_matrix(aggname, agg)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    if (statename != "") st_matrix(statename, rng_state)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
}

// The unclustered core: the draws are taken over the influence functions
// themselves and every standard error is divided by sqrt(n). See the note on
// the object for why this and cluster_core() below are two routines.
void csdid__Agg::core()
{
    real matrix bres_col, bres_cband
    real colvector bsigma, bsigma_cband, seboot
    real scalar j, iqr_norm, simple_duplicate, phase_t0

    phase_t0 = csdid__profile_start()
    n = rows(sc)
    k_effects = rows(agg)
    k = cols(sc)
    if (n == 0 | k_effects == 0 | k != k_effects + 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }
    if (biters < 1) {
        errprintf("wboot() reps() must be a positive integer\n")
        _error(198)
    }

    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    pointcrit = invnormal(1 - alp / 2)  // transcribes R's qnorm(1 - alp/2); parity keeps the complement form
    crit = pointcrit
    csdid__agg_boot_profile_add(1, phase_t0, n * k)

    phase_t0 = csdid__profile_start()
    // The duplicate rule is a property of the AGGREGATION TYPE, not of the
    // influence matrix. R runs one mboot for type="simple" and reads its se
    // as both the effect and the overall se (compute.aggte.R:310); every
    // other type consumes one block per effect, one for the band and one
    // more for the overall column (compute.aggte.R:352/370/414), whatever
    // the effect count. A numeric identity test cannot tell the two apart:
    // a one-effect dynamic/group/calendar window has a bit-identical
    // overall column and still gets all three blocks in R.
    simple_duplicate = (is_simple & k_effects == 1)
    bres = J(biters, k, .)
    if (simple_duplicate) {
        bres_col = csdid__bootstrap_auto(sc[., 1], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
        bres[., 1] = bres_col
        bsigma[1] = csdid__bootstrap_sigma(bres_col, iqr_norm)
        if (bsigma[1] < .) seboot[1] = bsigma[1] / sqrt(n)
        bres[., k] = bres[., 1]
        bsigma[k] = bsigma[1]
        seboot[k] = seboot[1]
    }
    else if (!use_bmisc & dist == "rademacher" & !cband & n * biters <= 20000000) {
        bres = csdid__native_rboot_indep(sc, biters) / sqrt(n)
        for (j = 1; j <= k; j++) {
            bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
        }
    }
    else if (use_bmisc & dist == "rademacher" & cband) {
        if (n * biters * k_effects <= 250000000) {
            bres[., 1..k_effects] = csdid__bmisc_boot_dense_indep(sc[., 1..k_effects], biters, rng_state) / sqrt(n)
            for (j = 1; j <= k_effects; j++) {
                bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
                if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
            }
        }
        else {
            for (j = 1; j <= k_effects; j++) {
                bres_col = csdid__bmisc_bootstrap_auto(sc[., j], biters, rng_state) / sqrt(n)
                bres[., j] = bres_col
                bsigma[j] = csdid__bootstrap_sigma(bres_col, iqr_norm)
                if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
            }
        }
        bres_cband = csdid__bmisc_bootstrap_auto(sc[., 1..k_effects], biters, rng_state) / sqrt(n)
        bsigma_cband = J(k_effects, 1, .)
        for (j = 1; j <= k_effects; j++) {
            bsigma_cband[j] = csdid__bootstrap_sigma(bres_cband[., j], iqr_norm)
        }
        crit = csdid__bootstrap_cband_crit(bres_cband, bsigma_cband, alp, pointcrit)
        bres_col = csdid__bmisc_bootstrap_auto(sc[., k], biters, rng_state) / sqrt(n)
        bres[., k] = bres_col
        bsigma[k] = csdid__bootstrap_sigma(bres_col, iqr_norm)
        if (bsigma[k] < .) seboot[k] = bsigma[k] / sqrt(n)
    }
    else if (use_bmisc & dist == "rademacher" & !cband & rows(sc) * biters * cols(sc) <= 10000000) {
        bres = csdid__bmisc_boot_dense_indep(sc, biters, rng_state) / sqrt(n)
        for (j = 1; j <= k; j++) {
            bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
        }
    }
    else {
        for (j = 1; j <= k_effects; j++) {
            bres_col = csdid__bootstrap_auto(sc[., j], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
            bres[., j] = bres_col
            bsigma[j] = csdid__bootstrap_sigma(bres_col, iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
        }
        if (cband) {
            bres_cband = csdid__bootstrap_auto(sc[., 1..k_effects], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
            bsigma_cband = J(k_effects, 1, .)
            for (j = 1; j <= k_effects; j++) {
                bsigma_cband[j] = csdid__bootstrap_sigma(bres_cband[., j], iqr_norm)
            }
            crit = csdid__bootstrap_cband_crit(bres_cband, bsigma_cband, alp, pointcrit)
        }
        bres_col = csdid__bootstrap_auto(sc[., k], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
        bres[., k] = bres_col
        bsigma[k] = csdid__bootstrap_sigma(bres_col, iqr_norm)
        if (bsigma[k] < .) seboot[k] = bsigma[k] / sqrt(n)
    }
    csdid__agg_boot_profile_add(2, phase_t0, n * biters * k)

    phase_t0 = csdid__profile_start()
    csdid__agg_assemble_bootout(agg, seboot, crit, pointcrit, bootout)
    csdid__agg_boot_profile_add(3, phase_t0, biters * k)
}

// The clustered core: the draws are taken over the CLUSTER SUMS, so every
// standard error is scaled by sqrt(nc)/n -- nc clusters, n units -- and the
// type(simple) duplicate rule sits on the other side of the dense-draw branch.
void csdid__Agg::cluster_core()
{
    real matrix bres_col, bres_cband
    real colvector bsigma, bsigma_cband, seboot
    real scalar j, iqr_norm, simple_duplicate, phase_t0

    phase_t0 = csdid__profile_start()
    k_effects = rows(agg)
    k = cols(sc)
    nc = rows(sc)
    if (nc == 0 | k_effects == 0 | k != k_effects + 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }
    if (biters < 1) {
        errprintf("wboot() reps() must be a positive integer\n")
        _error(198)
    }

    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    pointcrit = invnormal(1 - alp / 2)  // transcribes R's qnorm(1 - alp/2); parity keeps the complement form
    crit = pointcrit
    csdid__agg_boot_profile_add(1, phase_t0, nc * k)

    phase_t0 = csdid__profile_start()
    // see csdid__aggte_core: the rule follows the type, not the numbers
    simple_duplicate = (is_simple & k_effects == 1)
    bres = J(biters, k, .)
    if (!simple_duplicate & !use_bmisc & dist == "rademacher" & !cband & nc * biters <= 20000000) {
        bres = csdid__native_rboot_indep(sc, biters) / sqrt(nc)
        for (j = 1; j <= k; j++) {
            bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] * sqrt(nc) / n
        }
    }
    else {
        for (j = 1; j <= k_effects; j++) {
            bres_col = csdid__bootstrap_auto(sc[., j], biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
            bres[., j] = bres_col
            bsigma[j] = csdid__bootstrap_sigma(bres_col, iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] * sqrt(nc) / n
        }
        if (simple_duplicate) {
            bres[., k] = bres[., 1]
            bsigma[k] = bsigma[1]
            seboot[k] = seboot[1]
        }
        else {
            if (cband) {
                bres_cband = csdid__bootstrap_auto(sc[., 1..k_effects], biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
                bsigma_cband = J(k_effects, 1, .)
                for (j = 1; j <= k_effects; j++) {
                    bsigma_cband[j] = csdid__bootstrap_sigma(bres_cband[., j], iqr_norm)
                }
                crit = csdid__bootstrap_cband_crit(bres_cband, bsigma_cband, alp, pointcrit)
            }
            bres_col = csdid__bootstrap_auto(sc[., k], biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
            bres[., k] = bres_col
            bsigma[k] = csdid__bootstrap_sigma(bres_col, iqr_norm)
            if (bsigma[k] < .) seboot[k] = bsigma[k] * sqrt(nc) / n
        }
    }
    csdid__agg_boot_profile_add(2, phase_t0, nc * biters * k)

    phase_t0 = csdid__profile_start()
    csdid__agg_assemble_bootout(agg, seboot, crit, pointcrit, bootout)
    csdid__agg_boot_profile_add(3, phase_t0, biters * k)
}

// R parity for aggte() on a bstrap = FALSE fit: compute.aggte still runs the
// multiplier bootstrap for the SIMULTANEOUS band -- one joint draw block over
// the effect columns, nothing else -- warns that it did, and keeps every
// standard error analytic. This entry is that one block and nothing else:
// no per-effect draws, no overall draw, so a banded analytical aggregation
// consumes exactly the one block R's session stream loses (measured: R
// set.seed(2468) + aggte(dynamic) crit 2.5879258429398755, the second call
// 2.595670815356983, type(simple) consuming nothing in between). ifname
// empty reads the aggregation cache like csdid_bootstrap_aggte_direct;
// otherwise the influence functions come from the named Stata matrix, with
// the cluster vector resolved exactly as csdid_bootstrap_aggte_cluster
// resolves it. statename empty draws from the session stream (R's own
// semantics for a fit that carries no bootstrap state; set seed reproduces
// it); a supplied state uses the seeded emulation, which is how the R
// bit-parity of this block is tested. csdid__bootstrap_cband_crit sets the
// same fallback flags the seeded band sets, so the clamp labeling is shared.
void csdid_analytical_cband(
    string scalar aggname,
    string scalar ifname,
    string scalar clustervecname,
    string scalar unitname,
    string scalar timename,
    real scalar use_cluster,
    real scalar reps,
    real scalar alpha,
    string scalar statename,
    string scalar critname,
    string scalar pointcritname)
{
    external class csdid__Engine scalar CSDID_ENGINE
    class csdid__Agg scalar ag
    real matrix inf, bres_cband
    real colvector cluster_vec, bsigma_cband
    real scalar j, k_eff, nc_l, crit, pointcrit, iqr_norm

    ag.agg = st_matrix(aggname)
    ag.use_cluster = use_cluster
    ag.boot_setup(reps, alpha, 1, "rademacher", 0, statename)
    if (ifname == "") {
        ag.n = csdid__agg_boot_assemble(unitname, timename, use_cluster, ag.sc)
    }
    else {
        inf = st_matrix(ifname)
        ag.n = rows(inf)
        if (use_cluster) {
            csdid__engine_ensure()
            if (clustervecname != "") cluster_vec = st_matrix(clustervecname)
            else cluster_vec = CSDID_ENGINE.cluster_vec
            if (rows(cluster_vec) != ag.n | sum(cluster_vec :>= .) > 0) {
                errprintf("cluster() could not be aligned with aggregate influence functions\n")
                _error(498)
            }
            ag.sc = csdid__cluster_sums(cluster_vec, inf)
        }
        else ag.sc = inf
    }
    k_eff = rows(ag.agg)
    nc_l = rows(ag.sc)
    if (nc_l == 0 | k_eff == 0 | cols(ag.sc) != k_eff + 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }
    if (reps < 1) _error(198)
    pointcrit = invnormal(1 - alpha / 2)
    iqr_norm = invnormal(.75) - invnormal(.25)
    bres_cband = csdid__bootstrap_auto(ag.sc[., 1..k_eff], reps, "rademacher", ag.rng_state, ag.use_bmisc, 1) / sqrt(nc_l)
    bsigma_cband = J(k_eff, 1, .)
    for (j = 1; j <= k_eff; j++) {
        bsigma_cband[j] = csdid__bootstrap_sigma(bres_cband[., j], iqr_norm)
    }
    crit = csdid__bootstrap_cband_crit(bres_cband, bsigma_cband, alpha, pointcrit)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    if (statename != "") st_matrix(statename, ag.rng_state)
}

void csdid_bootstrap_aggte(
    string scalar aggname,
    string scalar ifname,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname,
    | real scalar is_simple)
{
    // Name-based wrapper kept for the saved-RIF/storeall entry, where the
    // influence functions genuinely live in Stata matrices. Fresh-fit estat
    // calls go through csdid_bootstrap_aggte_direct, which never crosses the
    // boundary with an n_units-row object.
    // is_simple is optional: a caller that omits it is not aggregating
    // type(simple), which is the only type that reuses one draw block.
    class csdid__Agg scalar ag

    if (args() < 12) is_simple = 0
    csdid__agg_boot_profile_reset()
    ag.agg = st_matrix(aggname)
    ag.sc = st_matrix(ifname)
    ag.boot_setup(biters, alp, cband, dist, is_simple, statename)
    ag.core()
    ag.boot_finish(aggname, bootname, drawsname, statename, critname, pointcritname)
}

void csdid_bootstrap_aggte_cluster(
    string scalar aggname,
    string scalar ifname,
    string scalar clustervecname,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname,
    | real scalar is_simple)
{
    // Name-based wrapper; see csdid_bootstrap_aggte for why it survives and
    // why is_simple is optional.
    external class csdid__Engine scalar CSDID_ENGINE
    class csdid__Agg scalar ag
    real matrix inf
    real colvector cluster_vec

    csdid__engine_ensure()

    if (args() < 13) is_simple = 0
    csdid__agg_boot_profile_reset()
    ag.agg = st_matrix(aggname)
    inf = st_matrix(ifname)
    if (clustervecname != "") {
        cluster_vec = st_matrix(clustervecname)
    }
    else {
        cluster_vec = CSDID_ENGINE.cluster_vec
    }
    ag.boot_setup(biters, alp, cband, dist, is_simple, statename)
    ag.n = rows(inf)
    if (ag.n == 0 | rows(ag.agg) == 0 | cols(inf) != rows(ag.agg) + 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }
    if (rows(cluster_vec) != ag.n | sum(cluster_vec :>= .) > 0) {
        errprintf("cluster() could not be aligned with aggregate influence functions\n")
        _error(498)
    }
    ag.sc = csdid__cluster_sums(cluster_vec, inf)
    if (rows(ag.sc) == 0) {
        errprintf("cluster() has no clusters in the estimation sample\n")
        _error(498)
    }
    ag.cluster_core()
    ag.boot_finish(aggname, bootname, drawsname, statename, critname, pointcritname)
}
real scalar csdid__agg_boot_assemble(
    string scalar unitname,
    string scalar timename,
    real scalar use_cluster,
    real matrix sc)
{
    // The ordering/collapse step of the aggregate bootstrap, in Mata end to
    // end. Factored out of csdid_agg_boot_plugin_prep_vars so the permutation
    // logic exists exactly once; both the plugin feed and the direct Mata
    // driver call this. Returns the ORIGINAL number of units n; sc comes
    // back as the kernel input (ordered IF, or cluster sums under
    // clustering).
    //
    // Row order on the CLUSTER branch, corrected: the note here used to say
    // cluster rows are consumed in "first-appearance order". They are not.
    // csdid__cluster_sums emits one row per cluster in ASCENDING CLUSTER-ID
    // order, which is a function of the cluster values alone and therefore
    // invariant to the order of the input rows. That is precisely why the
    // unit permutation is skipped on this branch: applying it would change
    // nothing, and the draw-to-cluster assignment matches the estimation
    // stage whatever order the influence functions arrive in. F-022 is the
    // standing reminder that row order on the UNIT branch is easy to get
    // wrong; describing the cluster branch by the unit branch's rule was
    // exactly the kind of note that makes someone "fix" a correct path.
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix inf, unit_group
    real colvector cluster_vec, ord
    real scalar n

    csdid__engine_ensure()

    inf = CSDID_ENGINE.agg_inffunc
    n = rows(inf)
    if (n == 0 | cols(inf) < 2) {
        errprintf("the aggregation influence-function cache is empty; rerun csdid before csdid_stats\n")
        _error(498)
    }
    unit_group = st_matrix(unitname)
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_ENGINE.unit_group) > 0) {
        unit_group = CSDID_ENGINE.unit_group
    }
    if (rows(unit_group) != n | cols(unit_group) < 2) {
        errprintf("stored unit/group map does not match bootstrap influence functions\n")
        _error(498)
    }
    if (use_cluster) {
        cluster_vec = J(0, 1, .)
        if (rows(CSDID_ENGINE.cluster_vec) > 0) {
            cluster_vec = CSDID_ENGINE.cluster_vec
        }
        else {
            cluster_vec = st_matrix("e(cluster_vec)")
        }
        if (rows(cluster_vec) != n | sum(cluster_vec :>= .) > 0) {
            errprintf("cluster() could not be aligned with aggregate influence functions\n")
            _error(498)
        }
        sc = csdid__cluster_sums(cluster_vec, inf)
    }
    else {
        ord = csdid__boot_row_order(unit_group, timename, n)
        sc = inf[ord, .]
    }
    if (rows(sc) == 0) {
        errprintf("the fast bootstrap could not be set up for this aggregation; re-run csdid with the nofast option\n")
        _error(498)
    }
    return(n)
}

void csdid_bootstrap_aggte_direct(
    string scalar aggname,
    string scalar unitname,
    string scalar timename,
    real scalar use_cluster,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname,
    | real scalar is_simple)
{
    // The estat-stage aggregate bootstrap without a single n_units-row
    // boundary crossing: assemble the kernel input in Mata from the
    // aggregation cache, run the same core arithmetic the name-based
    // wrappers run (draw for draw), and write back only k_effects- and
    // biters-sized objects. This is the path every fresh-fit estat call
    // takes when the plugin does not run -- unseeded fits, non-rademacher
    // draws, and every platform without the shipped plugin.
    class csdid__Agg scalar ag
    real scalar phase_t0

    if (args() < 14) is_simple = 0
    csdid__agg_boot_profile_reset()
    phase_t0 = csdid__profile_start()
    ag.agg = st_matrix(aggname)
    ag.use_cluster = use_cluster
    ag.boot_setup(biters, alp, cband, dist, is_simple, statename)
    ag.n = csdid__agg_boot_assemble(unitname, timename, use_cluster, ag.sc)
    csdid__agg_boot_profile_add(1, phase_t0, rows(ag.sc) * cols(ag.sc))
    if (use_cluster) {
        ag.cluster_core()
    }
    else {
        ag.core()
    }
    ag.boot_finish(aggname, bootname, drawsname, statename, critname, pointcritname)
}

// ===========================================================================
// SECTION 20 -- POSTING RESULTS BACK TO STATA
//
// Everything that crosses back into Stata's classic-matrix layer: e(b) and
// e(V) construction and rescaling, the cluster-cache check, and the RIF
// artifact export. Each crossing is quadratic in the matrix's longest
// dimension, which is why each is done once.
// ===========================================================================


void csdid__rescale_v_to_se(real matrix V, real colvector se)
{
    real scalar j, l, sj, tol

    // tol is R's degenerate-SE threshold (att_gt.R:570/593, compute.aggte.R:312),
    // so it is only meaningful against an SE. Compared against the VARIANCE
    // V[j,j] it fired on every ordinary cell with se < sqrt(tol) = 3.9e-04 and
    // zeroed that cell's covariances, which made every test/lincom after csdid
    // depend on the units the outcome happens to be measured in.
    tol = sqrt(epsilon(1)) * 10
    for (j = 1; j <= rows(V); j++) {
        if (se[j] >= .) {
            V[j, .] = J(1, cols(V), 0)
            V[., j] = J(rows(V), 1, 0)
            continue
        }
        if (V[j, j] < . & V[j, j] > tol * tol) {
            sj = se[j] / sqrt(V[j, j])
            V[j, .] = V[j, .] :* sj
            V[., j] = V[., j] :* sj
        }
        else {
            V[j, .] = J(1, cols(V), 0)
            V[., j] = J(rows(V), 1, 0)
            V[j, j] = se[j]^2
        }
    }
    for (j = 1; j <= rows(V); j++) {
        for (l = 1; l <= cols(V); l++) {
            if (V[j, l] >= .) V[j, l] = 0
        }
    }
}

real scalar csdid__cluster_cache_ok(real scalar expected_token, real scalar n)
{
    external class csdid__Engine scalar CSDID_ENGINE

    csdid__engine_ensure()

    // The cluster cache belongs to whichever csdid ran LAST. Adopting it on a
    // row count alone applied an unrelated run's cluster structure to this
    // e(V)'s off-diagonals - invisibly, because csdid__rescale_v_to_se pins
    // the diagonal back to the reported SEs. Same token rule the aggregate-IF
    // cache uses (see _csdid_post.ado and csdid_cache_validate); a zero token
    // means full storage, where the caller passes the vector by name instead.
    if (expected_token >= . | expected_token <= 0) return(0)
    if (CSDID_ENGINE.token != expected_token) return(0)
    return(rows(CSDID_ENGINE.cluster_vec) == n & sum(CSDID_ENGINE.cluster_vec :>= .) == 0)
}

// ---------------------------------------------------------------------------
// The covariance of the columns `keep' of `inf', which is what both posters
// below want and the only thing they wanted differently was what they called
// it. Two sources, in the order the posters try them:
//
//   the DRAWS, when the run bootstrapped and kept them. R exposes no bootstrap
//   V at all; Stata's postestimation contract requires one, so it is the
//   draws' own correlation, scaled to the reported standard errors by the
//   caller afterwards (owner-approved divergence, see AGENTS.md). The scale is
//   nc/n^2 when the run clustered and 1/n when it did not.
//
//   the INFLUENCE FUNCTIONS, when there are no usable draws -- cluster sums
//   first if a cluster vector survived, the unit-level functions otherwise.
//
// The cluster vector is the caller's named one, or the estimation cache when
// the caller's token says the cache belongs to these results.
// ---------------------------------------------------------------------------
void csdid__post_v_from_if(
    real matrix inf,
    real rowvector keep,
    string scalar clustervecname,
    string scalar drawsname,
    real scalar use_boot,
    real scalar cache_token,
    real matrix V)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix sc, draws, centered
    real colvector cluster_vec
    real scalar n, nc, scale

    n = rows(inf)

    cluster_vec = J(0, 1, .)
    if (clustervecname != "") {
        cluster_vec = st_matrix(clustervecname)
    }
    else if (csdid__cluster_cache_ok(cache_token, n)) {
        cluster_vec = CSDID_ENGINE.cluster_vec
    }

    V = J(cols(keep), cols(keep), .)
    if (use_boot != 0 & drawsname != "") {
        draws = st_matrix(drawsname)
        if (rows(draws) > 1 & cols(draws) == cols(inf)) {
            centered = draws[., keep]
            centered = centered :- J(rows(centered), 1, 1) * (colsum(centered) / rows(centered))
            V = quadcross(centered, centered) / (rows(centered) - 1)
            if (rows(cluster_vec) == n & sum(cluster_vec :>= .) == 0) {
                nc = rows(uniqrows(cluster_vec))
                scale = nc / (n^2)
            }
            else {
                scale = 1 / n
            }
            V = V * scale
        }
    }

    if (sum(V :< .) == 0) {
        if (rows(cluster_vec) == n & sum(cluster_vec :>= .) == 0) {
            sc = csdid__cluster_sums(cluster_vec, inf)
            V = quadcross(sc[., keep], sc[., keep]) / (n^2)
        }
        else {
            V = quadcross(inf[., keep], inf[., keep]) / (n^2)
        }
    }
}

void csdid_post_attgt_v(
    string scalar attname,
    string scalar ifname,
    string scalar clustervecname,
    string scalar drawsname,
    real scalar use_boot,
    string scalar vname,
    | real scalar cache_token)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix att, inf, V
    real rowvector keep
    real colvector se, se_diag

    csdid__engine_ensure()

    if (args() < 7) cache_token = .
    att = st_matrix(attname)
    // The excluded cell is the universal-base NORMALISATION row, identified by
    // its own marker (base_time == time, e(attgt) column 10), not by
    // event_time == -1: under anticipation(), base_period(varying) or a
    // non-unit-spaced time axis the normalisation row does not sit at event
    // time -1, and a genuine estimate does. Inferring it from a missing SE is
    // equally unsound - csdid.mata blanks the SE of a genuine cell whose
    // influence function is degenerate.
    if (cols(att) < 10) {
        errprintf("these ATT(g,t) results predate the base_time column and cannot be posted; re-run csdid (or re-save the RIF artifact) with csdid 2.0.0 or later\n")
        _error(498)
    }
    keep = csdid__selidx((att[., 4] :< .) :& (att[., 10] :!= att[., 2]))'
    if (cols(keep) == 0) {
        st_matrix(vname, J(0, 0, .))
        return
    }

    if (ifname != "") {
        inf = st_matrix(ifname)
    }
    else {
        inf = CSDID_ENGINE.inffunc
    }
    if (rows(inf) == 0 | cols(inf) != rows(att)) {
        // Diagonal fallback: no influence functions to build a full covariance
        // from. A genuine cell can carry a missing SE (a degenerate influence
        // function blanks it), and this exit returns BEFORE
        // csdid__rescale_v_to_se, so the missing value used to reach
        // `ereturn post' and fail it with r(504) -- an unrelated-looking
        // error at the end of a run that had already computed everything.
        // Zero is what csdid__rescale_v_to_se puts there on the normal path.
        se_diag = att[keep, 5]:^2
        se_diag = editmissing(se_diag, 0)
        st_matrix(vname, diag(se_diag'))
        return
    }
    // The guard above has already refused a mismatch, so cols(inf) IS
    // rows(att) here, which is the column count the shared routine screens the
    // draws matrix against.
    csdid__post_v_from_if(inf, keep, clustervecname, drawsname, use_boot,
        cache_token, V = J(0, 0, .))

    se = att[keep, 5]
    csdid__rescale_v_to_se(V, se)
    st_matrix(vname, V)
}

void csdid_post_mapped_v(
    string scalar ifname,
    string scalar clustervecname,
    string scalar drawsname,
    real scalar use_boot,
    string scalar mapname,
    string scalar vname,
    | real scalar cache_token)
{
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix inf, V, Vvalid, oldV
    real rowvector map, valid_pos, cols_keep
    real colvector se
    real scalar j

    csdid__engine_ensure()

    if (args() < 7) cache_token = .
    if (ifname == "") {
        // Lean aggregation posts no e(agg_inffunc): an n_units-row matrix
        // never crosses into Stata's classic-matrix layer, whose cost is
        // quadratic in the longest dimension (see csdid_aggte). The caller
        // has already token-validated the cache against the active results,
        // so the posted covariances are computed from the cached copy.
        inf = CSDID_ENGINE.agg_inffunc
    }
    else {
        inf = st_matrix(ifname)
    }
    oldV = st_matrix(vname)
    map = st_matrix(mapname)
    if (rows(map) > 1) map = map'
    V = J(cols(map), cols(map), 0)
    if (cols(map) == 0 | rows(inf) == 0 | cols(inf) == 0) {
        st_matrix(vname, V)
        return
    }
    valid_pos = csdid__selidx((map :>= 1) :& (map :<= cols(inf)))
    if (cols(valid_pos) == 0) {
        st_matrix(vname, V)
        return
    }
    cols_keep = map[valid_pos]

    // cols(cols_keep) is cols(valid_pos): the mapped columns are the valid
    // positions read through the map, so the block the shared routine returns
    // is the block scattered back into V below.
    csdid__post_v_from_if(inf, cols_keep, clustervecname, drawsname, use_boot,
        cache_token, Vvalid = J(0, 0, .))

    for (j = 1; j <= cols(valid_pos); j++) {
        V[valid_pos[j], valid_pos] = Vvalid[j, .]
    }

    se = sqrt(diagonal(oldV))
    csdid__rescale_v_to_se(V, se)
    st_matrix(vname, V)
}

// ---------------------------------------------------------------------------
// RIF artifact export.
//
// Fills the CURRENT (empty) dataset with the saved-RIF columns in one Mata
// call: id/group/weight from the unit map, one rif# column per ATT(g,t) cell,
// and the cluster identifiers when the run was clustered. The influence
// functions come from e(inffunc) under full storage and from the Mata cache
// under lean storage; both are read into Mata and written out with st_store,
// which is linear, where routing them through `matrix IF = e(inffunc)' plus
// svmat crosses Stata's classic-matrix layer three times, each crossing
// quadratic in n_units (see csdid_aggte).
//
// The caller sets the observation count from e(N_units) before calling; this
// routine refuses if that count, or the column count, disagrees with the
// influence functions it found.
// ---------------------------------------------------------------------------
void csdid_rif_export()
{
    external class csdid__Engine scalar CSDID_ENGINE
    real matrix inf, ug
    real colvector cluster_vec
    real scalar n, k, j
    string rowvector rifnames
    real rowvector idx

    csdid__engine_ensure()

    // Reading a Stata matrix INTO Mata is linear (measured: 0.00s at 50k
    // rows); only writes and Stata-side copies pay the quadratic cost. So
    // the export reads whichever source holds the influence functions -
    // e(inffunc) under full storage, the cache under lean - and never
    // creates another Stata matrix.
    inf = st_matrix("e(inffunc)")
    if (rows(inf) > 0) {
        ug = st_matrix("e(unit_group)")
    }
    else {
        inf = CSDID_ENGINE.inffunc
        ug = CSDID_ENGINE.unit_group
    }
    n = rows(inf)
    k = cols(inf)
    if (k != rows(st_matrix("e(attgt)"))) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (st_nobs() != n) {
        errprintf("csdid_rif_export: observation count does not match the influence functions\n")
        _error(498)
    }
    // schema: id group weight, exactly as the svmat path produced. The unit
    // map may carry a 4th (bootstrap draw-order) column on the unbalanced and
    // repeated-cross-section paths; it is internal and stays out of the
    // artifact, which is what keeps a file this tree writes readable by a
    // reader that knows only the three columns, and a file written before the
    // column existed readable here (F-001/F-022).
    idx = st_addvar("double", ("id", "group", "weight"))
    st_store(., idx, ug[., 1..3])
    // AGG-03: the cluster identifiers are not derivable from anything else in
    // the artifact, so a clustered estimation must carry them or the reload
    // silently reports i.i.d. standard errors. Written only when the run was
    // clustered, which keeps the unclustered artifact's variable list as it
    // has always been.
    if (st_global("e(clustervar)") != "") {
        cluster_vec = st_matrix("e(cluster_vec)")
        if (rows(cluster_vec) != n) cluster_vec = CSDID_ENGINE.cluster_vec
        if (rows(cluster_vec) != n) {
            errprintf("saverif() cannot record the cluster identifiers this run used; re-run csdid with storeall\n")
            _error(498)
        }
        st_store(., st_addvar("double", "cluster"), cluster_vec)
    }
    rifnames = J(1, k, "")
    for (j = 1; j <= k; j++) rifnames[j] = "rif" + strofreal(j)
    idx = st_addvar("double", rifnames)
    st_store(., idx, inf)
}

void csdid__globals_init()
{
    external real matrix CSDID_PROFILE, CSDID_BOOT_PROFILE, CSDID_BOOT_KERNEL_PROFILE
    external real matrix CSDID_AGG_BOOT_PROFILE
    external real scalar CSDID_BOOT_PLUGIN_PROFILE_START
    external real matrix CSDID_OVL_X
    external real colvector CSDID_OVL_D
    external real scalar CSDID_OVL_STATUS
    external real matrix CSDID_AND8, CSDID_XOR8, CSDID_RBITS8, CSDID_MT_XOR_MAG
    external real colvector CSDID_AND8F, CSDID_XOR8F, CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    external real scalar CSDID_RNG_TABLES_READY
    external real scalar CSDID_GLOBALS_READY
    // The engine object is BORN here. Measured semantics (Stata 17 MP, both
    // this file's probes and the S1 recheck's): declaring
    // `external class ... CSDID_ENGINE' on an absent name does NOT raise --
    // it materialises a pointer scalar, and rc 3261 comes lazily, at the
    // first MEMBER reference; assigning a constructed instance to that name
    // is fine, so a class-typed declaration would also work at this site.
    // transmorphic is kept as the weakest type that says nothing the reader
    // must double-check. The assignment below runs only when
    // CSDID_GLOBALS_READY is unset, so the object is constructed exactly
    // once per session: constructing it on every csdid call would throw
    // away the cache the postestimation commands are about to read.
    external transmorphic CSDID_ENGINE

    if (CSDID_GLOBALS_READY == 1) return

    CSDID_ENGINE = csdid__Engine()
    CSDID_PROFILE = J(8, 3, 0)
    CSDID_BOOT_PROFILE = J(6, 3, 0)
    CSDID_BOOT_KERNEL_PROFILE = J(5, 3, 0)
    CSDID_AGG_BOOT_PROFILE = J(3, 3, 0)
    CSDID_BOOT_PLUGIN_PROFILE_START = 0
    CSDID_AND8 = J(0, 0, .)
    CSDID_XOR8 = J(0, 0, .)
    CSDID_AND8F = J(0, 1, .)
    CSDID_XOR8F = J(0, 1, .)
    CSDID_RBITS8 = J(0, 0, .)
    CSDID_MT_TEMPER_LO = J(0, 1, .)
    CSDID_MT_TEMPER_HI = J(0, 1, .)
    CSDID_MT_XOR_MAG = J(0, 0, .)
    CSDID_RNG_TABLES_READY = 0
    CSDID_OVL_X = J(0, 0, .)
    CSDID_OVL_D = J(0, 1, .)
    CSDID_OVL_STATUS = .
    CSDID_GLOBALS_READY = 1
}

csdid__globals_init()

end
