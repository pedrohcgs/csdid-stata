{smcl}
{* *! version 2.0.0 25aug2026}{...}
{vieweralsosee "csdid" "help csdid"}{...}
{vieweralsosee "csdid_estat" "help csdid_estat"}{...}
{vieweralsosee "csdid_stats" "help csdid_stats"}{...}
{vieweralsosee "csdid_plot" "help csdid_plot"}{...}
{vieweralsosee "" "--"}{...}
{vieweralsosee "[R] estimates" "help estimates"}{...}
{vieweralsosee "[R] lincom" "help lincom"}{...}
{vieweralsosee "[R] test" "help test"}{...}
{viewerjumpto "Postestimation commands" "csdid_postestimation##commands"}{...}
{viewerjumpto "Description" "csdid_postestimation##description"}{...}
{viewerjumpto "Remarks" "csdid_postestimation##remarks"}{...}
{viewerjumpto "Examples" "csdid_postestimation##examples"}{...}
{viewerjumpto "Stored results" "csdid_postestimation##results"}{...}
{viewerjumpto "References" "csdid_postestimation##references"}{...}
{viewerjumpto "Authors" "csdid_postestimation##authors"}{...}
{title:Title}

{p2colset 5 30 32 2}{...}
{p2col:{bf:csdid postestimation} {hline 2}}Postestimation tools for
{cmd:csdid}{p_end}
{p2colreset}{...}


{marker commands}{...}
{title:Postestimation commands}

{pstd}
The following postestimation commands are available after {cmd:csdid}:

