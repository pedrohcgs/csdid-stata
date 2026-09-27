{smcl}
{* *! version 2.0.0 27sep2026}{...}
{vieweralsosee "csdid" "help csdid"}{...}
{vieweralsosee "csdid postestimation" "help csdid_postestimation"}{...}
{vieweralsosee "csdid_estat" "help csdid_estat"}{...}
{vieweralsosee "csdid_stats" "help csdid_stats"}{...}
{vieweralsosee "csdid_plot" "help csdid_plot"}{...}
{vieweralsosee "csdid legacy utilities" "help csdid_legacy"}{...}
{viewerjumpto "csdid 2.0.0" "csdid_whatsnew##v200"}{...}
{viewerjumpto "Also see" "csdid_whatsnew##alsosee"}{...}

{title:Title}

{p2colset 5 22 24 2}{...}
{p2col:{bf:csdid whatsnew} {hline 2}}What's new in csdid{p_end}
{p2colreset}{...}

{pstd}
This is what changed for someone upgrading from csdid Version 1.82, the last
revision of the 1.8x line; {cmd:ssc install csdid} installs Version 1.81,
whose two further differences are listed in {helpb csdid}. The command surface
is deliberately the same, so most existing do-files run unchanged. The entries
below summarize where they do not, and the things that are new;
{help csdid##remarks_legacy:Migrating from Stata csdid Version 1.82} in
{helpb csdid} lists every change with what replaces it.


{marker v200}{...}
{hline 8} {hi:csdid 2.0.0} {hline}

{pstd}
{bf:Five defaults moved. Read these first: they change numbers.}

{phang}
{bf:1. Not-yet-treated is the default comparison group.} Version 1.82 compared
each treated cohort with the never-treated units. Version 2.0.0 also uses every
unit not yet treated in either period of the comparison. It uses more of the data, usually gives
tighter standard errors, and does not depend on a never-treated group existing
or being large enough to trust. {cmd:nevertreated} asks for the older
behaviour. See {help csdid##opt_control:comparison-group options}.

{phang}
{bf:2. The base period is universal.} Version 1.82 measured each cell against
the preceding observed period for pre-treatment comparisons. Version 2.0.0
uses one reference per cohort: the last observed period before
{it:g - anticipation}, or {it:g}{cmd:-1} on a consecutive calendar without
anticipation. Post-treatment
effects are the same under either choice; only the pre-treatment cells differ,
and the universal base period additionally reports its reference-period
normalisation row. Use {cmd:base_period(varying)} when pre-testing, so that a
violation shows up in the period where it happens rather than being carried
into every later cell.

{phang}
{bf:3. Standard errors are bootstrapped, with simultaneous confidence bands.}
Version 1.82 reported pointwise analytical standard errors unless {cmd:wboot}
was asked for. Version 2.0.0 runs the multiplier bootstrap over 1,000
iterations by default and reports bands that cover the estimated effects
jointly, because a staggered design produces dozens of estimates and pointwise
intervals do not account for looking at all of them at once. An aggregation's
overall summary effect is a single number, so it is reported with a pointwise
interval.
{cmd:analytical} restores analytical standard errors (an aggregation's
per-effect rows still
carry a simultaneous band, its critical value bootstrapped with a note,
unless {cmd:pointwise} is added), and
{cmd:pointwise} gives pointwise intervals from the bootstrap. Point estimates
are unaffected by either. The bootstrap draws Rademacher multipliers only;
Version 1.82's {cmd:wboot} drew Mammen multipliers unless told otherwise.

{phang}
{bf:4. Propensity scores are trimmed at .995.} Under {cmd:method(dr)} and
{cmd:method(ipw)}, comparison observations whose estimated propensity score is
.995 or more are dropped, without a message. Version 1.82 did not trim.
{cmd:pscoretrim(1)} turns trimming off.

{phang}
{bf:5. Unbalanced panels are balanced once, and csdid says so.} Version 1.82
balanced each comparison separately: it said the panel was unbalanced, but not
which or how many units each comparison dropped. Version 2.0.0 makes the
choice explicit: {cmd:bal(full)}, the default, drops units not observed in
every period, once, for all comparisons; {cmd:bal(pair)} balances each 2x2
separately, which is what Version 1.82 did; {cmd:bal(none)} keeps every unit.
Whenever a mode discards observations, {cmd:csdid} reports how many, and
{cmd:e(panel_mode)} records the layout it resolved to.

{pstd}
{bf:Three more changes move numbers, and no option undoes them.}

{phang}
{bf:6. notyet pre-treatment cells follow Version 1.82's asinr rule.} A
comparison unit must be untreated in both periods of the comparison, as under
Version 1.82's {cmd:notyet asinr}; Version 1.82's plain {cmd:notyet} used only
the cohorts treated after {it:g} in pre-treatment cells. Under
{cmd:notyet base_period(varying)}, pre-treatment cells and the pre-test move;
post-treatment cells do not.

{phang}
{bf:7. long reverses the sign of Version 1.82's long pre-treatment cells.}
{cmd:long} and {cmd:long2} both give Version 1.82's {cmd:long2} cells, so after
{cmd:long} each pre-treatment cell and each pre-period event-study coefficient
changes sign, and the coefficients move one event time earlier.

{phang}
{bf:8. The overall standard error of estat group} differs from Version 1.82's.
The cohort effects, their standard errors and the overall effect are
unchanged.

{pstd}
{bf:New in 2.0.0}

{phang}
{bf:9. No external dependencies.} Version 1.82 required {cmd:drdid} from SSC.
Version 2.0.0 requires nothing beyond Stata itself: the estimation engine is
Mata, ships precompiled, and runs on Windows, macOS, and Linux.

{phang}
{bf:10. A rewritten engine.} On the same data, with 2.0.0 asked for
Version 1.82's own defaults so that both compute the same numbers, 2.0.0 runs between
10 and 308 times faster in the published comparisons, with the gap widening as
the number of cohorts and periods -- and so the number of ATT(g,t) cells --
grows.

{phang}
{bf:11. Postestimation in the conventional forms.} {cmd:estat event},
{cmd:estat group}, {cmd:estat calendar}, {cmd:estat simple} and
{cmd:estat attgt} are joined by {cmd:estat dynamic}, and every one of them
takes {cmd:saving()}, so any aggregation can be written to a dataset without a
separate export command. {cmd:estat tidy} and {cmd:estat glance} export the
table and the header. {helpb csdid_plot} draws the figure -- also reachable as
{cmd:estat plot} -- and {cmd:csdid_plot, saving()} exports the numbers behind
it -- estimates, band bounds, axis values -- to draw with {helpb twoway}
exactly as you want it. See {helpb csdid_estat} and {helpb csdid_plot}.

{phang}
{bf:12. Two diagnostics.} {cmd:csdid version} reports the version, the copy of
{cmd:csdid.ado} that answered, and the engine the session is using, and
changes nothing. {cmd:csdid reset} clears the session's engine decision and
estimation cache, so that a csdid installed or replaced mid-session is the one
that runs next. See
{help csdid##support:Installation, upgrading and diagnostics}.

{phang}
{bf:13. A bootstrap accelerator on macOS.} The package installs a small
compiled accelerator, a universal binary covering Intel and Apple-silicon
machines, used for explicitly seeded Rademacher draws. It draws the same
multipliers as the Mata path, leaves the same random-number state, and agrees
with it to floating-point rounding. Unseeded draws, every other platform, and
a Mac where it cannot load use the Mata path, and
{cmd:e(bootstrap_accelerator)} and {cmd:e(bootstrap_accelerator_status)}
report which path ran.

{phang}
{bf:14. Repeated cross sections, declared.} {cmd:rcs} says that the data are
repeated cross sections while keeping an identifier variable, which
{cmd:cluster()} can then use. Omitting {cmd:ivar()} still works and means the
same thing.

{phang}
{bf:15. More is refused instead of being accepted quietly.} A panel whose
shape contradicts the design is refused with a message naming the variable at
fault: a unit appearing twice in a period, a {cmd:gvar()} that changes within a
unit, a {cmd:cluster()} that changes within a unit. Options that Version 1.82
took and then ignored are refused too, rather than leaving inference running at
settings you did not ask for. See
{help csdid##remarks_behavior:Notes on specific behavior} in {helpb csdid}.

{pstd}
{bf:Migrating}

{phang}
Six legacy spellings still run, each with a message saying what it resolved
to. Version 1.82 options and postestimation forms that are gone, such as
{cmd:method(drimp)}, {cmd:estat pretrend} and {cmd:estore()}, are refused. The
option-by-option list, with what replaces each, is at
{help csdid##remarks_legacy:Migrating from Stata csdid Version 1.82} in
{helpb csdid}, and installation and upgrading are covered at
{help csdid##support:Installation, upgrading and diagnostics}.

{hline}


{marker alsosee}{...}
{title:Also see}

{psee}
Online:  {helpb csdid}, {helpb csdid_postestimation:csdid postestimation},
{helpb csdid_estat}, {helpb csdid_stats}, {helpb csdid_plot},
{helpb csgvar}, {helpb csdid_legacy:csdid legacy utilities}
{p_end}
