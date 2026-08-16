* The installed package runs from a compiled Mata library, not from the source
* file, and the library has no file-scope code: nothing in it runs until an
* entry point is called. Every gate before this one loaded the engine from
* src/mata/csdid.mata, whose trailing initialisation runs as a side effect of
* the load, so no gate could see what the library-only configuration does.
*
* Two properties are checked in that configuration, both of them promises the
* help makes. A full estimation from the library agrees with the same
* estimation from source, figure for figure. And `csdid_stats using' on a RIF
* file written by an EARLIER session works, for every aggregation type, in a
* session where csdid itself never runs -- the workflow csdid_stats.sthlp
* sells as "a long estimation can be aggregated many ways later, or in another
* session, without re-estimating".
*
* The second property is the one that needs a separate process. csdid_stats
* has its own loader and never runs the estimation command, so a session that
* reaches it from a saved RIF is the only session in the suite where the
* engine has to already exist without any csdid having built it. This test
* therefore builds the library the way src/build.do builds the shipped one,
* stages it with the ado files and WITHOUT csdid.mata, and launches a real
* Stata process against it (tests/stata/mlib-session-fresh.do). The child
* reports return codes and figures to a csv; the judging all happens here.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local data "`root'/tests/fixtures/parity/f034/inputs/input.csv"
confirm file "`data'"
confirm file "`root'/tests/stata/mlib-session-fresh.do"

tempfile stub rif
local scratch "`stub'-mlib"
mkdir "`scratch'"
local childcsv "`scratch'/fresh-session.csv"
local refcsv   "`scratch'/source-reference.csv"
display as text "test-mlib-session: staging under `scratch'"

* The staging directory goes away whether this test passes or fails. A red run
* used to leave a compiled library and six ado copies behind in the temp
* directory, once per red run, because the cleanup sat after the assertions.
* The child process's log is the one thing from that directory worth keeping,
* so a red run prints it into THIS log before the directory goes.
program define mlib_stage_clean
    version 15
    args scratch

    capture erase "`scratch'/fresh-session.csv"
    capture erase "`scratch'/source-reference.csv"
    capture erase "`scratch'/lcsdid_v2.mlib"
    * Stata derives the batch log's name from the do-file it is given; this
    * test does not depend on which form it picks, so both are removed.
    capture erase "`scratch'/fresh-session.log"
    capture erase "`scratch'/mlib-session-fresh.log"
    foreach f in csdid.ado _csdid_post.ado _csdid_engine_load.ado csdid_estat.ado csdid_stats.ado csdid_plot.ado csdid_p.ado {
        capture erase "`scratch'/`f'"
    }
    foreach arm in thisbuild newerstata othercsdid nostamp {
        capture erase "`scratch'/stamp-`arm'/lcsdid_v2.mlib"
        capture rmdir "`scratch'/stamp-`arm'"
    }
    foreach arm in cwd-lib cwd-trap {
        capture erase "`scratch'/`arm'/lcsdid_v2.mlib"
        capture rmdir "`scratch'/`arm'"
    }
    capture rmdir "`scratch'"
end

* How many times did a run say a given thing? Stata wraps a long line in a log
* with a "> " continuation, so the log is read back as one unbroken string
* before the message is looked for in it.
*
* The count is the assertion, not just presence: each arm below runs csdid
* TWICE, and a loader that judged the library again on every call would say
* the same thing twice.
program define mlib_log_says
    version 15
    syntax using/, MESSAGE(string) [EXPECT(integer 1)]

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body'`clean' "'
        file read `fh' line
    }
    file close `fh'
    local hay = subinstr(`"`body'"', " ", "", .)
    local needle = subinstr(`"`message'"', " ", "", .)
    local said = 0
    local at = strpos(`"`hay'"', `"`needle'"')
    while `at' > 0 {
        local said = `said' + 1
        local hay = substr(`"`hay'"', `at' + strlen(`"`needle'"'), .)
        local at = strpos(`"`hay'"', `"`needle'"')
    }
    assert `said' == `expect'
end

