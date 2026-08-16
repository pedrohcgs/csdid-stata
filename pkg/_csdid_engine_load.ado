*! _csdid_engine_load 2.0.0 30jul2026
* ---------------------------------------------------------------------------
* Bringing the Mata engine into the session.
*
* Two commands need the engine and only one of them is csdid: `csdid_stats
* using <riffile>' aggregates an estimation that ran in an earlier session, so
* it reaches the engine with no csdid before it. Both arrive here, and the
* rules are written once: probe the name, index a package installed during
* this session, ask the library what it is, keep it or fall back to the
* source, put the library that was kept where Stata will find it quickly, and
* notice on every later call if the installation under the session has moved.
*
* Callers get an engine or an error. Nothing else is returned; the caller's
* own state is untouched.
* ---------------------------------------------------------------------------
program define _csdid_engine_load
    version 14

    * -----------------------------------------------------------------------
    * DECIDED ONCE PER SESSION.
    *
    * Everything below is a question about the installation, not about the
    * command being run: which library is on the adopath, whether this csdid
    * built it, whether this Stata can read it. It is settled on the call that
    * first needs an engine and written into $CSDID_ENGINE_RESOLVED -- the
    * stamp of the engine the session settled on, and the settings that stamp
    * was an answer about.
    *
    * The settings are half of the marker because the stamp is not evidence
    * about the adopath. csdid_mlib_version() is a Mata function, and Mata
    * answers a name it is already holding without going near a library, so a
    * copy held from one installation keeps answering after the adopath has
    * moved to another. The stamp says what the session HOLDS; what it would
    * LOAD is said by Stata's own settings, where a held function has no vote.
    * Those are what the marker carries: the library list Mata searches, the
    * ado-path, and the directories the ado-path's keywords stand for. Between
    * them they decide which file answers a name Mata is not holding, and a
    * change in any of them sends the session back through the decision below.
    *
    * The WORKING DIRECTORY is the ninth, and it is there because an ado-path
    * entry may be relative: `.' is one on every default installation, so a
    * library sitting in the working directory is a library on the ado-path,
    * and `cd' replaces it with whatever the next directory holds while
    * c(adopath) and all five sysdir values stay character for character the
    * same. Measured: a session that estimated once, then cd'd into a directory
    * holding another lcsdid_v2.mlib, then bootstrapped, died with
    * `csdid__bmisc_rng_init() not found' -- the arriving library answering for
    * the one function the first estimation had not made the session hold.
    *
    * It is read unconditionally, and the alternative was measured rather than
    * assumed. c(pwd) is the one expensive c() here -- 9.5-12.5us against
    * 0.6-0.8us for c(sysdir_base), because it is asked of the operating system
    * and not of a setting Stata is holding -- so asking first whether the
    * ado-path has any relative entry looks like the thrifty design. It is not:
    * in ado it is the number of STATEMENTS that costs, and the three-line
    * conditional that would skip the read measured the same 16-18us as the
    * read it skips, while also having to walk the ado-path. A session whose
    * ado-path is entirely absolute therefore re-decides once after each `cd'
    * and finds nothing changed, which costs it one decision and no Mata state:
    * the block below discards nothing when the library resolves to the same
    * file.
    *
    * The stamp is what says an engine is there at all: `mata clear' takes it
    * away, the call below then fails, and the session decides again from the
    * top. The marker itself outlives `clear all' (measured on 17.0 and 19.5:
    * only `macro drop _all' removes it), which is harmless precisely because
    * the stamp half is checked first and fails once Mata has been cleared.
    *
    * Measured 2026-08-16, 2,000 calls x 5 rounds x 6 processes per arm, arms
    * interleaved and their order rotated, every arm in the same loop so that
    * the loop is in all of the figures. On a session holding an accepted
    * library: 46.0-50.5us for the question below, against 177.5-195.5us for
    * the block it skips. Without the working directory the same question read
    * 29.5-34.5us and the same block 128.5-147.0us. On a source-only session
    * the two arms are 46.0-51.0 against 222.0-238.5, and 29.5-35.5 against
    * 162.0-182.5. Asking the stamp and nothing else is 12.0-17.5us in every
    * one of them, so the Mata crossing is a quarter of the question and
    * c(pwd) is a further third; the question stays well under the block it
    * skips either way, and it is asked once per command, not once per cell.
    * -----------------------------------------------------------------------
    local live_stamp ""
    capture mata: st_local("live_stamp", csdid_mlib_version())
    if !_rc & `"`live_stamp'"' != "" {
        local live_mark `"`live_stamp';`c(adopath)';`c(matalibs)';`c(sysdir_base)';`c(sysdir_site)';`c(sysdir_personal)';`c(sysdir_plus)';`c(sysdir_oldplace)';`c(pwd)'"'
        if `"$CSDID_ENGINE_RESOLVED"' == `"`live_mark'"' exit
    }

    * -----------------------------------------------------------------------
    * WHICH LIBRARY THE SESSION LAST DECIDED ABOUT.
    *
    * The marker above says that something able to decide has moved. This says
    * what it moved to: the file the ado-path now resolves lcsdid_v2 to, asked
    * of the filesystem, where nothing held in memory can answer, against
    * $CSDID_ENGINE_LIBRARY -- the file the last decision was made about.
    *
    * While that is the same file the last decision was made about, the engine
    * in memory came from it and the questions below may be put to the engine
    * in memory -- an ado-path that gained a directory for some other package
    * has changed nothing about csdid, and re-deciding costs the session its
    * Mata state for no reason. When it is a DIFFERENT file, or none, nothing
    * held can speak for it: the stamp, the class definitions and every engine
    * function in memory belong to the installation that left, so the version
    * gate below would be shown the departed library's stamp and would accept
    * the arriving library's code, and the estimation that followed would run
    * two installations' functions at once. That is the case this block
    * exists for, and the only way out of it is to stop holding the departed
    * engine: the memory goes and the index is rebuilt, and everything below
    * then reads the installation that is actually there.
    *
    * The same file, out of the search order, is the other way the session can
    * arrive here and is a repair rather than a re-decision: the library Mata
    * would have read is the one already judged, so nothing has to be
    * discarded and re-indexing puts it back where the decision left it.
    * Being out of the order is not harmless while it lasts -- Mata answers
    * only from the list, so a name the session has not yet called cannot be
    * found at all, which is `csdid__prescan() not found' in the middle of an
    * estimation for any session holding less than the whole engine. A
    * `csdid_stats using' on a saved RIF file holds exactly the aggregation
    * half, and is the shape a user meets it in.
    *
    * A library REPLACED IN PLACE -- same path, same list -- is not visible
    * here, and seeing it would mean reading the file's contents on every
    * call. Measured in the same loop as the figures above: `findfile' alone
    * is 26.0-26.5us, which is most of what the whole question above costs,
    * and reading the file is far more again, so the file is resolved only
    * once the cheap question has said that something moved.
    * -----------------------------------------------------------------------
    capture quietly findfile lcsdid_v2.mlib
    local mlib_found = (_rc == 0)
    local mlib_file "none"
    if `mlib_found' {
        * findfile answers with the path it matched on, and that path is
        * relative whenever the ado-path entry it matched under is -- `./
        * lcsdid_v2.mlib' is what a default installation returns for a library
        * sitting in the working directory. A relative name is not a name for a
        * file: two directories answer it with two different libraries, and the
        * identity test below would call them the same one. It is made absolute
        * here, once, on the path that has already decided something moved --
        * never on the per-call question above, which is why this costs nothing
        * a session pays repeatedly.
        *
        * The separator is char(92) and never a written-out backslash: a
        * one-character macro holding one, expanded between quotes, escapes the
        * quote that follows it and the command dies at r(132) instead. Kept
        * inside the expression, the character is never expanded at all.
        local mlib_file `"`r(fn)'"'
        if substr(`"`mlib_file'"', 1, 1) == "." & ///
            inlist(substr(`"`mlib_file'"', 2, 1), "/", char(92)) {
            local mlib_file = substr(`"`mlib_file'"', 3, .)
        }
        if !(inlist(substr(`"`mlib_file'"', 1, 1), "/", char(92), "~") | ///
            substr(`"`mlib_file'"', 2, 1) == ":") {
            local mlib_file `"`c(pwd)'`c(dirsep)'`mlib_file'"'
        }
    }
    if `"$CSDID_ENGINE_LIBRARY"' != "" {
        if `"$CSDID_ENGINE_LIBRARY"' != `"`mlib_file'"' {
            mata: mata clear
            capture quietly mata: mata mlib index
        }
        else if `mlib_found' & strpos(";`c(matalibs)';", ";lcsdid_v2;") == 0 {
            capture quietly mata: mata mlib index
        }
    }

    * -----------------------------------------------------------------------
    * Is an engine reachable at all? The name probe answers from a compiled
    * library or from a source copy this session already compiled, and cannot
    * tell them apart -- that is the stamp's job, below. `mata mlib index' is
    * retried once because a package installed during this session is not in
    * the index Stata built when it started.
    * -----------------------------------------------------------------------
    local engine_from_source = 0
    capture mata: csdid__mean(J(1, 1, 0))
    if _rc {
        capture quietly mata: mata mlib index
        capture mata: csdid__mean(J(1, 1, 0))
    }
    if _rc {
        capture quietly findfile csdid.mata
        if _rc {
            display as error "csdid Mata source not found on adopath"
            exit 499
        }
        quietly do "`r(fn)'"
        local engine_from_source = 1
    }

    * -----------------------------------------------------------------------
    * A compiled library that answered the probe has to be THIS csdid's,
    * compiled by a Stata this one can read. The probe establishes neither: a
    * library left behind by an earlier csdid answers it with its own code, and
    * one compiled by a NEWER Stata answers it until some function it uses
    * turns out not to exist here, in the middle of an estimation. Both are
    * wrong numbers or unaccountable failures rather than load errors -- the
    * failure mode that put `panelsum() not found' in front of boottest's users
    * in 2020 -- so the library is asked what it is.
    *
    * The package half must match exactly. The Stata half must not be NEWER
    * than this session: a library compiled by an older Stata runs here, which
    * is why this is not an equality test -- making it one would send every
    * user whose Stata is not the build machine's down the source path, and the
    * source path is the slow one the library exists to remove. A library with
    * no stamp at all predates the stamp, which makes it another csdid's.
    *
    * Discarding it takes `mata clear', not just a reload: the library's
    * functions are already in the session, its class definitions with them,
    * and CSDID_GLOBALS_READY would otherwise tell csdid__globals_init that an
    * engine built against the discarded definitions is ready to use. Clearing
    * costs the session its Mata state, which is why it happens only here, on
    * the one call that discovers the mismatch: the source loaded next defines
    * the same names, a session resolves its own definitions before any
    * library's, and every later csdid call in this session stops at the
    * marker above and says nothing.
    *
    * The two refusals are told apart because the user's position differs. A
    * library belonging to another installation of csdid is a leftover, and
    * re-installing removes it. A library built by a NEWER Stata is not a
    * leftover and not a fault: it is what a shipped package looks like to
    * anyone whose Stata is older than the machine that built it, and there is
    * nothing for them to do -- csdid reads its source copy, which produces
    * the same numbers and only costs a moment more to load. Telling that user
    * to re-install would send them round a loop that cannot end, so the note
    * says which case this is and asks for nothing it cannot deliver.
    * -----------------------------------------------------------------------
    if !`engine_from_source' {
        local mlib_stamp ""
        capture mata: st_local("mlib_stamp", csdid_mlib_version())
        local mlib_bar = strpos("`mlib_stamp'", "|")
        local mlib_pkg = substr("`mlib_stamp'", 1, `mlib_bar' - 1)
        local mlib_stata = substr("`mlib_stamp'", `mlib_bar' + 1, .)
        local mlib_stale = ("`mlib_pkg'" != "2.0.0")
        local mlib_newer = 0
        if !`mlib_stale' & "`mlib_stata'" != "source" {
            local mlib_newer = (real("`mlib_stata'") < . & real("`mlib_stata'") > c(stata_version))
            local mlib_stale = (real("`mlib_stata'") >= . | `mlib_newer')
        }
        if `mlib_stale' {
            capture quietly findfile csdid.mata
            if _rc {
                display as error "csdid's compiled library cannot be used in this Stata and the source copy it falls back on is not on the adopath; re-install csdid"
                exit 499
            }
            if `mlib_newer' {
                display as text "note: csdid's compiled library was built by Stata `mlib_stata' and this is Stata `c(stata_version)', so csdid is reading its source copy instead. The results are the same; only the first csdid of a session takes a moment longer. Nothing needs to be done."
            }
            else {
                display as text "note: the compiled csdid library on the adopath belongs to a different installation of csdid and is being ignored; re-install csdid to replace it"
            }
            local mata_source "`r(fn)'"
            mata: mata clear
            quietly do "`mata_source'"
        }
        else if "`mlib_stata'" != "source" {
            * -------------------------------------------------------------
            * Where the accepted library sits in Stata's search order.
            *
            * Mata resolves a function name it is not already holding by
            * searching c(matalibs) in order, and an installed package is
            * indexed AFTER Stata's own libraries and after anything else
            * already installed -- twenty-one shipped libraries on a plain
            * installation, more wherever a user has other Mata packages --
            * so every FIRST call to an engine function is answered from the
            * end of the list. Measured on this machine over twenty-four
            * first calls, four sessions per arm: 29.5ms from last position
            * against 1.5ms from first, i.e. 1.17ms per function against
            * 0.06ms. The figure does not move with the number of members in
            * the library asked (48 and 424 both read 28ms), so it is the
            * position that costs and not the load.
            *
            * One estimation calls tens of engine functions for the first
            * time, so a fresh session paid tens of milliseconds of pure
            * lookup, and the bill grew with every function the engine was
            * split into: a charge on how the source is ARRANGED rather than
            * on what it computes. Measured end to end on a 50,000-row
            * panel, moving the library to the front takes the first
            * estimation of a session from 0.117s to 0.071s and the first
            * doubly-robust one from 0.122s to 0.105s; the second and later
            * estimations, which hold their functions already, do not move.
            *
            * What it costs everything else is nothing measurable. Every
            * global name the library defines begins with csdid, so a lookup
            * for anything else misses it and searches on. Measured
            * directly, by putting a 400-member library ahead of another
            * library's functions and timing twenty-four first calls to
            * them: 32.0ms against 32.5ms without it, six sessions per arm.
            * Position matters because of what stands in front, not because
            * of how many things do -- moving an unrelated library to the
            * front changes nothing (30ms), and neither does setting the
            * list to itself (29.5ms). Only the library holding the
            * functions being called is worth moving, which is why this
            * moves exactly one. Functions already held are not disturbed:
            * re-calling three of them after the reorder costs 0ms against
            * the 4ms their first calls cost.
            *
            * Only a library gets moved. A stamp whose second half reads
            * `source' is the source copy answering -- either this session
            * compiled it, or a library was compiled from a source that
            * src/build.do never stamped -- and there is nothing to promote
            * in the first case and no way to tell the two apart in the
            * second. The shipped library always carries the Stata that
            * built it, so this costs an installed package nothing, and it
            * is what keeps a REFUSED library out of the search order it was
            * refused from: a session that fell back reads `source' from
            * then on.
            * -------------------------------------------------------------
            local mlib_order ";`c(matalibs)';"
            if strpos("`mlib_order'", ";lcsdid_v2;") > 1 {
                local mlib_order : subinstr local mlib_order ";lcsdid_v2;" ";", all
                local mlib_order = substr("`mlib_order'", 2, strlen("`mlib_order'") - 2)
                set matalibs "lcsdid_v2;`mlib_order'"
            }
        }
    }

    * The decision, written down in the shape the top of this program checks
    * it in: what the engine this session ended up with says it is, and the
    * settings it says it about. The settings are read HERE, after the block
    * above has put the accepted library where it wants it -- reading them
    * before would record a library list this program was about to change, and
    * every later call would find the marker stale and decide again.
    local live_stamp ""
    capture mata: st_local("live_stamp", csdid_mlib_version())
    global CSDID_ENGINE_RESOLVED `"`live_stamp';`c(adopath)';`c(matalibs)';`c(sysdir_base)';`c(sysdir_site)';`c(sysdir_personal)';`c(sysdir_plus)';`c(sysdir_oldplace)';`c(pwd)'"'
    global CSDID_ENGINE_LIBRARY `"`mlib_file'"'
end
