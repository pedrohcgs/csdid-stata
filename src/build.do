* Version number deliberately omitted, per the [M-3] lmbuild exemplar: this
* script's whole purpose is to produce a modern library, so nothing here is
* to be backdated -- the COMPILE-TIME version is pinned where it belongs, by
* the `version 14' at the top of src/mata/csdid.mata.
capture mkdir build

* ---------------------------------------------------------------------------
* The build host is pinned. A .mlib is object code readable only by the Stata
* that compiled it and newer, so which Stata runs this script decides which
* users get the precompiled engine: at 17, Stata 14-16 installations read the
* shipped source instead (announced by the loader, identical numbers, one
* compile per session). Moving this floor -- up on a Stata upgrade, down if a
* Stata 14 build machine appears -- is a release decision, not an accident of
* whichever machine ran the build; change the number here and the shipped-mlib
* stamp gate together, deliberately.
* ---------------------------------------------------------------------------
if c(stata_version) != 17 {
    display as error "the release library is built by Stata 17 (this is `c(stata_version)'); see the build-host note above before changing this"
    exit 459
}

* ---------------------------------------------------------------------------
* The library's stamp.
*
* csdid_mlib_version() ships in the source reading "2.0.0|source". The copy
* compiled into the library says which Stata compiled it instead, because that
* is what csdid.ado cannot find out any other way and what it has to know: a
* library built by a newer Stata than the one running has every name the
* loader probes and fails later, inside an estimation. The substitution
* happens in a COPY, so the source file -- which ships as the fallback and is
* compiled by whatever Stata loads it -- keeps the word it should.
* ---------------------------------------------------------------------------
* The previous library is erased FIRST: a build that aborts anywhere below --
* the host pin, the compile, the note gate -- must leave no artifact for the
* copy step (or a harness trusting batch Stata's exit-0) to pick up as fresh.
capture erase build/lcsdid_v2.mlib
capture erase pkg/lcsdid_v2.mlib
tempfile stamped
filefilter "src/mata/csdid.mata" "`stamped'", ///
    from("2.0.0|source") to("2.0.0|`c(stata_version)'") replace
mata: mata clear
* All three compile-time settings are pinned, not just strictness. matalnum
* keeps line numbers in the compiled code and DEFEATS the optimizer; a build
* host that happened to have it on produced a library 16% larger with no error
* and nothing in the suite able to notice, and mataoptimize off makes the
* compiled engine slower in a way no numeric gate can see. What the shipped
* library is must not depend on how the machine that built it was configured.
mata: mata set matastrict on
mata: mata set matalnum off
mata: mata set mataoptimize on
* ---------------------------------------------------------------------------
* The compiler's NOTES are read, not just its return code. A note is the
* compiler flagging a conceptual error -- a variable set and never used is
* how dead state and shadowed logic ship silently -- and rc alone cannot see
* them. The compile is logged and any `note:' line stops the build.
* ---------------------------------------------------------------------------
tempfile compile_log
quietly log using "`compile_log'", text name(csdid_compile)
* Under an ENCLOSING quietly (a harness that runs `quietly do src/build.do')
* no output reaches this log at all -- noisily does not override an
* enclosing quietly ([P] quietly) -- so the two log-reading gates below skip
* themselves explicitly on that path instead of misfiring on an empty file.
* The canonical release build is the noisy batch run, where both gates bite.
do "`stamped'"
quietly log close csdid_compile
* The scan runs in Mata: an echoed source line can hold any quote or macro
* character, which no ado file-read loop can expand safely (measured: r(132)).
* A compiler note starts its line, so the match is anchored at column 1.
local compile_notes 0
if c(noisily) {
    mata: st_local("compile_notes", strofreal(rows(cat(st_local("compile_log"))) == 0 ? 0 : sum(strpos(cat(st_local("compile_log")), "note:") :== 1)))
}
if `compile_notes' > 0 {
    copy "`compile_log'" build/mata-compile.log, replace
    display as error "the Mata compile emitted `compile_notes' note(s); a note is a flagged conceptual error, not style -- fix the source (or deliberately pragma it) before building. The full compile log is build/mata-compile.log"
    exit 459
}
mata: st_local("built_stamp", csdid_mlib_version())
assert "`built_stamp'" == "2.0.0|`c(stata_version)'"

* ---------------------------------------------------------------------------
* Precompiled Mata library.
*
* Without it, csdid.ado falls back to `do csdid.mata', which COMPILES ~8,500
* lines of Mata source on the first csdid call of every Stata session.
* Measured on mpdta: first call 0.799s vs 0.024s for subsequent calls, i.e.
* ~0.77s of pure compilation that every user pays once per session (on a
* 38,890-row panel, 2.26s -> 1.51s end to end). Shipping lcsdid_v2.mlib
* removes it. Results are unchanged by construction: identical source,
* compiled ahead of time rather than on demand (verified bit-identical on
* mpdta).
*
* Stata indexes l*.mlib found along the adopath, so the library is picked up
* automatically once installed; csdid.ado retains the source fallback for
* installations where the library is absent or was built by an incompatible
* Stata version.
*
* The library is named lcsdid_v2, NOT lcsdid: the csdid2 package distributes
* a library called lcsdid.mlib, so shipping the same filename would make the
* two packages overwrite each other's library on installation.
*
* `complete' makes the add REFUSE a class definition that is not whole, rather
* than saving the part it has. The engine carries three, and a partially
* serialised class does not fail at load: it fails later, inside a user's
* estimation, on whichever member did not travel. Trading that for a build
* that stops here is not a close call.
* ---------------------------------------------------------------------------
* size() is explicit (163 members today, headroom to 512, hard Mata cap 2048),
* and the add is scoped to the package namespace rather than a bare *() --
* the library's contents are an intended list, not whatever the session held.
mata: mata mlib create lcsdid_v2, dir("build") replace size(512)
mata: mata mlib add lcsdid_v2 csdid*(), dir("build") complete
mata: mata mlib index
* ---------------------------------------------------------------------------
* The member count is asserted against the engine's own banner arithmetic
* (132 free functions + 3 classes + 28 methods = 163; src/mata/csdid.mata,
* "HOW MANY NAMES"). A count that moved means the source and this build
* disagree about what the library holds -- drift this gate exists to stop.
* ---------------------------------------------------------------------------
* `mata describe using' resolves its library over the ado-path only (dir()
* is not among its options -- measured), so build/ joins the path for the
* one statement that reads the file just written, and leaves it after.
adopath ++ "build"
tempfile desc_log
quietly log using "`desc_log'", text name(csdid_desc)
mata: mata describe using lcsdid_v2
quietly log close csdid_desc
adopath - "build"
local member_ok 0
if c(noisily) {
    mata: st_local("member_ok", strofreal(rows(cat(st_local("desc_log"))) == 0 ? 0 : sum(strpos(cat(st_local("desc_log")), "library contains 163 members") :> 0)))
}
else {
    * the gate cannot read suppressed output; the noisy release build is
    * where it runs.
    local member_ok 1
}
if `member_ok' == 0 {
    display as error "lcsdid_v2 does not hold the 163 members the source declares (mata describe using lcsdid_v2 disagrees)"
    display as error "update the count here AND the csdid.mata banner together if the surface deliberately changed"
    exit 459
}
copy src/ado/csdid.ado build/csdid.ado, replace
copy src/ado/_csdid_post.ado build/_csdid_post.ado, replace
copy src/ado/_csdid_engine_load.ado build/_csdid_engine_load.ado, replace
copy src/ado/csdid_estat.ado build/csdid_estat.ado, replace
copy src/ado/csdid_stats.ado build/csdid_stats.ado, replace
copy src/ado/csdid_plot.ado build/csdid_plot.ado, replace
copy src/ado/csdid_p.ado build/csdid_p.ado, replace

* ---------------------------------------------------------------------------
* Utility and legacy commands carried over from csdid Version 1.82.
*
* csgvar/_gcsgvar build the gvar cohort variable from a treatment indicator and
* are SUPPORTED: self-contained, no dependency on csdid internals.
*
* csdid_rif, csdid_table, dipt and tsvmat are DEPRECATED. They ship so that
* existing do-files keep running, each printing a notice on invocation. They
* are not covered by the parity suite. Stata compiles an ado only when its
* command is first called and no csdid command calls any of them, so shipping
* them costs nothing at runtime.
* ---------------------------------------------------------------------------
copy src/ado/csgvar.ado build/csgvar.ado, replace
copy src/ado/_gcsgvar.ado build/_gcsgvar.ado, replace
copy src/legacy/csdid_rif.ado build/csdid_rif.ado, replace
copy src/legacy/csdid_table.ado build/csdid_table.ado, replace
copy src/legacy/dipt.ado build/dipt.ado, replace
copy src/legacy/tsvmat.ado build/tsvmat.ado, replace
copy src/help/csdid_legacy.sthlp build/csdid_legacy.sthlp, replace
copy src/mata/csdid.mata build/csdid.mata, replace
copy src/help/csdid.sthlp build/csdid.sthlp, replace
copy src/help/csdid_postestimation.sthlp build/csdid_postestimation.sthlp, replace
copy src/help/csdid_estat.sthlp build/csdid_estat.sthlp, replace
copy src/help/csdid_stats.sthlp build/csdid_stats.sthlp, replace
copy src/help/csdid_plot.sthlp build/csdid_plot.sthlp, replace
copy src/help/csdid_whatsnew.sthlp build/csdid_whatsnew.sthlp, replace
* csgvar has its own full help topic; the four deprecated commands keep
* one-line `.h' aliases so that a user who types the command name reaches
* help by that name (without them `help dipt' answered "help not found" on
* an installation that has dipt.ado).
foreach f in csgvar csdid_rif csdid_table dipt tsvmat {
    copy "src/help/`f'.sthlp" "build/`f'.sthlp", replace
}
capture erase build/stata.toc
capture erase build/csdid.pkg

* ---------------------------------------------------------------------------
* Tracked distribution directory.
*
* csdid.pkg used to name files under build/, which .gitignore excludes, so
* every path the manifest promised was untracked, and installing the package
* from its public repository URL -- the only route a public audience has --
* resolved to nothing.
* pkg/ is committed, so the manifest points at files that actually exist in
* the repository. build/ is retained unchanged for the local test harness,
* which loads the runtime from there.
* ---------------------------------------------------------------------------
capture mkdir pkg
foreach f in csdid.ado _csdid_post.ado _csdid_engine_load.ado csdid_estat.ado csdid_stats.ado csdid_plot.ado csdid_p.ado ///
             csgvar.ado _gcsgvar.ado csdid_rif.ado csdid_table.ado dipt.ado tsvmat.ado {
    copy "build/`f'" "pkg/`f'", replace
}
copy build/csdid.mata pkg/csdid.mata, replace
capture erase build/lcsdid.mlib
capture erase pkg/lcsdid.mlib
copy build/lcsdid_v2.mlib pkg/lcsdid_v2.mlib, replace
* The license travels with the installed files (MIT's notice condition), and
* the example dataset ships as an ancillary a user retrieves with net get.
copy LICENSE pkg/LICENSE, replace
copy src/data/mpdta.dta pkg/mpdta.dta, replace
foreach f in csdid.sthlp csdid_postestimation.sthlp csdid_estat.sthlp csdid_stats.sthlp csdid_plot.sthlp ///
             csdid_legacy.sthlp csgvar.sthlp csdid_rif.sthlp csdid_table.sthlp dipt.sthlp tsvmat.sthlp ///
             csdid_whatsnew.sthlp {
    copy "build/`f'" "pkg/`f'", replace
}

* ---------------------------------------------------------------------------
* The compiled accelerator.
*
* It is a binary, so this copies the built file rather than producing it;
* tools/plugin/build-bootstrap-plugin.sh is what compiles it, from
* src/plugin/csdid_bootstrap_plugin.c. Copying it HERE is what makes pkg/ the
* output of this script and nothing else: while the plugin sat outside the
* build, pkg/ kept a binary placed by hand, and it went nine days stale
* against a C source that had gained an RNG guard -- macOS installs ran an
* accelerator that accepted the one absorbing state of MT19937 and reported
* success. A detector was added for that; this is the cause.
* ---------------------------------------------------------------------------
* The release payload ships ONE copy of the binary, in pkg/, and strips the
* one in src/ado -- so in that tree there is no source copy to refresh from
* and nothing to refresh. It is recognised by the absence of the script that
* assembles it, which the payload also strips. In the development tree the
* source copy is required, and a missing one stops the build naming the script
* that compiles it rather than quietly shipping the previous binary.
capture confirm file "tools/release/build-release-payload.sh"
local plugin_from_source = (_rc == 0)
foreach f in csdid_bootstrap_macosx.plugin {
    if `plugin_from_source' {
        capture confirm file "src/ado/`f'"
        if _rc {
            display as error "src/ado/`f' is missing -- build it with tools/plugin/build-bootstrap-plugin.sh, then rerun this script"
            exit 601
        }
        copy "src/ado/`f'" "build/`f'", replace
        copy "build/`f'" "pkg/`f'", replace
        * Stata's `copy' does not carry file permissions, and this one is a
        * compiled binary that the tree tracks executable. Restore the bit
        * rather than let a rebuild rewrite the mode of a shipped file.
        if "`c(os)'" != "Windows" {
            capture shell chmod 755 "build/`f'" "pkg/`f'"
        }
    }
}

* ---------------------------------------------------------------------------
* The manifest and the payload must name the same files, both ways.
*
* csdid.pkg and stata.toc are NOT written here: they carry the package
* description, the author list and the distribution date, which are editorial
* and belong to a human. What is mechanical is the agreement between the `f'
* lines and what this script just produced, and that is checked -- in both
* directions, because each has failed on its own. A manifest line with no file
* behind it makes `net install' 404 for every user; a file in pkg/ that no
* line names is built, committed, and never delivered.
* ---------------------------------------------------------------------------
tempname pkgfh
local manifest ""
file open `pkgfh' using "csdid.pkg", read text
file read `pkgfh' pkgline
while r(eof) == 0 {
    local pkgkind : word 1 of `macval(pkgline)'
    if inlist("`pkgkind'", "f", "F") {
        local pkgpath : word 2 of `macval(pkgline)'
        local manifest "`manifest' `pkgpath'"
    }
    * g/G lines gate a file by platform; the FILE is word 3. The same path
    * may appear once per platform, so it joins the manifest only once.
    if inlist("`pkgkind'", "g", "G") {
        local pkgpath : word 3 of `macval(pkgline)'
        local hit : list posof "`pkgpath'" in manifest
        if !`hit' local manifest "`manifest' `pkgpath'"
    }
    file read `pkgfh' pkgline
}
file close `pkgfh'
local manifest = strtrim("`manifest'")
if "`manifest'" == "" {
    display as error "csdid.pkg declares no files -- this check would verify nothing"
    exit 459
}
local pkgbad 0
foreach p of local manifest {
    capture confirm file "`p'"
    if _rc {
        display as error "csdid.pkg names `p', which this build did not produce"
        local pkgbad = `pkgbad' + 1
    }
}
local shipped : dir "pkg" files "*"
foreach s of local shipped {
    local sname `s'
    if substr("`sname'", 1, 1) != "." {
        local hit : list posof "pkg/`sname'" in manifest
        if !`hit' {
            display as error "pkg/`sname' is in the payload directory but no manifest line in csdid.pkg delivers it"
            local pkgbad = `pkgbad' + 1
        }
    }
}
if `pkgbad' {
    display as error "csdid.pkg and pkg/ disagree on `pkgbad' file(s); net install delivers the manifest, not the directory"
    exit 459
}
display as text "packaged into pkg/ (commit this directory; net install reads it)"
display as text "csdid.pkg and pkg/ agree: `: word count `manifest'' files, each named once and present"
