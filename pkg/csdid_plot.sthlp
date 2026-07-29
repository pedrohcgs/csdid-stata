{smcl}
{* *! version 2.0.0 26jul2026}{...}
{vieweralsosee "csdid" "help csdid"}{...}
{vieweralsosee "csdid postestimation" "help csdid_postestimation"}{...}
{vieweralsosee "csdid_stats" "help csdid_stats"}{...}
{vieweralsosee "csdid_estat" "help csdid_estat"}{...}
{vieweralsosee "" "--"}{...}
{vieweralsosee "[G-2] graph twoway" "help twoway"}{...}
{vieweralsosee "[G-2] graph twoway rcap" "help twoway_rcap"}{...}
{vieweralsosee "[G-2] graph twoway rarea" "help twoway_rarea"}{...}
{vieweralsosee "[G-3] by_option" "help by_option"}{...}
{viewerjumpto "Syntax" "csdid_plot##syntax"}{...}
{viewerjumpto "Description" "csdid_plot##description"}{...}
{viewerjumpto "Options" "csdid_plot##options"}{...}
{viewerjumpto "Remarks" "csdid_plot##remarks"}{...}
{viewerjumpto "Plot-data schema" "csdid_plot##schema"}{...}
{viewerjumpto "Notes on the exported series" "csdid_plot##plotnotes"}{...}
{viewerjumpto "Relationship to legacy Stata csdid Version 1.82" "csdid_plot##legacy"}{...}
{viewerjumpto "Examples" "csdid_plot##examples"}{...}
{viewerjumpto "Stored results" "csdid_plot##results"}{...}
{viewerjumpto "Diagnostics" "csdid_plot##errors"}{...}
{viewerjumpto "References" "csdid_plot##references"}{...}
{viewerjumpto "Authors" "csdid_plot##authors"}{...}
{title:Title}

{p2colset 5 20 22 2}{...}
{p2col :{cmd:csdid_plot} {hline 2}}Export plot data from {cmd:csdid} group-time
average treatment effects{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 15 2}
{cmd:csdid_plot}{cmd:,} {opth sav:ing(filename)} [{opt replace} {opt group(numlist)}]

{pstd}
The same syntax exports two different things. Run directly after {cmd:csdid},
it exports ATT(g,t) plot data; run after an aggregation has been computed with
{helpb csdid_stats} or {helpb csdid_estat}, it exports plot data for that
aggregation. See {help csdid_plot##description:Description}.

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main}
{synopt :{opth sav:ing(filename)}}name of the plot-data dataset to write; required{p_end}
{synopt :{opt replace}}overwrite {it:filename} if it already exists{p_end}

