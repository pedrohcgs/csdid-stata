{smcl}
{* *! version 2.0.0 28aug2026}{...}
{vieweralsosee "csdid" "help csdid"}{...}
{vieweralsosee "csdid legacy utilities" "help csdid_legacy"}{...}
{vieweralsosee "" "--"}{...}
{vieweralsosee "[D] egen" "help egen"}{...}
{vieweralsosee "[D] generate" "help generate"}{...}
{viewerjumpto "Syntax" "csgvar##syntax"}{...}
{viewerjumpto "Description" "csgvar##description"}{...}
{viewerjumpto "Options" "csgvar##options"}{...}
{viewerjumpto "Remarks" "csgvar##remarks"}{...}
{viewerjumpto "Diagnostics" "csgvar##errors"}{...}
{viewerjumpto "Examples" "csgvar##examples"}{...}
{viewerjumpto "Authors" "csgvar##authors"}{...}
{viewerjumpto "Also see" "csgvar##alsosee"}{...}

{title:Title}

{p2colset 5 16 18 2}{...}
{p2col:{bf:csgvar} {hline 2}}Build the cohort variable {cmd:csdid} needs from a
binary treatment indicator{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{pstd}
{bf:Command form}

{p 8 16 2}
{cmd:csgvar} [{it:type}] {newvar} {cmd:=} {it:exp} {ifin}{cmd:,}
{opth tvar(varname)} {opth ivar(varname)}

{pstd}
{bf:egen form}

{p 8 16 2}
{cmd:egen} [{it:type}] {newvar} {cmd:=} {cmd:csgvar(}{it:exp}{cmd:)} {ifin}{cmd:,}
{opth tvar(varname)} {opth ivar(varname)}

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main}
{p2coldent :* {opth tvar(varname)}}time period variable; numeric{p_end}
{p2coldent :* {opth ivar(varname)}}panel unit identifier; numeric{p_end}
{synoptline}
{p2colreset}{...}
{p 4 6 2}
* {opt tvar()} and {opt ivar()} are required.{p_end}
{p 4 6 2}
{it:exp} is the treatment indicator: a variable, or any numeric expression
{helpb generate} accepts. It must take at most two values on the selected
sample, and the untreated state must be coded {cmd:0}.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:csgvar} creates the cohort variable that {helpb csdid}'s {cmd:gvar()}
option expects: for each unit, the first period in which that unit is treated,
and {cmd:0} for a unit never treated within the sample. That is the coding
{cmd:csdid} requires, and it is the one piece of data preparation a staggered
design usually needs.

