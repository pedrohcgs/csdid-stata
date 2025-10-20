* stata14-mp -b do test/base.do && mv base.log test/log/base.before.log
* stata14-mp -b do test/base.do && mv base.log test/log/base.after.log

log close _all
log using base.log, replace

version 14.2
local root `c(pwd)'
cd codes
do `root'/test/common.do

local methods drimp dripw reg stdipw
local aggtyps simple group calendar dynamic
use `root'/tmp/base.dta, clear

    foreach m of local methods {
        tempfile `m'
    }
    foreach m of local methods {
        disp "`m'"
        qui csdid Y X, gvar(G) time(period) method(`m') id(id)
        qui estimates save "``m''.ster", replace
    }

    foreach m of local methods {
        mata: `m' = _loadmat("`root'/tmp/tmpbase_`m'")
        foreach typ of local aggtyps {
            mata: `m'`typ' = _loadmat("`root'/tmp/tmpbase_`m'_`typ'")
        }
    }

    foreach m of local methods {
        estimates use "``m''.ster"
        qui csdid
        mata out    = st_matrix("r(table)")[1::2,1..rows(`m')]'
        mata errors = colmax(abs(reldif(`m', out)))
        mata printf("\n%17s: %9.6g\t%9.6g\n", "`m'", errors[1], errors[2])
        foreach typ of local aggtyps {
            if "`typ'" == "dynamic" {
                qui csdid_estat event
                mata row = st_matrix("r(table)")[1::2,.]'
                mata row = row[2::rows(row),.]
            }
            else {
                qui csdid_estat `typ'
                mata row = st_matrix("r(table)")[1::2,.]'
            }
            mata errors = colmax(abs(reldif(`m'`typ', row)))
            mata printf("%17s: %9.6g\t%9.6g\n", "`typ' `m'", errors[1], errors[2])
        }
    }
