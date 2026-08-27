{smcl}
{* *! version 2.0.0 27aug2026}{...}
{vieweralsosee "csdid" "help csdid"}{...}
{vieweralsosee "csdid postestimation" "help csdid_postestimation"}{...}
{vieweralsosee "csdid_estat" "help csdid_estat"}{...}
{vieweralsosee "csdid_stats" "help csdid_stats"}{...}
{vieweralsosee "csgvar" "help csgvar"}{...}
{viewerjumpto "Supported" "csdid_legacy##supported"}{...}
{viewerjumpto "Deprecated" "csdid_legacy##deprecated"}{...}
{viewerjumpto "Replacements" "csdid_legacy##replacements"}{...}
{viewerjumpto "Authors" "csdid_legacy##authors"}{...}

{title:Title}

{p2colset 5 21 23 2}{...}
{p2col:{bf:csdid_legacy} {hline 2}}Utility and deprecated commands carried over
from csdid Version 1.82{p_end}
{p2colreset}{...}


{marker supported}{...}
{title:Supported utility commands}

{pstd}
{bf:csgvar} builds the cohort variable that {cmd:gvar()} expects, from a binary
treatment indicator. It is fully supported and has a help topic of its own:
see {helpb csgvar}.
{p_end}


{marker deprecated}{...}
{title:Deprecated commands}

{pstd}
{bf:These four commands are deprecated and will be removed in a future release of csdid.} They ship so that existing do-files keep running, and each prints a
notice when invoked. They are unsupported: they are kept only to ease migration
away from csdid Version 1.82, and they should not be used in new work.
{p_end}

{synoptset 18 tabbed}{...}
{synopthdr:Command}
{synoptline}
{synopt :{cmd:csdid_rif}}builds tables from saved RIF variables{p_end}
{synopt :{cmd:csdid_table}}formats a results table; an internal helper of csdid Version 1.82{p_end}
{synopt :{cmd:dipt}}undocumented utility{p_end}
{synopt :{cmd:tsvmat}}creates temporary variables from a matrix{p_end}
{synoptline}

{pstd}
Nothing in {cmd:csdid} calls any of them, so their presence costs nothing:
Stata compiles an ado file only when its command is first invoked.
{p_end}


{pstd}
{bf:What the deprecated commands refuse rather than ignore.} Each of them
parsed options it then discarded. {cmd:csdid_table} accepted {cmd:level()},
{cmd:noci}, {cmd:cformat()} and {cmd:sformat()} and consulted none of them --
its number formats are fixed and its bounds come from {cmd:e(cband)} at
whatever level {cmd:csdid} was run with, so {cmd:csdid_table, level(90)}
printed a 90% heading over bounds computed at another level. It now refuses
those four with return code 198. {cmd:dipt} parsed {cmd:cluster()} and never
passed it on, so it returned unclustered standard errors without saying so;
it forwards it now, and its weight specification, which made every weighted
call a syntax error, is fixed.
{p_end}

{marker replacements}{...}
{marker syntax}{...}
{title:Syntax and stored results of the deprecated commands}

{pstd}
Each command keeps its Version 1.82 grammar, stated here so an old do-file
can be read without the old manual.

{pstd}
{cmd:csdid_rif} {it:rifvarlist} {ifin} [{cmd:,} {opt cluster(varname)}
{opt level(#)} {opt reps(#)} {opt wboot} {opt seed(#)}]{break}
averages the saved RIF columns into coefficients. It is eclass: it posts
{cmd:e(b)}, {cmd:e(V)}, {cmd:e(N)}, {cmd:e(sample)}, {cmd:e(cmd)}
({cmd:csdid_rif}), {cmd:e(vcetype)} ({cmd:Robust} or {cmd:WBoot}),
{cmd:e(level)}, {cmd:e(clustvar)} and {cmd:e(N_clust)} when clustered, and
{cmd:e(cband)} (the wild-bootstrap band matrix) under {cmd:wboot}.
{opt level()} must be a confidence level and {opt reps()} a positive count;
both are validated before anything is computed or the RNG state moves.

{pstd}
{cmd:csdid_table} [{cmd:,} {it:frozen options}]{break}
redisplays the active {cmd:csdid} or {cmd:csdid_rif} result as the Version
1.82 table and leaves {cmd:r(table)} behind. It is rclass; it posts
nothing to {cmd:e()}. The four frozen formatting options ({cmd:level()},
{cmd:noci}, {cmd:cformat()}, {cmd:sformat()}) are refused with return code
198; any other estimator's results are refused with return code 459.

{pstd}
{cmd:dipt} {it:depvar} [{it:indepvars}] {ifin} {it:weight} [{cmd:,}
{opt cluster(varname)} {opt from(matname)}]{break}
is a thin shim over {helpb mlexp}; everything it posts is {cmd:mlexp}'s own.

{pstd}
{cmd:tsvmat} {it:matname}{cmd:,} {opt name(newvarlist)}{break}
writes matrix columns into new double variables, expanding the data to the
matrix's row count when needed. Every refusal -- an existing or invalid
name, a duplicated name, more names than columns -- fires before the
dataset changes. It returns nothing.

{title:What to use instead}

{pstd}
{bf:Instead of {cmd:csdid_rif}}, take results as a dataset directly. This is
the same information in a form you can table, merge or plot, and it comes from
the same estimation path {cmd:csdid} itself reports:
{p_end}

{phang2}{cmd:. csdid y, ivar(id) time(t) gvar(g)}{p_end}
{phang2}{cmd:. estat attgt, saving(results) replace}{p_end}
{phang2}{cmd:. use results, clear}{p_end}

{pstd}
{cmd:estat attgt, saving()} returns one row per estimate with the estimate, its
standard error, the test statistic, the p-value and the confidence bounds. Every
aggregation exports itself the same way: {cmd:estat event, saving()},
{cmd:estat group, saving()}, {cmd:estat calendar, saving()} or
{cmd:estat simple, saving()}.
{p_end}

{pstd}
The saved-RIF workflow itself is still supported: {cmd:csdid_stats} accepts a
saved RIF file with {cmd:csdid_stats using} {it:filename}. Only the
table-building command is deprecated.
{p_end}

{pstd}
{bf:Instead of {cmd:csdid_table}}, use the table {cmd:csdid} prints, or
{cmd:estat tidy, saving()} when you want the numbers rather than the display.
{p_end}

{pstd}
{bf:{cmd:dipt} and {cmd:tsvmat}} were never part of the documented command
surface and have no replacement.
{p_end}


{marker authors}{...}
{title:Authors}

{pstd}
{cmd:csdid} is by Brantly Callaway, Fernando Rios-Avila, and Pedro H. C.
Sant'Anna. Full affiliations and contact addresses, the acknowledgments, how to
report a problem, and how to cite the package are in
{help csdid##authors:help csdid}.


{marker alsosee}{...}
{title:Also see}

{psee}
Online:  {helpb csdid}, {helpb csdid_postestimation:csdid postestimation},
{helpb csdid_estat}, {helpb csdid_stats}, {helpb csdid_plot},
{helpb csgvar}
{p_end}
