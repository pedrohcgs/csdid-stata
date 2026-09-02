{smcl}
{* *! version 2.0.0 01sep2026}{...}
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
This is what changed for someone upgrading from csdid Version 1.82, the
version SSC distributes. The command surface is deliberately the same, so most
existing do-files run unchanged; the entries below are the places where they do
not, and the things that are new. {helpb csdid} documents everything in full.


{marker v200}{...}
{hline 8} {hi:csdid 2.0.0, released August 2026} {hline}

{pstd}
{bf:Three defaults moved. Read these first: they change numbers.}

{phang}
{bf:1. Not-yet-treated is the default comparison group.} Version 1.82 compared
each treated cohort with the never-treated units. Version 2.0.0 uses every unit
not yet treated at period {it:t}. It uses more of the data, usually gives
tighter standard errors, and does not depend on a never-treated group existing
or being large enough to trust. {cmd:nevertreated} asks for the older
behaviour. See {help csdid##opt_control:comparison-group options}.

{phang}
{bf:2. The base period is universal.} Version 1.82 measured each cell against
the period before {it:t}. Version 2.0.0 measures every cell against
{it:g}{cmd:-1}, which is the layout an event-study plot assumes. Post-treatment
effects are the same under either choice; only the pre-treatment cells differ,
and the universal base period additionally reports the {it:g}{cmd:-1}
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
are unaffected by either.

{phang}
{bf:4. Unbalanced panels are balanced once, and csdid says so.} Version 1.82
dropped, without comment, the units not observed in both periods of each
comparison. Version 2.0.0 makes the choice explicit: {cmd:bal(full)}, the
default, drops units not observed in every period, once, for all comparisons;
{cmd:bal(pair)} balances each 2x2 separately, which is what Version 1.82 did
silently; {cmd:bal(none)} keeps every unit. Whenever a mode discards
observations, {cmd:csdid} reports how many, and {cmd:e(panel_mode)} records the
layout it resolved to.

{pstd}
{bf:New in 2.0.0}

{phang}
{bf:5. No external dependencies.} Version 1.82 required {cmd:drdid} from SSC.
Version 2.0.0 requires nothing beyond Stata itself: the estimation engine is
Mata, ships precompiled, and behaves identically on Windows, macOS, and Linux.

{phang}
{bf:6. A rewritten engine.} On the same data, with 2.0.0 asked for Version
1.82's own defaults so that both compute the same numbers, 2.0.0 runs between
17 and 334 times faster, with the gap widening as the number of cohorts and
periods -- and so the number of ATT(g,t) cells -- grows.

{phang}
{bf:7. Postestimation in the conventional forms.} {cmd:estat event},
{cmd:estat group}, {cmd:estat calendar}, {cmd:estat simple},
{cmd:estat dynamic} and {cmd:estat attgt} aggregate the stored results, and
every one of them takes {cmd:saving()}, so any aggregation can be written to a
dataset without a separate export command. {cmd:estat tidy} and
{cmd:estat glance} export the table and the header. {helpb csdid_plot} draws
the figure -- also reachable as {cmd:estat plot} -- and
{cmd:csdid_plot, saving()} exports the numbers behind it --
estimates, band bounds, axis values -- to draw with {helpb twoway} exactly as
you want it. See {helpb csdid_estat} and {helpb csdid_plot}.

{phang}
{bf:8. Redisplay, and two diagnostics.} A bare {cmd:csdid} after an estimation
redisplays the results, as official estimation commands do.
{cmd:csdid version} reports the version, the copy of {cmd:csdid.ado} that
answered, and the engine the session is using, and changes nothing.
{cmd:csdid reset} clears the session's engine decision and estimation cache, so
that a csdid installed or replaced mid-session is the one that runs next. See
{help csdid##support:Installation, upgrading and diagnostics}.

{phang}
{bf:9. A bootstrap accelerator on macOS.} The package installs a small
compiled accelerator, a universal binary covering Intel and Apple-silicon
machines, used for explicitly seeded Rademacher draws. Its results are
identical to the Mata path, including the random-number state. Everywhere else
-- and on macOS whenever it cannot load -- the bootstrap runs through Mata,
and {cmd:e(bootstrap_accelerator)} and
{cmd:e(bootstrap_accelerator_status)} report which path ran.

{phang}
{bf:10. Repeated cross sections, declared.} {cmd:rcs} says that the data are
repeated cross sections while keeping an identifier variable, which
{cmd:cluster()} can then use. Omitting {cmd:ivar()} still works and means the
same thing.

{phang}
{bf:11. More is refused instead of being accepted quietly.} A panel whose
shape contradicts the design is refused with a message naming the variable at
fault: a unit appearing twice in a period, a {cmd:gvar()} that changes within a
unit, a {cmd:cluster()} that changes within a unit. Options that Version 1.82
took and then ignored are refused too, rather than leaving inference running at
settings you did not ask for. See
{help csdid##remarks_behavior:Notes on specific behavior} in {helpb csdid}.

{pstd}
{bf:Migrating}

{phang}
Legacy spellings still run, each with a message saying what it resolved to;
{cmd:from()} and a handful of others are refused by name with the replacement
in the message. The option-by-option list is at
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
