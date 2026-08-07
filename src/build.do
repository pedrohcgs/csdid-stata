version 15
mata: mata clear
mata: mata set matastrict on
do src/mata/csdid.mata
capture mkdir build

* ---------------------------------------------------------------------------
* Precompiled Mata library.
*
* Without it, csdid.ado falls back to `do csdid.mata', which COMPILES ~5000
* lines of Mata source on the first csdid call of every Stata session.
* Measured on mpdta: first call 0.799s vs 0.024s for subsequent calls, i.e.
* ~0.77s of pure compilation that every user pays once per session (on a
* 38,890-row panel, 2.26s -> 1.51s end to end). Shipping lcsdid.mlib removes
* it. Results are unchanged by construction: identical source, compiled ahead
* of time rather than on demand (verified bit-identical on mpdta).
*
* Stata indexes l*.mlib found along the adopath, so the library is picked up
* automatically once installed; csdid.ado retains the source fallback for
* installations where the library is absent or was built by an incompatible
* Stata version.
* ---------------------------------------------------------------------------
mata: mata mlib create lcsdid, dir("build") replace
mata: mata mlib add lcsdid *(), dir("build")
mata: mata mlib index
copy src/ado/csdid.ado build/csdid.ado, replace
copy src/ado/_csdid_post.ado build/_csdid_post.ado, replace
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
foreach f in csdid.ado _csdid_post.ado csdid_estat.ado csdid_stats.ado csdid_plot.ado csdid_p.ado ///
             csgvar.ado _gcsgvar.ado csdid_rif.ado csdid_table.ado dipt.ado tsvmat.ado {
    copy "build/`f'" "pkg/`f'", replace
}
* The compiled plugin. It was NOT copied here before, so pkg/ kept whatever
* binary was placed by hand: the shipped macOS plugin sat nine days behind its
* own C source and lacked the all-zero RNG-state guard, while src/ado/ carried
* a build that had it. net install ships pkg/, so macOS users got the stale one.
foreach p in csdid_bootstrap_macosx.plugin csdid_bootstrap_unix.plugin ///
             csdid_bootstrap_windows.plugin {
    capture confirm file "build/`p'"
    if !_rc {
        copy "build/`p'" "src/ado/`p'", replace
        copy "build/`p'" "pkg/`p'", replace
        display as text "packaged `p'"
    }
}

copy build/csdid.mata pkg/csdid.mata, replace
copy build/lcsdid.mlib pkg/lcsdid.mlib, replace
foreach f in csdid.sthlp csdid_postestimation.sthlp csdid_estat.sthlp csdid_stats.sthlp csdid_plot.sthlp ///
             csdid_legacy.sthlp {
    copy "build/`f'" "pkg/`f'", replace
}
display as text "packaged into pkg/ (commit this directory; net install reads it)"
