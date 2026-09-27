* ---------------------------------------------------------------------------
* saverif(file, replace) onto a target that exists but cannot be overwritten
* refuses before anything is estimated, and the previous results survive.
*
* The entry check asked only whether the file was new, and replace waved an
* existing one through. A read-only file, or a directory with the file's name,
* then failed at the save -- after the whole estimation, with e() posted but
* no e(cmd), and the previous fit gone. help csdid promises the opposite:
* nothing is estimated, and results already in memory remain as they were.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 200

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

use "`root'/src/data/mpdta.dta", clear
tempfile stub
local dir "`stub'-srw"
mkdir "`dir'"

* -- 1. a directory named like the target -----------------------------------
mkdir "`dir'/asdir.dta"
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(dr)
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(reg) ///
    saverif("`dir'/asdir.dta", replace)
assert _rc != 0
assert "`e(cmd)'" == "csdid"
assert "`e(method)'" == "dr"

* -- 2. a read-only file (where the OS has chmod) ---------------------------
if c(os) != "Windows" {
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(dr) ///
        saverif("`dir'/ro.dta", replace)
    shell chmod 444 "`dir'/ro.dta"
    capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(reg) ///
        saverif("`dir'/ro.dta", replace)
    local rc = _rc
    shell chmod 644 "`dir'/ro.dta"
    assert `rc' != 0
    assert "`e(cmd)'" == "csdid"
    assert "`e(method)'" == "dr"
    erase "`dir'/ro.dta"

    * -- 3. a writable file in a read-only directory -------------------------
    * save, replace writes into the directory, so this failed at the save,
    * after the whole estimation, until the directory was probed as well
    mkdir "`dir'/rodir"
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(dr) ///
        saverif("`dir'/rodir/rif.dta", replace)
    shell chmod 555 "`dir'/rodir"
    capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(reg) ///
        saverif("`dir'/rodir/rif.dta", replace)
    local rc = _rc
    shell chmod 755 "`dir'/rodir"
    assert `rc' != 0
    assert "`e(cmd)'" == "csdid"
    assert "`e(method)'" == "dr"
    erase "`dir'/rodir/rif.dta"
    rmdir "`dir'/rodir"
}
rmdir "`dir'/asdir.dta"
rmdir "`dir'"

display as text "test-saverif-unwritable: an unwritable saverif() target refuses before estimating"
