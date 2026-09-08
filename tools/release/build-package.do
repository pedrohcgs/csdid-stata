* The consumer runtime may differ from the pinned release compiler. Stata's
* shell status is not a build verdict; only a fresh, checked receipt is one.
version 15
local build_root "`c(pwd)'"
tempfile built
capture confirm file "`built'"
if !_rc {
    display as error "the package-build receipt already exists; refusing stale build evidence"
    exit 459
}
shell bash "`build_root'/tools/release/build-package.sh" "`built'"
capture confirm file "`built'"
if _rc {
    display as error "the release package build did not complete; inspect build.log"
    exit 459
}
tempname receipt
file open `receipt' using "`built'", read text
file read `receipt' completed
file close `receipt'
if "`completed'" != "CSDID-PACKAGE-BUILD-COMPLETE" {
    display as error "the release package build returned an invalid receipt; inspect build.log"
    exit 459
}
