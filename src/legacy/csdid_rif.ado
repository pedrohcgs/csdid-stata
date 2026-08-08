*! csdid_rif 2.0.0 30jul2026
* Corrects Aggregation when data is missing

* v1 csdid_rif
* Goal, you feed the RIF, it provides you with Stats 
* Could be use for post aggregation
* could be a bit faster... but is faster than csdid_stats right now

mata: 

// This creates a vector to obtain the WBefects in bsmean
real matrix mboot_any(real matrix rif, real scalar reps, bwtype) {
	 
	mean_rif=mean(rif)
	rr=rif:-mean_rif
 	bsmean=J(reps,cols(rif),0)
	real scalar i,nrows,ncols, k1, k2
	nrows=rows(rr)
	ncols=cols(rr)
	k1=((1+sqrt(5))/(2*sqrt(5)))
	k2=0.5*(1+sqrt(5)) 
 	// check Repetitions and parameters
 
	mdsize = min((reps, max( (1,floor(1e7/nrows)) )))

	if (bwtype==1) {
		coord1=1
		mdsize_eff = mdsize
		for(i=1;i<=reps;i=i+mdsize){ 
 			wmult = (k2:-sqrt(5)*(rbinomial(nrows,mdsize_eff,1,k1)))
			ccrd = (coord1,1) \ ( coord1+mdsize_eff-1 ,ncols)
			coord1=coord1+mdsize_eff
 			bsmean[|ccrd|]=cross(rr,wmult )':/nrows	
 			mdsize_eff = min( (mdsize, reps-(coord1-1)) )
 
		}
	}
	else if (bwtype==2) {
		// Rademacher multipliers. This branch used to read `rbinomial(n,
		// ...)' -- there is no `n' in this function, the row count is
		// `nrows' -- so any call with wbtype=2 aborted on an undefined
		// symbol. It never fired only because the single caller hardcodes
		// bwtype=1 and exposes no option for it. Fixed rather than deleted:
		// the branch is one symbol away from correct and the sibling
		// clustered routine has the same shape.
		coord1=1
		mdsize_eff = mdsize
		for(i=1;i<=reps;i=i+mdsize){
			wmult = (1:-2*rbinomial(nrows,mdsize_eff,1,0.5) ) 
			ccrd = (coord1,1) \ ( coord1+mdsize_eff-1 ,ncols)
			coord1=coord1+mdsize_eff
 			bsmean[|ccrd|]=cross(rr,wmult )':/nrows	
 			mdsize_eff = min( (mdsize, reps-(coord1-1)) )	
		}
	}
	return(bsmean)
}
 // Same but with Cluster
 // we can do it a bit faster. but needs extra to control for Max iterations.
real matrix mboot_anyc(real matrix rif, real scalar reps, bwtype, clv) {
	mean_rif=mean(rif)
	rr=rif:-mean_rif
	bsmean=J(reps,cols(rif),0)
	real scalar i,nrows,ncols, k1, k2, nn
	nrows=rows(rr)
	ncols=cols(rr)
	k1=((1+sqrt(5))/(2*sqrt(5)))
	k2=0.5*(1+sqrt(5)) 

	real matrix sclv, wmult
	sclv=uniqrows(clv)
	nn=rows(sclv)
	st_numscalar("__csdid_rif_nclust", nn)		

	mdsize = min((reps, max( (1,floor(1e7/nrows)) )))

		
 	if (bwtype==1) {
 		coord1=1
		mdsize_eff = mdsize
		// a bare `nn' statement used to sit here, which PRINTS the cluster
		// count into the middle of the user's output on every call
		for(i=1;i<=reps;i=i+mdsize){
		    wmult=(rbinomial(nn,mdsize_eff,1,k1))
			wmult=k2:-sqrt(5)*wmult[clv,] 
			//wmult[clv] this is kind of merge. 
			//clv is the key 1..K
			ccrd = (coord1,1) \ ( coord1+mdsize_eff-1 ,ncols)
			coord1=coord1+mdsize_eff
 			bsmean[|ccrd|]=cross(rr,wmult )':/nrows	
 			mdsize_eff = min( (mdsize, reps-(coord1-1)) )
		}
	}
	else if (bwtype==2) {
		coord1=1
		mdsize_eff = mdsize
		for(i=1;i<=reps;i=i+mdsize){
			wmult=(rbinomial(nn,mdsize_eff,1,0.5))
			wmult=1:-2*wmult[clv,]
			ccrd = (coord1,1) \ ( coord1+mdsize_eff-1 ,ncols)
			coord1=coord1+mdsize_eff
 			bsmean[|ccrd|]=cross(rr,wmult )':/nrows	
 			mdsize_eff = min( (mdsize, reps-(coord1-1)) )
		}
	}
	return(bsmean)
}