{pstd}
The same computation is available as an {helpb egen} function. The two forms
are one implementation -- the command forwards to the {cmd:egen} entry point --
so they accept the same options, produce the same variable, and raise the same
refusals. They differ only in the default storage type; see
{help csgvar##remarks_type:Storage type} below.

{pstd}
{cmd:csgvar} does not change the sort order of the data in memory.


{marker options}{...}
{title:Options}

{dlgtab:Main}

{phang}
{opth tvar(varname)} names the time period variable. It is the variable whose
values become cohort codes: the cohort assigned to a treated unit is the
smallest {cmd:tvar()} value at which the indicator is nonzero for that unit.
It is required.

{phang}
{opth ivar(varname)} names the panel unit identifier. Cohorts are assigned per
unit, so a unit treated from 2004 onward carries {cmd:2004} in every one of its
rows, including its pre-treatment rows. It is required.

{pmore}
Observations where {cmd:tvar()}, {cmd:ivar()} or the indicator is missing take
part in nothing: they are excluded from the computation and the new variable is
missing there.


{marker remarks}{...}
{title:Remarks}

{pstd}
{bf:What {cmd:gvar()} means.} {cmd:csdid} estimates one ATT(g,t) per treatment
cohort {it:g} and period {it:t}, and {it:g} is the period in which a cohort
first becomes treated. So {cmd:gvar()} is not a treatment status: it is a
constant per unit, equal to that unit's first treated period on the same
calendar axis as {cmd:time()}, and {cmd:0} for a unit that is never treated in
the sample. Never-treated units are what the {cmd:nevertreated} comparison
group is made of, and they enter the not-yet-treated comparison group as well.

{pstd}
{bf:What the indicator must look like.} The untreated state must be coded
{cmd:0}; that, and only that, is what makes a never-treated unit come out as
cohort {cmd:0}. The treated value is free -- {cmd:0}/{cmd:5} works as well as
{cmd:0}/{cmd:1} -- and an indicator taking two values neither of which is
{cmd:0}, such as {cmd:1}/{cmd:2} or {cmd:-1}/{cmd:1}, is refused rather than
accepted: with that coding every unit would be given a positive cohort, the
result would contain no never-treated units at all, and {cmd:csdid} would
estimate on it without complaint.

{pstd}
{bf:Absorbing and non-absorbing treatment.} {cmd:csgvar} takes the {it:first}
period at which the indicator is nonzero. A unit whose treatment switches off
again therefore keeps the cohort of its first treated period, which is what
the staggered-adoption design assumes; if your treatment is not absorbing,
{cmd:csdid} is estimating something other than what your data contain, and the
cohort variable will not tell you so.

{marker remarks_type}{...}
{pstd}
{bf:Storage type.} A cohort code is a value on your time axis, so
{cmd:csgvar} computes it in {cmd:double} and then stores it in the type you
asked for. With no type given, the command form gives you a {cmd:double}; the
{helpb egen} form takes {cmd:egen}'s own default, which is whatever
{helpb set type} is, so write {cmd:egen double} when the time axis needs it. A
type too narrow to hold the cohort code exactly is refused with return code
{cmd:r(198)} rather than rounded: a rounded cohort is a different treatment
group. This matters on a {cmd:%tc} or epoch-second axis, whose values run past
{cmd:float}'s exact range.

{pstd}
{bf:An expression is accepted.} {it:exp} is a Stata expression, not just a
variable name, so the indicator can be built in place --
{cmd:csgvar g = (state_policy > 0)} -- without generating it first. The
messages and the variable label report the expression as you typed it.


{marker errors}{...}
{title:Diagnostics}

{pstd}
{cmd:csgvar} refuses rather than producing a cohort variable it cannot stand
behind:

{p2colset 5 14 16 2}{...}
{p2col:{cmd:r(198)}}the requested storage type would round the cohort code.
An expression that cannot be evaluated aborts earlier with Stata's own code
for the specific failure (for example 111 for an unknown variable, 133 for an
unknown function, 109 for a type mismatch){p_end}
{p2col:{cmd:r(459)}}the indicator takes more than two values on the selected
sample, or takes two values neither of which is {cmd:0}; the message names the
values it found{p_end}
{p2col:{cmd:r(2000)}}no observations: the indicator, {cmd:tvar()} and
{cmd:ivar()} are jointly missing on every selected observation{p_end}
{p2colreset}{...}


{marker examples}{...}
{title:Examples}

{pstd}Setup: a four-period panel of twenty units, half of them treated from
2003 onward{p_end}
{phang2}{cmd:. clear}{p_end}
{phang2}{cmd:. set obs 80}{p_end}
{phang2}{cmd:. generate id = ceil(_n/4)}{p_end}
{phang2}{cmd:. bysort id: generate year = 2000 + _n}{p_end}
{phang2}{cmd:. generate byte treated = (id <= 10) & (year >= 2003)}{p_end}

{hline}
{pstd}Build the cohort variable and look at it{p_end}
{phang2}{cmd:. csgvar gvar = treated, tvar(year) ivar(id)}{p_end}
{phang2}{cmd:. tabulate gvar}{p_end}

{pstd}
Units 1-10 carry {cmd:2003} in all four of their rows; units 11-20 carry
{cmd:0}.{p_end}

{hline}
{pstd}The {helpb egen} form, asking for a storage type explicitly{p_end}
{phang2}{cmd:. egen double gvar2 = csgvar(treated), tvar(year) ivar(id)}{p_end}
{phang2}{cmd:. assert gvar2 == gvar}{p_end}

{hline}
{pstd}The indicator as an expression, built in place{p_end}
{phang2}{cmd:. csgvar gvar3 = (id <= 10 & year >= 2003), tvar(year) ivar(id)}{p_end}
{phang2}{cmd:. assert gvar3 == gvar}{p_end}

{hline}
{pstd}Then estimate{p_end}
{phang2}{cmd:. set seed 1}{p_end}
{phang2}{cmd:. generate y = rnormal() + 2*(gvar > 0 & year >= gvar)}{p_end}
{phang2}{cmd:. csdid y, ivar(id) time(year) gvar(gvar) analytical}{p_end}
{hline}


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
{helpb csdid_legacy:csdid legacy utilities}, {helpb egen}, {helpb generate}
{p_end}