{syntab:Selection {help csdid_plot##opt_group:[+]}}
{synopt :{opt group(numlist)}}restrict the exported rows to the listed treatment
cohorts; applies to ATT(g,t) and group-type aggregation plots only{p_end}
{synoptline}
{p2colreset}{...}

{p 4 6 2}
{cmd:csdid_plot} is a postestimation command and requires results from
{helpb csdid} in {cmd:e()}.{p_end}
{p 4 6 2}
No other options are accepted; graph-styling options are rejected with an error.
See {help csdid_plot##remarks:Remarks}.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:csdid_plot} writes a small Stata dataset containing everything needed to
draw a Callaway and Sant'Anna (2021) event-study or group-time plot: the point
estimates, the confidence-band bounds, the x-axis values, and pre-/post-treatment
labels. It does not draw a graph and it does not impose a graph style. You draw
the picture yourself with {helpb twoway} (or any other tool), which means the
appearance of the figure is entirely under your control and the numbers behind
it are inspectable, storable, and reproducible.

{pstd}
Which plot data are written depends on what is currently in {cmd:e()}:

{p2colset 5 40 42 2}{...}
{p2col :{it:what is in e()}}{it:what is exported}{p_end}
{p2line}
{p2col :{cmd:csdid} results, no aggregation}ATT(g,t) by cohort and calendar period{p_end}
{p2col :{cmd:type(dynamic)} aggregation}event study: ATT by length of exposure{p_end}
{p2col :{cmd:type(group)} aggregation}ATT by treatment cohort{p_end}
{p2col :{cmd:type(calendar)} aggregation}ATT by calendar period{p_end}
{p2col :{cmd:type(simple)} aggregation}nothing; {cmd:csdid_plot} exits with error 498{p_end}
{p2line}
{p2colreset}{...}

{pstd}
The rule is mechanical: if the matrix {cmd:e(aggte)} is present, the active
aggregation is exported; otherwise the ATT(g,t) table {cmd:e(attgt)} is
exported. {cmd:e(aggte)} is posted by {helpb csdid_stats}, by
{cmd:estat dynamic}/{cmd:group}/{cmd:calendar}/{cmd:event} (see
{helpb csdid_estat}), and by {cmd:csdid, agg(event)}. To go back to the
ATT(g,t) plot after an aggregation, rerun {cmd:csdid}.

{pstd}
{cmd:csdid_plot} does not modify the data in memory (it uses {helpb preserve}
and {helpb restore}) and does not modify {cmd:e()}.


{marker options}{...}
{title:Options}

{dlgtab:Main}

{phang}
{opth sav:ing(filename)} is required. It names the Stata dataset that
{cmd:csdid_plot} writes; {cmd:.dta} is added if {it:filename} has no extension.

{pmore}
Both spellings of {cmd:replace} work. {cmd:csdid_plot, saving(myplot) replace}
is the documented form, and the more common Stata idiom
{cmd:saving(myplot, replace)} is parsed as well, so a comma inside
{cmd:saving()} can no longer end up as part of the filename.
{cmd:replace} is the only sub-option {cmd:saving()} accepts; anything else after
the comma is refused by name with return code 198, as is a comma with no
filename in front of it.

{phang}
{opt replace} permits {cmd:csdid_plot} to overwrite an existing
{it:filename}. Without it, writing over an existing file fails with the usual
"file already exists" error, return code 602.

{marker opt_group}{...}
{dlgtab:Selection}

{phang}
{opt group(numlist)} restricts the exported rows to the listed treatment
cohorts, that is, to the listed values of the {cmd:gvar()} variable. It is
useful when a design has many cohorts and you want one figure per subset.

{phang2}
On the ATT(g,t) export, {cmd:group()} keeps the rows whose {cmd:group} value is
in {it:numlist}.

{phang2}
On a {cmd:type(group)} aggregation export, {cmd:group()} keeps the rows whose
cohort is in {it:numlist}.

{phang2}
On {cmd:type(dynamic)} and {cmd:type(calendar)} aggregation exports,
{cmd:group()} is not meaningful - those aggregations have no cohort dimension
left - and {cmd:csdid_plot} says so out loud:

{pmore2}
{it:group() applies to group-type aggregations; ignored for the dynamic aggregation plot.}

{phang2}
If none of the requested cohorts exists in the results, {cmd:csdid_plot} does
not fail and does not write an empty dataset. It reports

{pmore2}
{it:Some of the specified groups do not exist in the data. Reporting all available groups.}

{pmore}
and exports every available cohort.


{marker remarks}{...}
{title:Remarks}

{pstd}
{cmd:csdid_plot} exports plot {it:data}, not a graph. That is a deliberate
design choice, and it has three consequences worth stating plainly.

{phang}
{bf:1. No graph is drawn and no styling option is accepted.} Options such as
{cmd:title()}, {cmd:xtitle()}, {cmd:legend()}, {cmd:name()}, {cmd:style()}, or
{cmd:color()} are rejected with

{pmore}
{it:unsupported option(s): ...}

{pmore}
and return code 198. Pass those options to {helpb twoway} instead, when you draw
the exported data. Nothing about the appearance of a csdid figure is baked into
this package.

{phang}
{bf:2. The exported numbers are the numbers.} Every quantity a reader would see
in the figure - point estimate, lower bound, upper bound, and whether the
interval excludes zero - is a variable in the dataset, so a referee, a coauthor,
or your future self can check the figure against the estimates without
reverse-engineering a graph.

{phang}
{bf:3. The bounds inherit the inference you asked for.}
{cmd:ci_low} is {cmd:estimate - c*se} and {cmd:ci_high} is
{cmd:estimate + c*se}, where {cmd:c} is the critical value {cmd:csdid} or
{cmd:csdid_stats} already computed at estimation time:

{p2colset 5 38 40 2}{...}
{p2col :{it:inference requested}}{it:the critical value c}{p_end}
{p2line}
{p2col :bootstrap with bands (default)}{cmd:e(crit_val)}, the simultaneous
(uniform) critical value{p_end}
{p2col :bootstrap with {cmd:pointwise}}{cmd:e(crit_val)}, which under
{cmd:pointwise} is the normal quantile{p_end}
{p2col :{cmd:analytical}, {cmd:vce(analytical)}}the normal quantile at the
reported confidence level{p_end}
{p2line}
{p2colreset}{...}

{pmore}
Exactly: the ATT(g,t) export uses {cmd:e(crit_val)} (falling back to the normal
quantile at {cmd:e(level)} if it is missing). An aggregation export uses
{cmd:e(crit_val)} when the estimation used the bootstrap, and otherwise the
normal quantile at {cmd:e(agg_level)}, the level the aggregation itself
reported. That distinction matters only if you asked for a {cmd:level()}
different from the estimation level under analytical inference.

{pmore}
Either way, the exported band is the band of the aggregation that is active
when {cmd:csdid_plot} runs, at the level that aggregation reported. Because
{helpb csdid_stats} and {helpb csdid_estat} recompute the aggregation every
time -- bootstrap inference included -- re-running the aggregation at a
different {cmd:level()} and exporting again gives a band at the new level, not
the old one.

{pmore}
Because the csdid default is a multiplier bootstrap with simultaneous bands, by
default the exported interval is a {it:uniform} band that covers all reported
effects simultaneously with probability {cmd:e(level)}/100 - it is wider than a
pointwise 95% interval, and {cmd:significant} therefore marks
uniform-band significance, not a pointwise test. If you want pointwise
intervals in the figure, estimate with {cmd:pointwise} (see {helpb csdid}), or
export {cmd:estat tidy} (see {helpb csdid_estat}), which reports both the band
bounds and the pointwise bounds along with standard errors and p-values.

{pstd}
Standard errors, p-values, the overall aggregated ATT, and the treated/control
cell counts are {it:not} in the plot dataset; they are one command away in
{cmd:estat tidy}, {cmd:e(attgt)}, and {cmd:e(aggte)}.


{marker schema}{...}
{title:Plot-data schema}

{pstd}
The exported dataset always has exactly these eleven variables, in this order.
The schema is identical for all plot types, so the same graph code can be reused
across figures.

{synoptset 16 tabbed}{...}
{synopthdr:variable}
{synoptline}
{synopt :{cmd:plot_type}}{cmd:str24}; which export this is: {cmd:attgt},
{cmd:aggte_dynamic}, {cmd:aggte_group}, or {cmd:aggte_calendar}{p_end}
{synopt :{cmd:series}}{cmd:str8}; {cmd:Pre} or {cmd:Post}; see the note
below{p_end}
{synopt :{cmd:x}}{cmd:double}; the x-axis value: calendar period ({cmd:attgt},
{cmd:aggte_calendar}), event time ({cmd:aggte_dynamic}), or treatment cohort
({cmd:aggte_group}){p_end}
{synopt :{cmd:x_label}}{cmd:str32}; {cmd:x} formatted as text, for use as an
axis label{p_end}
{synopt :{cmd:estimate}}{cmd:double}; the point estimate: ATT(g,t) or the
aggregated ATT{p_end}
{synopt :{cmd:ci_low}}{cmd:double}; {cmd:estimate - c*se}{p_end}
{synopt :{cmd:ci_high}}{cmd:double}; {cmd:estimate + c*se}{p_end}
{synopt :{cmd:group}}{cmd:double}; treatment cohort; filled for {cmd:attgt} and
{cmd:aggte_group}, missing otherwise{p_end}
{synopt :{cmd:time}}{cmd:double}; calendar period; filled for {cmd:attgt} and
{cmd:aggte_calendar}, missing otherwise{p_end}
{synopt :{cmd:event_time}}{cmd:double}; length of exposure, t minus g; filled
for {cmd:attgt} and {cmd:aggte_dynamic}, missing otherwise{p_end}
{synopt :{cmd:significant}}{cmd:byte}; 1 if the interval from {cmd:ci_low} to
{cmd:ci_high} excludes zero, 0 otherwise (also 0 when a bound is missing){p_end}
{synoptline}
{p2colreset}{...}

{phang}
{bf:series.} On the {cmd:attgt} export, {cmd:series} is {cmd:"Post"} when
{cmd:time >= group} and {cmd:"Pre"} otherwise. On aggregation exports it is
{cmd:"Post"} when {cmd:x >= 0}. That is exactly right for {cmd:aggte_dynamic},
where {cmd:x} is event time; but note that for {cmd:aggte_group} and {cmd:aggte_calendar}
{cmd:x} is a calendar year or cohort, so every row is labeled {cmd:"Post"} and
the variable carries no information. Use {cmd:series} for {cmd:attgt} and
{cmd:aggte_dynamic} plots; ignore it elsewhere.

{phang}
{bf:sort order.} The {cmd:attgt} export is sorted by {cmd:group} then
{cmd:time}; aggregation exports are sorted by {cmd:x}.

{phang}
{bf:omitted rows.} The exported rows are exactly the rows of {cmd:e(attgt)} or
{cmd:e(aggte)}: whatever window, {cmd:balance_e()}, or missing-value handling
you requested at the aggregation step is already reflected there. Nothing is
padded, and no zero-variance placeholder rows are invented for event times that
were not estimated.


{marker plotnotes}{...}
{title:Notes on the exported series}

{pstd}
{cmd:csdid_plot} writes a dataset rather than rendering a graph, so the styling
is yours: draw it with {cmd:twoway} and whatever theme, colors, reference line,
and {cmd:by(group)} faceting you prefer.

{phang2}
o {bf:Interval construction.} {cmd:ci_low} and {cmd:ci_high} are
{cmd:att - c*att.se} to {cmd:att + c*att.se}, using the critical value actually
applied by the estimation or aggregation being exported.{p_end}

{phang2}
o {bf:Pre/post labeling.} {cmd:series} is {cmd:"Post"} when
{cmd:time >= group} on {cmd:attgt} exports and when {cmd:x >= 0} on aggregation
exports.{p_end}

{phang2}
o {bf:type(simple) has no plot.} A simple aggregation is a single number, so
there is nothing to plot; {cmd:csdid_plot} exits with return code 498 and a
message saying so.{p_end}

{phang2}
o {bf:Unknown cohorts} named in {cmd:group()} are reported and the export falls
back to every available cohort.{p_end}

{phang2}
o {cmd:group()} is honored on {cmd:type(group)} aggregation exports as well as
on group-time exports, and {cmd:csdid_plot} reports when it is ignoring it.{p_end}

{marker legacy}{...}
{title:Relationship to legacy Stata csdid Version 1.82}

{pstd}
Legacy {cmd:csdid_plot} drew a graph directly and accepted styling options
({cmd:style()}, {cmd:title()}, {cmd:xtitle()}, {cmd:ytitle()}, {cmd:name()},
{cmd:color*}, {cmd:lwidth*}, {cmd:legend()}). Those options are
{bf:not accepted} here and are not silently ignored: they raise error 198. The
migration is mechanical - export the data, then pass your old styling options to
{cmd:twoway}. Instead of

{phang2}{cmd:. csdid_plot, group(2004) title("Cohort 2004")}{p_end}

{pstd}
write

{phang2}{cmd:. csdid_plot, saving(pd) replace group(2004)}{p_end}
{phang2}{cmd:. use pd, clear}{p_end}
{phang2}{cmd:. twoway (rcap ci_high ci_low x) (scatter estimate x), title("Cohort 2004")}{p_end}

{pstd}
{cmd:group()} keeps its legacy meaning (select treatment cohorts) and, unlike in
some legacy paths, it is now honored on group-type aggregation plots rather than
silently discarded. See {help csdid_postestimation} and
{it:docs/legacy-migration-guide.md}, distributed with the package source.


{marker examples}{...}
{title:Examples}

{pstd}{bf:Setup: a small staggered-adoption panel}{p_end}
{phang2}{cmd:. clear}{p_end}
{phang2}{cmd:. set seed 12345}{p_end}
{phang2}{cmd:. set obs 2000}{p_end}
{phang2}{cmd:. generate long id = ceil(_n/5)}{p_end}
{phang2}{cmd:. bysort id: generate int year = 2003 + _n}{p_end}
{phang2}{cmd:. generate int gvar = cond(id <= 160, 0, cond(id <= 280, 2005, 2007))}{p_end}
{phang2}{cmd:. generate byte treated = gvar > 0 & year >= gvar}{p_end}
{phang2}{cmd:. generate double x = rnormal()}{p_end}
{phang2}{cmd:. generate double y = .3*(year - 2003) + .5*treated}{p_end}
{phang2}{cmd:. replace y = y + .2*x + rnormal()}{p_end}

{pstd}{bf:Estimate, then export ATT(g,t) plot data}{p_end}
{phang2}{cmd:. csdid y x, ivar(id) time(year) gvar(gvar) ///}{break}
{cmd:         wboot(reps(200) rseed(20260726))}{p_end}
{phang2}{cmd:. csdid_plot, saving(attgt_plotdata) replace}{p_end}

{pstd}{bf:Export event-study (dynamic aggregation) plot data}{p_end}
{phang2}{cmd:. csdid_stats event, dropmissing}{p_end}
{phang2}{cmd:. csdid_plot, saving(event_plotdata) replace}{p_end}

{pstd}{bf:Export cohort (group aggregation) plot data for one cohort only}{p_end}
{phang2}{cmd:. csdid_stats group}{p_end}
{phang2}{cmd:. csdid_plot, saving(group_plotdata) replace group(2007)}{p_end}

{pstd}{bf:Inspect what was written}{p_end}
{phang2}{cmd:. use attgt_plotdata, clear}{p_end}
{phang2}{cmd:. describe}{p_end}
{phang2}{cmd:. list in 1/6, clean noobs}{p_end}

{pstd}{bf:Draw the group-time figure: one panel per cohort, pre and post distinguished}{p_end}
{phang2}{cmd:. use attgt_plotdata, clear}{p_end}
{phang2}{cmd:. twoway (rcap ci_high ci_low x if series == "Pre", lcolor(gs9)) ///}{break}
{cmd:         (scatter estimate x if series == "Pre", mcolor(gs9)) ///}{break}
{cmd:         (rcap ci_high ci_low x if series == "Post", lcolor(navy)) ///}{break}
{cmd:         (scatter estimate x if series == "Post", mcolor(navy)), ///}{break}
{cmd:         by(group, note("")) yline(0) xtitle("Calendar period") ///}{break}
{cmd:         ytitle("ATT(g,t)") ///}{break}
{cmd:         legend(order(2 "Pre-treatment" 4 "Post-treatment"))}{p_end}

{pstd}{bf:Draw the event study with a shaded band}{p_end}
{phang2}{cmd:. use event_plotdata, clear}{p_end}
{phang2}{cmd:. twoway (rarea ci_high ci_low x, color(navy%20)) ///}{break}
{cmd:         (connected estimate x, mcolor(navy) lcolor(navy)), ///}{break}
{cmd:         yline(0) xline(-0.5) xtitle("Event time") ytitle("ATT(e)") ///}{break}
{cmd:         legend(off)}{p_end}

{pstd}
The do-files in the {cmd:examples/} directory of the package source run the
same workflow end to end, including on the Callaway and Sant'Anna county
teen-employment data ({cmd:examples/06_mpdta_workflow.do}).


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:csdid_plot} stores nothing. It is not an {cmd:eclass} command: the
estimation results left by {cmd:csdid}, {cmd:csdid_stats}, or {cmd:estat} are
still in {cmd:e()} afterwards, unchanged, so you can export several plot
datasets in a row and then continue with other postestimation commands. The
data in memory are also unchanged.

{pstd}
Its output is the dataset named in {opt sav:ing()}, documented in
{help csdid_plot##schema:Plot-data schema} above.


{marker errors}{...}
{title:Diagnostics}

{p2colset 5 12 14 2}{...}
{p2col :{it:rc}}{it:condition and message}{p_end}
{p2line}
{p2col :{cmd:301}}No {cmd:csdid} results in {cmd:e()}:
{it:csdid_plot requires prior csdid results}{p_end}
{p2col :{cmd:198}}{opt sav:ing()} not specified:
{it:csdid_plot requires saving(filename). To export plot data, run:}
{it:csdid_plot, saving(filename) replace}{p_end}
{p2col :{cmd:198}}An option that is not {cmd:saving()}, {cmd:replace}, or
{cmd:group()} was given: {it:unsupported option(s): ...}{p_end}
{p2col :{cmd:198}}Something other than {cmd:replace} follows the comma in
{cmd:saving()}:
{it:saving() accepts only the replace sub-option; cannot parse: ...}{p_end}
{p2col :{cmd:198}}{cmd:saving()} has a comma but no filename before it:
{it:saving() requires a filename before the comma, as in saving(myfile, replace)}{p_end}
{p2col :{cmd:498}}The active aggregation is {cmd:type(simple)}:
{it:Plot method not available for this type of aggregation}{p_end}
{p2col :{cmd:602}}{it:filename} exists and {cmd:replace} was not specified{p_end}
{p2line}
{p2colreset}{...}

{pstd}
Two messages are notes, not errors: the {cmd:group()}-is-ignored note on
dynamic and calendar aggregation plots, and the fall-back-to-all-cohorts note
when no requested cohort exists. Both are described under
{help csdid_plot##opt_group:group()}.

{pstd}
A successful export prints nothing. The scratch-dataset work
{cmd:csdid_plot} does to build the file is silent, so neither observation-count
notices nor a {cmd:more} prompt interrupts the export; the notes above are the
only things it ever says on a run that succeeds.


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
{help csdid##authors:help csdid}. Please report anything that looks numerically
wrong with a reproducible example - the plot data are derived from
{cmd:e(attgt)} and {cmd:e(aggte)}, so include the {cmd:csdid} command line that
produced them.


{title:Also see}

{psee}
Online:  {helpb csdid}, {helpb csdid_postestimation}, {helpb csdid_stats},
{helpb csdid_estat}, {helpb twoway}
{p_end}