* The marker the loader writes, rebuilt here from the two things it is made
* of: the stamp of the engine the session holds, and the settings that decide
* which engine a name the session is NOT holding would be answered from. Both
* halves are asserted because either alone can go stale -- a held stamp keeps
* answering for a library that has left the adopath, and settings alone say
* nothing about whether an engine is there alive.
*
* The working directory is one of those settings: `.' is an ado-path entry on
* every default installation, so which lcsdid_v2.mlib a name resolves from is a
* question about where the session is standing, and a marker that did not carry
* c(pwd) let a `cd' past the decision it should have reopened.
program define mlib_marker_agrees
    version 15
    args expected_stamp

    local live ""
    capture mata: st_local("live", csdid_mlib_version())
    assert "`live'" == "`expected_stamp'"
    assert `"$CSDID_ENGINE_RESOLVED"' == `"`live';`c(adopath)';`c(matalibs)';`c(sysdir_base)';`c(sysdir_site)';`c(sysdir_personal)';`c(sysdir_plus)';`c(sysdir_oldplace)';`c(pwd)'"'
end

capture noisily {

    * ---------------------------------------------------------------------------
    * The prior session: an estimation that writes the RIF file, and the source-path
    * figures every library-path figure is judged against.
    * ---------------------------------------------------------------------------
    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) saverif("`rif'") replace analytical notyet
    confirm file "`rif'"

    tempname fh
    file open `fh' using "`refcsv'", write replace text

    foreach t in simple group calendar dynamic {
        ereturn clear
        csdid_stats using "`rif'", type(`t')
        tempname A
        matrix `A' = e(aggte)
        forvalues i = 1/`=rowsof(`A')' {
            forvalues j = 1/`=colsof(`A')' {
                file write `fh' "using_`t',aggte,`i',`j'," %21.17e (`A'[`i', `j']) _n
            }
        }
    }

    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
    tempname ATT B V
    matrix `ATT' = e(attgt)
    forvalues i = 1/`=rowsof(`ATT')' {
    forvalues j = 1/`=colsof(`ATT')' {
        file write `fh' "estimate,attgt,`i',`j'," %21.17e (`ATT'[`i', `j']) _n
    }
    }
    matrix `B' = e(b)
    matrix `V' = vecdiag(e(V))
    forvalues j = 1/`=colsof(`B')' {
    file write `fh' "estimate,b,1,`j'," %21.17e (`B'[1, `j']) _n
    file write `fh' "estimate,vdiag,1,`j'," %21.17e (`V'[1, `j']) _n
    }

    foreach t in simple group calendar dynamic {
    csdid_stats, type(`t')
    tempname AA
    matrix `AA' = e(aggte)
    forvalues i = 1/`=rowsof(`AA')' {
        forvalues j = 1/`=colsof(`AA')' {
            file write `fh' "post_`t',aggte,`i',`j'," %21.17e (`AA'[`i', `j']) _n
        }
    }
    }
    file close `fh'

    * The seeded bootstrap from source, which the accepted-library arm below is
    * judged against draw for draw. Analytical standard errors reach none of
    * the bootstrap machinery, so until this ran, no gate had ever taken a
    * draw from a compiled library: the class the draws are held in, the
    * seeded stream, and the table they become were all exercised from source
    * only. rseed() fixes the stream, so "the same numbers" is exact here and
    * not a tolerance.
    tempname BATT BB BV
    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) notyet ///
        wboot(reps(200) rseed(1))
    matrix `BATT' = e(attgt)
    matrix `BB' = e(b)
    matrix `BV' = e(V)

    * ---------------------------------------------------------------------------
    * The library, built the way src/build.do builds lcsdid_v2 -- including the
    * stamp it compiles in, because a library that says `source' is not the
    * shape an installed package has -- and staged with the ado files.
    * csdid.mata is deliberately NOT copied: its absence is what makes the
    * source fallback in every loader unavailable.
    * ---------------------------------------------------------------------------
    tempfile staged_mata
    filefilter "`root'/src/mata/csdid.mata" "`staged_mata'", ///
        from("2.0.0|source") to("2.0.0|`c(stata_version)'") replace
    mata: mata clear
    mata: mata set matastrict on
    do "`staged_mata'"
    mata: mata mlib create lcsdid_v2, dir("`scratch'") replace
    mata: mata mlib add lcsdid_v2 *(), dir("`scratch'") complete
    mata: mata mlib index

    * The search order as this session found it. Every arm below starts from
    * it, so that what one arm does to the order cannot be read as another
    * arm's doing.
    local matalibs0 "`c(matalibs)'"
    confirm file "`scratch'/lcsdid_v2.mlib"
    foreach f in csdid.ado _csdid_post.ado _csdid_engine_load.ado csdid_estat.ado csdid_stats.ado csdid_plot.ado csdid_p.ado {
    copy "`root'/src/ado/`f'" "`scratch'/`f'", replace
    }
    capture confirm file "`scratch'/csdid.mata"
    assert _rc == 601

    * ---------------------------------------------------------------------------
    * The fresh process.
    * ---------------------------------------------------------------------------
    shell cd "`scratch'" && stata-mp -b do "`root'/tests/stata/mlib-session-fresh.do" "`scratch'" "`rif'" "`data'" "`childcsv'" > /dev/null 2>&1
    capture confirm file "`childcsv'"
    if _rc {
    display as error "the library-only session wrote no results"
    exit 9
    }

    * ---------------------------------------------------------------------------
    * Judging.
    * ---------------------------------------------------------------------------
    import delimited using "`childcsv'", clear varnames(nonames) stringcols(_all)
    rename (v1 v2 v3 v4 v5) (channel item row col value)

    * The configuration first: a green run against a session that could still see
    * the source would prove nothing at all.
    quietly count if channel == "config" & item == "source_findfile_rc" & value == "601"
    assert r(N) == 1
    quietly count if channel == "config" & item == "mlib_findfile_rc" & value == "0"
    assert r(N) == 1
    quietly count if channel == "config" & item == "mlib_is_staged" & value == "1"
    assert r(N) == 1
    quietly count if channel == "config" & item == "ado_is_staged" & value == "1"
    assert r(N) == 1
    * and the library the session accepted is where the loader says it puts
    * it, on the one route that gets there without csdid.
    quietly count if channel == "config" & item == "matalibs_promoted" & value == "1"
    assert r(N) == 1

    * Every command in that session has to have completed. r(3261) here is the
    * engine refusing to exist, which is exactly what this test is for.
    quietly count if item == "rc"
    assert r(N) == 9
    quietly levelsof channel if item == "rc" & value != "0", local(failed) clean
    if "`failed'" != "" {
    display as error "the library-only session refused: `failed'"
    list channel item value if item == "rc" & value != "0", noobs
    exit 9
    }

    quietly drop if item == "rc" | channel == "config"
    rename value libvalue
    tempfile libfigs
    quietly save "`libfigs'"

    import delimited using "`refcsv'", clear varnames(nonames) stringcols(_all)
    rename (v1 v2 v3 v4 v5) (channel item row col value)
    quietly merge 1:1 channel item row col using "`libfigs'", assert(match) nogenerate
    assert _N > 0
    assert value == libvalue

    display as text "test-mlib-session: `=_N' figures identical from the compiled library, all four aggregation types reloaded from a RIF written by a prior session"

    * ---------------------------------------------------------------------------
    * The library's stamp, and what a wrong one costs.
    *
    * A compiled library answers the loader's name probe whichever csdid built
    * it and whichever Stata compiled it, so the probe cannot tell a usable
    * library from a leftover one. csdid_mlib_version() is what makes the
    * difference visible, and this cell is the reason to trust it. Four
    * libraries are staged, each in its own directory placed FIRST on the
    * adopath, and the same estimation is run against each:
    *
    *   this build     2.0.0|<this Stata>       accepted, and used
    *   a newer Stata  2.0.0|<this Stata + 1>   refused, source used instead
    *   another csdid  1.82.0|<this Stata>      refused, source used instead
    *   no stamp       (the function is absent) refused, source used instead
    *
    * The three refusals are the qualification: each of those libraries passes
    * the name probe, so without the stamp each would run, and the first two
    * are exactly the two ways a library goes wrong in the field -- a Stata
    * newer than the user's compiled it, or an older install left its own
    * behind. The refusals are read off the engine itself after the run, not
    * off the message: a session that fell back reports the source stamp.
    *
    * Falling back is only worth something if what it falls back to is right,
    * so every arm must also reproduce the source path's ATT(g,t) table figure
    * for figure.
    * ---------------------------------------------------------------------------
    local newer_stata = c(stata_version) + 1
    * SOME OTHER csdid's version, and deliberately not this one: it stands for
    * a library left behind by a different installation, so it must NOT move
    * when the package is stamped with a new version number. Every other
    * version literal in this file is a copy of the stamp csdid_mlib_version()
    * carries and is kept in step by tools/release/stamp-version.py, which is
    * why this one is held in a macro instead of written out beside them.
    local other_pkg "1.82.0"
    tempfile fp_thisbuild fp_newerstata fp_othercsdid fp_nostamp
    filefilter "`root'/src/mata/csdid.mata" "`fp_thisbuild'", ///
        from("2.0.0|source") to("2.0.0|`c(stata_version)'") replace
    filefilter "`root'/src/mata/csdid.mata" "`fp_newerstata'", ///
        from("2.0.0|source") to("2.0.0|`newer_stata'") replace
    filefilter "`root'/src/mata/csdid.mata" "`fp_othercsdid'", ///
        from("2.0.0|source") to("`other_pkg'|`c(stata_version)'") replace
    * A library that predates the stamp: the function is not merely wrong, it
    * is not there.
    filefilter "`root'/src/mata/csdid.mata" "`fp_nostamp'", ///
        from("csdid_mlib_version") to("csdid_mlib_absentstamp") replace

    foreach arm in thisbuild newerstata othercsdid nostamp {
        mkdir "`scratch'/stamp-`arm'"
        mata: mata clear
        mata: mata set matastrict on
        quietly do "`fp_`arm''"
        quietly mata: mata mlib create lcsdid_v2, dir("`scratch'/stamp-`arm'") replace
        quietly mata: mata mlib add lcsdid_v2 *(), dir("`scratch'/stamp-`arm'") complete
        confirm file "`scratch'/stamp-`arm'/lcsdid_v2.mlib"
    }

    foreach arm in thisbuild newerstata othercsdid nostamp {
        adopath ++ "`scratch'/stamp-`arm'"
        mata: mata clear
        * The search order this arm starts from: the list as this session
        * found it, plus wherever Stata's own indexing puts the library it has
        * just been shown. Restoring it here is what keeps one arm's doing out
        * of the next arm's reading -- `set matalibs' is a session-wide
        * setting, and an accepted library stays in front of everything that
        * follows it until something puts it back.
        set matalibs "`matalibs0'"
        quietly mata: mata mlib index
        local order_before "`c(matalibs)'"
        * Stata does not index an installed package first, which is the whole
        * reason the loader moves the one it accepts. If that stopped being
        * true, the assertions below would pass without testing anything.
        assert strpos(";`order_before';", ";lcsdid_v2;") > 1

        * What the accepted library's place should be, spelled out rather than
        * tested by prefix alone: the entry moves to the front and the rest of
        * the list is untouched, which is also what says it moved once rather
        * than being added a second time.
        local promoted ";`order_before';"
        local promoted : subinstr local promoted ";lcsdid_v2;" ";", all
        local promoted = substr("`promoted'", 2, strlen("`promoted'") - 2)
        local promoted "lcsdid_v2;`promoted'"

        import delimited using "`data'", clear asdouble
        tempfile armlog
        log using "`armlog'", replace text name(stamparm)
        csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
        * Where the library sits after the call that judged it. A library the
        * loader REFUSED is not a library to search first: the three refusing
        * arms fall back to the source and must leave the order exactly as
        * they found it.
        local order_after1 "`c(matalibs)'"
        if "`arm'" == "thisbuild" assert "`order_after1'" == "`promoted'"
        else                      assert "`order_after1'" == "`order_before'"

        * The second call of the session is the one that has to decide
        * nothing. It is also where a loader that re-judged the library every
        * time would promote one it had just refused: a session that fell back
        * reports the source stamp from then on, which is not a stale library
        * and reads as an acceptance to anything that only compares versions.
        csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
        log close stamparm
        assert "`c(matalibs)'" == "`order_after1'"

        * What the session ended up running: the source stamp means the loader
        * refused the staged library and reloaded the source. The decision the
        * session recorded has to be the engine it actually holds, and the
        * settings it holds it under -- a marker that could disagree with
        * either is a way to skip the decision after the thing it decided
        * about has changed.
        if "`arm'" == "thisbuild" mlib_marker_agrees "2.0.0|`c(stata_version)'"
        else                      mlib_marker_agrees "2.0.0|source"

        * and the note is printed exactly when the library was refused, and
        * says which of the two refusals this is. The user's position differs:
        * a leftover from another installation goes away on re-install, and a
        * library built by a newer Stata is what a shipped package looks like
        * to anyone whose Stata is older than the build machine's -- there is
        * nothing for them to do, and telling them to re-install would send
        * them round a loop that cannot end.
        mlib_log_says using "`armlog'", ///
            message("built by Stata `newer_stata' and this is Stata `c(stata_version)'") ///
            expect(`= "`arm'" == "newerstata"')
        mlib_log_says using "`armlog'", ///
            message("belongs to a different installation of csdid") ///
            expect(`= "`arm'" == "othercsdid" | "`arm'" == "nostamp"')
        mlib_log_says using "`armlog'", message("re-install csdid") ///
            expect(`= "`arm'" == "othercsdid" | "`arm'" == "nostamp"')
        mlib_log_says using "`armlog'", message("Nothing needs to be done") ///
            expect(`= "`arm'" == "newerstata"')

        tempname ARM
        matrix `ARM' = e(attgt)
        assert rowsof(`ARM') == rowsof(`ATT') & colsof(`ARM') == colsof(`ATT')
        assert mreldif(`ARM', `ATT') == 0

        * The accepted arm is the one running the library, so it is the arm
        * that takes its draws from it: same seed, same draws, same table, to
        * the bit. Everything the bootstrap owns travels in the library --
        * the class the draws are held in, the seeded stream and the screen --
        * and a class that did not serialise whole fails here rather than in a
        * user's estimation.
        if "`arm'" == "thisbuild" {
            import delimited using "`data'", clear asdouble
            csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) notyet ///
                wboot(reps(200) rseed(1))
            tempname ARMBATT ARMBB ARMBV
            matrix `ARMBATT' = e(attgt)
            matrix `ARMBB' = e(b)
            matrix `ARMBV' = e(V)
            assert mreldif(`ARMBATT', `BATT') == 0
            assert mreldif(`ARMBB', `BB') == 0
            assert mreldif(`ARMBV', `BV') == 0
            display as text "test-mlib-session: the seeded bootstrap from the compiled library is identical to the source path"
        }

        adopath - "`scratch'/stamp-`arm'"
    }
    display as text "test-mlib-session: the stamp accepts this build's library and refuses the other three, all four arms reproduce the source path's estimates exactly, and the refused libraries stay where they were in the search order"

    * ---------------------------------------------------------------------------
    * The installation changing under a running session.
    *
    * The four arms above each start from a cleared Mata, so each of them asks
    * the stamp question of a library. A session that has already estimated
    * does not: Mata answers a function name it is already holding without
    * going near a library, so that session's own copy of csdid_mlib_version()
    * answers for whatever library is really on the adopath. Move the adopath
    * from one csdid installation to another and the loader is holding the
    * departed installation's stamp, while every engine function the session
    * has not yet called -- the doubly-robust fitters here, because the first
    * estimation is method(reg) -- would be answered by the arriving library.
    * A stamp is not evidence about the adopath, and this is the arm that says
    * so: it is the one place in this file where the question is put to a
    * session that could answer it from memory.
    *
    * The arriving installation is the `other_pkg' library, which is the thing
    * the loader is required to refuse, so the refusal is the assertion --
    * the note that names another installation, an engine reporting the source
    * stamp afterwards, a marker that agrees with it, and the source path's
    * figures. Without them the estimation completes, says nothing, and is run
    * partly by each installation.
    * ---------------------------------------------------------------------------
    mata: mata clear
    set matalibs "`matalibs0'"
    adopath ++ "`scratch'/stamp-thisbuild"
    quietly mata: mata mlib index

    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(reg) analytical notyet
    mlib_marker_agrees "2.0.0|`c(stata_version)'"

    adopath - "`scratch'/stamp-thisbuild"
    adopath ++ "`scratch'/stamp-othercsdid"
    quietly mata: mata mlib index

    import delimited using "`data'", clear asdouble
    tempfile switchlog
    log using "`switchlog'", replace text name(switcharm)
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
    log close switcharm

    mlib_log_says using "`switchlog'", ///
        message("belongs to a different installation of csdid") expect(1)
    mlib_marker_agrees "2.0.0|source"

    tempname SWITCHATT
    matrix `SWITCHATT' = e(attgt)
    assert rowsof(`SWITCHATT') == rowsof(`ATT') & colsof(`SWITCHATT') == colsof(`ATT')
    assert mreldif(`SWITCHATT', `ATT') == 0

    adopath - "`scratch'/stamp-othercsdid"
    set matalibs "`matalibs0'"
    display as text "test-mlib-session: a session whose adopath moves to another csdid refuses the arriving library instead of answering from the departed one's stamp"

    * ---------------------------------------------------------------------------
    * The accepted library leaving the search order it was accepted into.
    *
    * Mata answers a name only from `c(matalibs)', so a library out of that
    * list is a library that cannot answer -- but only for the names the
    * session is not already holding, which is why a session that has
    * estimated once notices nothing: one estimation touches the whole engine.
    * `csdid_stats using' on a saved RIF file is the shape that does notice.
    * It holds the aggregation half and nothing else, so the next estimation
    * asks for csdid__prescan() and, with the library out of the list, is told
    * there is no such function -- in the middle of a command, with the
    * library sitting on the adopath the whole time.
    *
    * The library is the one already judged, so the answer is to put it back
    * rather than to judge it again: the estimation completes, on the source
    * path's figures, with the library returned to the front of the order.
    * ---------------------------------------------------------------------------
    mata: mata clear
    set matalibs "`matalibs0'"
    adopath ++ "`scratch'/stamp-thisbuild"
    quietly mata: mata mlib index

    csdid_stats using "`rif'", type(simple)
    mlib_marker_agrees "2.0.0|`c(stata_version)'"
    assert strpos(";`c(matalibs)';", ";lcsdid_v2;") == 1

    local order_less ";`c(matalibs)';"
    local order_less : subinstr local order_less ";lcsdid_v2;" ";", all
    local order_less = substr("`order_less'", 2, strlen("`order_less'") - 2)
    set matalibs "`order_less'"
    assert strpos(";`c(matalibs)';", ";lcsdid_v2;") == 0

    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
    assert strpos(";`c(matalibs)';", ";lcsdid_v2;") == 1
    mlib_marker_agrees "2.0.0|`c(stata_version)'"

    tempname ORDERATT
    matrix `ORDERATT' = e(attgt)
    assert rowsof(`ORDERATT') == rowsof(`ATT') & colsof(`ORDERATT') == colsof(`ATT')
    assert mreldif(`ORDERATT', `ATT') == 0

    adopath - "`scratch'/stamp-thisbuild"
    set matalibs "`matalibs0'"
    display as text "test-mlib-session: a library taken out of the search order is put back rather than judged again, and the estimation that needed it completes"

    * ---------------------------------------------------------------------------
    * The installation changing under a session that changed nothing but its
    * working directory.
    *
    * `.' is an ado-path entry on every default installation, so a library in
    * the working directory is a library on the ado-path -- and `cd' replaces it
    * with whatever the next directory holds while c(adopath), c(matalibs) and
    * all five sysdir values stay character for character the same. A session
    * that decided which engine to use before the cd would go on believing that
    * decision about a different file.
    *
    * The trap below answers the loader's name probe and says it is another
    * csdid's, which is the library the loader is required to refuse; it holds
    * two functions and nothing else, so a session that does NOT notice it goes
    * on to ask it for the first engine function the session is not already
    * holding. The first leg here is analytical, so that function is in the
    * bootstrap, and the failure is `csdid__bmisc_rng_init() not found' in the
    * middle of a user's estimation rather than anything a return code of 0
    * would let through.
    *
    * The recorded library path is the other half. findfile answers `./
    * lcsdid_v2.mlib' for a library reached through `.', and two directories
    * answer that name with two different files -- so the path the decision is
    * recorded against must be absolute, and the first leg asserts that it is.
    * ---------------------------------------------------------------------------
    mkdir "`scratch'/cwd-lib"
    mkdir "`scratch'/cwd-trap"
    copy "`scratch'/lcsdid_v2.mlib" "`scratch'/cwd-lib/lcsdid_v2.mlib", replace

    * The trap holds the two functions the loader asks a library for and
    * nothing else: the name it probes with and the stamp it judges by. It is
    * the `other_pkg' source, so the stamp is the one the loader must refuse,
    * and the two-member `mlib add' is what makes every OTHER engine name
    * unanswerable from it.
    mata: mata clear
    mata: mata set matastrict on
    quietly do "`fp_othercsdid'"
    quietly mata: mata mlib create lcsdid_v2, dir("`scratch'/cwd-trap") replace
    quietly mata: mata mlib add lcsdid_v2 csdid_mlib_version() csdid__mean(), dir("`scratch'/cwd-trap")
    confirm file "`scratch'/cwd-trap/lcsdid_v2.mlib"

    mata: mata clear
    set matalibs "`matalibs0'"
    cd "`scratch'/cwd-lib"
    local cwd_lib "`c(pwd)'"
    quietly mata: mata mlib index

    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(reg) analytical notyet
    mlib_marker_agrees "2.0.0|`c(stata_version)'"
    * The decision was recorded against a file, not against a name that means
    * whatever the working directory makes it mean.
    assert `"$CSDID_ENGINE_LIBRARY"' == `"`cwd_lib'/lcsdid_v2.mlib"'

    cd "`scratch'/cwd-trap"
    local cwd_trap "`c(pwd)'"
    assert "`cwd_trap'" != "`cwd_lib'"
    quietly mata: mata mlib index

    import delimited using "`data'", clear asdouble
    tempfile cwdlog
    log using "`cwdlog'", replace text name(cwdarm)
    capture noisily csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) notyet ///
        wboot(reps(200) rseed(1))
    local cwd_rc = _rc
    log close cwdarm
    if `cwd_rc' {
        display as error "test-mlib-session: after cd the session ran against the library it had not judged (rc `cwd_rc')"
    }
    assert `cwd_rc' == 0

    * The trap is refused and the source is what answered, so the marker says
    * source, the note names the case, and the figures are the ones the source
    * path produced at the top of this file -- draw for draw, same seed.
    mlib_log_says using "`cwdlog'", ///
        message("belongs to a different installation of csdid") expect(1)
    mlib_marker_agrees "2.0.0|source"
    assert `"$CSDID_ENGINE_LIBRARY"' == `"`cwd_trap'/lcsdid_v2.mlib"'

    tempname CWDATT CWDB CWDV
    matrix `CWDATT' = e(attgt)
    matrix `CWDB' = e(b)
    matrix `CWDV' = e(V)
    assert mreldif(`CWDATT', `BATT') == 0
    assert mreldif(`CWDB', `BB') == 0
    assert mreldif(`CWDV', `BV') == 0

    cd "`root'"
    mata: mata clear
    set matalibs "`matalibs0'"
    display as text "test-mlib-session: a session that only changes directory is sent back through the engine decision, and the library it decided about is recorded by a path that means one file"

    display as text "test-mlib-session passed"

}
capture cd "`root'"
local staged_rc = _rc
if `staged_rc' {
    display as error "test-mlib-session: the library-only session's log follows"
    capture confirm file "`scratch'/fresh-session.log"
    if _rc == 0 type "`scratch'/fresh-session.log"
    capture confirm file "`scratch'/mlib-session-fresh.log"
    if _rc == 0 type "`scratch'/mlib-session-fresh.log"
}
mlib_stage_clean "`scratch'"
if `staged_rc' exit `staged_rc'