void mboot(real matrix rif, vv, cband, string scalar clv,
			real scalar ci, reps, wbtype) {
    //, real scalar reps, bwtype, ci 
    real matrix fr, tt
	real matrix ifse , ccb, mean_rif
	mean_rif = mean(rif)
	
	// this gets the Bootstraped values
	if (clv ==" ") {
		fr=mboot_any(rif, reps, wbtype)
		ifse = iqrse(fr)
		tt = qtp(abs(fr :/ ifse),ci) 
		
		cband=( mean_rif',
				ifse',
				mean_rif':/ifse',
				mean_rif':-tt':* ifse' ,  
				mean_rif':+tt':* ifse'   )
	}
	else {
		clvar=st_data(.,clv)
		
		fr=mboot_anyc(rif,reps, wbtype, clvar)
		ifse = iqrse(fr)
		// this gets Tvalue
		tt = qtp(abs(fr :/ ifse),ci)  
		// Just matrix with all info 		
		cband=( mean_rif',
				ifse',
				mean_rif':/ifse',
				mean_rif':-tt':* ifse' ,  
				mean_rif':+tt':* ifse'   )
	}
	//bb=mean_rif This Squares the variance
	vv=quadcross(ifse,ifse):*I(rows(ifse))
	//sqrt(variance(fr))
	//st_matrix(vv,iqrse(fr)^2)
	//st_matrix(cband,ccb)
}

real matrix iqrse(real matrix y) {
    real scalar q25,q75
	q25=floor(rows(y)*.25)+1
	q75=floor(rows(y)*.75)+1
	real scalar j
	real matrix iqrs
	iqrs=J(1,cols(y),0)
	for(j=1;j<=cols(y);j++){
	    y=sort(y,j)
		iqrs[,j]=(y[q75,j]-y[q25,j]):/(invnormal(.75)-invnormal(.25))
	}
	return(iqrs)
}

real vector qtp(real matrix y, real scalar p) {
    real scalar k, i, q
	real matrix yy, qq
	qq=J(1,0,.)
	k = cols(y)
	y=rowmax(y)
	for(i=1;i<=k;i++){
		yy=sort(y,1)
		q=floor(rows(yy)*p)+1 
		qq=qq,yy[q,]
	}    
	return(qq)
}
// SE if nothing
void clusterse(real matrix iiff, cl, V, real scalar cln){
    real matrix ord, xcros, ifp, info, vv 
	ord  = order(cl,1)
	iiff = iiff[ord,]
	cl   = cl[ord,]	
	info  = panelsetup(cl,1)
	ifp   = panelsum(iiff,info)
	xcros = quadcross(ifp,ifp)	
	real scalar nt, nc
	nt=rows(iiff)
	nc=rows(info)
	V =	xcros/(nt^2)
	cln=nc
}

void fix_rif(real matrix rif){
	real matrix mn_rif, rif2
	
	//mn_rif= colsum(rif)
	mn_rif= colsum(rif):/colnonmissing(rif)
 	rif2  = rif:-mn_rif
	rif   = editmissing(rif2,0)
	rif   = mn_rif:+rif:*(rows(rif2):/colnonmissing(rif2))
 
	
	///:*(rows(rif2):/colnonmissing(rif))
 
	//mean(rif2:^2):/mean(rif:^2)
	//exp_factor = (rows(rr):/colnonmissing(rr))
	
}

// #63: the results used to be shuttled out through the fixed global Stata
// names bb_, VV_ and cln_, so a user with a matrix of either name lost it
// silently. The coefficient and variance matrices now arrive by name, the way
// cband_ already did; the cluster count keeps a global because it is also set
// deeper in mboot_anyc(), but it is namespaced so it cannot collide.
void make_tbl(string scalar rifv, clv, touse, cband_, bmat_, vmat_,
			  real scalar setype, ci, reps, wbtype){
	real matrix nobs, clvar
	real scalar cln
	rif=st_data(.,rifv,touse)
	// `>= 0' is a tautology -- a sum of a 0/1 matrix always is -- so fix_rif
	// ran on every call, rescaling and re-centring the whole RIF matrix even
	// when nothing was missing. With no missings the rescale factor is
	// exactly 1, so the result was mathematically rif but not bitwise rif.
	if (sum(rif:==.)>0) fix_rif(rif)
	 
	bb=mean(rif)
	nobs=rows(rif)
		
	// simple
	if ( setype ==1 ) {	
		VV=quadcrossdev(rif,bb,rif,bb):/ (nobs^2) 
	}
	// cluster std
	if ( setype ==2 ) {
		clvar = st_data(.,clv,touse)
		clusterse((rif:-bb),clvar,VV,cln)
		// was: a bare `cln' statement, which PRINTS the cluster count
		// into the middle of the user's output on every clustered call.
		st_numscalar("__csdid_rif_nclust", cln)
	}
	real matrix cband
	// wboot w / wo cluster
	if ( setype ==3 ) {
		mboot(rif,  VV, cband, clv, ci, reps, wbtype)
		st_matrix(cband_,cband)
		
	}
	
	st_matrix(bmat_,bb)
	st_matrix(vmat_,VV)
 } 
end
  program define Display
                syntax [, bmatrix(passthru) vmatrix(passthru) *]
 		 
        _get_diopts diopts rest, `options'
        local myopts `bmatrix' `vmatrix'        
                if ("`rest'"!="") {
                                display in red "option {bf:`rest'} not allowed"
                                exit 198
                }
 				if ("`e(vcetype)'"=="WBoot") {
                    csdid_table, `diopts'
					display "{p}Note: RIF Std. err. "
					* csdid 2.0.0 stores this as e(clustervar); legacy csdid used e(clustvar).
                    local csdid_cvar = cond("`e(clustervar)'" != "", "`e(clustervar)'", "`e(clustvar)'")
                    if "`csdid_cvar'"!="" {
						display "adjusted for `e(N_clust)' clusters in `csdid_cvar'{p_end}"
					}
					
                 }
                else {
                    _coef_table,  `diopts' `myopts' 
                }
                
 
end


//mata:make_tbl("rif*","agex","as",3,.95, 10000, 1)
// RIF, Cluster, touse, where to save CBAND
 program csdid_rif, eclass
    * DEPRECATED in csdid 2.0.0. Shipped only so existing do-files keep
    * running; it is not covered by the parity suite and will be removed in
    * a future release. Replacement: estat tidy, saving() for a results
    * dataset, or csdid_stats using <file> for the saved-RIF path.
    display as text "note: csdid_rif is deprecated and will be removed in a future release of csdid; see {help csdid_legacy}"

	version 14
	syntax varlist [if] [in], [  cluster(varname) level(real 95) reps(int 999) wboot seed(string) ]
	tempvar touse
	qui:gen byte `touse'=0
	qui:replace `touse'=1 `if' `in'
	markout `touse' `cluster'
	
	// cluster trams
	if "`cluster'"!="" {
		local ocluster `cluster'
		tempvar clust
		qui: egen double `clust'=group(`cluster') if `touse'
		local cluster `clust'
	}
 
	// SB type
	local rtype 1
	if "`cluster'" != "" local rtype 2 
	if "`wboot'"   != "" {
		local rtype 3
		if "`seed'"!="" set seed `seed'
	}
	tempname cband bmat vmat
	local tlevel = `level'/100
	 mata:make_tbl("`varlist'"," `cluster'","`touse'","`cband'","`bmat'","`vmat'",`rtype',`tlevel', `reps', 1)	
	// rename 
	matrix colname `bmat' = `varlist'
	matrix colname `vmat' = `varlist'
	matrix rowname `vmat' = `varlist'
	ereturn post `bmat' `vmat'
	ereturn local cmd csdid_rif
	capture confirm matrix `cband'
	if _rc==0 {
		matrix colname `cband' = b se t ll uu
		matrix rowname `cband' = `varlist'
		ereturn matrix cband = `cband'
		
	} 
	if `rtype'==1 ereturn local vcetype Robust 
	if `rtype'==2 ereturn local vcetype Robust
	if `rtype'==3 ereturn local vcetype WBoot
	ereturn local clustvar `ocluster'
	capture  confirm scalar __csdid_rif_nclust
	if _rc==0 {
		ereturn scalar N_clust = __csdid_rif_nclust
		scalar drop __csdid_rif_nclust
	}
	Display, level(`level')
	
end
 