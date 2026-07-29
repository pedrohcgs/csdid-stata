{smcl}
{* *! version 2.0.0 26jul2026}{...}
{vieweralsosee "csdid postestimation" "help csdid_postestimation"}{...}
{vieweralsosee "csdid_stats" "help csdid_stats"}{...}
{vieweralsosee "csdid_estat" "help csdid_estat"}{...}
{vieweralsosee "csdid_plot" "help csdid_plot"}{...}
{vieweralsosee "" "--"}{...}
{vieweralsosee "[CAUSAL] didregress" "help didregress"}{...}
{vieweralsosee "[CAUSAL] xtdidregress" "help xtdidregress"}{...}
{vieweralsosee "[CAUSAL] hdidregress" "help hdidregress"}{...}
{vieweralsosee "[XT] xtreg" "help xtreg"}{...}
{vieweralsosee "" "--"}{...}
{viewerjumpto "Syntax" "csdid##syntax"}{...}
{viewerjumpto "Description" "csdid##description"}{...}
{viewerjumpto "Options" "csdid##options"}{...}
{viewerjumpto "Remarks" "csdid##remarks"}{...}
{viewerjumpto "Examples" "csdid##examples"}{...}
{viewerjumpto "Stored results" "csdid##results"}{...}
{viewerjumpto "Methods and formulas" "csdid##methods"}{...}
{viewerjumpto "Acknowledgments" "csdid##acknowledgments"}{...}
{viewerjumpto "References" "csdid##references"}{...}
{viewerjumpto "Authors" "csdid##authors"}{...}
{viewerjumpto "Support and updates" "csdid##support"}{...}
{title:Title}

