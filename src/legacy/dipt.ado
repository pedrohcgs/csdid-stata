**program drop dipt
program dipt, eclass
    * DEPRECATED in csdid 2.0.0. Shipped only so existing do-files keep
    * running; it is not covered by the parity suite and will be removed in
    * a future release. Replacement: no replacement; it was never part of the documented surface.
    display as text "note: dipt is deprecated and will be removed in a future release of csdid; see {help csdid_legacy}"


syntax varlist(fv ts) [if] [iw pw fw], [cluster(passthru) from(passthru)] 

// ML
gettoken y xvar:varlist
marksample touse

mlexp (`y'*{xb:`xvar' _cons}-(`y'==0)*exp({xb:}))  ///
					if `touse' [`exp'`weight'],  ///
					 derivative(/xb=`y'-(`y'==0)*exp({xb:})) ///
                     `from'
                     
end                     

program dipt0, eclass

syntax varlist(fv ts) [if] [iw pw fw], [cluster(passthru) *] 

// ML
gettoken y xvar:varlist
marksample touse

mlexp ({xb:`xvar' _cons}-(`y'==0)*exp({xb:}))  ///
					if `touse' [`exp'`weight'],  ///
					 derivative(/xb=1-(`y'==0)*exp({xb:})) ///
                     `options'
                     
end 

program dipt1, eclass

syntax varlist(fv ts) [if] [iw pw fw], [cluster(passthru) *] 

// ML
gettoken y xvar:varlist
marksample touse

mlexp ({xb:`xvar' _cons}-(`y'==1)*exp({xb:}))  ///
					if `touse' [`exp'`weight'],  ///
					 derivative(/xb=1-(`y'==1)*exp({xb:})) ///
                     `options'
                     
end 