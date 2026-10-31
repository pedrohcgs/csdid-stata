---
title: "Speed against Version 1.82"
benchmark_version: 2.0.3
---

# Speed against Version 1.82

Version 1.82 is the last `csdid` before 2.0.0 (November 2025); SSC
distributes Version 1.81. The
[upgrading guide](upgrading-from-182.html) covers what changed in the
estimates; this page reports how long each version takes to produce them.
Our protocol is the median of 7 timed trials for 2.0.3 with one discarded
warmup; Version 1.82 uses a preset trial schedule of 7, 5, 3 or 2 trials
depending on the rung. Its million-row sample-size rung is skipped and
recorded when the projection from the measured 500,000-row call exceeds
120 seconds. Each version is invoked in its own syntax in its own
fresh Stata process, on identical data with one covariate, at seed 20260729
throughout. To keep the comparison
about speed alone, we pin 2.0.3 to Version 1.82's defaults in every cell
(never-treated comparison group, varying base
period, and pair balancing on unbalanced panels), so that both versions
compute the same numbers and differ only in how long they take. The
workload is a doubly robust event study with clustered standard errors
throughout (the same specification in every table below). Timings depend
on the machine they were taken on, so the ratios travel better than the
seconds do. All the timings on this page were measured on 31 October 2026 with StataNow/MP 19.5
on Mac (Apple Silicon) with 10 processors, in the same measurement campaign as the
[main speed tables](csdid-against-the-field.html#speed).

<div class="note" markdown="1">
Because 2.0.3 is pinned to the old defaults here, the times in the
2.0.3 column are not comparable to the shipped-defaults times in the
[main speed tables](csdid-against-the-field.html#speed), which run the
same engine under different estimand settings.
</div>

## By sample size

| n (T=10, G=4) | rows | 1.82 | 2.0.3 | gain |
| --- | ---: | ---: | ---: | ---: |
| 1,000 | 10,000 | 1.99s | 0.04s | 46x |
| 5,000 | 50,000 | 6.05s | 0.13s | 48x |
| 20,000 | 200,000 | 25.5s | 0.37s | 68x |
| 50,000 | 500,000 | 79.8s | 0.87s | **91x** |
| 100,000 | 1,000,000 | not run | 1.69s | &mdash; |

<p class="table-note" markdown="span">Version 1.82 was not timed in every cell &mdash; 100,000: skipped by the 120s cap; projection basis: measured 500k legacy call 79.7500s x 2.05 rows.</p>

The gain grows overall with the sample size, and then the comparison stops: at a
million rows, Version 1.82 projected past two and a half minutes per run,
so we did not run it and the last row reports 2.0.3 alone, which does the
same cell in 1.69 seconds.

## By number of periods

The number of periods is where the two versions differ most. Version
1.82's cost grows faster than linearly in the number of ATT(g,t) cells,
while 2.0.3's grows about linearly in them:

| T (n=5,000, G=4) | rows | 1.82 | 2.0.3 | gain |
| --- | ---: | ---: | ---: | ---: |
| 5 | 25,000 | 1.61s | 0.07s | 24x |
| 10 | 50,000 | 5.98s | 0.13s | 47x |
| 20 | 100,000 | 27.9s | 0.23s | 122x |
| 40 | 200,000 | 130.1s | 0.43s | **305x** |

At forty periods (a monthly panel over three and a half years), Version
1.82 takes over two minutes and 2.0.3 takes under half a second.

## By number of cohorts

| G (n=5,000, T=20) | rows | 1.82 | 2.0.3 | gain |
| --- | ---: | ---: | ---: | ---: |
| 3 | 100,000 | 20.5s | 0.20s | 103x |
| 6 | 100,000 | 44.2s | 0.26s | 168x |
| 12 | 100,000 | 93.0s | 0.40s | **230x** |

The data size is the same in every row. The number of adoption dates and
the cohort shares vary; the never-treated share falls from 24.5% to 6.8%.
The Version 1.82 column grows as the number of underlying ATT(g,t) cells
increases across these designs.

## By sampling scheme

| scheme (n=10,000, T=10, G=4) | rows | 1.82 | 2.0.3 | gain |
| --- | ---: | ---: | ---: | ---: |
| balanced panel | 100,000 | 12.6s | 0.21s | **60x** |
| unbalanced panel (15% of rows deleted) | 85,219 | 10.1s | 0.27s | 38x |
| repeated cross sections | 100,000 | 8.56s | 0.81s | 11x |

Repeated cross sections are the sampling scheme where 2.0.3 gains least,
and they set the low end of this page: 11x there against 305x at forty
periods, which are the two extremes across all four tables.

## Where the workload gains were certified

The per-workload comparison at fixed size (analytical, bootstrap,
weighted, clustered, and event-study variants) ships in the
package README, and it was produced by a
seven-trial A/B harness run against an installed copy of Version 1.82. This page extends that comparison across sizes and
designs, and it does not replace those numbers or restate them. Neither
set of timings says anything about which version is more accurate, since
both compute the same estimates here.

[Back to the guides](../guides.html)
