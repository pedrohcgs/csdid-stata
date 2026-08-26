{smcl}
{* *! version 2.0.0 26aug2026}{...}
{vieweralsosee "csdid" "help csdid"}{...}
{vieweralsosee "csdid postestimation" "help csdid_postestimation"}{...}
{vieweralsosee "csdid_estat" "help csdid_estat"}{...}
{vieweralsosee "csdid_plot" "help csdid_plot"}{...}
{vieweralsosee "" "--"}{...}
{viewerjumpto "Syntax" "csdid_stats##syntax"}{...}
{viewerjumpto "Description" "csdid_stats##description"}{...}
{viewerjumpto "Options" "csdid_stats##options"}{...}
{viewerjumpto "Remarks" "csdid_stats##remarks"}{...}
{viewerjumpto "Examples" "csdid_stats##examples"}{...}
{viewerjumpto "Stored results" "csdid_stats##results"}{...}
{viewerjumpto "Methods and formulas" "csdid_stats##methods"}{...}
{viewerjumpto "References" "csdid_stats##references"}{...}
{viewerjumpto "Authors" "csdid_stats##authors"}{...}
{title:Title}

{p2colset 5 20 22 2}{...}
{p2col:{bf:csdid_stats} {hline 2}}Aggregate group-time average treatment
effects estimated by {cmd:csdid}{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{pstd}
Aggregate the results of the {cmd:csdid} estimation in memory

{p 8 15 2}
{cmd:csdid_stats} [{it:type}] [{cmd:,} {it:{help csdid_stats##options_table:options}}]

{pstd}
Aggregate influence functions saved earlier by {cmd:csdid, saverif()}

{p 8 15 2}
{cmd:csdid_stats} [{it:type}] {cmd:using} {it:riffile}
[{cmd:,} {it:{help csdid_stats##options_table:options}}]

{pstd}
{it:type} is {cmd:simple}, {cmd:group}, {cmd:dynamic}, {cmd:event}, or
{cmd:calendar}; {cmd:event} is a synonym for {cmd:dynamic}. The default is
{cmd:group}.

{marker options_table}{...}
{synoptset 26 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Aggregation}
{synopt:{opt type(type)}}aggregation to compute; may also be given as the
positional {it:type}{p_end}

{syntab:Event time {help csdid_stats##opt_window:[+]}}
{synopt:{opt win:dow(min max)}}report and average event times from {it:min}
through {it:max}{p_end}
{synopt:{opt bal:ance(#)}}keep only cohorts with at least {it:#} periods of
post-treatment data and truncate the event-time grid{p_end}
{synopt:{opt min_e(#)}}synonym for the lower bound of {cmd:window()}{p_end}
{synopt:{opt max_e(#)}}synonym for the upper bound of {cmd:window()}{p_end}
{synopt:{opt balance_e(#)}}{cmd:balance()} written under its
cross-implementation name{p_end}

{syntab:Sample}
{synopt:{opt dropm:issing}}drop missing ATT(g,t) cells before aggregating{p_end}
{synopt:{opt na_rm}}synonym for {cmd:dropmissing};
{cmd:na.rm} is also accepted{p_end}

{syntab:Reporting {help csdid_stats##opt_level:[+]}}
{synopt:{opt cluster(clustvar)}}assert the estimation-time cluster variable;
{cmd:clustervars()} is a synonym{p_end}
{synopt:{opt l:evel(#)}}set confidence level; default is the confidence level
used by {cmd:csdid}{p_end}
{synoptline}
{p2colreset}{...}

{p 4 6 2}
{cmd:csdid_stats} may be used after {cmd:csdid}, or with {cmd:using} after
{cmd:csdid, saverif()}. On {cmd:csdid_stats}, {cmd:window()} may be abbreviated
to {cmd:win()}; on {cmd:estat}, which is a separate command, it must be spelled
in full. The Stata-conventional {cmd:estat} forms of the same
aggregations are documented in {helpb csdid_estat}.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:csdid_stats} averages the group-time average treatment effects ATT(g,t)
produced by {cmd:csdid} into the four summary parameters of Callaway and
Sant'Anna (2021): an overall {cmd:simple} average, a {cmd:group} (cohort)
average, a {cmd:dynamic} (event-study) profile, and a {cmd:calendar}-time
profile. It is the computational engine behind {cmd:estat simple},
{cmd:estat group}, {cmd:estat calendar}, {cmd:estat dynamic}, and
{cmd:estat event}; see {helpb csdid_estat}.

{pstd}
Aggregation is done with the influence functions of the ATT(g,t) estimates, so
standard errors account for the estimation of both the cell effects and the
aggregation weights. Clustering, the multiplier bootstrap, and simultaneous
confidence bands are inherited from the {cmd:csdid} call that produced the
results.

{pstd}
Aggregation needs the influence functions of the ATT(g,t) estimates, which
{cmd:csdid} keeps in its Mata cache (and additionally materializes as
{cmd:e(inffunc)} and {cmd:e(unit_group)} under {cmd:storeall}). Both live in
the current session: after {cmd:clear all}, {cmd:mata clear}, or a restart,
re-run {cmd:csdid} or use the {cmd:using} form below. {cmd:csdid_stats} says
what is missing and exits with return code 498 rather than aggregating
something stale.

{pstd}
The {cmd:using} form reloads a saved influence-function (RIF) file written by
{cmd:csdid, saverif()} and aggregates it without re-estimating. That file
carries only what is needed for analytical inference, so aggregations from a
RIF file are always analytical.

{pstd}
{cmd:csdid_stats} does not overwrite {cmd:e(b)} and {cmd:e(V)}: after it runs,
the posted coefficient vector is still the one left by {cmd:csdid}. Use
{cmd:estat} {it:type}{cmd:, post} when you want {cmd:test}, {cmd:lincom}, or
{cmd:estimates} to operate on the aggregated effects; see
{helpb csdid_estat##post:csdid_estat}.


{marker options}{...}
{title:Options}

{dlgtab:Aggregation}

{marker opt_type}{...}
{phang}
{opt type(type)} selects the aggregation. {it:type} is {cmd:simple},
{cmd:group}, {cmd:dynamic}, {cmd:event}, or {cmd:calendar}; {cmd:event} is a
synonym for {cmd:dynamic}. The default is {cmd:group}. The type may also be
given positionally, as in
{cmd:csdid_stats event}. What each type averages is described under
{help csdid_stats##types:Aggregation types}.

{pmore}
Give the type one way or the other, not both ways differently.
{cmd:csdid_stats simple, type(group)} names two different aggregations in one
command and is refused with return code 198 rather than silently running one of
them; {cmd:csdid_stats event, type(dynamic)} names the same aggregation twice
and is accepted. A type that is not one of the five is refused either way, and
the message follows the form you used: an unrecognized positional token is
reported as an unsupported subcommand, an unrecognized {cmd:type()} as a bad
{cmd:type()}, so you are never told to fix an option you did not type. A second
positional token is reported as an extra token, for the same reason.

{dlgtab:Event time}

{marker opt_window}{...}
{phang}
{opt window(min max)} restricts the event times that are reported and
averaged. {cmd:min_e()} and {cmd:max_e()} are synonyms for its two bounds. Both
bounds must be numeric; one number, three numbers, or a nonnumeric bound is an
error. Comma-separated bounds, as in {cmd:window(-3,3)}, are also accepted.

{pmore}
The upper bound is not only a reporting filter. For {cmd:type(simple)} and
{cmd:type(group)} it restricts which post-treatment cells enter the average to
those with t <= g + {it:max}; the lower bound has no effect on those two types,
because they average post-treatment cells only. For {cmd:type(dynamic)} both
bounds select the reported event times, and the overall post-treatment effect
is the average of the effects that survive the window. For
{cmd:type(calendar)} the window has no effect and a warning says so. This is
the documented behavior.

{pmore}
A window that leaves no event time at all, or no post-treatment event time,
is refused with return code 498. No placeholder
coefficients are created for event times that are not in the data.

{marker opt_balance}{...}
{phang}
{opt balance(#)} restricts the dynamic aggregation to a balanced event-time
sample. It applies two restrictions:

{pmore}
1. Only cohorts observed for at least {it:#} periods after treatment
contribute, that is, cohorts with {it:last period} - g >= {it:#}.

{pmore}
2. The reported event times are truncated to the range {it:#} -
({it:last period} - {it:first period}) through {it:#}. Event times outside that
range are dropped, because they are not available for every retained cohort.

{pmore}
Truncation is what makes the retained cohorts comparable; without it the
reported profile would mix event times that only some cohorts contribute to.
{cmd:balance(0)} is legal and keeps every cohort with at least one
post-treatment period. {cmd:balance()} needs the first period of the estimation
sample, which {cmd:csdid} stores in {cmd:e(time_first)}; a RIF file written by
an older version of {cmd:csdid} does not carry it, and {cmd:csdid_stats}
then refuses with return code 498 rather than guessing.

{phang}
{opt min_e(#)}, {opt max_e(#)}, and {opt balance_e(#)} are the same three
settings under the argument names the aggregation is usually written with
outside Stata. They are current spellings, not deprecated ones: nothing is
warned about and nothing is slated for removal, so code and worked examples
carried over from that vocabulary run unchanged. They must be typed in full
and may not be combined with the Stata spelling they duplicate:
{cmd:min_e()} or {cmd:max_e()} together with {cmd:window()}, or
{cmd:balance_e()} together with {cmd:balance()}, is an error. Repeating any one
of them, as in {cmd:min_e(-3) min_e(-2)}, is also an error, and the message
names the repeated option rather than reporting it as unsupported. The same
holds for the options declared on the syntax line -- {cmd:type()},
{cmd:window()}, {cmd:balance()}, {cmd:level()} -- in every abbreviation Stata
accepts for them: {cmd:win(0 1) win(1 2)} is reported as a repeated
{cmd:window()}, not as an unsupported option.

{phang}
{opt from(#)} was a lower bound on event time in Stata {cmd:csdid} Version
1.82, applied to the simple, group and calendar aggregations. It is rejected
with return code 198 and a message naming the replacement. There is no
equivalent: those three aggregations are defined from event time 0 upward, so
a lower bound below that has nothing to restrict and one above it would
silently redefine the estimand. Use {cmd:window(}{it:# #}{cmd:)} with
{cmd:type(dynamic)} for an event-time window.

{dlgtab:Sample}

{marker opt_dropmissing}{...}
{phang}
{opt dropmissing} drops ATT(g,t) cells whose estimate is missing before
aggregating. Without it, a missing cell stops the aggregation with return code
498 and a message that names the option, so a silently dropped cell can never
change a reported average. {opt na_rm} and {cmd:na.rm} are the alternative
spellings. The same option, with the same meaning, is accepted on every
{cmd:estat} aggregation route; see
{helpb csdid_estat##opt_dropmissing:csdid_estat}.

{dlgtab:Reporting}

{phang}
{opt cluster(clustvar)} (synonym {opt clustervars(clustvar)}) asserts the
cluster variable. Clustered aggregation standard errors are computed
automatically whenever {cmd:csdid} itself was run with {cmd:cluster()}, so this
option is only a check. A cluster variable that differs from the estimation
cluster variable is refused with return code 498; falling back to unclustered
standard errors, or re-clustering influence functions that were computed under
a different design, would silently change inference. Specifying it twice, or
specifying both spellings, is an error rather than a last-one-wins: the
discarded one is the one that might have matched.

{marker opt_level}{...}
{phang}
{opt level(#)} sets the confidence level used for the aggregation. When
{cmd:level()} is not given, the level is inherited from the {cmd:csdid} call
that produced the results, that is, from {cmd:e(level)}: after
{cmd:csdid ..., level(90)} every aggregation reports 90% intervals whatever the
session {help level:set level} value is. See
{help csdid_stats##level:Confidence levels} for the one case in which an
explicitly typed level is not distinguishable from the default.


{marker remarks}{...}
{title:Remarks}

{pstd}
Remarks are presented under the following headings:

{p2colset 8 36 38 2}{...}
{p2col:{help csdid_stats##types:Aggregation types}}{p_end}
{p2col:{help csdid_stats##window:Event-time windows}}{p_end}
{p2col:{help csdid_stats##balance:Balanced event-time samples}}{p_end}
{p2col:{help csdid_stats##level:Confidence levels}}{p_end}
{p2col:{help csdid_stats##rif:Aggregating a saved RIF file}}{p_end}
{p2colreset}{...}

{marker types}{...}
{title:Aggregation types}

{pstd}
{cmd:csdid} estimates one effect ATT(g,t) for each treatment cohort g and each
period t. Those cells are the primitive; every summary number is a weighted
average of them, and the four types differ only in which cells they average and
with what weights. Let P(G=g) be the (weighted) share of the sample in cohort
g, restricted to cohorts that contribute to the average.

{phang}
{cmd:type(simple)} averages every post-treatment cell (t >= g) at once, with
weights proportional to P(G=g). It is one number, the "overall" ATT. Cohorts
treated early therefore contribute more cells than cohorts treated late.

{phang}
{cmd:type(group)} averages the post-treatment cells within each cohort with
equal weights, giving one effect per cohort: the average effect of treatment on
cohort g over the time it has been treated. The overall effect is the average
of the cohort effects with weights proportional to P(G=g). This is the default
and is usually the safest single summary.

{phang}
{cmd:type(dynamic)} averages cells by event time e = t - g, with weights
proportional to P(G=g) among the cohorts observed at that event time. This is
the event study: effects at e < 0 are pre-treatment placebo estimates and
effects at e >= 0 are post-treatment. The overall effect is the {it:unweighted}
average of the reported e >= 0 effects, so it changes with
{cmd:window()} and {cmd:balance()}.

{phang}
{cmd:type(calendar)} averages, within each period t, the cells of all cohorts
already treated by t, with weights proportional to P(G=g). Periods before the
earliest treatment are not reported. The overall effect is the unweighted
average of the reported period effects.

{pstd}
Every weight used above is nonnegative and the weights sum to one, so none of
these parameters can put negative weight on a treatment effect. What separates
them is the question they answer, not their robustness; see Callaway and
Sant'Anna (2021, sections 3 and 4) for the interpretation of each parameter and
of the weights it uses.

{marker window}{...}
{title:Event-time windows}

{pstd}
{cmd:window(-3 3)} and the synonyms {cmd:min_e(-3) max_e(3)} are the same
thing. Two properties are easy to overlook:

{phang}
The overall effect is recomputed inside the window. For a dynamic aggregation,
the reported overall effect is the average of the post-treatment event-time
effects that are still reported, not the unwindowed overall effect. Narrowing
the window therefore changes the headline number.

{phang}
The upper bound also trims {cmd:simple} and {cmd:group}. Both average the cells
with t <= g + {it:max}, so {cmd:csdid_stats group, window(-3 1)} reports, for
each cohort, the average effect over its first two treated periods rather than
over all of them. Use the upper bound deliberately, and remember that the lower
bound does nothing for these two types.

{marker balance}{...}
{title:Balanced event-time samples}

{pstd}
A dynamic profile computed on the full sample changes composition along the
x-axis: only early-treated cohorts are observed at long event times, so a
downward-sloping profile can be composition rather than dynamics.
{cmd:balance(#)} removes that by keeping only cohorts with at least {it:#}
post-treatment periods and then truncating the event-time grid to the range
those cohorts share. Both steps matter: the cohort restriction alone would
leave event times that not every retained cohort reaches.

{pstd}
With the county-level example below, which runs from 2003 to 2007,
{cmd:balance(1)} keeps the 2004 and 2006 cohorts and reports event times -2
through 1. {cmd:balance(3)} keeps only the 2004 cohort and truncates the grid to
event times -1 through 3, of which 0 through 3 are estimated -- the base period
of that cohort is not an estimated cell. Because the retained cohorts change,
so does the overall effect.

{marker level}{...}
{title:Confidence levels}

{pstd}
Aggregation inherits the confidence level of the estimation rather than any
session setting.

{pstd}
There is one boundary case. Stata's option parser cannot distinguish an
explicitly typed level from an omitted one when the value typed equals the
current session {help level:set level} value. In that case the estimation-time
level wins.
Concretely, after {cmd:csdid ..., level(90)} with the session default at 95,
{cmd:csdid_stats simple, level(95)} reports 90% intervals; ask for any other
level, or re-run {cmd:csdid} at the level you want, and the requested level is
used.

{pstd}
Under analytical inference the interval is the estimate plus or minus the
normal quantile at the reported level. Under the default multiplier bootstrap
the interval uses the bootstrap critical value, which is recomputed by the
aggregation bootstrap each time {cmd:csdid_stats} runs, at the level in force
for that run; with simultaneous bands it exceeds the pointwise normal quantile.
Both critical values are stored, in {cmd:e(crit_val)} and
{cmd:e(point_crit_val)}.

{pstd}
Two aggregations are always banded pointwise, whatever the estimation asked
for, and the header above the table says so. {cmd:type(simple)} reports a
single overall effect, for which a simultaneous band over one effect is the
pointwise interval; and when the estimation's time grid has only two periods
there is one comparison to band, so the simultaneous band is not defined
separately from the pointwise one. The ATT(g,t) table keeps the simultaneous
band it was estimated with in both cases; only the aggregation is affected.

{pstd}
{cmd:e(agg_cband)} reports which band the aggregation just computed carries: 1
simultaneous, 0 pointwise. Read it rather than {cmd:e(cband)}, which describes
the estimation and stays 1 through both cases above.

{marker rif}{...}
{title:Aggregating a saved RIF file}

{pstd}
{cmd:csdid, saverif(}{it:filename}{cmd:)} writes one row per unit and one
{cmd:rif}{it:#} variable per ATT(g,t) cell, with the cell metadata attached as
variable characteristics. {cmd:csdid_stats} {cmd:using} {it:filename} rebuilds
the estimation results needed for aggregation from that file, so a long
estimation can be aggregated many ways later, or in another session, without
re-estimating.

{pstd}
Two consequences follow from what the file contains. First, aggregation from a
RIF file is analytical: bootstrap draws and the bootstrap random-number state
are not saved. Second, the {cmd:using} form replaces the estimation results in
{cmd:e()} with the reconstructed ones, so it should be run in a fresh
postestimation state rather than on top of results you still need.

{pstd}
Clustering does travel with the file. A RIF written by a run with
{cmd:cluster(}{it:clustvar}{cmd:)} carries the cluster identifiers, and
{cmd:csdid_stats using} reports the same clustered standard errors as
aggregating the estimation directly; {cmd:cluster(}{it:clustvar}{cmd:)} on the
{cmd:using} form is accepted, and naming a different variable is refused, as it
is for a live estimation. A file that does not record the clustering at all is
refused by name rather than aggregated as if the estimation had been
unclustered; re-run {cmd:csdid} with {cmd:saverif()} to rewrite it.

{pstd}
The confidence level travels with the file. {cmd:saverif()} records the level
of the estimation that wrote it, and the {cmd:using} form restores it as
{cmd:e(level)} and bands at it, exactly as an in-memory aggregation inherits
{cmd:e(level)}. So a RIF file written by {cmd:csdid ..., level(90)} still
reports 90% intervals when it is aggregated in a later session whose
{help level:set level} is 95, and {cmd:e(level)} and {cmd:e(agg_level)} agree.
Type {cmd:level()} on the {cmd:csdid_stats} command to override it. A file
written by an older version of {cmd:csdid} that does not carry the level falls
back to the session default.

{marker examples}{...}
{title:Examples}

{pstd}
The examples use {cmd:mpdta.dta}, the county-level teen-employment panel of
Callaway and Sant'Anna (2021), which ships with the package as an ancillary
file: {cmd:net get csdid} copies it into the current directory.

{pstd}{bf:Setup}{p_end}
{phang2}{cmd:. net get csdid}{p_end}
{phang2}{cmd:. use mpdta, clear}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat)}{p_end}

{pstd}{bf:The four aggregations}{p_end}
{phang2}{cmd:. csdid_stats simple}{p_end}
{phang2}{cmd:. csdid_stats group}{p_end}
{phang2}{cmd:. csdid_stats calendar}{p_end}
{phang2}{cmd:. csdid_stats event}{p_end}

{pstd}{bf:Event study restricted to a window}{p_end}
{phang2}{cmd:. csdid_stats event, window(-3 3)}{p_end}

{pstd}{bf:Same thing, using the synonyms}{p_end}
{phang2}{cmd:. csdid_stats event, min_e(-3) max_e(3)}{p_end}

{pstd}{bf:Balanced event-time sample: cohorts with at least one post period}{p_end}
{phang2}{cmd:. csdid_stats event, balance(1)}{p_end}

{pstd}{bf:Aggregate at a level chosen at estimation time}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) level(90)}{p_end}
{phang2}{cmd:. csdid_stats event}{p_end}

{pstd}{bf:Aggregate influence functions saved to disk}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) analytical saverif(mpdta_rif) replace}{p_end}
{phang2}{cmd:. csdid_stats using mpdta_rif, type(dynamic) window(-2 2)}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:csdid_stats} adds the following to the results left by {cmd:csdid}. All
results of the estimation itself are preserved, including {cmd:e(b)},
{cmd:e(V)}, and {cmd:e(attgt)}.

{pstd}
{cmd:csdid_stats} stores the following in {cmd:e()}:

{synoptset 26 tabbed}{...}
{p2col 5 26 29 2: Scalars}{p_end}
{synopt:{cmd:e(N_aggte)}}number of aggregated effects reported{p_end}
{synopt:{cmd:e(agg_level)}}confidence level used for the aggregation{p_end}
{synopt:{cmd:e(agg_cband)}}1 if the band reported for this aggregation is
simultaneous, 0 if it is pointwise{p_end}
{synopt:{cmd:e(crit_val)}}the aggregation's own simultaneous critical value
{it:(posted only under bootstrap inference)}{p_end}
{synopt:{cmd:e(point_crit_val)}}the aggregation's own pointwise critical value
{it:(posted only under bootstrap inference)}{p_end}
{synopt:{cmd:e(agg_boot_accel_rc)}}return code of the optional bootstrap
accelerator, 0 when none was needed
{it:(posted only under bootstrap inference; diagnostic)}{p_end}

{p2col 5 26 29 2: Macros}{p_end}
{synopt:{cmd:e(agg_type)}}aggregation computed: {cmd:simple}, {cmd:group},
{cmd:dynamic}, or {cmd:calendar}{p_end}
{synopt:{cmd:e(agg_clustervar)}}cluster variable named in {cmd:cluster()}, if
any{p_end}
{synopt:{cmd:e(agg_boot_accelerator)}}engine used by the aggregation bootstrap
{it:(posted only under bootstrap inference; diagnostic)}{p_end}
{synopt:{cmd:e(agg_boot_accel_status)}}why that engine was used
{it:(posted only under bootstrap inference; diagnostic)}{p_end}

{p2col 5 26 29 2: Matrices}{p_end}
{synopt:{cmd:e(aggte)}}aggregation table, one row per reported effect, with
columns {cmd:egt}, {cmd:att}, {cmd:se}, {cmd:overall_att}, {cmd:overall_se};
{cmd:egt} is the cohort, event time, or period the row refers to, and is
missing for {cmd:type(simple)}{p_end}
{synopt:{cmd:e(agg_inffunc)}}influence functions of the aggregated effects, one
row per unit and one column per reported effect, plus a final column for the
overall effect. Posted under {cmd:storeall} only: by default the influence
functions are held internally, and every postestimation result, including
the posted {cmd:e(V)} after {cmd:post}, is computed from the internal
copy{p_end}
{synopt:{cmd:e(boot_aggte)}}bootstrap aggregation table with columns
{cmd:egt}, {cmd:att}, {cmd:se_boot}, {cmd:crit_val}, {cmd:ci_low},
{cmd:ci_high}, {cmd:point_crit_val}, {cmd:point_ci_low}, {cmd:point_ci_high},
{cmd:overall_se}; posted under bootstrap inference{p_end}
{synopt:{cmd:e(agg_boot_draws)}}bootstrap draws of the aggregated effects, one
row per iteration; posted under bootstrap inference{p_end}
{synopt:{cmd:e(agg_bootstrap_profile)}}timing by bootstrap phase
{it:(posted only under bootstrap inference; diagnostic)}{p_end}
{p2colreset}{...}

{pstd}
Under {cmd:analytical} inference {cmd:csdid_stats} posts none of the
bootstrap results above, and {cmd:e(crit_val)} and {cmd:e(point_crit_val)} are
left holding the values {cmd:csdid} stored at estimation time. They do
{bf:not} track a {cmd:level()} given to {cmd:csdid_stats}: under analytical
inference the aggregation's critical value is the normal quantile at
{cmd:e(agg_level)}. {cmd:estat} {it:type}, {cmd:estat tidy}, and
{helpb csdid_plot} already apply that rule; apply it too if you build bands by
hand.

{pstd}
The {cmd:using} form additionally rebuilds the estimation results it needs from
the RIF file: {cmd:e(attgt)}, {cmd:e(inffunc)}, {cmd:e(group_prob)},
{cmd:e(unit_group)}, {cmd:e(cmd)}, {cmd:e(cmdline)}, {cmd:e(method)},
{cmd:e(control_group)}, {cmd:e(base_period)}, {cmd:e(panel_mode)},
{cmd:e(rif_file)}, {cmd:e(N)}, {cmd:e(N_units)}, {cmd:e(N_attgt)},
{cmd:e(N_groups)}, {cmd:e(N_time)}, {cmd:e(anticipation)}, {cmd:e(level)},
{cmd:e(version)}, the postestimation plumbing macros {cmd:e(estat_cmd)},
{cmd:e(predict)}, and {cmd:e(marginsnotok)}, {cmd:e(time_first)} when the
file carries it, and -- when the estimation that wrote the file was
clustered -- {cmd:e(clustervar)}, {cmd:e(cluster_vec)}, and
{cmd:e(N_clusters)}.

{pstd}
Results marked diagnostic exist for support and performance work. They are not
a stable interface and must not be used to select an estimator or to interpret
an estimate.


{marker methods}{...}
{title:Methods and formulas}

{pstd}
Write ATT(g,t) for the estimated effect in cell (g,t), psi_gt(i) for its
influence function evaluated at unit i, and n for the number of units. Each
aggregated effect is theta = sum_{(g,t) in S} w_gt ATT(g,t) over a set S of
cells with weights w_gt that sum to one, as described under
{help csdid_stats##types:Aggregation types}.

{pstd}
The influence function of theta is

{p 8 8 2}
psi(i) = sum_{(g,t) in S} w_gt psi_gt(i) + sum_{(g,t) in S} ATT(g,t) xi_gt(i),

{pstd}
where the second term is the correction for having estimated the weights
themselves: the cohort shares P(G=g) are sample quantities, and xi_gt(i) is
their influence function. Aggregations with equal weights inside a cell set,
such as the within-cohort average of {cmd:type(group)} and the overall averages
of {cmd:type(dynamic)} and {cmd:type(calendar)}, carry no such correction.

{pstd}
The standard error is sqrt(sum_i psi(i)^2)/n. With {cmd:cluster()}, influence
functions are summed within cluster first, and the standard error is
sqrt(sum_c (sum_{i in c} psi(i))^2)/n.

{pstd}
Under the default multiplier bootstrap, each iteration reweights the same
influence functions by Rademacher multipliers. The bootstrap standard error is
the interquartile range of the draws divided by the normal interquartile range
and by sqrt(n), which is robust to the occasional extreme draw. Under
{cmd:cluster()} the draws are cluster-level, so the same scaled interquartile
range is multiplied by sqrt(C)/n -- C the number of clusters -- to express the
cluster-level dispersion on the unit scale. With
simultaneous bands, the critical value is the 1 - alpha quantile of the maximum
over reported effects of the absolute studentized draw, floored at the
pointwise normal quantile, so the band covers the whole profile with the stated
probability; {cmd:pointwise} at estimation time asks for the pointwise quantile
instead. See Callaway and Sant'Anna (2021, section 4.2).

{pstd}
The aggregation bootstrap is implemented in Mata. On macOS the package also
installs a compiled accelerator, which is used only for explicitly seeded
Rademacher draws; it computes exactly the same draws from the same
random-number state, so its results are identical to the Mata path, including
the full random-number state. Every other case -- every other platform, every
unseeded or non-Rademacher draw, and any run where the accelerator cannot load
-- uses Mata. {cmd:e(agg_boot_accelerator)} and
{cmd:e(agg_boot_accel_status)} record which path ran; they are diagnostics and
never change results.


{marker references}{...}
{title:References}

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
101-122. {browse "https://doi.org/10.1016/j.jeconom.2020.06.003"}.
{p_end}


{marker authors}{...}
{title:Authors}

{pstd}
{cmd:csdid} is by Brantly Callaway, Fernando Rios-Avila, and Pedro H. C.
Sant'Anna. Full affiliations and contact addresses, the acknowledgments, how to
report a problem, and how to cite the package are in
{help csdid##authors:help csdid}.


{title:Also see}

{psee}
Online:  {helpb csdid}, {helpb csdid_postestimation:csdid postestimation},
{helpb csdid_estat}, {helpb csdid_plot}
{p_end}
