{smcl}
{* *! version 2.0.0 30jul2026}{...}
{vieweralsosee "csdid" "help csdid"}{...}
{vieweralsosee "csdid postestimation" "help csdid_postestimation"}{...}
{vieweralsosee "csdid_estat" "help csdid_estat"}{...}
{vieweralsosee "csdid_stats" "help csdid_stats"}{...}
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
treatment indicator. It is fully supported.
{p_end}

{phang2}{cmd:. csgvar} {it:newvar} {cmd:=} {it:treatment} [{it:if}] [{it:in}]{cmd:,}
{cmd:tvar(}{it:timevar}{cmd:)} {cmd:ivar(}{it:panelvar}{cmd:)}{p_end}

{pstd}
The result is 0 for units never treated within the sample and the first treated
period otherwise, which is exactly the coding {cmd:csdid} requires. The
treatment indicator must take at most two values, and the untreated state must
be coded 0 -- that is what makes a never-treated unit come out as cohort 0.
An indicator coded {cmd:1}/{cmd:2}, or {cmd:-1}/{cmd:1}, would otherwise give
every unit a positive cohort and leave the data with no never-treated units at
all, so {cmd:csgvar} refuses it with return code {cmd:r(459)}, naming the two
values it found. More than two values is the same refusal. The treated value
itself is free: {cmd:0}/{cmd:5} works as well as {cmd:0}/{cmd:1}.
{p_end}

{phang2}{cmd:. csgvar gvar = treated, tvar(year) ivar(county)}{p_end}
{phang2}{cmd:. csdid y, ivar(county) time(year) gvar(gvar)}{p_end}

{pstd}
The same cohort variable is available as an {helpb egen} function, which is
what {cmd:_gcsgvar.ado} provides:
{p_end}

{phang2}{cmd:. egen gvar = csgvar(treated), tvar(year) ivar(county)}{p_end}

{pstd}
The two forms are the same computation -- {cmd:csgvar} forwards to
{cmd:_gcsgvar} -- so they accept the same options and raise the same refusals.
{p_end}

{pstd}
{bf:Storage type.} A cohort code is a value on your time axis, so
{cmd:csgvar} computes it in {cmd:double} and stores it in the type you ask
for. With no type asked for, {cmd:csgvar} gives you a {cmd:double}; the
{helpb egen} form takes {cmd:egen}'s own default, which is whatever
{cmd:set type} is, so write {cmd:egen double} when your time variable needs
it. A type too narrow to hold the cohort code exactly is
refused with return code {cmd:r(198)} rather than rounding it: a rounded
cohort is a different treatment group, and {cmd:csdid} would estimate it
without complaint. This matters on a {cmd:%tc} or epoch-second axis, where the
values run past {cmd:float}'s exact range.
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
{helpb csdid_estat}, {helpb csdid_stats}, {helpb csdid_plot}
{p_end}
