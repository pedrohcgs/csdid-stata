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
treatment indicator must take at most two values.
{p_end}

{phang2}{cmd:. csgvar gvar = treated, tvar(year) ivar(county)}{p_end}
{phang2}{cmd:. csdid y, ivar(county) time(year) gvar(gvar)}{p_end}

{pstd}
{cmd:_gcsgvar} is the internal helper {cmd:csgvar} calls. Do not call it
directly.
{p_end}


{marker deprecated}{...}
{title:Deprecated commands}

{pstd}
{bf:These four commands are deprecated and will be removed in a future release
of csdid.} They ship so that existing do-files keep running, and each prints a
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
{cmd:csdid} is by Fernando Rios-Avila, Pedro H. C. Sant'Anna, and Brantly
Callaway. Full affiliations and contact addresses, the acknowledgments, how to
report a problem, and how to cite the package are in
{help csdid##authors:help csdid}.


{marker alsosee}{...}
{title:Also see}

{psee}
Online:  {helpb csdid}, {helpb csdid_postestimation:csdid postestimation},
{helpb csdid_estat}, {helpb csdid_stats}, {helpb csdid_plot}
{p_end}
