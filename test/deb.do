* stata14-mp -b do test/deb.do && mv deb.log test/log/deb.before.log
* stata14-mp -b do test/deb.do && mv deb.log test/log/deb.after.log

log close _all
log using deb.log, replace

version 14.2
local root `c(pwd)'
cd codes
do `root'/test/common.do

local methods drimp dripw reg stdipw
local aggtyps simple group calendar dynamic
use `root'/../reply_to_DNWZ/data/Deb_etal_20251006_Stata.dta, clear
    * csdid y, gvar(c) time(t) long2 reg vce(cluster g)

    foreach m of local methods {
        tempfile `m'
    }
    foreach m of local methods {
        disp "`m'"
        qui csdid y, gvar(c) time(t) method(`m') vce(cluster g)
        qui estimates save "``m''.ster", replace
    }

    foreach m of local methods {
        mata: `m' = _loadmat("`root'/tmp/tmpout_`m'")
        foreach typ of local aggtyps {
            mata: `m'`typ' = _loadmat("`root'/tmp/tmpout_`m'_`typ'")
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