{synoptset 30 tabbed}{...}
{p2coldent :Command}Description{p_end}
{synoptline}
{synopt :{helpb csdid_estat##syntax:estat attgt}}display the group-time
ATT(g,t) table{p_end}
{synopt :{helpb csdid_estat##syntax:estat event}}display the event study as
coefficients, with {cmd:Post_avg}{p_end}
{synopt :{helpb csdid_estat##syntax:estat simple}}overall average treatment
effect on the treated{p_end}
{synopt :{helpb csdid_estat##syntax:estat group}}average effect by treatment
cohort{p_end}
{synopt :{helpb csdid_estat##syntax:estat calendar}}average effect by calendar
period{p_end}
{synopt :{helpb csdid_estat##syntax:estat dynamic}}average effect by event
time{p_end}
{synopt :{helpb csdid_estat##syntax:estat tidy}}write a dataset of estimates,
one row per ATT(g,t) cell or per aggregated effect{p_end}
{synopt :{helpb csdid_estat##syntax:estat glance}}write a single-row dataset of
model metadata{p_end}
{synopt :{helpb csdid_stats}}aggregation with the full option set, including
{cmd:balance()} and saved influence functions{p_end}
{synopt :{helpb csdid_plot}}draw the plot, or export plot-ready data for
user-controlled graphs{p_end}
{synoptline}
{p2colreset}{...}

{p 4 6 2}
{cmd:estat} {it:subcommand} may also be typed {cmd:csdid_estat}
{it:subcommand}. All aggregation subcommands accept {cmd:window()},
{cmd:post}, {cmd:level()}, and {cmd:dropmissing}; see {helpb csdid_estat}.
{cmd:estat attgt} accepts none of them and says so.{p_end}

{pstd}
Standard Stata postestimation commands that work after {cmd:csdid}:

{synoptset 30 tabbed}{...}
{p2coldent :Command}Description{p_end}
{synoptline}
{synopt :{helpb test}}Wald tests on the posted effects{p_end}
{synopt :{helpb testnl}}Wald tests of nonlinear hypotheses{p_end}
{synopt :{helpb lincom}}linear combinations of the posted effects{p_end}
{synopt :{helpb nlcom}}nonlinear combinations, with delta-method standard
errors{p_end}
{synopt :{helpb predictnl}}point estimates and standard errors of expressions in
the posted effects{p_end}
{synopt :{helpb estimates}}{cmd:store}, {cmd:restore}, {cmd:dir},
{cmd:describe}, {cmd:table}, {cmd:stats}, and {cmd:replay}{p_end}
{synopt :{cmd:csdid}}typed on its own, redisplays the stored results without
recomputing them; {cmd:level()} must be the level they were estimated at{p_end}
{synopt :{helpb estat_vce:estat vce}}display {cmd:e(V)}, with the usual
{cmd:estat vce} options{p_end}
{synopt :{helpb estat_summarize:estat summarize}}summarize the estimation
sample, off {cmd:e(sample)}{p_end}
{synoptline}
{p2colreset}{...}

{p 4 6 2}
All of these read {cmd:e(b)} and {cmd:e(V)}, so they act on the ATT(g,t) cells
immediately after {cmd:csdid} and on the aggregated effects after
{cmd:estat} {it:type}{cmd:, post}. {cmd:estimates stats} runs but reports
missing AIC and BIC, because {cmd:csdid} is not likelihood based.{p_end}

{pstd}
Standard postestimation commands that do {it:not} work after {cmd:csdid}, and
why:

{synoptset 30 tabbed}{...}
{p2coldent :Command}Why not{p_end}
{synoptline}
{synopt :{helpb predict}}{cmd:e(b)} holds treatment effects, not coefficients on
variables in the data: there is no linear index to score. Refused by name, rc
198{p_end}
{synopt :{helpb margins}}same reason; {cmd:csdid} sets
{cmd:e(marginsnotok)} {cmd:=} {cmd:_ALL}, so {cmd:margins} refuses with rc 322
instead of tabulating a meaningless margin{p_end}
{synopt :{helpb estat_ic:estat ic}, {helpb lrtest}}no likelihood: {cmd:csdid} is
a moment estimator and stores no {cmd:e(ll)}{p_end}
{synopt :{cmd:estat bootstrap}}{cmd:csdid}'s multiplier bootstrap is not the
{helpb bootstrap} prefix and leaves none of its results{p_end}
{synopt :{helpb contrast}, {helpb pwcompare}}the coefficients are not
factor-variable terms, so there is nothing to contrast{p_end}
{synoptline}
{p2colreset}{...}

{p 4 6 2}
The refusals in the second half of the table are Stata's own, raised by the
result that is missing; {cmd:predict} and {cmd:margins} are refused by
{cmd:csdid} itself, with a message that explains why rather than with an error
naming an internal coefficient.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:csdid} estimates one average treatment effect ATT(g,t) for each treatment
cohort g and each period t. That table is the primitive result; the summaries
people report -- an overall effect, an effect per cohort, an event study, a
calendar-time profile -- are weighted averages of those cells, computed after
estimation from the stored influence functions. The postestimation commands
compute those averages, post them for Stata's inference commands, and export
them.

{pstd}
Aggregating after estimation is not a convenience: it is how the method works.
The cells are estimated once, and every summary reuses their influence
functions, so all summaries are mutually consistent and their standard errors
account for the estimation of both the cell effects and the aggregation
weights.


{marker remarks}{...}
{title:Remarks}

{pstd}
Remarks are presented under the following headings:

{p2colset 8 42 44 2}{...}
{p2col:{help csdid_postestimation##session:A typical session}}{p_end}
{p2col:{help csdid_postestimation##choosing:Choosing an aggregation}}{p_end}
{p2col:{help csdid_postestimation##stata:Standard Stata postestimation}}{p_end}
{p2col:{help csdid_postestimation##export:Exporting results}}{p_end}
{p2colreset}{...}

{marker session}{...}
{title:A typical session}

{pstd}
Estimate once, then summarize as often as you like:

{phang2}{cmd:. net get csdid}{p_end}
{phang2}{cmd:. use mpdta, clear}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat)}{p_end}
{phang2}{cmd:. estat attgt}{p_end}
{phang2}{cmd:. estat event}{p_end}
{phang2}{cmd:. estat group}{p_end}
{phang2}{cmd:. estat event, post}{p_end}
{phang2}{cmd:. csdid_plot, saving(plotdata) replace}{p_end}

{pstd}
Estimate the cells; look at them; summarize them as an event study and by
cohort; post the event study so that {cmd:test} and {cmd:lincom} act on it;
export plot data.

{pstd}
Each aggregation subcommand recomputes from the same stored ATT(g,t) results
and replaces the active aggregation in {cmd:e()}; {cmd:e(agg_type)} says which
one is active, and the estimation results themselves are never disturbed.
{cmd:csdid} must have been run in the same session, because aggregation reads
the influence functions it left behind; use {cmd:csdid, saverif()} and
{helpb csdid_stats:csdid_stats using} to aggregate later or elsewhere.

{pstd}
"Recomputes" is literal: an {cmd:estat} aggregation never reuses one already in
{cmd:e()}, so the {cmd:window()}, {cmd:level()}, and {cmd:dropmissing} you type
are the ones the reported numbers were computed under, and asking for a
different confidence level really does give you a band at that level, bootstrap
inference included. Recomputation is reproducible to the bit, because the
multiplier draws come from the random-number state the estimation stored. See
{helpb csdid_estat##level:csdid_estat}.

{marker choosing}{...}
{title:Choosing an aggregation}

{pstd}
The four aggregations answer different questions and are described in full,
with their weights, in {helpb csdid_stats##types:csdid_stats}.

{p2colset 8 26 28 2}{...}
{p2col:{bf:Aggregation}}{bf:Question it answers}{p_end}
{p2col:{cmd:simple}}what was the average effect across all treated cells,
weighting cohorts by size{p_end}
{p2col:{cmd:group}}how much did each cohort gain over the time it was treated;
the overall effect weights cohorts by size{p_end}
{p2col:{cmd:dynamic}, {cmd:event}}how does the effect evolve with time since
treatment, and do pre-treatment effects look flat{p_end}
{p2col:{cmd:calendar}}how large was the effect in each calendar period, across
the cohorts already treated{p_end}
{p2colreset}{...}

{pstd}
Two cautions carry over from Callaway and Sant'Anna (2021). Effects at event
times e < 0 are placebo estimates of a maintained assumption, not treatment
effects, and the coefficient at e = -1 is reported like the others rather than
being pinned at zero. And a dynamic profile computed on the full sample changes
composition along the x-axis, since only early-treated cohorts reach long event
times; {helpb csdid_stats##balance:csdid_stats, balance()} holds the
composition fixed.

{marker stata}{...}
{title:Standard Stata postestimation}

{pstd}
Immediately after {cmd:csdid}, {cmd:e(b)} and {cmd:e(V)} hold the nonbase
ATT(g,t) cells, named cohort, period, and base period run together, as in
{cmd:g2004___2004_2003}. Specifying
{cmd:post} on any {cmd:estat} aggregation replaces them with the aggregated
effects, so {helpb test}, {helpb testnl}, {helpb lincom}, {helpb nlcom},
{helpb predictnl}, and {helpb estimates} then operate on the aggregation. This
is the supported way to test a hypothesis about a summary parameter, for
example that all pre-treatment event-time effects are zero.

{pstd}
{cmd:estimates store} and {cmd:estimates restore} round-trip whatever is
posted, so several aggregations of one estimation can be stored and tabulated
side by side; {cmd:e(agg_type)} is restored with them, so a restored set still
says which aggregation it is. {cmd:estat attgt} keeps working throughout, since
the estimation results themselves are never overwritten.

{pstd}
{cmd:estat vce} works too, and displays whichever {cmd:e(V)} is current. What
does not work, and why, is listed in the second table under
{help csdid_postestimation##commands:Postestimation commands}: the short version
is that {cmd:csdid} posts treatment effects rather than coefficients on
variables and has no likelihood, so {cmd:predict}, {cmd:margins},
{cmd:estat ic}, and {cmd:lrtest} have nothing to work from. Each refuses by
name. {cmd:estat summarize} works, off {cmd:e(sample)}.

{marker export}{...}
{title:Exporting results}

{pstd}
Two export routes write Stata datasets instead of printing:

{phang}
{cmd:saving(}{it:filename}{cmd:)} on any {cmd:estat} subcommand writes the
result that subcommand computed. {cmd:estat attgt, saving()} writes one row per
ATT(g,t) cell; {cmd:estat event, saving()} writes the event study; and so on for
{cmd:dynamic}, {cmd:simple}, {cmd:group} and {cmd:calendar}. Each row carries
the estimate, standard error, test statistic, p-value, and both the reported and
the pointwise confidence limits. Add {cmd:replace} to overwrite.

{phang}
{helpb csdid_plot} draws the ATT(g,t) plot or the active dynamic, group, or
calendar aggregation. With {cmd:saving()} it writes the plot data instead --
{cmd:plot_type}, {cmd:series}, {cmd:x}, {cmd:x_label}, {cmd:estimate},
{cmd:ci_low}, {cmd:ci_high}, the group/time/event-time identifiers, and
{cmd:significant} -- and draws nothing. That is how graph styling stays under
your control: the exported dataset is a normal Stata dataset that
{helpb twoway} can draw directly.

{pstd}
{cmd:saving()} exports what the subcommand computed, so put {cmd:window()},
{cmd:level()} and {cmd:dropmissing} on the subcommand itself and they are
reflected in the file. {cmd:estat attgt} accepts only {cmd:saving()} and
{cmd:replace}, because there is nothing about the stored ATT(g,t) table to
window, re-level or aggregate.

{pstd}
The event-time coefficient vector includes the e = -1 reference period, and no
coefficient is created for an event time that is absent from the data.


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

{pstd}{bf:Look at the cells, then summarize them four ways}{p_end}
{phang2}{cmd:. estat attgt}{p_end}
{phang2}{cmd:. estat simple}{p_end}
{phang2}{cmd:. estat group}{p_end}
{phang2}{cmd:. estat calendar}{p_end}
{phang2}{cmd:. estat event}{p_end}

{pstd}{bf:Event study on a window, then a composition-constant version}{p_end}
{phang2}{cmd:. estat event, window(-3 3)}{p_end}
{phang2}{cmd:. csdid_stats event, balance(1)}{p_end}

{pstd}{bf:Test the pre-treatment coefficients jointly}{p_end}
{phang2}{cmd:. estat event, window(-3 3) post}{p_end}
{phang2}{cmd:. test Tm3 = Tm2 = Tm1 = 0}{p_end}

{pstd}
The window is given here so that the coefficient names {cmd:Tm3}, {cmd:Tm2}
and {cmd:Tm1} are known to exist. Note that {cmd:estat} never inherits an
aggregation computed earlier: every {cmd:estat} aggregation recomputes from
the ATT(g,t) cells, and {cmd:balance()} is a {helpb csdid_stats} option that
{cmd:estat} does not accept and cannot forward. So the {cmd:balance(1)} line
above does not carry into the {cmd:estat event, post} that follows it -- the
posted event study is the unbalanced one. To test coefficients from a
balanced-event-time profile, run {cmd:csdid_stats event, balance(1)} and read
its table, or post from it with {cmd:_csdid_post event, post}.

{pstd}{bf:Export estimates, metadata, and plot data}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat)}{p_end}
{phang2}{cmd:. estat attgt, saving(attgt_cells) replace}{p_end}
{phang2}{cmd:. estat glance, saving(model_summary) replace}{p_end}
{phang2}{cmd:. estat event}{p_end}
{phang2}{cmd:. csdid_plot, saving(event_plotdata) replace}{p_end}

{pstd}{bf:Draw the event study from the exported data}{p_end}
{phang2}{cmd:. preserve}{p_end}
{phang2}{cmd:. use event_plotdata, clear}{p_end}
{phang2}{cmd:. twoway (rcap ci_high ci_low x) (scatter estimate x), yline(0) xline(-0.5)}{p_end}
{phang2}{cmd:. restore}{p_end}

{pstd}{bf:Aggregate a long estimation later, from saved influence functions}{p_end}
{phang2}{cmd:. csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) analytical saverif(mpdta_rif) replace}{p_end}
{phang2}{cmd:. csdid_stats using mpdta_rif, type(group)}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
Aggregation results are stored in {cmd:e()} by {helpb csdid_stats}, which lists
them in {helpb csdid_stats##results:its own Stored results section}. The
headline items are {cmd:e(aggte)} (the aggregation table), {cmd:e(agg_type)},
{cmd:e(agg_level)}, {cmd:e(crit_val)}, and, under {cmd:storeall},
{cmd:e(agg_inffunc)}.

{pstd}
With {cmd:post}, {cmd:e(b)} and {cmd:e(V)} hold the aggregated effects and
{cmd:r(table)} holds their standard errors, tests, and confidence limits; see
{helpb csdid_estat##results:csdid_estat}. Estimation results, including
{cmd:e(attgt)}, {cmd:e(group_prob)}, and the estimation macros and scalars,
survive every postestimation command, so {cmd:estat attgt} always shows the
cells no matter what has been aggregated or posted.

{pstd}
The estimation results themselves are documented in
{helpb csdid##results:help csdid}.


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
Online:  {helpb csdid}, {helpb csdid_estat}, {helpb csdid_stats},
{helpb csdid_plot}
{p_end}
