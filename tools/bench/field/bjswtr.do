* did_imputation: default vs wtr(population-share), all designs where it appears.
args nunits reps outfile
quietly do "simdgp.do"
capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

capture program drop mkwtr
program define mkwtr
    quietly capture drop K w0 w1 w2 ncell
    quietly gen int K = time - gvar if gvar > 0 & time >= gvar
    forvalues h = 0/2 {
        quietly capture drop ncell
        quietly bysort gvar time: egen double ncell = total(K == `h') if K == `h'
        quietly gen double w`h' = cond(K == `h' & ncell > 0, 1/(3*ncell), 0)
        quietly replace w`h' = 0 if missing(w`h')
    }
end

forvalues r = 1/`reps' {
    foreach reg in balanced varmiss unbalanced {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace

        use "`d'", clear
        capture did_imputation y id time gvar_miss, horizons(0/2) autosample
        local ok = (_rc == 0)
        forvalues h = 0/2 {
            local e = .
            local s = .
            if `ok' {
                matrix B = r(table)
                local cn : colnames B
                local p : list posof "tau`h'" in cn
                if `p' > 0 {
                    local e = B[1,`p']
                    local s = B[2,`p']
                }
            }
            file write out "`reg',bjs,`r',`h'," (string(`e',"%18.0g")) "," (string(`s',"%18.0g")) _n
        }

        use "`d'", clear
        mkwtr
        capture did_imputation y id time gvar_miss, wtr(w0 w1 w2) autosample
        local ok2 = (_rc == 0)
        forvalues h = 0/2 {
            local e2 = .
            local s2 = .
            if `ok2' {
                matrix W = r(table)
                local cw : colnames W
                local p2 : list posof "tau_w`h'" in cw
                if `p2' > 0 {
                    local e2 = W[1,`p2']
                    local s2 = W[2,`p2']
                }
            }
            file write out "`reg',bjs_wtr,`r',`h'," (string(`e2',"%18.0g")) "," (string(`s2',"%18.0g")) _n
        }
    }
    if mod(`r',25)==0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
