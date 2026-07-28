{smcl}
{* *! version 2.0.0 26jul2026}{...}
{vieweralsosee "csdid" "help csdid"}{...}
{vieweralsosee "csdid postestimation" "help csdid_postestimation"}{...}
{vieweralsosee "csdid_stats" "help csdid_stats"}{...}
{vieweralsosee "csdid_plot" "help csdid_plot"}{...}
{vieweralsosee "" "--"}{...}
{viewerjumpto "Syntax" "csdid_estat##syntax"}{...}
{viewerjumpto "Description" "csdid_estat##description"}{...}
{viewerjumpto "Options" "csdid_estat##options"}{...}
{viewerjumpto "Remarks" "csdid_estat##remarks"}{...}
{viewerjumpto "Examples" "csdid_estat##examples"}{...}
{viewerjumpto "Stored results" "csdid_estat##results"}{...}
{viewerjumpto "References" "csdid_estat##references"}{...}
{viewerjumpto "Authors" "csdid_estat##authors"}{...}
{title:Title}

{p2colset 5 20 22 2}{...}
{p2col:{bf:csdid_estat} {hline 2}}Display, post, and export {cmd:csdid}
results{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{pstd}
Display the group-time ATT(g,t) table

{p 8 16 2}
{cmd:estat} {cmd:attgt}

{pstd}
Display the event-study coefficients

{p 8 16 2}
{cmd:estat} {cmd:event} [{cmd:,} {opt window(min max)} {opt post}
{opt l:evel(#)} {opt dropm:issing}]

{pstd}
Compute and display an aggregation

{p 8 16 2}
{cmd:estat} {it:aggregation} [{cmd:,} {opt window(min max)} {opt post}
{opt l:evel(#)} {opt dropm:issing}]

{pstd}
Export a results dataset

{p 8 16 2}
{cmd:estat} {cmd:tidy}{cmd:,} {opt sav:ing(filename)} [{opt replace}]

{p 8 16 2}
{cmd:estat} {cmd:glance}{cmd:,} {opt sav:ing(filename)} [{opt replace}]

{pstd}
{it:aggregation} is {cmd:simple}, {cmd:group}, {cmd:calendar}, or
{cmd:dynamic}.

{pstd}
Every form above may also be typed as {cmd:csdid_estat} instead of
{cmd:estat}, for example {cmd:csdid_estat event, window(-3 3)}. The two are the
same command; {cmd:estat} is the Stata-conventional spelling and
{cmd:csdid_estat} is convenient in scripts that must not depend on
{cmd:e(estat_cmd)}.

{synoptset 26 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main}
{synopt:{opt window(min max)}}restrict the aggregation to event times {it:min}
through {it:max}{p_end}
{synopt:{opt post}}leave the aggregated effects posted in {cmd:e(b)} and
{cmd:e(V)}{p_end}
{synopt:{opt l:evel(#)}}set confidence level; default is the confidence level
used by {cmd:csdid}{p_end}
{synopt:{opt dropm:issing}}drop missing ATT(g,t) cells before aggregating{p_end}

{syntab:Export}
{synopt:{opt sav:ing(filename)}}required file to write; {cmd:tidy} and
{cmd:glance} only{p_end}
{synopt:{opt replace}}overwrite {it:filename} if it exists{p_end}
{synoptline}
{p2colreset}{...}

{p 4 6 2}
{cmd:estat attgt} takes no options, and says so with return code 198 rather
than accepting one and ignoring it. {cmd:window()} must be spelled in full.
{cmd:dropmissing} is accepted only on {cmd:event} and on the four
{it:aggregation} subcommands, which are the subcommands that aggregate.
{cmd:estat} may be used only after {cmd:csdid}; the aggregation itself is
computed by {helpb csdid_stats}.{p_end}

{p 4 6 2}
The standard {cmd:estat} subcommands {cmd:vce}, {cmd:summarize}, {cmd:ic}, and
{cmd:bootstrap} are passed through to Stata; see
{help csdid_estat##standard:Standard estat subcommands}. Any other subcommand
is refused with return code 498 and a list of the supported ones.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:estat} after {cmd:csdid} displays results, posts them for Stata's
inference commands, and exports them to datasets.

{pstd}
{cmd:estat attgt} redisplays the group-time ATT(g,t) table exactly as
{cmd:csdid} produced it.

{pstd}
{cmd:estat event} reports the event study as a coefficient vector: one
coefficient per event time present in the data, including the e = -1 reference
period, plus {cmd:Post_avg}, the average of the post-treatment event-time
effects. Standard errors, tests, and confidence intervals are in
{cmd:r(table)}.

{pstd}
{cmd:estat simple}, {cmd:estat group}, {cmd:estat calendar}, and
{cmd:estat dynamic} compute the corresponding aggregation with
{helpb csdid_stats} and display its table: one row per aggregated effect with
its standard error, and the overall effect and its standard error repeated in
the last two columns of every row. {cmd:estat dynamic} and
{cmd:estat event} are the same aggregation shown two ways -- a table of effects
and standard errors, or a posted coefficient vector.

{pstd}
{cmd:estat tidy} and {cmd:estat glance} write a Stata dataset of estimates and
of model metadata, in a tidy column layout suited to tables and reporting.
{helpb csdid_plot} exports plot-ready data.


{marker options}{...}
{title:Options}

{dlgtab:Main}

{marker opt_window}{...}
{phang}
{opt window(min max)} restricts the aggregation to event times {it:min}
through {it:max}. The window is applied by recomputing the aggregation over the
requested range, not by hiding rows of a wider one, so the reported overall
effect ({cmd:Post_avg} for {cmd:event}) is the overall effect of the windowed
event times. Both bounds must be numeric. See
{help csdid_estat##window:Event windows} for what is refused.

{marker opt_post}{...}
{phang}
{opt post} leaves the aggregated effects in {cmd:e(b)} and {cmd:e(V)}, so that
{helpb test}, {helpb lincom}, {helpb estimates store}, and table-building
commands operate on the aggregation rather than on the ATT(g,t) cells. It works
on {cmd:event} and on all four aggregations; the coefficient names are listed
under {help csdid_estat##post:Posting the aggregation}. Without {cmd:post},
every one of the five restores the coefficient vector that was posted before it
ran, so a display-only aggregation never changes what {cmd:test} or
{cmd:lincom} would act on.

{marker opt_level}{...}
{phang}
{opt level(#)} sets the confidence level of the reported interval. When it is
not specified, the level of the {cmd:csdid} call is used. The level reaches
the band under bootstrap inference as well as
under analytical inference, because the aggregation is recomputed; see
{help csdid_estat##level:Confidence levels}.

{marker opt_dropmissing}{...}
{phang}
{opt dropmissing} drops ATT(g,t) cells whose estimate is missing before
aggregating. It is forwarded to
{helpb csdid_stats##opt_dropmissing:csdid_stats} and means there exactly what it
means there. Without it, a missing cell stops the aggregation with return code
498 and a message naming the option, on {cmd:estat event} as on the other four
aggregation subcommands.

{dlgtab:Export}

{phang}
{opt saving(filename)} names the dataset to write. It is required by
{cmd:tidy} and {cmd:glance}; without it they exit with return code 198 rather
than printing something that cannot be saved.

{phang}
{opt replace} allows {cmd:saving()} to overwrite an existing file.


{marker remarks}{...}
{title:Remarks}

{pstd}
Remarks are presented under the following headings:

{p2colset 8 44 46 2}{...}
{p2col:{help csdid_estat##which:Which subcommand to use}}{p_end}
{p2col:{help csdid_estat##window:Event windows}}{p_end}
{p2col:{help csdid_estat##post:Posting the aggregation}}{p_end}
{p2col:{help csdid_estat##level:Confidence levels}}{p_end}
{p2col:{help csdid_estat##export:Exported datasets}}{p_end}
{p2col:{help csdid_estat##standard:Standard estat subcommands}}{p_end}
{p2colreset}{...}

{marker which}{...}
{title:Which subcommand to use}

{pstd}
The aggregations themselves, and the parameter each one estimates, are
documented in {helpb csdid_stats##types:csdid_stats}. This command decides only
how the numbers reach you.

{p2colset 8 30 32 2}{...}
{p2col:{bf:Command}}{bf:What you get}{p_end}
{p2col:{cmd:estat attgt}}the ATT(g,t) table{p_end}
{p2col:{cmd:estat event}}event-study coefficients and {cmd:Post_avg};
{cmd:r(table)} carries the standard errors{p_end}
{p2col:{cmd:estat dynamic}}the same aggregation as a table of effects and
standard errors{p_end}
{p2col:{cmd:estat simple}}one overall effect{p_end}
{p2col:{cmd:estat group}}one effect per treatment cohort, plus the overall
effect{p_end}
{p2col:{cmd:estat calendar}}one effect per period, plus the overall
effect{p_end}
{p2col:{cmd:csdid_stats}}the same four aggregations with the full option set,
including {cmd:balance()} and saved-influence-function input{p_end}
{p2colreset}{...}

{pstd}
Four behaviors follow from the fact that these subcommands compute rather than
replay:

{phang}
{cmd:estat event} and the four {it:aggregation} subcommands always recompute.
None of them reuses an aggregation that happens to be sitting in {cmd:e()}, so
the options you type on the command you type are the options the reported
numbers were computed under -- including {cmd:level()}, which under bootstrap
inference could otherwise be answered with a band computed at some earlier
level, and {cmd:window()}, which {cmd:csdid_stats} does not record in
{cmd:e()} and which therefore cannot be detected as stale. The price is one
aggregation per command; the guarantee is that {cmd:estat event} and
{cmd:estat dynamic} can never disagree.

{phang}
Recomputing is exactly reproducible, bootstrap inference included. The
multiplier draws come from the random-number state {cmd:csdid} stored at
estimation time ({cmd:e(boot_rng_state)}, or {cmd:e(boot_seed)}), which survives
posting, so repeated aggregations of one estimation are bit-identical to each
other and to the same aggregation computed immediately after estimating.

{phang}
Each one replaces the active aggregation in {cmd:e()}. Running
{cmd:estat group} and then {cmd:estat event} leaves the dynamic aggregation
active, and {cmd:e(agg_type)} says which one it is. {cmd:e(attgt)} and the
estimation results are never disturbed, so {cmd:estat attgt} always shows the
ATT(g,t) table.

{phang}
Missing ATT(g,t) cells stop every one of them, {cmd:estat event} included. If
any cell of {cmd:e(attgt)} is missing, {cmd:estat event},
{cmd:estat simple}, {cmd:estat group}, {cmd:estat calendar}, and
{cmd:estat dynamic} stop with return code 498 and tell you to drop them, which
you do with {cmd:dropmissing} on the same command, as in
{cmd:estat event, dropmissing}, or with {cmd:csdid_stats} {it:type}{cmd:,}
{cmd:dropmissing}. A missing cell is a signal that some (g,t) comparison could
not be estimated, so it should be seen before it is averaged away. {cmd:tidy}
and {cmd:glance} export an aggregation rather than computing one, so they do not
accept {cmd:dropmissing}; specify it on the aggregation before exporting.

{marker window}{...}
{title:Event windows}

{pstd}
{cmd:window()} is forwarded to {helpb csdid_stats##opt_window:csdid_stats}, so
it behaves exactly as it does there -- including the fact that on
{cmd:estat simple} and {cmd:estat group} only the upper bound bites, by
restricting which post-treatment cells are averaged. The reported overall
effect is recomputed over the window, and the coefficient vector covers exactly
the event times present in the data. No
coefficient is fabricated for an event time that does not exist, and none is
given a zero variance to fill a gap in the grid.

{pstd}
A window that leaves no event time at all, that is reversed, or that contains
only pre-treatment event times is refused with return code 498. In the example
below, whose event times run from -3 to 3, both
{cmd:estat event, window(5 8)} and {cmd:estat event, window(-3 -1)} stop with a
message naming the empty window rather than reporting an average of nothing.

{marker post}{...}
{title:Posting the aggregation}

{pstd}
{cmd:post} replaces {cmd:e(b)} and {cmd:e(V)} with the aggregated effects, on
every subcommand that computes one. Coefficient names are:

{p2colset 8 30 32 2}{...}
{p2col:{cmd:estat event}}{cmd:Tm}{it:#} for event time -{it:#}, {cmd:Tp}{it:#}
for event time {it:#}, and {cmd:Post_avg}{p_end}
{p2col:{cmd:estat dynamic}}the same names as {cmd:estat event}{p_end}
{p2col:{cmd:estat group}}{cmd:G}{it:#} per cohort, and {cmd:Overall}{p_end}
{p2col:{cmd:estat calendar}}{cmd:T}{it:#} per period, and {cmd:Overall}{p_end}
{p2col:{cmd:estat simple}}{cmd:ATT}{p_end}
{p2colreset}{...}

{pstd}
The event-time coefficient vector includes the e = -1 reference period, whose
effect is an estimated placebo and not identically zero. The posted covariance
matrix is not diagonal:
it is built from the influence functions of the aggregated effects, or from the
bootstrap draws under bootstrap inference, so {cmd:test} and {cmd:lincom}
account for the correlation between event times.

{pstd}
{cmd:post} displays nothing. Use {cmd:estat event} or {cmd:estat} {it:type}
without {cmd:post} to see the table, or read {cmd:r(table)}, or run
{cmd:lincom} on the coefficient you care about. After {cmd:post}, an ordinary
{cmd:estimates store} keeps the aggregation, so several aggregations can be
stored side by side and compared.

{pstd}
{cmd:r(table)} is filled on all five aggregation routes whether or not
{cmd:post} is given, and it always describes the aggregation just computed. It
is never left holding an earlier aggregation's numbers: if the command you typed
fails or posts nothing, {cmd:r(table)} is cleared rather than left standing.

{marker level}{...}
{title:Confidence levels}

{pstd}
Under analytical inference the interval always follows the level in force: the
estimation level, or the level requested with {cmd:level()}.

{pstd}
Under the default multiplier bootstrap the interval uses the bootstrap critical
value in {cmd:e(crit_val)}, which the aggregation bootstrap produces at the
level in force when the aggregation is computed. Because {cmd:estat} recomputes
the aggregation whenever it is asked for one, the level you type is the level
the band is computed at, on the first request and on every later one. After a
seeded estimation, {cmd:estat event, level(90)} and then
{cmd:estat event, level(99)} report two different critical values, and the
second is the value a fresh estimation followed by
{cmd:estat event, level(99)} reports -- measured, on the same data and seed,
{cmd:e(crit_val)} 1.8781945 then 2.6979590, with the fresh run also giving
2.6979590. A narrower or wider {cmd:window()} likewise recomputes the band over
the event times that survive it.

{pstd}
Re-levelling is exact rather than approximate because the recomputation redraws
from the multiplier state {cmd:csdid} stored at estimation time, not from a
fresh random-number stream. The band you get by re-levelling is therefore the
band you would have got by estimating again at that level, not an approximation
to it.

{pstd}
One consequence is worth stating because it is what users check: everything that
reads the level agrees. {cmd:e(agg_level)}, {cmd:r(table)}, the displayed
interval, {cmd:estat tidy}, and {helpb csdid_plot} all describe the level of the
aggregation you last asked for, not of some earlier one.

{marker export}{...}
{title:Exported datasets}

{pstd}
{cmd:estat tidy} and {cmd:estat glance} describe the active result. If an
aggregation is active they export the aggregation; otherwise they export the
ATT(g,t) estimates. To export ATT(g,t) after having computed an aggregation,
re-run {cmd:csdid}.

{pstd}
{cmd:estat tidy} after estimation writes one row per ATT(g,t) cell with
{cmd:term} (the label {cmd:ATT(}{it:g}{cmd:,}{it:t}{cmd:)}), {cmd:group},
{cmd:time}, {cmd:estimate}, {cmd:std_error}, {cmd:statistic}, {cmd:p_value},
{cmd:conf_low}, {cmd:conf_high}, {cmd:point_conf_low}, and
{cmd:point_conf_high}. The {cmd:conf_*} columns use the reported critical value
-- simultaneous under the default bootstrap -- and the {cmd:point_conf_*}
columns use the pointwise one, so both bands are available without recomputing.

{pstd}
{cmd:estat tidy} after an aggregation writes one row per aggregated effect,
with a leading {cmd:type} column naming the aggregation and the same estimate
columns. The row identifier follows the aggregation: {cmd:event_time} for
{cmd:dynamic}, {cmd:time} for {cmd:calendar}, {cmd:group} for {cmd:group}, and
{cmd:term} alone for {cmd:simple}. The {cmd:group} export adds a final
{cmd:ATT(Average)} row, sorted first, holding the overall effect.

{pstd}
{cmd:estat glance} writes a single row of model metadata: {cmd:nobs} (units),
{cmd:ngroup}, {cmd:ntime}, {cmd:control_group}, and {cmd:est_method}, preceded
by {cmd:type} when an aggregation is active.

{pstd}
Both exports are silent on success. The scratch dataset each one builds is put
together quietly, so a successful export prints no observation-count notices and
raises no {cmd:more} prompt; the data in memory are restored unchanged. Refusals
are still displayed.

{pstd}
Because Stata variable names cannot contain dots, the tidy column names
({cmd:std.error}, {cmd:p.value}, {cmd:conf.low}, {cmd:conf.high},
{cmd:point.conf.low}, {cmd:point.conf.high}, {cmd:control.group},
{cmd:est.method}) are carried as variable labels.

{marker standard}{...}
{title:Standard estat subcommands}

{pstd}
{cmd:estat} after {cmd:csdid} is not a closed menu. The standard subcommands
{cmd:vce}, {cmd:summarize}, {cmd:ic}, and {cmd:bootstrap} are handed to Stata's
own {cmd:estat} implementation, with their own options, so
{cmd:estat vce, format(%9.4f)} works exactly as it does after any other
estimation command. What each one does after {cmd:csdid} follows from what
{cmd:csdid} stores:

{p2colset 8 32 34 2}{...}
{p2col:{cmd:estat vce}}displays {cmd:e(V)}: the covariance matrix of the
ATT(g,t) cells, or of the aggregated effects after {cmd:post}{p_end}
{p2col:{cmd:estat summarize}}refuses:
{it:e(sample) information not available}, because {cmd:csdid} does not set
{cmd:e(sample)}{p_end}
{p2col:{cmd:estat ic}}refuses: {cmd:csdid} is not likelihood based and stores no
{cmd:e(ll)}{p_end}
{p2col:{cmd:estat bootstrap}}refuses: {cmd:csdid}'s multiplier bootstrap is not
Stata's {helpb bootstrap} prefix and leaves none of its results{p_end}
{p2colreset}{...}

{pstd}
The three refusals are Stata's own, not a csdid restriction, and they name the
result that is absent. A subcommand that is neither one of these nor one of
{cmd:csdid}'s is refused with return code 498 and a list of the supported
subcommands, rather than with Stata's generic "not valid" message.

{pstd}
Two option mistakes are also named rather than lumped together. An option
{cmd:estat} does not have -- a graph-styling option, say -- exits with
{it:unsupported option(s):} and return code 198; an option typed twice, as in
{cmd:estat event, window(-1 1) window(0 1)}, exits with
{it:option(s) specified more than once:} and return code 198, so the message
names the real fault instead of telling you to remove a supported option. A bare
{cmd:csdid_estat} with no subcommand lists the subcommands.


{marker examples}{...}
{title:Examples}

{pstd}
The examples use the county-level teen-employment panel of Callaway and
Sant'Anna (2021). Loading it requires an internet connection.

{pstd}{bf:Setup}{p_end}
{phang2}{cmd:. use "http://fmwww.bc.edu/repec/bocode/m/mpdta.dta", clear}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat)}{p_end}

{pstd}{bf:The estimated cells, then the four summaries}{p_end}
{phang2}{cmd:. estat attgt}{p_end}
{phang2}{cmd:. estat simple}{p_end}
{phang2}{cmd:. estat group}{p_end}
{phang2}{cmd:. estat calendar}{p_end}
{phang2}{cmd:. estat event}{p_end}

{pstd}{bf:Event study restricted to a window}{p_end}
{phang2}{cmd:. estat event, window(-3 3)}{p_end}

{pstd}{bf:Change the confidence level; the band is recomputed, not reused}{p_end}
{phang2}{cmd:. estat event, level(90)}{p_end}
{phang2}{cmd:. display e(crit_val), e(agg_level)}{p_end}
{phang2}{cmd:. estat event, level(99)}{p_end}
{phang2}{cmd:. display e(crit_val), e(agg_level)}{p_end}

{pstd}{bf:Aggregate when some ATT(g,t) cells could not be estimated}{p_end}
{phang2}{cmd:. estat event, dropmissing}{p_end}

{pstd}{bf:Post the event study, then test and combine coefficients}{p_end}
{phang2}{cmd:. estat event, post}{p_end}
{phang2}{cmd:. matrix list r(table)}{p_end}
{phang2}{cmd:. test Tm3 = Tm2 = 0}{p_end}
{phang2}{cmd:. lincom (Tp0 + Tp1)/2}{p_end}

{pstd}{bf:Store two aggregations and compare them}{p_end}
{phang2}{cmd:. estat group, post}{p_end}
{phang2}{cmd:. estimates store bycohort}{p_end}
{phang2}{cmd:. estat calendar, post}{p_end}
{phang2}{cmd:. estimates store bycalendar}{p_end}
{phang2}{cmd:. estimates table bycohort bycalendar, se}{p_end}

{pstd}{bf:Export results}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat)}{p_end}
{phang2}{cmd:. estat tidy, saving(attgt_tidy) replace}{p_end}
{phang2}{cmd:. estat glance, saving(model_summary) replace}{p_end}
{phang2}{cmd:. estat event}{p_end}
{phang2}{cmd:. estat tidy, saving(event_tidy) replace}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:estat attgt} stores nothing; it displays {cmd:e(attgt)}.

{pstd}
{cmd:estat event} and {cmd:estat} {it:aggregation} compute the aggregation with
{helpb csdid_stats} and therefore store everything
{helpb csdid_stats##results:csdid_stats} stores, including {cmd:e(aggte)},
{cmd:e(agg_inffunc)}, {cmd:e(agg_type)}, {cmd:e(agg_level)},
{cmd:e(crit_val)}, and {cmd:e(point_crit_val)}. In addition, they store the
following in {cmd:e()}:

{synoptset 26 tabbed}{...}
{p2col 5 26 29 2: Matrices}{p_end}
{synopt:{cmd:e(b)}}aggregated effects, when {cmd:post} is specified (and,
transiently, whenever {cmd:estat event} builds its table){p_end}
{synopt:{cmd:e(V)}}covariance matrix of the aggregated effects, from their
influence functions or from the bootstrap draws{p_end}
{p2colreset}{...}

{pstd}
and the following in {cmd:r()}:

{synoptset 26 tabbed}{...}
{p2col 5 26 29 2: Matrices}{p_end}
{synopt:{cmd:r(table)}}estimate, standard error, z, p-value, confidence limits,
and critical value for each posted effect{p_end}
{p2colreset}{...}

{pstd}
{cmd:r(table)} is an {cmd:r()} result like any other: read or copy it
immediately, because the next command that returns in {cmd:r()} -- including
{cmd:lincom} and {cmd:test} -- replaces it.

{pstd}
{cmd:e(cmd)} remains {cmd:csdid} and {cmd:e(attgt)}, {cmd:e(group_prob)},
{cmd:e(inffunc)} and the estimation macros and scalars are preserved across
posting, so aggregation and estimation results can be read from the same
{cmd:e()}.

{pstd}
{cmd:estat tidy} and {cmd:estat glance} store nothing; they write the dataset
named in {cmd:saving()}.

{pstd}
{cmd:predict} and {cmd:margins} are not supported after {cmd:csdid}. The posted
coefficients are group-time or aggregated treatment effects, not coefficients
on variables in the data, and no prediction is defined for them. Both refuse by
name -- {cmd:predict} with return code 198 and {cmd:margins} with return code
322 -- rather than failing on an internal coefficient name.
{helpb test}, {helpb lincom}, {helpb nlcom}, {helpb predictnl}, and
{helpb estimates} all work on what is posted; the complete list is in
{helpb csdid_postestimation##commands:csdid postestimation}.


{marker acknowledgments}{...}
{title:Acknowledgments}

{phang}
The R package {bf:did}, by Brantly Callaway and Pedro H.C. Sant'Anna, is the
reference implementation of these methods. {cmd:csdid} derives from it and was
constructed and benchmarked against {bf:did} version 2.5.1.{p_end}


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


{marker authors}{...}
{title:Authors}

{pstd}
{cmd:csdid} is by Fernando Rios-Avila, Pedro H. C. Sant'Anna, and Brantly
Callaway. Full affiliations and contact addresses, the acknowledgments, how to
report a problem, and how to cite the package are in
{help csdid##authors:help csdid}.


{title:Also see}

{psee}
Online:  {helpb csdid}, {helpb csdid_postestimation:csdid postestimation},
{helpb csdid_stats}, {helpb csdid_plot}
{p_end}
