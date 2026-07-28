version 15
args outfile release_gates_status

if `"`outfile'"' == "" {
    local outfile "reports/platform-matrix-local.csv"
}

if `"`release_gates_status'"' == "" {
    local release_gates_status "unverified"
}

capture mkdir "reports"

tempname fh
file open `fh' using `"`outfile'"', write replace text
file write `fh' "date,stata_version,edition,os,machine_type,byteorder,release_gates_status" _n
local row "`c(current_date)',`c(stata_version)',`c(edition_real)',`c(os)',`c(machine_type)',`c(byteorder)',`release_gates_status'"
file write `fh' "`row'" _n
file close `fh'

display as text "wrote platform row to `outfile'"
