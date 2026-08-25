*! csdid_rif 2.0.0 24aug2026
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
real matrix mboot_anyc(real matrix rif, real scalar reps, bwtype, clv, string scalar nclname) {
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
	st_numscalar(nclname, nn)		

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
			real scalar ci, reps, wbtype, string scalar nclname) {
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
		
		fr=mboot_anyc(rif,reps, wbtype, clvar, nclname)
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
			  real scalar setype, ci, reps, wbtype, string scalar nclname){
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
		// The count travels through the tempname scalar the caller hands
		// in, never a fixed global name a user's own scalar could collide
		// with (cold-audit LEG-5).
		st_numscalar(nclname, cln)
	}
	real matrix cband
	// wboot w / wo cluster
	if ( setype ==3 ) {
		mboot(rif,  VV, cband, clv, ci, reps, wbtype, nclname)
		st_matrix(cband_,cband)
		
	}
	
	st_matrix(bmat_,bb)
	st_matrix(vmat_,VV)
 } 
end
  program define Display
                version 14
                syntax [, bmatrix(passthru) vmatrix(passthru) Level(cilevel) *]
 		 
        _get_diopts diopts rest, `options'
        local myopts `bmatrix' `vmatrix'        
                if ("`rest'"!="") {
                                display in red "option {bf:`rest'} not allowed"
                                exit 198
                }
 				if ("`e(vcetype)'"=="WBoot") {
                    * csdid_table refuses a level() differing from c(level)
                    * when a direct user asks (it cannot recompute matrix
                    * bounds); the level is therefore consumed by the syntax
                    * line above and never forwarded -- the table labels the
                    * bounds from the e(level) csdid_rif just posted
                    * (cold-audit LEG-1).
                    csdid_table, `diopts'
					display "{p}Note: RIF Std. err. "
					* csdid 2.0.0 stores this as e(clustervar); legacy csdid used e(clustvar).
                    local csdid_cvar = cond("`e(clustervar)'" != "", "`e(clustervar)'", "`e(clustvar)'")
                    if "`csdid_cvar'"!="" {
						display "adjusted for `e(N_clust)' clusters in `csdid_cvar'{p_end}"
					}
					
                 }
                else {
                    _coef_table,  level(`level') `diopts' `myopts' 
                }
                
 
end


//mata:make_tbl("rif*","agex","as",3,.95, 10000, 1)
// RIF, Cluster, touse, where to save CBAND
 program csdid_rif, eclass
	version 14
    * DEPRECATED in csdid 2.0.0. Shipped only so existing do-files keep
    * running; it is not covered by the parity suite and will be removed in
    * a future release. Replacement: estat tidy, saving() for a results
    * dataset, or csdid_stats using <file> for the saved-RIF path.
    display as text "note: csdid_rif is deprecated and will be removed in a future release of csdid; see {help csdid_legacy}"

	syntax varlist [if] [in], [  cluster(varname) level(real 95) reps(int 999) wboot seed(string) ]
	* An impossible confidence level refuses before any computation, any
	* RNG state change, or any e() posting (cold-audit LEG-1): the level
	* drives the wild-bootstrap band quantile below, so it must be a level.
	if `level' < 10 | `level' > 99.99 {
		display as error "level(`level') is not a confidence level; specify a value between 10 and 99.99"
		exit 198
	}
	tempvar touse
	* novarlist is deliberate. A missing entry in a RIF column means that
	* ATT(g,t) cell failed for that unit, not that the unit is unusable: the
	* Mata side (fix_rif) rescales the column and keeps every cell that did
	* work, which is what this file exists to do. Marking out the varlist would
	* delete the whole row instead and is a different estimator -- measured on
	* a 2000-row RIF with two seeded missings, listwise deletion moves the
	* first coefficient by 6.2e-05.
	marksample touse, novarlist
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
		* refused BEFORE `set seed': an invalid replication count must not
		* first reseed the session's RNG stream (cold-audit LEG-4).
		if `reps' < 1 {
			display as error "reps(`reps') is not a positive replication count"
			exit 198
		}
		if "`seed'"!="" set seed `seed'
	}
	tempname cband bmat vmat nclust
	local tlevel = `level'/100
	 mata:make_tbl("`varlist'"," `cluster'","`touse'","`cband'","`bmat'","`vmat'",`rtype',`tlevel', `reps', 1, "`nclust'")	
	// rename 
	matrix colname `bmat' = `varlist'
	matrix colname `vmat' = `varlist'
	matrix rowname `vmat' = `varlist'
	* Without obs() and esample() there is no e(N) and e(sample) is all zeros,
	* so `summarize if e(sample)', estat summarize and the bootstrap prefix all
	* have nothing to work with. esample() CONSUMES the variable it is handed,
	* so it gets a copy: `touse' is still live for the Display call below.
	quietly count if `touse'
	local rif_N = r(N)
	tempvar rif_esmp
	quietly generate byte `rif_esmp' = `touse'
	ereturn post `bmat' `vmat', obs(`rif_N') esample(`rif_esmp')
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
	capture  confirm scalar `nclust'
	if _rc==0 {
		ereturn scalar N_clust = `nclust'
	}
	* The level the bands were computed at travels with the result, so a
	* replay (csdid_table) labels the bounds with their own provenance
	* rather than whatever c(level) happens to be later (cold-audit LEG-2).
	ereturn scalar level = `level'
	* Last e() assignment: e(cmd) is what a postestimation command reads to
	* decide the results are complete, so nothing may be posted after it.
	ereturn local cmd csdid_rif
	Display, level(`level')
	
end
 