{p2colset 5 15 17 2}{...}
{p2col:{bf:csdid} {hline 2}}Difference-in-differences with multiple time
periods and staggered treatment adoption (Callaway and Sant'Anna 2021){p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{pstd}
{bf:Panel data} (one row per unit and period; {cmd:ivar()} identifies the unit)

{p 8 16 2}
{cmd:csdid} {depvar} [{indepvars}] {ifin} [{help csdid##weight:{it:weight}}]{cmd:,}{break}
{opth time(varname)}
{opth gvar(varname)}
{opth ivar(varname)}
[{it:{help csdid##options_table:options}}]

{pstd}
{bf:Repeated cross sections} (no unit identifier; omit {cmd:ivar()})

{p 8 16 2}
{cmd:csdid} {depvar} [{indepvars}] {ifin} [{help csdid##weight:{it:weight}}]{cmd:,}{break}
{opth time(varname)}
{opth gvar(varname)}
[{it:{help csdid##options_table:options}}]

{pstd}
{bf:Version query}

{p 8 16 2}
{cmd:csdid} {cmd:version}


{marker options_table}{...}
{synoptset 28 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main {help csdid##opt_main:[+]}}
{p2coldent :* {opth time(varname)}}time period variable; numeric{p_end}
{p2coldent :* {opth gvar(varname)}}period of first treatment for each unit,
{cmd:0} for never treated; numeric{p_end}
{synopt:{opth ivar(varname)}}panel unit identifier; omit for repeated cross
sections{p_end}
{synopt:{opth id(varname)}}synonym for {cmd:ivar()}{p_end}
{synopt:{opt rcs}}declare the data to be repeated cross sections, even when
{cmd:ivar()} is supplied{p_end}
{synopt:{opt bal(mode)}}panel balancing: {cmd:full}, {cmd:pair}, or
{cmd:none}; default is {cmd:bal(full)}{p_end}

{syntab:Model {help csdid##opt_model:[+]}}
{synopt:{opt method(string)}}2x2 estimator: {cmd:dr}, {cmd:reg}, or
{cmd:ipw}; default is {cmd:method(dr)}{p_end}
{synopt:{opt pscoretrim(#)}}propensity-score trimming level; default is
{cmd:pscoretrim(.995)}{p_end}
{synopt:{opt fix_w:eights(rule)}}weight rule when {cmd:iweight}s are used:
{cmd:varying}, {cmd:base}, or {cmd:first}; by default the option is not set{p_end}

{syntab:Control group {help csdid##opt_control:[+]}}
{synopt:{opt notyet}}state the default not-yet-treated comparison group
explicitly{p_end}
{synopt:{opt notyettreated}}synonym for {cmd:notyet}{p_end}
{synopt:{opt nevertreated}}use only never-treated units as the comparison
group{p_end}

{syntab:Base period and anticipation {help csdid##opt_base:[+]}}
{synopt:{opt base_p:eriod(rule)}}{cmd:varying} or {cmd:universal} base period;
default is {cmd:base_period(universal)}{p_end}
{synopt:{opt baseperiod(rule)}}synonym for {cmd:base_period()}{p_end}
{synopt:{opt varying}}synonym for {cmd:base_period(varying)}{p_end}
{synopt:{opt universal}}synonym for {cmd:base_period(universal)}{p_end}
{synopt:{opt anticip:ation(#)}}number of periods of anticipated treatment
effect; default is {cmd:anticipation(0)}{p_end}

{syntab:Inference {help csdid##opt_inference:[+]}}
{synopt:{opt wboot(bootopts)}}multiplier-bootstrap suboptions; bootstrap
inference is already the default{p_end}
{synopt:{opt reps(#)}}number of bootstrap iterations; default is
{cmd:reps(1000)}{p_end}
{synopt:{opt biters(#)}}synonym for {cmd:reps()}{p_end}
{synopt:{opt rseed(#)}}positive integer seed making the bootstrap draws
reproducible{p_end}
{synopt:{opt seed(#)}}synonym for {cmd:rseed()}{p_end}
{synopt:{opt point:wise}}report pointwise instead of simultaneous confidence
bands{p_end}
{synopt:{opt analyt:ical}}use analytical influence-function standard errors
instead of the bootstrap{p_end}
{synopt:{cmd:vce(analytical)}}synonym for {cmd:analytical}{p_end}
{synopt:{opth cl:uster(varname)}}cluster inference on {it:varname}; numeric{p_end}
{synopt:{cmd:vce(cluster} {it:clustvar}{cmd:)}}synonym for {cmd:cluster()}{p_end}

{syntab:Reporting {help csdid##opt_reporting:[+]}}
{synopt:{opt l:evel(#)}}set confidence level; default is {cmd:level(95)}{p_end}
{synopt:{opt agg(event)}}immediately compute and post the event-study
aggregation{p_end}

{syntab:Saving {help csdid##opt_saving:[+]}}
{synopt:{opt saverif(filename)}}save the influence functions as a Stata
dataset for later use by {helpb csdid_stats}{p_end}
{synopt:{opt replace}}overwrite the file named in {cmd:saverif()}{p_end}

{syntab:Storage and diagnostics {help csdid##opt_storage:[+]}}
{synopt:{opt storeall}}always copy the large influence-function matrices into
{cmd:e()}{p_end}
{synopt:{opt lean}}never copy them into {cmd:e()}{p_end}
{synopt:{opt perf:ormance(mode)}}{cmd:auto}, {cmd:lean}, or {cmd:full} storage;
default is {cmd:performance(auto)}{p_end}
{synopt:{opt fast}}force the optimized Mata kernels{p_end}
{synopt:{opt nofast}}force the baseline Mata kernels{p_end}

{syntab:Legacy compatibility {help csdid##opt_legacy:[+]}}
{synopt:{opt asinr}}accepted as a no-op{p_end}
{synopt:{opt never}}accepted as a no-op{p_end}
{synopt:{opt long}, {opt long2}}deprecated event-study layout aliases{p_end}
{synopt:{opt allowunbalanced}}deprecated name for {cmd:bal(none)}{p_end}
{synopt:{opt balanceall}}deprecated name for {cmd:bal(full)}{p_end}
{synopt:{opt balancepair}}deprecated name for {cmd:bal(pair)}{p_end}
{synoptline}
{p2colreset}{...}
{p 4 6 2}
* {opt time()} and {opt gvar()} are required.{p_end}
{p 4 6 2}
{it:depvar} and {it:indepvars} must be numeric. {it:indepvars} may contain
{help fvvarlist:factor variables}.{p_end}
{marker weight}{...}
{p 4 6 2}
{cmd:iweight}s are allowed; see {help weight} and
{help csdid##opt_main:Main} below.  {cmd:aweight}s, {cmd:fweight}s, and
{cmd:pweight}s are not allowed.{p_end}
{p 4 6 2}
{cmd:csdid} does not set {cmd:e(sample)} and does not support {cmd:predict} or
{cmd:margins}; see {help csdid##remarks_post:Postestimation}.{p_end}
{p 4 6 2}
See {helpb csdid_postestimation:csdid postestimation} for the commands
available after {cmd:csdid}.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:csdid} estimates group-time average treatment effects, ATT(g,t), for
designs in which different units become treated in different periods and stay
treated afterwards ({it:staggered adoption}), following
{help csdid##callaway2021:Callaway and Sant'Anna (2021)}. Each ATT(g,t) is the
average effect of treatment at time
{it:t} for the cohort of units first treated at time {it:g}. Aggregations of
those effects into event-study, cohort, calendar-time, and overall summaries
are produced by {helpb csdid_stats} and {helpb csdid_estat}.

{pstd}
Each ATT(g,t) is estimated from a two-period, two-group comparison between
cohort {it:g} and a comparison group of units that are not (yet) treated,
using the doubly robust, outcome-regression, or inverse-probability-weighting
estimators of {help csdid##santannazhao2020:Sant'Anna and Zhao (2020)}.
Standard errors come from the
estimator's influence function, either analytically or through a multiplier
bootstrap that also delivers simultaneous confidence bands.

{pstd}
Four companion commands complete the package: {helpb csdid_stats} computes and
reports the aggregations, {helpb csdid_estat} makes the same aggregations and
the export tables available through {cmd:estat}, {helpb csdid_plot} draws and
exports event-study and cohort plots, and
{helpb csdid_postestimation:csdid postestimation} lists everything that may be
run after {cmd:csdid}.

{pstd}
{cmd:csdid} implements the estimators of
{help csdid##callaway2021:Callaway and Sant'Anna (2021)} in Mata. See
{help csdid##remarks_behavior:Notes on specific behavior} for the places where
it refuses rather than guessing.

{pstd}
{cmd:csdid version} displays the package version.

{pstd}
Source, issue tracker, and release notes are at
{browse "https://github.com/pedrohcgs/csdid-stata":github.com/pedrohcgs/csdid-stata}.

{pstd}
{it:Requires Stata 14 or later.}


{marker options}{...}
{title:Options}

{marker opt_main}{...}
{dlgtab:Main}

{phang}
{opth time(varname)} specifies the numeric time-period variable. It is
required. Periods need not be consecutive integers, but they must be ordered
sensibly on the number line.

{pmore}
The period and cohort {it:values} are pasted into the ATT(g,t) coefficient
names (see {help csdid##remarks_post:Postestimation}), and Stata names are
limited to 32 characters. {cmd:csdid} measures the width the names would need
from the ranges of {cmd:time()} and {cmd:gvar()} {it:before} estimating and, if
32 characters would not be enough, refuses with return code 198 rather than
failing later inside {cmd:matrix colnames}. That happens with axes such as
epoch seconds or {cmd:%tc} milliseconds. The remedy the message names is to
relabel the axis - use years rather than epoch seconds, or build a compact
index with {cmd:egen} {it:t2}{cmd: = group(}{it:timevar}{cmd:)} and the
matching {cmd:gvar()}. A monotone relabelling of the periods leaves every
estimate unchanged.

{phang}
{opth gvar(varname)} specifies the numeric variable holding the first period
in which each unit is treated. Never-treated units must have {cmd:gvar()}
equal to {cmd:0}. Negative values are an error. {cmd:gvar()} must be constant
within a unit. It encodes
the staggered-adoption design: treatment is absorbing, so a unit with
{cmd:gvar()} equal to {it:g} is treated in every period from {it:g} onward.

{phang}
{opth ivar(varname)} specifies the numeric panel unit identifier. Supply it
for panel data. {opth id(varname)} is a synonym; specifying both with
different variables is an error. Omitting {cmd:ivar()} estimates the repeated
cross-section version of the estimator.

{phang}
{cmd:iweight}s are allowed and are treated as nonnegative sampling weights
with positive mean. They are
normalized internally. {cmd:aweight}s, {cmd:fweight}s, and {cmd:pweight}s are
not accepted.

{marker opt_model}{...}
{dlgtab:Model}

{phang}
{opt method(string)} selects the 2x2 estimator used for every (g,t) cell:

{p2colset 12 26 28 2}{...}
{p2col:{cmd:dr}}doubly robust (the default): the improved, locally efficient
estimator of Sant'Anna and Zhao (2020){p_end}
{p2col:{cmd:reg}}outcome regression only{p_end}
{p2col:{cmd:ipw}}normalized (Hajek) inverse probability weighting only{p_end}
{p2colreset}{...}

{pmore}
With no covariates all three coincide with the unconditional two-by-two
difference in differences. The legacy Stata spellings {cmd:method(dripw)} and
{cmd:method(stdipw)} are accepted with a compatibility message and are mapped
to {cmd:dr} and {cmd:ipw}; the requested spelling is recorded in
{cmd:e(method_requested)}. The legacy names {cmd:method(drimp)} and
{cmd:method(aipw)} are {bf:rejected} with return code 198, because they do not
correspond to any of the estimators above, and silently substituting one
would change the estimand.

{phang}
{opt pscoretrim(#)} sets the propensity-score trimming level used by
{cmd:method(dr)} and {cmd:method(ipw)}. Comparison observations whose
estimated propensity score is at or above {it:#} are dropped from that cell;
treated observations are never dropped. {it:#} must be greater than 0, and the
default is {cmd:pscoretrim(.995)}. Specify {cmd:pscoretrim(1)} (or any larger
value) to disable trimming entirely; this is the level earlier versions of
{cmd:csdid} used by default. This is an overlap safeguard, not a specification
choice: if it binds often, the overlap assumption is in doubt.

{phang}
{opt fix_weights(rule)} controls how {cmd:iweight}s are applied over time in
panel data. {it:rule} may
be {cmd:varying} (use each observation's own weight in each of the two periods
of the comparison), {cmd:base} or {cmd:base_period} (freeze each unit's weight
at the base period), or {cmd:first} or {cmd:first_period} (freeze each unit's
weight at its first observed period). {cmd:fixweights()}, without the
underscore, is an accepted synonym. The fixed rules require {cmd:ivar()}: there is no
repeated-cross-section analogue. The resolved rule is reported in
{cmd:e(fix_weights)}, which is empty when the option is not given.

{pmore}
{bf:The default is not} {cmd:fix_weights(varying)}: it is to leave the option
unset. On a balanced panel an
unset {cmd:fix_weights()} uses, for each 2-by-2 comparison, the weight from the
{it:earlier} of the two periods, that is the base period for post-treatment
cells. {cmd:fix_weights(varying)} is a different rule and gives different
numbers whenever the weights vary within a unit over time; if they do not vary,
all four settings coincide. {cmd:csdid} prints a note when it detects
time-varying weights.

{marker opt_control}{...}
{dlgtab:Control group}

{phang}
{opt notyet} uses units that have not been treated as of the current period,
including units that will be treated later, as the comparison group.
{opt notyettreated} is a synonym.

{phang}
{opt nevertreated} states the default explicitly: only units with
{cmd:gvar() == 0} serve as controls. Combining it with {cmd:notyet} is an
error. If the data contain no never-treated units, {cmd:csdid} falls back to
using the latest treated cohort as the comparison group and says so. The
resolved choice is recorded in
{cmd:e(control_group)}.

{marker opt_base}{...}
{dlgtab:Base period and anticipation}

{phang}
{opt base_period(rule)} chooses the period each ATT(g,t) differences against.

{p2colset 12 26 28 2}{...}
{p2col:{cmd:varying}}(the default) for post-treatment periods, {it:t >= g}, the
base period is {it:g - 1 - anticipation}; for pre-treatment periods the base
period is the period immediately before {it:t}. Pre-treatment estimates are
then short-differences and are the natural placebo checks.{p_end}
{p2col:{cmd:universal}}every ATT(g,t), pre and post, differences against the
single base period {it:g - 1 - anticipation}. Pre-treatment estimates are then
long-differences relative to a common reference period, and the reference
period itself appears in {cmd:e(attgt)} with an estimate of exactly zero and a
missing standard error.{p_end}
{p2colreset}{...}

{pmore}
{opt baseperiod(rule)}, without the underscore, is an accepted synonym, as are
the bare options {opt varying} and {opt universal}. Specifying two spellings
with different values is an error. The choice does not change the
post-treatment ATT(g,t) estimates; it changes which pre-treatment comparisons
are reported and how an event study lines up.

{phang}
{opt anticipation(#)} allows units to respond up to {it:#} periods before
their nominal treatment date. It shifts every base period back by {it:#}
periods, so the no-anticipation assumption is only required from
{it:g - #} onward. {it:#} must be a nonnegative integer; the default is
{cmd:anticipation(0)}. Cohorts left without a usable base period, that is
cohorts with {it:g - # } at or before the first period in the sample, are
dropped with a message.

{marker opt_inference}{...}
{dlgtab:Inference}

{phang}
{cmd:csdid} bootstraps by default: 1,000
multiplier-bootstrap iterations with Rademacher multipliers, reported with
simultaneous confidence bands at {cmd:level(95)}. No option is needed to turn
this on.

{phang}
{opt wboot(bootopts)} passes suboptions to the multiplier bootstrap.
{it:bootopts} may contain {cmd:reps(}{it:#}{cmd:)} or
{cmd:biters(}{it:#}{cmd:)}, {cmd:rseed(}{it:#}{cmd:)} or
{cmd:seed(}{it:#}{cmd:)}, {cmd:cluster(}{it:clustvar}{cmd:)}, and
{cmd:wtype(rademacher)} or {cmd:wbtype(rademacher)}. The legacy shorthand
{cmd:wboot reps(}{it:#}{cmd:)} {cmd:rseed(}{it:#}{cmd:)}, with the suboptions
written at the top level, is also accepted. Multiplier distributions other
than {cmd:rademacher} exit with return code 498 rather than being silently
coerced to a distribution you did not ask for.

{pmore}
The suboptions are parsed strictly: each must be spelled in full and in lower
case, and each may appear at most once. {cmd:wboot(rep(7))},
{cmd:wboot(REPS(7))}, {cmd:wboot(frobnicate(9))} and
{cmd:wboot(reps(7) reps(9))} all exit with return code 198 and a message
listing the accepted suboptions. Earlier builds matched the contents of
{cmd:wboot()} with a pattern that silently ignored anything it did not
recognize, so a typo left inference running at the defaults without saying so.
Abbreviation is not offered because {cmd:reps()} and {cmd:rseed()} share a
prefix.

{phang}
{opt reps(#)} sets the number of bootstrap iterations. The default is
{cmd:reps(1000)}. {opt biters(#)} is a synonym. Supplying both with different
values is an error. The
replication count actually used is stored in both {cmd:e(biters)} and
{cmd:e(reps)}.

{phang}
{opt rseed(#)} sets the bootstrap seed. {it:#} must be a positive integer.
Seeding is what makes a run reproducible: the same seed reproduces the same
multiplier draws, and therefore the same bootstrap standard errors and
simultaneous critical values. {opt seed(#)} is a synonym. The seed is
recorded in {cmd:e(boot_seed)} and in {cmd:e(rseed)}, and the resulting
random-number state in {cmd:e(boot_rng_state)}. An unseeded
bootstrap leaves {cmd:e(rseed)} empty, and the header of the results table
says so, because unseeded bootstrap standard errors move by a few percent
between two otherwise identical runs.

{phang}
{opt pointwise} reports pointwise confidence intervals instead of the default
simultaneous ({it:uniform}) bands. Pointwise
intervals are correct one at a time; the default bands cover the whole family
of ATT(g,t) simultaneously and are what you want when reading a table or a
plot as a whole. {cmd:e(cband)} and {cmd:e(pointwise)} record which was used,
and {cmd:e(crit_val)} holds the critical value actually applied.

{phang}
{opt analytical}, or equivalently {cmd:vce(analytical)}, replaces the
bootstrap with analytical standard errors computed directly from the
influence function. Analytical standard errors are pointwise only; requesting
{cmd:reps()}, {cmd:biters()}, {cmd:seed()}, {cmd:rseed()}, or {cmd:wboot()}
alongside them is an error rather than a silent no-op.

{phang}
{opth cluster(varname)} clusters the influence function on {it:varname},
which must be numeric and nested within units. {cmd:vce(cluster}
{it:clustvar}{cmd:)} is a synonym; specifying both with different variables is
an error. Clustering applies to analytical and bootstrap inference alike. The
number of clusters is stored in {cmd:e(N_clusters)}.

{marker opt_reporting}{...}
{dlgtab:Reporting}

{phang}
{opt level(#)} sets the confidence level; the default is {cmd:level(95)}.
Aggregations run afterwards
inherit the estimation-time level unless they are given their own
{cmd:level()}.

{phang}
{opt agg(event)} computes the event-study (dynamic) aggregation immediately
after estimation and posts it, so that {cmd:e(b)} and {cmd:e(V)} hold event-
time coefficients rather than ATT(g,t) coefficients. {cmd:agg(dynamic)} is the
same thing. Other aggregation types are not available here; run
{helpb csdid_stats} or {helpb csdid_estat} instead, which is also the more
flexible route for event studies because it supports windows and balanced
event-time samples.

{marker opt_saving}{...}
{dlgtab:Saving}

{phang}
{opt saverif(filename)} writes a Stata dataset containing the unit-level
influence functions, one variable per (g,t) cell, together with the unit,
cohort, and weight columns and the metadata needed to aggregate later. Load it
with {cmd:csdid_stats using} {it:filename} to produce aggregations without
re-estimating. {opt replace} overwrites an existing file. {cmd:saverif()}
cannot be combined with {cmd:lean} storage, which discards the influence
functions it would need to write.

{pmore}
The destination is checked {it:before} estimation starts, as
{helpb bootstrap}'s {cmd:saving()} is: naming a file that already exists
without {cmd:replace}, or a path that cannot be written, refuses immediately
with return code 602 and leaves {cmd:e()} cleared: nothing is estimated and no
partial results are posted. Earlier builds ran the whole estimation, printed
it, and only then failed to write the file. An aggregation run later from the
saved file bands at the confidence level of the estimation that wrote it, not
the session default, unless {helpb csdid_stats}'s own {cmd:level()} is given.

{marker opt_storage}{...}
{dlgtab:Storage and diagnostics}

{pstd}
These options change how much is kept in {cmd:e()} and which internal Mata
kernels run. They exist for large jobs, benchmarking, and support. They are
not part of the econometric specification and are not needed in normal use.

{phang}
{opt storeall} forces {cmd:e(inffunc)}, {cmd:e(unit_group)}, and
{cmd:e(cluster_vec)} into {cmd:e()} even on large samples. {cmd:store_all} is
an accepted synonym.

{phang}
{opt lean} does the opposite: the large matrices are never copied into
{cmd:e()}. {opt performance(mode)} spells the same choice out, with
{it:mode} equal to {cmd:auto} (the default), {cmd:lean}, or {cmd:full}. Under
{cmd:auto}, samples of at least
{cmd:e(performance_auto_threshold)} observations, 25,000 at present, use lean
storage unless {cmd:saverif()} was requested. {cmd:performance(materialized)}
is a deprecated spelling of {cmd:performance(full)}. The resolved mode is in
{cmd:e(performance_resolved)}, and {cmd:e(large_store)} records whether the
large matrices were kept.

{phang}
{opt fast} and {opt nofast} force or forbid the optimized Mata kernels.
{cmd:e(fast_used)} and {cmd:e(compute_path)} report which surface actually
ran. Use these only to isolate a performance question or a suspected numerical
issue.

{marker opt_panel}{...}
{dlgtab:Panel structure}

{phang}
{opt bal(mode)} controls what happens when the {cmd:ivar()} panel is
unbalanced, that is, when some units are not observed in every period. The
accepted modes are:

{p2colset 9 24 26 2}{...}
{p2col:{cmd:bal(full)}}drop every unit not observed in all periods, so that a
single balanced panel is used for all comparisons. This is the default.{p_end}
{p2col:{cmd:bal(pair)}}balance each 2x2 comparison separately, keeping the
units observed in both of that comparison's periods. Every unit stays in the
sample; what varies is which units each individual comparison can use.{p_end}
{p2col:{cmd:bal(none)}}keep every unit and use the repeated-cross-section
computation with the matching standard-error accounting.{p_end}
{p2colreset}{...}

{phang2}
Whenever a mode discards observations, {cmd:csdid} reports how many units and
how many observations were dropped. Changing the estimand is acceptable;
changing it silently is not. The resolved layout is in {cmd:e(panel_mode)}.

{phang2}
{cmd:bal(full)} is the default because it is what R's reference implementation
does, and because it keeps one fixed sample behind every reported cell. If you
would rather keep every observation, say {cmd:bal(none)}.
{cmd:bal(pair)} reproduces the behaviour of Stata {cmd:csdid} Version 1.82,
which balanced each comparison separately without saying so. Use it to
reproduce a result computed with that version. {cmd:e(panel_mode)} reports
{cmd:pair-balanced}.

{phang}
{opt rcs} declares that the data are repeated cross sections rather than a
panel. It is the counterpart of the reference implementation's
{cmd:panel = FALSE}.

{phang2}
Without it, {cmd:csdid} infers the structure from {cmd:ivar()}: supplied means
panel, omitted means repeated cross sections. That inference is usually right,
but it forces a false choice on anyone whose repeated cross sections carry an
identifier anyway -- a survey respondent number, a county code -- because the
only way to declare the data as cross sections was to withhold a variable that
genuinely exists.

{phang2}
With {cmd:rcs} the declaration is explicit, and {cmd:ivar()} may be supplied
alongside it. The identifier is then checked and used to exclude observations
where it is missing, but it does not enter estimation: each observation is
treated as its own unit. {cmd:e(idvar)} is therefore empty and
{cmd:e(panel_mode)} is {cmd:repeated-cross-section}. To put the identifier back
into the standard errors, use {cmd:cluster()}.

{phang2}
Repeated cross sections have nothing to balance, so {cmd:rcs} implies
{cmd:bal(none)}. Combining it with {cmd:bal(full)} is an
error, as is combining it with {cmd:fix_weights(base)} or
{cmd:fix_weights(first)}, which require following the same unit over time.

{marker opt_legacy}{...}
{dlgtab:Legacy compatibility}

{pstd}
These options exist so that do-files written for Stata {cmd:csdid} Version 1.82 keep
running. All of them announce themselves. None of them changes a default.
See {it:{help csdid##remarks_legacy:Migrating from Stata csdid Version 1.82}}.

{phang}
{opt asinr} and {opt never} are accepted as no-ops with a message.
{cmd:asinr} used to switch on an alternative not-yet-treated pre-treatment
selection, which is now governed by {cmd:notyet}; {cmd:never} used to request the
never-treated comparison group, which is now the default.

{phang}
{opt long} and {opt long2} are deprecated aliases for the legacy event-study
layout. When {cmd:base_period()} is not otherwise given, they select
{cmd:base_period(universal)}. New code should say
{cmd:base_period(universal)}.

{phang}
{opt allowunbalanced} and {cmd:allow_unbalanced} are deprecated names for
{cmd:bal(none)}; {opt balanceall} is a deprecated name for {cmd:bal(full)};
{opt balancepair} is a deprecated name for {cmd:bal(pair)}, which is not
implemented in this release and is refused. Each is accepted
with a note naming its replacement. Giving one of them together with a
{cmd:bal()} that means something different is an error rather than a silent
resolution.

{phang}
Inside {cmd:bal()} itself, the values {cmd:unbal}, {cmd:unbalanced} and
{cmd:allow_unbalanced} are deprecated spellings of {cmd:none}, and {cmd:all}
is a deprecated spelling of {cmd:full}. See
{it:{help csdid##opt_panel:Panel structure}} for the current vocabulary.

{phang}
{cmd:dryrun} was an internal option in the legacy package. It is rejected with
return code 198 rather than quietly accepted.


{marker remarks}{...}
{title:Remarks}

{pstd}
Remarks are presented under the following headings:

{p2colset 8 40 40 2}{...}
{p2col:{help csdid##remarks_setup:The estimand}}{p_end}
{p2col:{help csdid##remarks_assumptions:Identifying assumptions}}{p_end}
{p2col:{help csdid##remarks_data:What csdid requires of the data}}{p_end}
{p2col:{help csdid##remarks_control:Choosing the comparison group}}{p_end}
{p2col:{help csdid##remarks_base:Choosing the base period}}{p_end}
{p2col:{help csdid##remarks_agg:Why aggregation is necessary}}{p_end}
{p2col:{help csdid##remarks_inference:Inference}}{p_end}
{p2col:{help csdid##remarks_post:Postestimation}}{p_end}
{p2col:{help csdid##remarks_behavior:Notes on specific behavior}}{p_end}
{p2col:{help csdid##remarks_legacy:Migrating from Stata csdid Version 1.82}}{p_end}
{p2colreset}{...}

{marker remarks_setup}{...}
{title:The estimand}

{pstd}
Units are indexed by {it:i} and periods by {it:t}. Treatment is absorbing: once
a unit is treated it stays treated. Let {it:G_i} be the period in which unit
{it:i} is first treated, the variable supplied in {cmd:gvar()}, with
{it:G_i = 0} for never-treated units. Cohorts, or {it:groups}, are the sets of
units sharing a value of {it:G}. Let {it:Y_it(0)} be the untreated potential
outcome and {it:Y_it(g)} the outcome if first treated in period {it:g}.

{pstd}
The building block is the group-time average treatment effect

{p 12 12 2}
ATT(g,t) = E[ Y_t(g) - Y_t(0) | G = g ],

{pstd}
the average effect, in period {it:t}, of having been first treated in period
{it:g}, among the units actually first treated then. It is defined
period-by-period and cohort-by-cohort and makes no homogeneity assumption
across cohorts or across time since treatment. That is the point: a
two-way-fixed-effects regression with a single treatment dummy recovers a
weighted average of these effects with weights that can be negative when
effects vary, whereas ATT(g,t) is a well-defined causal parameter for every
cell. {cmd:csdid} estimates all of them and leaves the choice of summary to
you.

{pstd}
Cells with {it:t >= g} are post-treatment effects. Cells with {it:t < g} are
pre-treatment: under the identifying assumptions they estimate zero, so they
are the placebo evidence on which the design rests, not causal effects.

{marker remarks_assumptions}{...}
{title:Identifying assumptions}

{pstd}
{bf:1. Staggered adoption (irreversibility).} Treatment is absorbing:
{it:D_it = 1} implies {it:D_i,t+1 = 1}. Units do not switch back and forth.
This is imposed by construction through {cmd:gvar()}, which records a single
first-treatment period per unit. Designs with treatment reversal are outside
what {cmd:csdid} identifies.

{pstd}
{bf:2. No anticipation.} For each cohort {it:g}, outcomes in periods before
treatment equal untreated potential outcomes:
{it:E[Y_t(g) | G = g] = E[Y_t(0) | G = g]} for {it:t < g}. If units respond in
advance, for example because the policy was announced early, use
{cmd:anticipation(#)} to require the assumption only from {it:g - #} onward.
That is not free: it costs you the {it:#} periods immediately before treatment
as usable base periods and as placebo tests.

{pstd}
{bf:3. Parallel trends, conditional on covariates.} For every cohort {it:g}
and the comparison group, and conditional on the covariates {it:X} supplied as
{it:indepvars},

{p 12 12 2}
E[ Y_t(0) - Y_t-1(0) | X, G = g ] = E[ Y_t(0) - Y_t-1(0) | X, comparison ].

{pstd}
With no covariates this is the familiar unconditional parallel-trends
assumption. With covariates it is weaker in one direction and stronger in
another: it permits trends to differ across observably different units, but it
requires the covariate model to capture how. The covariates enter through the
outcome regression, the propensity score, or both, depending on
{cmd:method()}. The pre-treatment ATT(g,t) cells are the sample evidence on
this assumption, and {cmd:csdid} reports a joint test of them; see
{help csdid##remarks_pretest:The parallel-trends pre-test}.

{pstd}
{bf:4. Overlap.} Conditional on {it:X}, comparison units must exist for the
treated: the propensity score of being in cohort {it:g} rather than in the
comparison group must be bounded away from one. Without it the reweighting is
driven by a handful of observations with extreme weights.
{cmd:pscoretrim()} enforces a hard bound as a safeguard. Frequent trimming is
a symptom, not a fix; inspect the covariate distributions instead.

{pstd}
{bf:5. Sampling.} Units are independently and identically drawn from the
population of interest ({cmd:cluster()} relaxes this to independence across
clusters), and the sample is either a panel observed with the same identifier
over time or repeated cross sections drawn from the same population.

{marker remarks_data}{...}
{title:What csdid requires of the data}

{pstd}
{cmd:csdid} checks the shape of the estimation sample before it estimates
anything, and refuses with a message that names the variable and the value at
fault rather than failing later inside a matrix operation. Every check below is
run whether or not output is suppressed, so {cmd:quietly csdid ...} stops in
exactly the same cases, and a refusal leaves {cmd:e()} cleared rather than
posting a half-finished estimation.

{pstd}
{bf:Panel structure.} With {cmd:ivar()} supplied, each unit may appear at most
once per period, {cmd:gvar()} must be constant within a unit (treatment timing
is irreversible), and {cmd:cluster()}, when given, must also be constant within
a unit. Each violation is a separate {cmd:r(459)} refusal. The sample must
contain at least two distinct units: one unit cannot supply both sides of a
two-by-two comparison, and that case now refuses by name instead of failing
with a conformability error from the estimation kernel.

{pstd}
{bf:Covariates on the panel path.} A unit whose covariates are missing in any
period is dropped whole, because the estimator differences that unit over time.
A covariate that is missing for {it:every} observation of one period therefore
removes the entire sample. {cmd:csdid} detects that shape and refuses with
{cmd:r(459)}, naming the covariate and the period, rather than quietly
dropping that period and estimating on what remains. The remedies the message
names are to exclude the period (for
example {cmd:if} {it:timevar} {cmd:!=} {it:t}), to supply the covariate for it,
or to drop the covariate.

{pstd}
{bf:Period and cohort codes.} Values so large that the ATT(g,t) coefficient
names would exceed Stata's 32-character limit are refused with {cmd:r(198)}
before any estimation; see {cmd:time()} under
{help csdid##opt_main:Options} for the check and the remedy.

{pstd}
{bf:Estimable cohorts.} If no treated cohort has both a usable base period and
a comparison group -- for instance every unit is treated in the same period, or
{cmd:anticipation()} consumes every base period -- estimation stops with
{cmd:r(459)} and the diagnostic {cmd:No valid groups.}

{pstd}
{bf:When every cell fails.} If all of the two-by-two comparisons fail, so that
every ATT(g,t) is missing, {cmd:csdid} does not stop. It prints a warning
naming
the usual causes -- a collinear or constant covariate, a {cmd:pscoretrim()}
that empties every comparison group, comparison groups with too few units, an
outcome with no variation -- posts {bf:no} {cmd:e(b)} and {cmd:e(V)}, and
leaves the all-missing table in {cmd:e(attgt)}. Aggregation and hypothesis
testing then have nothing to work with and say so. Do not assume {cmd:e(b)}
exists after a run that returned zero.

{marker remarks_control}{...}
{title:Choosing the comparison group}

{pstd}
{bf:Never-treated} (the default) uses only units with {cmd:gvar() == 0}. It
is the cleanest comparison: those units are never affected by the treatment,
so parallel trends is required only against a group with no treatment
dynamics. Its cost is statistical: if few units are never treated, standard
errors are large, and if none exist, the group is empty. When there are no
never-treated units, {cmd:csdid} falls back to using the latest treated cohort
and reports that it did so.

{pstd}
{bf:Not-yet-treated} ({cmd:notyet}) additionally uses units that will be
treated later but have not been treated as of the period being compared. This
buys precision, sometimes a great deal of it, and it is often the only option
when treatment eventually reaches everyone. It requires parallel trends to
hold against those future-treated units as well, and it leans harder on no
anticipation, since a unit close to its own treatment date must still be
behaving as an untreated unit.

{pstd}
Comparing the two is a useful robustness exercise: estimate with each and look
at whether the post-treatment path moves.

{marker remarks_groupsize}{...}
{pstd}
{bf:When a group is too small.} Before estimating, {cmd:csdid} measures the
size of every cohort as the number of observations in the cohort divided by
the number of time periods, that is, the average number of units per period.
Any cohort averaging fewer than {it:k} + 5 units per
period, where {it:k} is the number of covariates, triggers

{pmore}
{cmd:warning: Some groups in your dataset have very few observations...}

{pstd}
and if the {bf:never-treated} group is one of them and the never-treated
comparison group is in use, estimation stops with {cmd:r(459)} and

{pmore}
{cmd:The never-treated group is too small to serve as a reliable control.}

{pstd}
The remedy the message names is {cmd:notyet}, which does not depend on the size
of the never-treated group; you can also add never-treated units or use fewer
covariates. The refusal is raised whether or not output is suppressed, so
{cmd:quietly csdid ...} stops as well.

{pstd}
On a balanced panel this measure equals the number of distinct units. On an
unbalanced panel it is strictly smaller, so the guard is stricter there.
Earlier builds of this package counted distinct units and therefore estimated
in some cases that are now refused; see
{help csdid##remarks_legacy:Migrating from Stata csdid Version 1.82}.

{marker remarks_base}{...}
{title:Choosing the base period}

{pstd}
Every ATT(g,t) is a difference in differences between period {it:t} and a base
period. The default, {cmd:base_period(varying)}, uses {it:g - 1} for
post-treatment cells and {it:t - 1} for pre-treatment cells; each
pre-treatment estimate is then a one-period placebo, and the estimates are
comparable in variance across event times.
{cmd:base_period(universal)} uses {it:g - 1} throughout, so every
pre-treatment estimate is a long difference from the same reference period.
Universal base periods make an event-study plot read like a conventional one,
with a normalized reference period, but the pre-treatment coefficients are
then serially dependent by construction and their magnitudes grow mechanically
with distance from the reference period.

{pstd}
Either way, the post-treatment ATT(g,t) estimates are the same. With
{cmd:anticipation(#)} the base period moves from {it:g - 1} to
{it:g - 1 - #}.

{pstd}
Cells whose event time is {it:-1} are the reference cells. They are reported
in {cmd:e(attgt)}, where under a universal base period they carry an estimate
of exactly zero and a missing standard error, but they are excluded from
{cmd:e(b)} and {cmd:e(V)}.

{marker remarks_agg}{...}
{title:Why aggregation is necessary}

{pstd}
A staggered design with {it:G} cohorts and {it:T} periods produces on the order
of {it:G x T} group-time effects. The mpdta example below has 12 of them for
three cohorts and five periods; realistic applications have hundreds. That
table is the right object to estimate, because it is what the assumptions
identify without further restrictions, but it is not a reportable summary and
it is not what most questions ask about.

{pstd}
Aggregation reduces ATT(g,t) to interpretable parameters by taking weighted
averages with weights chosen to answer a specific question, and by carrying
the influence functions through so that the standard errors are right. Use
{helpb csdid_stats} or {helpb csdid_estat}:

{p2colset 8 26 28 2}{...}
{p2col:{cmd:simple}}a single overall ATT, weighting each post-treatment cell
by cohort size{p_end}
{p2col:{cmd:event} / {cmd:dynamic}}average effect by event time (periods since
treatment): the event study{p_end}
{p2col:{cmd:group}}average post-treatment effect for each cohort{p_end}
{p2col:{cmd:calendar}}average effect in each calendar period{p_end}
{p2colreset}{...}

{pstd}
The event-study aggregation deserves a warning about composition: at long
event times only the early-treated cohorts contribute, so a trend across event
time can be composition rather than dynamics. {cmd:csdid_stats}'s
{cmd:balance()} option restricts the aggregation to cohorts observed for a
common number of post-treatment periods, and is the standard way to separate
the two.

{pstd}
{cmd:csdid, agg(event)} runs the event-study aggregation in one step. Any
other aggregation, and any windowing or balancing, goes through
{cmd:csdid_stats}.

{marker remarks_inference}{...}
{title:Inference}

{pstd}
All standard errors are built from the estimator's influence function: each
ATT(g,t) is asymptotically linear in a unit-level score, and those scores are
what {cmd:e(inffunc)} holds and what {cmd:saverif()} writes out. Aggregations
combine the same scores, which is why an aggregated standard error is not a
naive average of ATT(g,t) standard errors.

{pstd}
The default is the multiplier bootstrap: draw Rademacher multipliers, one per
unit (or per cluster) per iteration, recombine the influence functions, and
take the empirical distribution of the resulting estimates. It is fast,
because no re-estimation happens, and it supports simultaneous confidence
bands: a single critical value, reported in {cmd:e(crit_val)}, is chosen so
that the bands cover all ATT(g,t) at once with the nominal probability. That
critical value exceeds the pointwise 1.96 (at 95%) and by how much depends on
the correlation structure of the estimates.

{pstd}
Report the simultaneous bands when you display the whole table or an event
study, which is nearly always. Use {cmd:pointwise} only when a single,
pre-specified cell is the object of interest.

{pstd}
{cmd:analytical} skips the bootstrap. It is faster and deterministic, and
appropriate for a single pre-specified comparison or for a first look at a
large dataset, but it delivers pointwise standard errors only.

{pstd}
{cmd:cluster()} is required whenever treatment is assigned, or shocks arrive,
at a level coarser than the unit: a county panel with state-level policy needs
{cmd:cluster(state)}. Clustering enters the influence function directly, and
the bootstrap then draws one multiplier per cluster.

{pstd}
{bf:What the header reports.} The line printed above the ATT(g,t) table states
how the standard errors were produced: the bootstrap and its replication count
and seed, or {cmd:analytical}; the clustering variable and the number of
clusters when {cmd:cluster()} is used; and the level and kind of the reported
bands. An unseeded bootstrap is labelled {cmd:no seed set (not reproducible)},
which is the honest description: because the multipliers are redrawn, two
identical unseeded commands give standard errors that differ by a few percent.
Seed with {cmd:rseed()} whenever a number will be reported. The same facts are
stored in {cmd:e(vce)}, {cmd:e(reps)}, {cmd:e(rseed)}, and {cmd:e(cband)}.

{marker remarks_pretest}{...}
{pstd}
{bf:The parallel-trends pre-test.} When pre-treatment ATT(g,t) cells exist,
{cmd:csdid} computes a Wald test of the joint hypothesis that all of them are
zero and prints

{pmore}
{cmd:P-value for pre-test of parallel trends assumption:  0.16812}

{pstd}
beneath the table, rounded to five decimals. The statistic, its degrees of
freedom, and the p-value are stored in
{cmd:e(wald_stat)}, {cmd:e(wald_df)}, and {cmd:e(wald_pvalue)}, and those three
results are posted only when the test was computable, so
{cmd:confirm scalar e(wald_pvalue)} is the test for "a p-value was printed
here". The test is always built from the analytical influence-function
covariance matrix, so it does not depend on whether the bootstrap ran
and does not change with {cmd:reps()} or {cmd:rseed()}.

{pstd}
When the test cannot be formed, nothing is stored and a note explains which
case occurred: no pre-treatment cells exist at all; pre-treatment cells exist
but all of them have a missing or numerically zero variance; the pre-treatment
estimates contain missing values; or the pre-treatment covariance matrix is
singular.

{pstd}
A large p-value is weak evidence, not a certificate: the test has low power in
exactly the samples where parallel trends is most fragile, and it looks only at
the periods in the sample. Read it with the pre-treatment cells themselves and,
when the design turns on the assumption, with a sensitivity analysis.

{pstd}
The estimation engine is pure Mata. The package installs a precompiled Mata
library, {cmd:lcsdid.mlib}, which is portable bytecode rather than a
platform-specific binary; it holds exactly the code in {cmd:csdid.mata} and
only removes the cost of compiling that source on the first call of each
session. When a compiled bootstrap kernel is present in the ado path it is
used only for explicitly seeded Rademacher draws, and the package's
certification tests require it to be bit-identical to the Mata path, including
the full random-number state.
{cmd:e(bootstrap_accelerator)} and {cmd:e(bootstrap_accelerator_status)}
report which path ran. These are diagnostics; they never change results.

{marker remarks_post}{...}
{title:Postestimation}

{pstd}
{cmd:e(b)} and {cmd:e(V)} hold the ATT(g,t) estimates that are not reference
cells. Each coefficient is named by pasting the cohort, three underscores, the
period, one underscore, and the base period: ATT(2004, 2005) with base period
2003 is {cmd:g2004___2005_2003}. {cmd:test} and {cmd:lincom} therefore work on
individual cells and on linear combinations of them.

{pstd}
{cmd:predict} and {cmd:margins} are {bf:not} supported after {cmd:csdid}.
There is no linear index to predict from and no covariate profile to average
over: {cmd:e(b)} is a vector of treatment effects, not regression
coefficients. Both refuse rather than returning a number. {cmd:csdid} also does
not set {cmd:e(sample)}; use the same {cmd:if} restriction to reconstruct the
estimation sample.

{pstd}
The refusals are the conventional Stata ones. {cmd:csdid} sets
{cmd:e(predict)} to {cmd:csdid_p}, a program shipped with the package whose
only job is to explain why {cmd:predict} cannot work and exit with return code
198; without it, {cmd:predict} fell through to Stata's default scoring code and
failed with {cmd:r(111)} naming an internal coefficient, which reads like a
missing variable in your own data. {cmd:margins} is blocked by
{cmd:e(marginsnotok)}, which is set to {cmd:_ALL} and is preserved by
{helpb csdid_estat} and {helpb csdid_stats}, including when they replace
{cmd:e(b)} with an aggregation through {cmd:post}, so {cmd:margins} refuses
with {cmd:r(322)} at every stage of a session rather than producing a table of
fabricated numbers after an aggregation.

{pstd}
{cmd:csdid version} may be run at any time: it prints the version and leaves
{cmd:e()} untouched, so estimation results and every postestimation command
survive it.

{pstd}
See {helpb csdid_postestimation:csdid postestimation} for the full list of
what is available.

{marker remarks_behavior}{...}
{title:Notes on specific behavior}

{pstd}
A few choices are worth stating explicitly, because they are the places where
{cmd:csdid} refuses rather than guessing, or restricts an option to the form
that is defensible.

{phang2}
o {bf:Unbalanced panels.} By default an unbalanced {cmd:ivar()} panel is
balanced by dropping the units not observed in every period, and {cmd:csdid}
reports how many units and observations that removed. Dropping them changes the
estimand, so it is never done silently. {cmd:bal(none)} keeps every unit and
estimates with the repeated-cross-section computation and the standard-error
accounting that goes with it. See
{it:{help csdid##opt_panel:Panel structure}}.{p_end}

{phang2}
o {bf:Multiplier distribution.} The bootstrap draws Rademacher multipliers.
{cmd:wtype(mammen)}, {cmd:wtype(normal)}, and {cmd:wtype(gaussian)} exit with
an error rather than being silently coerced to something else.{p_end}

{phang2}
o {bf:Reference cells in e(b).} Cells at event time {it:-1} are reported in
{cmd:e(attgt)} but excluded from {cmd:e(b)} and {cmd:e(V)}, so that the posted
coefficients are estimable and the covariance matrix is not singular by
construction.{p_end}

{phang2}
o {bf:Immediate aggregation.} {cmd:agg()} accepts only {cmd:event} and
{cmd:dynamic}. The simple, group, and calendar aggregations are computed by
{helpb csdid_stats}.{p_end}

{phang2}
o {bf:Covariate missing for a whole period.} {cmd:csdid} refuses and names the
covariate and the period rather than quietly dropping that period, so that any
change in the estimation sample is yours to make. See
{help csdid##remarks_data:What csdid requires of the data}.{p_end}

{phang2}
o {bf:Negative period or cohort codes.} {cmd:csdid} refuses them, because
{cmd:gvar() == 0} is reserved for never-treated units. Shift the axis so that
it is nonnegative; a monotone relabelling of the periods leaves the estimates
unchanged.{p_end}

{phang2}
o {bf:Very large period or cohort codes.} {cmd:csdid} refuses when they would
push the ATT(g,t) coefficient names past Stata's 32-character limit, and names
the rescaling that fixes it.{p_end}

{phang2}
o {bf:fast and nofast.} These select internal Mata kernels and exist for
diagnostics. Neither changes the estimates.{p_end}


{marker remarks_legacy}{...}
{title:Migrating from Stata csdid Version 1.82}

{pstd}
This is a rewrite, not a patch of the legacy package, and its defaults differ
from legacy Stata. Two changes will move numbers in existing do-files:

{phang2}
o {bf:Inference is bootstrapped by default}, with simultaneous bands and 1,000
iterations. Add {cmd:analytical} to get analytical standard errors.{p_end}

{phang2}
o {bf:Unbalanced panels are balanced, and say so.} Version 1.82 dropped, without
comment, the units missing from either period of each 2x2 comparison. The
default is now {cmd:bal(full)}: units not observed in every period are dropped
once, for all comparisons, and {cmd:csdid} reports how many. To keep every
observation instead, use {cmd:bal(none)}; to reproduce Version 1.82's per-
comparison balancing, use {cmd:bal(pair)}.{p_end}

{pstd}
One further change does not move any number, but can stop a do-file that
previously ran:

{phang2}
o {bf:Group size is measured as observations divided by the number of
periods}, rather than as distinct units. On unbalanced panels this is stricter,
so the never-treated-too-small refusal now fires in cases that earlier builds
of this package estimated. Use {cmd:notyet}, which is the remedy the message
recommends. See
{help csdid##remarks_groupsize:When a group is too small} above.{p_end}

{pstd}
Legacy option spellings that still work, each with a message:
{cmd:method(dripw)}, {cmd:method(stdipw)}, {cmd:asinr}, {cmd:never},
{cmd:long}, {cmd:long2}, {cmd:allowunbalanced}, {cmd:balanceall},
{cmd:balancepair},
{cmd:performance(materialized)}, and the top-level bootstrap shorthand.
{cmd:method(drimp)}, {cmd:method(aipw)}, and {cmd:dryrun} are rejected. Each is
described under {help csdid##opt_legacy:Legacy compatibility} above; the
option-by-option migration guide is online at
{browse "https://github.com/pedrohcgs/csdid-stata":github.com/pedrohcgs/csdid-stata}.


{marker examples}{...}
{title:Examples}

{pstd}
The examples use the county teen-employment panel of Callaway and Sant'Anna
(2021). Loading it requires an internet connection.
{cmd:lemp} is log county-level teen employment, {cmd:lpop} is log county
population, {cmd:countyreal} is the county identifier, {cmd:year} is the
period, and {cmd:first_treat} is the year the county's state raised its
minimum wage, or {cmd:0} for never-treated counties.

{pstd}Setup{p_end}
{phang2}{cmd:. use "http://fmwww.bc.edu/repec/bocode/m/mpdta.dta", clear}{p_end}

{hline}
{pstd}Group-time average treatment effects, default settings throughout:
doubly robust, never-treated controls, varying base period, 1,000 bootstrap
iterations with simultaneous bands. Seed the bootstrap to make the run
reproducible.{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)}{p_end}

{hline}
{pstd}Same, conditioning on log population, so parallel trends is only
required among counties with similar population{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)}{p_end}

{hline}
{pstd}The legacy shorthand writes the bootstrap suboptions at the top level
rather than inside {cmd:wboot()}. Both spellings are accepted and give the
same estimates; the nested form is preferred in new code.{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot reps(1000) seed(12345)}{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(1000) seed(12345))}{p_end}

{hline}
{pstd}The event study, and the other three aggregations{p_end}
{phang2}{cmd:. estat event, window(-4 4)}{p_end}
{phang2}{cmd:. csdid_stats simple}{p_end}
{phang2}{cmd:. csdid_stats group}{p_end}
{phang2}{cmd:. csdid_stats calendar}{p_end}

{hline}
{pstd}Estimate and post the event study in one step{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806) agg(event)}{p_end}

{hline}
{pstd}Not-yet-treated comparison group, which uses the 2006 and 2007 cohorts
as controls for the 2004 cohort while they are still untreated{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) notyet rseed(20200806)}{p_end}

{hline}
{pstd}Analytical standard errors, clustered at the county level{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) analytical cluster(countyreal)}{p_end}

{hline}
{pstd}Universal base period, so the event study reads against a single
normalized reference period{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) base_period(universal) rseed(20200806)}{p_end}
{phang2}{cmd:. estat event, window(-4 4)}{p_end}

{hline}
{pstd}Allow one period of anticipation; cohorts left without a base period are
dropped{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) anticipation(1) rseed(20200806)}{p_end}

{hline}
{pstd}Outcome regression and IPW instead of the doubly robust estimator{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) method(reg) analytical}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) method(ipw) analytical}{p_end}

{hline}
{pstd}Treat the same data as repeated cross sections by omitting
{cmd:ivar()}{p_end}
{phang2}{cmd:. csdid lemp lpop, time(year) gvar(first_treat) method(ipw) rseed(20200806)}{p_end}

{hline}
{pstd}Pointwise intervals, a 90% level, and 999 iterations{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806) reps(999) pointwise level(90)}{p_end}

{hline}
{pstd}Sampling weights, held fixed at each county's base period{p_end}
{phang2}{cmd:. generate double wt = exp(lpop)}{p_end}
{phang2}{cmd:. csdid lemp [iw=wt], ivar(countyreal) time(year) gvar(first_treat) fix_weights(base) analytical}{p_end}

{hline}
{pstd}Save the influence functions and aggregate later without
re-estimating{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical saverif("mpdta_rif.dta") replace}{p_end}
{phang2}{cmd:. csdid_stats using "mpdta_rif.dta", type(dynamic) window(-4 4)}{p_end}

{hline}
{pstd}Export tables and plot data{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) rseed(20200806)}{p_end}
{phang2}{cmd:. estat tidy, saving("mpdta_attgt.dta") replace}{p_end}
{phang2}{cmd:. estat glance, saving("mpdta_glance.dta") replace}{p_end}
{phang2}{cmd:. csdid_plot, saving("mpdta_plotdata.dta") replace}{p_end}

{hline}
{pstd}Test the ATT(g,t) coefficients directly{p_end}
{phang2}{cmd:. csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical}{p_end}
{phang2}{cmd:. lincom g2004___2007_2003 - g2004___2004_2003}{p_end}
{hline}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:csdid} stores the following in {cmd:e()}. Results marked
{it:(conditional)} are present only in the circumstances described. Results
marked {it:(diagnostic)} are for profiling and support: they are not a stable
econometric API and must not be used to select an estimator or interpret an
estimate.

{synoptset 32 tabbed}{...}
{p2col 5 32 35 2: Scalars}{p_end}
{synopt:{cmd:e(N)}}number of observations used{p_end}
{synopt:{cmd:e(N_units)}}number of units (panel) or observations (repeated
cross sections) entering the influence function{p_end}
{synopt:{cmd:e(N_attgt)}}number of ATT(g,t) cells, that is rows of
{cmd:e(attgt)}{p_end}
{synopt:{cmd:e(N_groups)}}number of treated cohorts{p_end}
{synopt:{cmd:e(N_time)}}number of time periods{p_end}
{synopt:{cmd:e(N_clusters)}}number of clusters; present only with
{cmd:cluster()}{p_end}
{synopt:{cmd:e(time_first)}}first time period in the estimation sample{p_end}
{synopt:{cmd:e(level)}}confidence level{p_end}
{synopt:{cmd:e(crit_val)}}critical value applied to the reported intervals:
the simultaneous value under the default, the normal quantile under
{cmd:pointwise} or {cmd:analytical}{p_end}
{synopt:{cmd:e(point_crit_val)}}pointwise normal critical value{p_end}
{synopt:{cmd:e(anticipation)}}value of {cmd:anticipation()}{p_end}
{synopt:{cmd:e(pscoretrim)}}value of {cmd:pscoretrim()}{p_end}
{synopt:{cmd:e(bstrap)}}1 if the multiplier bootstrap was used, 0 if
analytical{p_end}
{synopt:{cmd:e(biters)}}number of bootstrap iterations (0 when analytical){p_end}
{synopt:{cmd:e(reps)}}number of bootstrap iterations, under the name Stata's
own {helpb bootstrap} uses {it:(conditional: bootstrap)}{p_end}
{synopt:{cmd:e(cband)}}1 if simultaneous confidence bands were computed{p_end}
{synopt:{cmd:e(pointwise)}}1 if pointwise intervals were requested{p_end}
{synopt:{cmd:e(wald_stat)}}chi-squared statistic of the parallel-trends
pre-test {it:(conditional: pre-test computable)}{p_end}
{synopt:{cmd:e(wald_df)}}its degrees of freedom, the number of pre-treatment
cells tested {it:(conditional: pre-test computable)}{p_end}
{synopt:{cmd:e(wald_pvalue)}}its p-value, rounded to five decimals
{it:(conditional: pre-test computable)}{p_end}
{synopt:{cmd:e(allow_unbalanced)}}1 if the unbalanced-panel path was used{p_end}
{synopt:{cmd:e(store_all)}}1 if {cmd:storeall} was requested{p_end}
{synopt:{cmd:e(lean)}}1 if lean storage was resolved{p_end}
{synopt:{cmd:e(large_store)}}1 if the large matrices were copied into
{cmd:e()}{p_end}
{synopt:{cmd:e(performance_auto_threshold)}}sample size at which {cmd:auto}
storage switches to lean{p_end}
{synopt:{cmd:e(fast_requested)}}1 if {cmd:fast} was typed {it:(diagnostic)}{p_end}
{synopt:{cmd:e(fast_auto)}}1 if the kernel choice was automatic
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(fast_allowed)}}1 unless {cmd:nofast} was typed
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(fast_used)}}1 if the optimized kernels were permitted
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(mata_cache)}}1 if influence functions were left in the Mata
cache {it:(diagnostic)}{p_end}
{synopt:{cmd:e(mata_cache_token)}}token identifying that cache
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(bootstrap_accelerator_rc)}}return code from the compiled
bootstrap kernel, 0 if none {it:(conditional: bootstrap; diagnostic)}{p_end}
{synopt:{cmd:e(bootstrap_accelerator_seconds)}}seconds spent drawing
multipliers {it:(conditional: bootstrap; diagnostic)}{p_end}

{p2col 5 32 35 2: Macros}{p_end}
{synopt:{cmd:e(cmd)}}{cmd:csdid}{p_end}
{synopt:{cmd:e(cmdline)}}command as typed{p_end}
{synopt:{cmd:e(version)}}package version{p_end}
{synopt:{cmd:e(estat_cmd)}}{cmd:csdid_estat}{p_end}
{synopt:{cmd:e(properties)}}{cmd:b V}{p_end}
{synopt:{cmd:e(marginsnotok)}}{cmd:_ALL}; this is what makes {cmd:margins}
refuse after {cmd:csdid}{p_end}
{synopt:{cmd:e(predict)}}{cmd:csdid_p}, the program that makes {cmd:predict}
refuse by name{p_end}
{synopt:{cmd:e(depvar)}}name of the outcome variable, for {cmd:estout},
{cmd:etable}, and {cmd:estimates table}{p_end}
{synopt:{cmd:e(vce)}}{cmd:bootstrap}, {cmd:cluster}, or {cmd:analytical};
{cmd:bootstrap} is reported when the bootstrap ran, whether or not
{cmd:cluster()} was used{p_end}
{synopt:{cmd:e(vcetype)}}title used for the standard-error column:
{cmd:Bootstrap}, {cmd:Robust}, or {cmd:Analytical}{p_end}
{synopt:{cmd:e(rseed)}}bootstrap seed as typed, empty when the bootstrap was
unseeded {it:(conditional: bootstrap)}{p_end}
{synopt:{cmd:e(yname)}}name of the outcome variable{p_end}
{synopt:{cmd:e(timevar)}}name of the {cmd:time()} variable{p_end}
{synopt:{cmd:e(gvar)}}name of the {cmd:gvar()} variable{p_end}
{synopt:{cmd:e(idvar)}}name of the {cmd:ivar()} variable, empty for repeated
cross sections{p_end}
{synopt:{cmd:e(clustervar)}}name of the {cmd:cluster()} variable, empty if
none{p_end}
{synopt:{cmd:e(weightvar)}}internal weight variable, empty if unweighted{p_end}
{synopt:{cmd:e(panel_mode)}}{cmd:panel}, {cmd:allow_unbalanced}, or
{cmd:repeated-cross-section}{p_end}
{synopt:{cmd:e(control_group)}}{cmd:nevertreated} or {cmd:notyettreated}{p_end}
{synopt:{cmd:e(method)}}resolved estimator: {cmd:dr}, {cmd:reg}, or
{cmd:ipw}{p_end}
{synopt:{cmd:e(method_requested)}}{cmd:method()} exactly as typed{p_end}
{synopt:{cmd:e(base_period)}}{cmd:varying} or {cmd:universal}{p_end}
{synopt:{cmd:e(fix_weights)}}{cmd:varying}, {cmd:base_period}, or
{cmd:first_period}; empty if not set{p_end}
{synopt:{cmd:e(boot_dist)}}multiplier distribution used: {cmd:rademacher}
{it:(conditional: bootstrap)}{p_end}
{synopt:{cmd:e(boot_dist_requested)}}multiplier distribution as typed
{it:(conditional: bootstrap)}{p_end}
{synopt:{cmd:e(boot_seed)}}bootstrap seed
{it:(conditional: seeded bootstrap)}{p_end}
{synopt:{cmd:e(rif_file)}}file written by {cmd:saverif()}
{it:(conditional)}{p_end}
{synopt:{cmd:e(compute_path)}}resolved computation surface
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(fast_mode)}}{cmd:auto}, {cmd:on}, or {cmd:off}
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(performance_mode)}}storage mode requested
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(performance_resolved)}}storage mode used
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(bootstrap_accelerator)}}{cmd:mata}, {cmd:plugin}, or
{cmd:none} {it:(diagnostic)}{p_end}
{synopt:{cmd:e(bootstrap_accelerator_status)}}why that path was taken
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(bootstrap_accelerator_file)}}compiled kernel loaded, if any
{it:(diagnostic)}{p_end}

{p2col 5 32 35 2: Matrices}{p_end}
{synopt:{cmd:e(b)}}posted ATT(g,t) coefficient vector, excluding event-time
{cmd:-1} cells and cells with a missing estimate; absent when every cell is
missing, in which case a warning says so{p_end}
{synopt:{cmd:e(V)}}covariance matrix of {cmd:e(b)}{p_end}
{synopt:{cmd:e(attgt)}}the full ATT(g,t) table, one row per cell, with columns
{cmd:group}, {cmd:time}, {cmd:event_time}, {cmd:att}, {cmd:se},
{cmd:n_treat_t}, {cmd:n_treat_pre}, {cmd:n_control_t}, and
{cmd:n_control_pre}{p_end}
{synopt:{cmd:e(group_prob)}}one row per cohort, with columns {cmd:group},
{cmd:prob} (the cohort's population share) and {cmd:n_units}{p_end}
{synopt:{cmd:e(inffunc)}}unit-by-cell influence functions
{it:(conditional: full storage)}{p_end}
{synopt:{cmd:e(unit_group)}}one row per unit, with columns {cmd:id},
{cmd:group}, {cmd:weight}, and, on unbalanced panels, an internal
{cmd:first_period} column {it:(conditional: full storage)}{p_end}
{synopt:{cmd:e(cluster_vec)}}cluster identifier per unit; present only with
{cmd:cluster()} and full storage{p_end}
{synopt:{cmd:e(boot_attgt)}}bootstrap results, one row per ATT(g,t) cell, with
columns {cmd:group}, {cmd:time}, {cmd:event_time}, {cmd:att}, {cmd:se_boot},
{cmd:se_analytic}, {cmd:crit_val}, {cmd:ci_low}, {cmd:ci_high},
{cmd:point_crit_val}, {cmd:point_ci_low}, and {cmd:point_ci_high}
{it:(conditional: bootstrap)}{p_end}
{synopt:{cmd:e(boot_draws)}}{cmd:e(biters)}-by-{cmd:e(N_attgt)} matrix of
bootstrap draws {it:(conditional: bootstrap)}{p_end}
{synopt:{cmd:e(boot_rng_state)}}final random-number state
{it:(conditional: seeded bootstrap)}{p_end}
{synopt:{cmd:e(profile)}}timing by estimation phase
{it:(diagnostic)}{p_end}
{synopt:{cmd:e(bootstrap_profile)}}timing by bootstrap phase
{it:(conditional: bootstrap; diagnostic)}{p_end}
{synopt:{cmd:e(bootstrap_kernel_profile)}}timing inside the multiplier kernel
{it:(conditional: bootstrap; diagnostic)}{p_end}
{p2colreset}{...}

{pstd}
{cmd:csdid} does {bf:not} set {cmd:e(sample)}.

{pstd}
After {cmd:csdid, agg(event)}, and after {helpb csdid_stats} or
{helpb csdid_estat} with {cmd:post}, {cmd:e(b)} and {cmd:e(V)} hold the
{it:aggregated} coefficients and the additional results {cmd:e(aggte)},
{cmd:e(agg_inffunc)}, {cmd:e(agg_type)}, and {cmd:e(N_aggte)} are present.
Those are documented in {helpb csdid_stats} and
{helpb csdid_postestimation:csdid postestimation}.

{pstd}
Stability policy: every result above that is not marked {it:(diagnostic)} is
part of the package's public interface, and its name and meaning will not
change without a note in the release notes. The {it:(diagnostic)} results exist
for profiling and support and may change or disappear in any release.


{marker methods}{...}
{title:Methods and formulas}

{pstd}
{bf:The estimand.} With {it:C} denoting the comparison group -- the
never-treated units under the default, or the units not yet treated as of
period {it:t} under {cmd:notyet} -- and {it:b} the base period ({it:g - 1 - d}
under {cmd:anticipation(}{it:d}{cmd:)}, or {it:t - 1} for pre-treatment cells
under a varying base period), conditional parallel trends identifies

{p 12 12 2}
ATT(g,t) = E[ Y_t - Y_b | X, G = g ] - E[ Y_t - Y_b | X, C ],

{pstd}
averaged over the covariate distribution of cohort {it:g}. Write
{it:DY = Y_t - Y_b}, let {it:D} indicate membership in cohort {it:g} among the
units used for this cell, and let

{p 12 12 2}
p(X) = Pr(D = 1 | X),{space 6}m(X) = E[ DY | X, D = 0 ]

{pstd}
be the propensity score and the comparison-group outcome regression. {it:p(X)}
is fit by weighted logit maximum likelihood on all observations entering the
cell; {it:m(X)} is fit by weighted least squares on the comparison
observations only.

{pstd}
{bf:The three estimators} are those of Sant'Anna and Zhao (2020):

{pstd}
Write {it:w1 = D} and {it:w0 = (1 - D) p(X) / (1 - p(X))} for the treated and
reweighted-comparison weights, each multiplied by the sampling weight when
{cmd:iweight}s are supplied.

{phang2}
{cmd:method(reg)}, outcome regression:{break}
{space 4}ATT = E[ w1 ( DY - m(X) ) ] / E[ w1 ]. Consistent when the outcome
model is correct.{p_end}

{phang2}
{cmd:method(ipw)}, normalized inverse probability weighting:{break}
{space 4}ATT = E[ w1 DY ] / E[ w1 ] - E[ w0 DY ] / E[ w0 ]. The Hajek
normalization by the estimated weight totals is what makes it exactly location
invariant. Consistent when the propensity score is correct.{p_end}

{phang2}
{cmd:method(dr)}, doubly robust (the default):{break}
{space 4}ATT = E[ w1 ( DY - m(X) ) ] / E[ w1 ] - E[ w0 ( DY - m(X) ) ] / E[ w0 ].
Consistent if {it:either} the outcome regression {it:or} the propensity score
is correctly specified, and locally efficient when both are. This is the
improved estimator of Sant'Anna and Zhao (2020), and is the default for that
reason.{p_end}

{pstd}
Under {cmd:pscoretrim(}{it:c}{cmd:)}, comparison observations with
{it:p(X) >= c} are excluded from the cell. With repeated cross sections the
same estimators are applied to the four period-by-group cells rather than to
within-unit differences, and this is also the path taken for unbalanced
panels.

{pstd}
{bf:Standard errors.} Each estimated cell is asymptotically linear,

{p 12 12 2}
sqrt(n) ( ATThat(g,t) - ATT(g,t) ) = (1/sqrt(n)) sum_i psi_gt(W_i) + o_p(1),

{pstd}
where the influence function {it:psi_gt} accounts for the estimation of
{it:p(X)} and {it:m(X)} as well as for the sample analogue itself. The
analytical standard error is the square root of the empirical variance of
{it:psi_gt} divided by {it:n}. Under {cmd:cluster()}, influence functions are
summed within cluster first and the variance is taken across clusters.
Aggregations are linear combinations of ATT(g,t) with estimated weights; their
influence functions carry the weight-estimation terms as well, which is why
{helpb csdid_stats} recomputes from {cmd:e(inffunc)} rather than from the
reported standard errors.

{pstd}
{bf:Multiplier bootstrap.} Following Callaway and Sant'Anna (2021), iteration
{it:b} draws independent Rademacher multipliers {it:V_i}, equal to 1 or -1
with probability one half, one per unit or per cluster, and forms

{p 12 12 2}
ATTstar_b(g,t) = ATThat(g,t) + (1/n) sum_i V_i psi_gt(W_i).

{pstd}
No re-estimation takes place, so the cost is one matrix multiplication per
iteration. The reported standard error of each cell is the interquartile range
of its bootstrap deviations across iterations, divided by the interquartile
range of the standard normal, {it:z(.75) - z(.25)}: a robust scale estimate
that is insensitive to a few extreme draws. This is why a bootstrap standard
error can differ noticeably from the analytical one in small samples even
though both are consistent for the same quantity.

{pstd}
{bf:Simultaneous bands.} For a uniform band, the maximum studentized deviation

{p 12 12 2}
max over (g,t) of | ATTstar_b(g,t) - ATThat(g,t) | / sehat(g,t)

{pstd}
is computed in every iteration, and its {it:1 - alpha} empirical quantile is
the critical value {cmd:e(crit_val)}. The band
{it:ATThat(g,t) +/- crit_val x sehat(g,t)} then covers all ATT(g,t)
simultaneously with asymptotic probability {it:1 - alpha}. {cmd:pointwise}
replaces this critical value with the normal quantile, giving intervals with
the nominal coverage one cell at a time only.

{pstd}
{bf:Parallel-trends pre-test.} Let {it:P} index the pre-treatment cells, those
with {it:t < g}, and let {it:V} be the analytical influence-function covariance
matrix of the ATT(g,t) estimates, {it:V = (1/n) sum_i psi(W_i) psi(W_i)'},
formed from cluster sums under {cmd:cluster()}. Cells whose implied standard
error {it:sqrt(V_jj / n)} is missing or below the square root of machine
epsilon are dropped from {it:P}. With {it:q} cells left and
{it:a} the vector of their estimates,

{p 12 12 2}
W = n a' inv(V_PP) a,

{pstd}
which is asymptotically chi-squared with {it:q} degrees of freedom under the
null that all pre-treatment ATT(g,t) are zero. {cmd:e(wald_pvalue)} is
{it:1 - Prob(chi2(q) <= W)}, rounded to five decimals. Nothing is stored, and a
note is printed instead, when {it:q = 0}, when {it:V_PP} contains missing
values, or when {it:V_PP} is numerically singular. {it:V} here is always the
analytical matrix, never the bootstrap one, so the pre-test is the same under
{cmd:analytical} and under the default bootstrap.

{pstd}
{bf:Random numbers.} Seeded runs draw the multipliers from a Mersenne-Twister
stream, and the resulting state is stored in {cmd:e(boot_rng_state)}.
Unseeded runs use Stata's own random-number stream, so {cmd:set seed} before
{cmd:csdid} also makes a run reproducible.


{marker acknowledgments}{...}
{title:Acknowledgments}

{pstd}
This package implements the estimators developed in Callaway and Sant'Anna
(2021) and Sant'Anna and Zhao (2020). The group-time average treatment effects,
the aggregation schemes, and the multiplier bootstrap are theirs; the two-period
doubly robust, outcome-regression, and inverse-probability-weighting estimators
applied to each (g,t) cell are those of Sant'Anna and Zhao (2020).

{phang}
The original Stata {cmd:csdid} package was written by Fernando Rios-Avila. It
brought these estimators to Stata users first, defined the command surface
that this rewrite preserves, and shaped what Stata users expect from a
Callaway-Sant'Anna package. The present package is an independent
reimplementation; see
{help csdid##remarks_legacy:Migrating from Stata csdid Version 1.82} for what changed
and why.{p_end}


{phang}
The R package {bf:did}, by Brantly Callaway and Pedro H.C. Sant'Anna, is the
reference implementation of these methods. {cmd:csdid} derives from it and was
constructed and benchmarked against {bf:did} version 2.5.1: the estimators, the
option defaults, and the sample rules follow it, and the group-time effects,
their aggregations, and their standard errors are checked directly against it.
{p_end}


{marker references}{...}
{title:References}

{marker abadie2005}{...}
{phang}
Abadie, A. 2005. Semiparametric difference-in-differences estimators.
{it:Review of Economic Studies} 72(1): 1-19.
{browse "https://doi.org/10.1111/0034-6527.00321"}.
{p_end}

{marker baker2026}{...}
{phang}
Baker, A., B. Callaway, S. Cunningham, A. Goodman-Bacon, and P. H. C.
Sant'Anna. 2026. Difference-in-differences designs: A practitioner's guide.
{it:Journal of Economic Literature} 64(2): 498-557.
{browse "https://doi.org/10.1257/jel.20251650"}.
{p_end}

{marker callaway2021}{...}
{phang}
Callaway, B., and P. H. C. Sant'Anna. 2021. Difference-in-differences with
multiple time periods. {it:Journal of Econometrics} 225(2): 200-230.
{browse "https://doi.org/10.1016/j.jeconom.2020.12.001"}.
{p_end}

{marker roth2023}{...}
{phang}
Roth, J., P. H. C. Sant'Anna, A. Bilinski, and J. Poe. 2023. What's trending in
difference-in-differences? A synthesis of the recent econometrics literature.
{it:Journal of Econometrics} 235(2): 2218-2244.
{browse "https://doi.org/10.1016/j.jeconom.2023.03.008"}.
{p_end}

{marker santannazhao2020}{...}
{phang}
Sant'Anna, P. H. C., and J. Zhao. 2020. Doubly robust
difference-in-differences estimators. {it:Journal of Econometrics} 219(1):
101-122.
{browse "https://doi.org/10.1016/j.jeconom.2020.06.003"}.
{p_end}

{pstd}
If you use {cmd:csdid} in your research, please cite Callaway and Sant'Anna
(2021) for the estimator, Sant'Anna and Zhao (2020) for the doubly robust
two-period estimators, and this package for the implementation.
{p_end}


{marker authors}{...}
{title:Authors}

{pstd}
{bf:Fernando Rios-Avila}{break}
Levy Economics Institute of Bard College{break}
{browse "mailto:f.rios.a@gmail.com":f.rios.a@gmail.com}
{p_end}

{pstd}
{bf:Pedro H.C. Sant'Anna} (maintainer){break}
Emory University{break}
{browse "mailto:pedro.santanna@emory.edu":pedro.santanna@emory.edu}
{p_end}

{pstd}
{bf:Brantly Callaway}{break}
University of Georgia{break}
{browse "mailto:brantly.callaway@uga.edu":brantly.callaway@uga.edu}
{p_end}

{pstd}
{cmd:csdid} 2.0.0 is a reimplementation of the estimator, sample handling and
inference. It succeeds the 1.8x Stata {cmd:csdid} line and reuses none of its
code.
{p_end}


{marker support}{...}
{title:Support and updates}

{pstd}
Source, issue tracker, and release notes:
{browse "https://github.com/pedrohcgs/csdid-stata":github.com/pedrohcgs/csdid-stata}.

{pstd}
{cmd:csdid} requires Stata 14 or newer, the same floor as the SSC {cmd:csdid}
it succeeds. The estimation engine is pure Mata and
the package installs no platform-specific binaries, so it behaves identically
on Windows, macOS, and Linux.

{pstd}
When reporting a numerical problem, please include the output of
{cmd:csdid version}, the exact command line, {cmd:e(cmdline)},
{cmd:e(method)}, {cmd:e(control_group)}, {cmd:e(base_period)},
{cmd:e(panel_mode)}, and {cmd:e(compute_path)}, and, if the issue concerns
inference, {cmd:e(bstrap)}, {cmd:e(biters)}, {cmd:e(boot_seed)}, and
{cmd:e(bootstrap_accelerator_status)}. A small dataset that reproduces the
problem is worth more than any description of it.


{marker license}{...}
{title:License}

{pstd}
{cmd:csdid} is released under the MIT License: use, modification and
redistribution, including commercial use, are permitted provided the copyright
notice and permission notice are retained. The full text ships with the package
source as {cmd:LICENSE}.
{p_end}


{marker alsosee}{...}
{title:Also see}

{psee}
Online:  {helpb csdid_postestimation:csdid postestimation},
{helpb csdid_stats}, {helpb csdid_estat}, {helpb csdid_plot}
{p_end}

{psee}
Online:  {helpb didregress}, {helpb xtdidregress}, {helpb hdidregress},
{helpb xtreg}
{p_end}
