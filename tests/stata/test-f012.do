version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/f012/expected/r/weighted-grid.csv"
confirm file "`root'/tests/fixtures/parity/f012/expected/r/time-invariant-fixweights.csv"
confirm file "`root'/tests/fixtures/parity/f012/expected/r/weighted-aggte.csv"
confirm file "`root'/tests/fixtures/parity/f012/expected/r/events.csv"
confirm file "`root'/tests/fixtures/parity/f012/inputs/input-unbalanced.csv"

program define f012_assert_log_contains
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    local found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`compact_body'"', `"`compact_message'"') > 0
    assert `found'
end

program define f012_assert_log_not_contains
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    local found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`compact_body'"', `"`compact_message'"') > 0
    assert !`found'
end

program define f012_save_agg
    version 15
    syntax , TYPE(string) PANELMODE(string) WEIGHTVAR(string) FIXWEIGHTS(string) ///
        COVARIATES(string) METHOD(string) SAVING(string) [APPEND]

    csdid_stats, type(`type')
    matrix M = e(aggte)
    preserve
    clear
    svmat double M, names(col)
    gen str24 panel_mode = "`panelmode'"
    gen str12 weight_var = "`weightvar'"
    gen str12 fix_weights = "`fixweights'"
    gen str12 covariates = "`covariates'"
    gen str8 method = "`method'"
    gen str16 type = "`type'"
    gen seq = _n
    rename (egt att se overall_att overall_se) ///
           (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
    keep panel_mode weight_var fix_weights covariates method type seq egt_stata ///
        att_stata se_stata overall_att_stata overall_se_stata
    if "`append'" != "" append using "`saving'"
    save "`saving'", replace
    restore
end

tempfile allactual
local first 1

foreach weight_var in wt wt_scaled {
    foreach fix_weights in default varying base_period first_period {
        local fixopt ""
        local expected_fix ""
        if "`fix_weights'" != "default" {
            local fixopt "fix_weights(`fix_weights')"
            local expected_fix "`fix_weights'"
        }
        foreach covariates in none numeric {
            foreach method in dr reg ipw {
                import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
                if "`covariates'" == "numeric" {
                    csdid y x1 x2 [iw=`weight_var'], ivar(id) time(time) gvar(g) method(`method') `fixopt' analytical
                }
                else {
                    csdid y [iw=`weight_var'], ivar(id) time(time) gvar(g) method(`method') `fixopt' analytical
                }
                assert e(method) == "`method'"
                assert "`e(panel_mode)'" == "panel"
                assert "`e(fix_weights)'" == "`expected_fix'"
                matrix A = e(attgt)
                clear
                svmat double A, names(col)
                gen str24 panel_mode = "panel"
                gen str12 weight_var = "`weight_var'"
                gen str12 fix_weights = "`fix_weights'"
                gen str12 covariates = "`covariates'"
                gen str8 method = "`method'"
                rename (att se) (att_stata se_stata)
                keep panel_mode weight_var fix_weights covariates method group time event_time att_stata se_stata
                if `first' {
                    save "`allactual'", replace
                    local first 0
                }
                else {
                    append using "`allactual'"
                    save "`allactual'", replace
                }
            }
        }
    }
}

foreach weight_var in wt wt_scaled {
    foreach fix_weights in default varying {
        local fixopt ""
        local expected_fix ""
        if "`fix_weights'" != "default" {
            local fixopt "fix_weights(`fix_weights')"
            local expected_fix "`fix_weights'"
        }
        foreach covariates in none numeric {
            foreach method in dr reg ipw {
                import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
                if "`covariates'" == "numeric" {
                    csdid y x1 x2 [iw=`weight_var'], time(time) gvar(g) method(`method') `fixopt' analytical
                }
                else {
                    csdid y [iw=`weight_var'], time(time) gvar(g) method(`method') `fixopt' analytical
                }
                assert e(method) == "`method'"
                assert "`e(panel_mode)'" == "repeated-cross-section"
                assert "`e(fix_weights)'" == "`expected_fix'"
                matrix A = e(attgt)
                clear
                svmat double A, names(col)
                gen str24 panel_mode = "repeated-cross-section"
                gen str12 weight_var = "`weight_var'"
                gen str12 fix_weights = "`fix_weights'"
                gen str12 covariates = "`covariates'"
                gen str8 method = "`method'"
                rename (att se) (att_stata se_stata)
                keep panel_mode weight_var fix_weights covariates method group time event_time att_stata se_stata
                append using "`allactual'"
                save "`allactual'", replace
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f012/expected/r/weighted-grid.csv", clear asdouble
merge 1:1 panel_mode weight_var fix_weights covariates method group time using "`allactual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8

preserve
keep if weight_var == "wt"
keep panel_mode fix_weights covariates method group time att se
rename (att se) (att_w se_w)
tempfile base
save "`base'"
restore

keep if weight_var == "wt_scaled"
merge 1:1 panel_mode fix_weights covariates method group time using "`base'", nogen assert(match)
assert abs(att - att_w) < 1e-12
assert abs(se - se_w) < 1e-10

tempfile allactual_const
local first_const 1
foreach fix_weights in default varying base_period first_period {
    local fixopt ""
    local expected_fix ""
    if "`fix_weights'" != "default" {
        local fixopt "fix_weights(`fix_weights')"
        local expected_fix "`fix_weights'"
    }
    foreach covariates in none numeric {
        foreach method in dr reg ipw {
            import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
            if "`covariates'" == "numeric" {
                csdid y x1 x2 [iw=wt_unit], ivar(id) time(time) gvar(g) method(`method') `fixopt' analytical
            }
            else {
                csdid y [iw=wt_unit], ivar(id) time(time) gvar(g) method(`method') `fixopt' analytical
            }
            assert e(method) == "`method'"
            assert "`e(panel_mode)'" == "panel"
            assert "`e(fix_weights)'" == "`expected_fix'"
            matrix A = e(attgt)
            clear
            svmat double A, names(col)
            gen str24 panel_mode = "panel"
            gen str12 weight_var = "wt_unit"
            gen str12 fix_weights = "`fix_weights'"
            gen str12 covariates = "`covariates'"
            gen str8 method = "`method'"
            rename (att se) (att_stata se_stata)
            keep panel_mode weight_var fix_weights covariates method group time event_time att_stata se_stata
            if `first_const' {
                save "`allactual_const'", replace
                local first_const 0
            }
            else {
                append using "`allactual_const'"
                save "`allactual_const'", replace
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f012/expected/r/time-invariant-fixweights.csv", clear asdouble
merge 1:1 panel_mode weight_var fix_weights covariates method group time using "`allactual_const'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8

preserve
keep if fix_weights == "default"
keep covariates method group time att_stata
rename att_stata att_default
tempfile const_default
save "`const_default'"
restore

merge m:1 covariates method group time using "`const_default'", nogen assert(match)
assert abs(att_stata - att_default) <= 1e-10 + 1e-10 * abs(att_default)

tempfile allactual_agg
local first_agg 1

foreach weight_var in wt wt_scaled {
    foreach fix_weights in default varying base_period first_period {
        local fixopt ""
        local expected_fix ""
        if "`fix_weights'" != "default" {
            local fixopt "fix_weights(`fix_weights')"
            local expected_fix "`fix_weights'"
        }
        foreach covariates in none numeric {
            foreach method in dr reg ipw {
                import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
                if "`covariates'" == "numeric" {
                    csdid y x1 x2 [iw=`weight_var'], ivar(id) time(time) gvar(g) method(`method') `fixopt' analytical
                }
                else {
                    csdid y [iw=`weight_var'], ivar(id) time(time) gvar(g) method(`method') `fixopt' analytical
                }
                foreach type in simple group calendar dynamic {
                    local appendopt ""
                    if !`first_agg' local appendopt "append"
                    f012_save_agg, type(`type') panelmode("panel") weightvar("`weight_var'") ///
                        fixweights("`fix_weights'") covariates("`covariates'") method("`method'") ///
                        saving("`allactual_agg'") `appendopt'
                    local first_agg 0
                }
            }
        }
    }
}

foreach weight_var in wt wt_scaled {
    foreach fix_weights in default varying {
        local fixopt ""
        local expected_fix ""
        if "`fix_weights'" != "default" {
            local fixopt "fix_weights(`fix_weights')"
            local expected_fix "`fix_weights'"
        }
        foreach covariates in none numeric {
            foreach method in dr reg ipw {
                import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
                if "`covariates'" == "numeric" {
                    csdid y x1 x2 [iw=`weight_var'], time(time) gvar(g) method(`method') `fixopt' analytical
                }
                else {
                    csdid y [iw=`weight_var'], time(time) gvar(g) method(`method') `fixopt' analytical
                }
                foreach type in simple group calendar dynamic {
                    f012_save_agg, type(`type') panelmode("repeated-cross-section") ///
                        weightvar("`weight_var'") fixweights("`fix_weights'") ///
                        covariates("`covariates'") method("`method'") saving("`allactual_agg'") append
                }
            }
        }
    }
}

foreach weight_var in wt wt_scaled {
    foreach fix_weights in default varying base_period first_period {
        local fixopt ""
        local expected_fix ""
        if "`fix_weights'" != "default" {
            local fixopt "fix_weights(`fix_weights')"
            local expected_fix "`fix_weights'"
        }
        foreach covariates in none numeric {
            foreach method in dr reg ipw {
                import delimited using "`root'/tests/fixtures/parity/f012/inputs/input-unbalanced.csv", clear asdouble
                if "`covariates'" == "numeric" {
                    csdid y x1 x2 [iw=`weight_var'], ivar(id) time(time) gvar(g) method(`method') `fixopt' analytical
                }
                else {
                    csdid y [iw=`weight_var'], ivar(id) time(time) gvar(g) method(`method') `fixopt' analytical
                }
                assert e(method) == "`method'"
                assert "`e(panel_mode)'" == "allow_unbalanced"
                assert "`e(fix_weights)'" == "`expected_fix'"
                foreach type in simple group calendar dynamic {
                    f012_save_agg, type(`type') panelmode("allow_unbalanced") ///
                        weightvar("`weight_var'") fixweights("`fix_weights'") ///
                        covariates("`covariates'") method("`method'") saving("`allactual_agg'") append
                }
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f012/expected/r/weighted-aggte.csv", clear asdouble
merge 1:1 panel_mode weight_var fix_weights covariates method type seq using "`allactual_agg'", nogen assert(match)
assert missing(egt) == missing(egt_stata) if missing(egt) | missing(egt_stata)
assert abs(egt - egt_stata) <= 1e-10 if !missing(egt)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata) if missing(`v') | missing(`v'_stata)
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
}

preserve
keep if weight_var == "wt"
keep panel_mode fix_weights covariates method type seq egt att se overall_att overall_se
rename (egt att se overall_att overall_se) ///
       (egt_w att_w se_w overall_att_w overall_se_w)
tempfile agg_base
save "`agg_base'"
restore

keep if weight_var == "wt_scaled"
merge 1:1 panel_mode fix_weights covariates method type seq using "`agg_base'", nogen assert(match)
assert missing(egt) == missing(egt_w) if missing(egt) | missing(egt_w)
assert abs(egt - egt_w) <= 1e-10 if !missing(egt)
foreach v in att se overall_att overall_se {
    assert abs(`v' - `v'_w) <= 1e-10 + 1e-10 * abs(`v'_w) if !missing(`v'_w)
}

import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
replace wt = -1 in 1
capture noisily csdid y [iw=wt], ivar(id) time(time) gvar(g) method(reg) analytical
assert _rc == 198

import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
capture noisily csdid y [iw=wt], time(time) gvar(g) method(reg) fix_weights(base_period) analytical
assert _rc == 198

import delimited using "`root'/tests/fixtures/parity/f012/expected/r/events.csv", clear varnames(1)
assert _N == 3
quietly count if event_key == "time_varying_weight_message" & expected_count >= 1
assert r(N) == 1
quietly count if event_key == "time_invariant_weight_no_message" & expected_count == 0
assert r(N) == 1
quietly count if event_key == "fixed_weight_reference_drop" & expected_count >= 1
assert r(N) == 1

tempfile f012log
import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
capture log close f012event
log using "`f012log'", text replace name(f012event)
capture noisily csdid y [iw=wt], ivar(id) time(time) gvar(g) method(reg) analytical
local actual = _rc
log close f012event
assert `actual' == 0
f012_assert_log_contains using "`f012log'", message("Time-varying weights detected")

import delimited using "`root'/tests/fixtures/parity/f012/inputs/input.csv", clear asdouble
capture log close f012event
log using "`f012log'", text replace name(f012event)
capture noisily csdid y [iw=wt_unit], ivar(id) time(time) gvar(g) method(reg) analytical
local actual = _rc
log close f012event
assert `actual' == 0
f012_assert_log_not_contains using "`f012log'", message("Time-varying weights detected")

import delimited using "`root'/tests/fixtures/parity/f012/inputs/input-unbalanced.csv", clear asdouble
capture log close f012event
log using "`f012log'", text replace name(f012event)
capture noisily csdid y [iw=wt], ivar(id) time(time) gvar(g) method(reg) fix_weights(first_period) analytical
local actual = _rc
log close f012event
assert `actual' == 0
f012_assert_log_contains using "`f012log'", message("units not observed in first_period")
