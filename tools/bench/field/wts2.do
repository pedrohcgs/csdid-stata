* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do wts2.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/runners.do"
capture program drop wtest
program define wtest
    args n3 n4
    clear
    set seed 99
    local tot = `n3' + `n4' + 100
    quietly set obs `tot'
    generate long id = _n
    generate int gvar = cond(id <= `n3', 3, cond(id <= `n3'+`n4', 4, 0))
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double eff = cond(gvar==3, 2.0, 0.5)
    quietly generate double y = id*0.0005 + time*0.3 + rnormal()*0.10
    quietly replace y = y + eff if gvar>0 & time>=gvar
    quietly generate byte treated = (gvar>0 & time>=gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar==0
    quietly generate int cl = mod(id,20)+1
    tempfile d
    quietly save "`d'", replace
    local eqw = (2.0+0.5)/2
    local szw = (`n3'*2.0 + `n4'*0.5)/(`n3'+`n4')
    di "W n3=`n3' n4=`n4'  equal=" %6.4f `eqw' "  size=" %6.4f `szw'
    foreach pkg in csdid jwdid bjs dcdh lpdid {
        use "`d'", clear
        if "`pkg'" == "csdid" {
            quietly csdid y, ivar(id) time(time) gvar(gvar) analytical base_period(varying) bal(none)
            quietly estat event, window(0 0)
            matrix E = e(aggte)
            di "W    csdid = " %6.4f E[1,2]
        }
        else {
            capture bench_`pkg', horizons(0) cluster(cl)
            if !_rc {
                matrix E = r(ES)
                di "W    `pkg' = " %6.4f E[1,2]
            }
        }
    }
end
wtest 100 900
wtest 500 500
wtest 900 100
