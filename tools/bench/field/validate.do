* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines bench_validate.
* ---------------------------------------------------------------------------
* Validate a generated dataset BEFORE any estimator touches it.
*
* Everything here is a property the design CLAIMS. If a claim fails the run
* aborts, because a silently wrong dataset costs more than a loud failure.
* ---------------------------------------------------------------------------
capture program drop bench_validate
program define bench_validate
    syntax , [QUIET MINCohorts(integer 2)]
    local fail 0

    * 1. no missing values anywhere that matters
    foreach v in id time gvar y {
        quietly count if missing(`v')
        if r(N) > 0 {
            display as error "VALIDATE: `v' has `=r(N)' missing values"
            local fail 1
        }
    }

    * 2. never-treated units must EXIST and have outcomes
    quietly count if gvar == 0
    local nev = r(N)
    if `nev' == 0 {
        display as error "VALIDATE: no never-treated observations"
        local fail 1
    }
    quietly count if gvar == 0 & !missing(y)
    if r(N) != `nev' {
        display as error "VALIDATE: never-treated have missing outcomes (`=`nev'-r(N)' of `nev')"
        local fail 1
    }

    * 3. treated units must exist, in more than one cohort
    quietly levelsof gvar if gvar > 0, local(gs)
    local ng : word count `gs'
    if `ng' < `mincohorts' {
        display as error "VALIDATE: fewer than `mincohorts' treated cohorts"
        local fail 1
    }

    * 4. gvar constant within unit
    tempvar gmin gmax
    quietly bysort id: egen double `gmin' = min(gvar)
    quietly bysort id: egen double `gmax' = max(gvar)
    quietly count if `gmin' != `gmax'
    if r(N) > 0 {
        display as error "VALIDATE: gvar varies within unit for `=r(N)' rows"
        local fail 1
    }

    * 5. every cohort needs a pre-period, or its ATT is not identified
    quietly summarize time, meanonly
    local tmin = r(min)
    foreach g of local gs {
        if `g' <= `tmin' {
            display as error "VALIDATE: cohort `g' has no pre-period (min time `tmin')"
            local fail 1
        }
    }

    * 6. the outcome must actually vary
    quietly summarize y
    if r(sd) == 0 {
        display as error "VALIDATE: outcome is constant"
        local fail 1
    }

    if `fail' {
        display as error "VALIDATE: dataset rejected"
        exit 459
    }
    if "`quiet'" == "" {
        quietly count
        display "VALIDATE ok: `=r(N)' rows, `ng' cohorts, `nev' never-treated rows, no missing"
    }
end